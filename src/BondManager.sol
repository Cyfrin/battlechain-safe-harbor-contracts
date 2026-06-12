// SPDX-License-Identifier: MIT
pragma solidity 0.8.34;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { SafeTransferLib } from "solady/utils/SafeTransferLib.sol";
import { IAttackRegistry } from "src/interface/IAttackRegistry.sol";

/// @title BondManager
/// @notice Abstract contract managing fee/bond collection for AttackRegistry.
/// @dev Fees go to treasury immediately. Only bonds are held in this contract.
///      The DAO can only withdraw slashed bonds via withdrawFunds.
///      The bond token MUST be a standard ERC20. Fee-on-transfer and rebasing tokens
///      are not supported — they would corrupt s_reservedByToken accounting.
/// @custom:security-contact security@battlechain.com
abstract contract BondManager {
    using SafeERC20 for IERC20;

    /*//////////////////////////////////////////////////////////////
                            STATE VARIABLES
    //////////////////////////////////////////////////////////////*/
    /// @dev ERC20 used for payments. address(0) = payments disabled.
    IERC20 internal s_bondToken;
    /// @dev Treasury address — receives fees immediately on collection.
    address internal s_treasury;
    /// @dev Non-refundable fee amount.
    uint256 internal s_feeAmount;
    /// @dev Bond for requestUnderAttack (verified path).
    uint256 internal s_verifiedBondAmount;
    /// @dev Bond for requestUnderAttackForUnverifiedContracts.
    uint256 internal s_unverifiedBondAmount;
    /// @dev Per-agreement deposit records.
    mapping(address agreement => IAttackRegistry.BondDeposit deposit) internal s_agreementBond;
    /// @dev Bonds reserved per token (pending + claimable, not slashed or claimed).
    mapping(IERC20 token => uint256 reserved) internal s_reservedByToken;
    /// @dev Storage gap for BondManager upgrades.
    // aderyn-ignore-next-line(unused-state-variable)
    uint256[200] private __bondGap;

    /*//////////////////////////////////////////////////////////////
                                 EVENTS
    //////////////////////////////////////////////////////////////*/
    event FeeCollected(address indexed agreement, address indexed payer, uint256 amount);
    event BondDeposited(address indexed agreement, address indexed depositor, uint256 amount);
    event BondClaimable(address indexed agreement, uint256 amount);
    event BondSlashed(address indexed agreement, uint256 amount);
    event BondClaimed(address indexed agreement, address indexed depositor, uint256 amount);
    event FundsWithdrawn(address indexed token, address indexed recipient, uint256 amount);
    event BondTokenChanged(address indexed newToken);
    event TreasuryChanged(address indexed newTreasury);
    event FeeAmountChanged(uint256 newAmount);
    event VerifiedBondAmountChanged(uint256 newAmount);
    event UnverifiedBondAmountChanged(uint256 newAmount);
    event BondForfeited(address indexed agreement, address indexed depositor, uint256 amount);

    /*//////////////////////////////////////////////////////////////
                                 ERRORS
    //////////////////////////////////////////////////////////////*/
    error BondManager__BondAlreadyClaimed(address agreement);
    error BondManager__BondAlreadySlashed(address agreement);
    error BondManager__NotBondDepositor(address caller, address depositor);
    error BondManager__NoBondDeposit(address agreement);
    error BondManager__ZeroAddress();
    error BondManager__TreasuryNotSet();
    error BondManager__BondNotYetClaimable(address agreement);

    /*//////////////////////////////////////////////////////////////
                  USER-FACING STATE-CHANGING FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /// @notice Claim bond back after a claimable outcome.
    /// @dev Caller must be the original depositor. Handles lazy marking for
    ///      time-based promotions that never triggered _markBondClaimable.
    /// @param agreementAddress The agreement whose bond to claim
    function claimBond(address agreementAddress) external virtual {
        IAttackRegistry.BondDeposit storage deposit = s_agreementBond[agreementAddress];

        if (deposit.depositor == address(0)) {
            revert BondManager__NoBondDeposit(agreementAddress);
        }
        if (msg.sender != deposit.depositor) {
            revert BondManager__NotBondDepositor(msg.sender, deposit.depositor);
        }
        if (deposit.claimed) {
            revert BondManager__BondAlreadyClaimed(agreementAddress);
        }
        if (deposit.slashed) {
            revert BondManager__BondAlreadySlashed(agreementAddress);
        }

        // Lazy-mark for time-based promotions that bypassed explicit marking
        if (!deposit.bondClaimable) {
            if (_getAgreementState(agreementAddress) == IAttackRegistry.ContractState.PRODUCTION) {
                // Zero-bond deposits (fee-only) have nothing to transfer — short-circuit so
                // off-chain automation that calls claimBond after PRODUCTION doesn't permanently
                // revert. Gated on PRODUCTION (same gate as non-zero claims) so the depositor
                // can't claim while the agreement is still in an active state.
                if (deposit.bondAmount == 0) {
                    emit BondClaimed(agreementAddress, deposit.depositor, 0);
                    deposit.claimed = true;
                    return;
                }
                emit BondClaimable(agreementAddress, deposit.bondAmount);
                deposit.bondClaimable = true;
            }
        }

        if (!deposit.bondClaimable) {
            revert BondManager__BondNotYetClaimable(agreementAddress);
        }

        // Effects
        emit BondClaimed(agreementAddress, deposit.depositor, deposit.bondAmount);
        deposit.claimed = true;
        s_reservedByToken[deposit.token] -= deposit.bondAmount;

        // Interaction
        deposit.token.safeTransfer(deposit.depositor, deposit.bondAmount);
    }

    /*//////////////////////////////////////////////////////////////
                    USER-FACING READ-ONLY FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    function getBondToken() external view virtual returns (address) {
        return address(s_bondToken);
    }

    function getTreasury() external view virtual returns (address) {
        return s_treasury;
    }

    function getFeeAmount() external view virtual returns (uint256) {
        return s_feeAmount;
    }

    function getVerifiedBondAmount() external view virtual returns (uint256) {
        return s_verifiedBondAmount;
    }

    function getUnverifiedBondAmount() external view virtual returns (uint256) {
        return s_unverifiedBondAmount;
    }

    function getBondDeposit(address agreementAddress)
        external
        view
        virtual
        returns (IAttackRegistry.BondDeposit memory)
    {
        return s_agreementBond[agreementAddress];
    }

    function getReservedByToken(address token) external view virtual returns (uint256) {
        return s_reservedByToken[IERC20(token)];
    }

    /*//////////////////////////////////////////////////////////////
                  INTERNAL STATE-CHANGING FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /// @notice Collect fee + bond from payer. Fee goes to treasury, bond stays here.
    /// @dev No-op when bond token is address(0) or both amounts are 0.
    /// @dev If a prior bond exists on this agreement that is unclaimed and unslashed (e.g.,
    ///      after a soft `rejectAttackRequest` whose depositor never called `claimBond`), it is
    ///      forfeited here: `s_reservedByToken` is decremented and `BondForfeited` is emitted,
    ///      but the prior deposit is overwritten by the new one with no token transfer back.
    ///      The forfeited tokens stay in this contract and are sweepable by the owner via
    ///      `withdrawFunds`. Agreement owners must call `claimBond` between a soft reject and
    ///      any re-registration to recover their original bond.
    function _collectFeeAndBond(address agreementAddress, address payer, uint256 bondAmount) internal {
        if (address(s_bondToken) == address(0)) return;

        uint256 fee = s_feeAmount;
        if (fee == 0 && bondAmount == 0) return;

        if (fee > 0 && s_treasury == address(0)) {
            revert BondManager__TreasuryNotSet();
        }

        // Forfeit any existing unclaimed bond to keep s_reservedByToken accurate
        IAttackRegistry.BondDeposit storage existing = s_agreementBond[agreementAddress];
        if (existing.bondAmount > 0 && !existing.claimed && !existing.slashed) {
            emit BondForfeited(agreementAddress, existing.depositor, existing.bondAmount);
            s_reservedByToken[existing.token] -= existing.bondAmount;
        }

        // Effects
        s_agreementBond[agreementAddress] = IAttackRegistry.BondDeposit({
            depositor: payer,
            token: s_bondToken,
            feeAmount: fee,
            bondAmount: bondAmount,
            bondClaimable: false,
            claimed: false,
            slashed: false
        });

        if (bondAmount > 0) {
            emit BondDeposited(agreementAddress, payer, bondAmount);
            s_reservedByToken[s_bondToken] += bondAmount;
        }

        if (fee > 0) {
            emit FeeCollected(agreementAddress, payer, fee);
        }

        // Interactions — fee to treasury, bond to this contract
        if (fee > 0) {
            s_bondToken.safeTransferFrom(payer, s_treasury, fee);
        }
        if (bondAmount > 0) {
            s_bondToken.safeTransferFrom(payer, address(this), bondAmount);
        }
    }

    /// @notice Mark bond as claimable (normal lifecycle outcomes).
    function _markBondClaimable(address agreementAddress) internal {
        IAttackRegistry.BondDeposit storage deposit = s_agreementBond[agreementAddress];
        if (deposit.bondAmount == 0) return;
        if (deposit.bondClaimable) return;

        emit BondClaimable(agreementAddress, deposit.bondAmount);
        deposit.bondClaimable = true;
    }

    /// @notice Slash the bond (DAO intervention or hard reject).
    /// @dev Decrements reserved amount so slashed funds become withdrawable.
    function _slashBond(address agreementAddress) internal {
        IAttackRegistry.BondDeposit storage deposit = s_agreementBond[agreementAddress];
        if (deposit.bondAmount == 0) return;
        if (deposit.slashed) return;

        emit BondSlashed(agreementAddress, deposit.bondAmount);
        deposit.slashed = true;
        s_reservedByToken[deposit.token] -= deposit.bondAmount;
    }

    /// @notice Withdraw all available (non-reserved) balance for a token.
    /// @dev For bond tokens, only slashed amounts are withdrawable. For other tokens/ETH, full balance.
    /// @return amount The amount withdrawn
    function _withdrawFunds(address token, address recipient) internal returns (uint256 amount) {
        if (recipient == address(0)) {
            revert BondManager__ZeroAddress();
        }

        if (token == address(0)) {
            amount = address(this).balance;
        } else {
            uint256 balance = IERC20(token).balanceOf(address(this));
            amount = balance - s_reservedByToken[IERC20(token)];
        }

        if (amount == 0) return 0;

        emit FundsWithdrawn(token, recipient, amount);

        if (token == address(0)) {
            SafeTransferLib.safeTransferETH(recipient, amount);
        } else {
            IERC20(token).safeTransfer(recipient, amount);
        }
    }

    function _setBondToken(address token) internal {
        emit BondTokenChanged(token);
        // aderyn-ignore-next-line(state-no-address-check)
        s_bondToken = IERC20(token);
    }

    function _setTreasury(address treasury) internal {
        if (treasury == address(0)) {
            revert BondManager__ZeroAddress();
        }
        emit TreasuryChanged(treasury);
        s_treasury = treasury;
    }

    function _setFeeAmount(uint256 amount) internal {
        emit FeeAmountChanged(amount);
        s_feeAmount = amount;
    }

    function _setVerifiedBondAmount(uint256 amount) internal {
        emit VerifiedBondAmountChanged(amount);
        s_verifiedBondAmount = amount;
    }

    function _setUnverifiedBondAmount(uint256 amount) internal {
        emit UnverifiedBondAmountChanged(amount);
        s_unverifiedBondAmount = amount;
    }

    /*//////////////////////////////////////////////////////////////
                    INTERNAL READ-ONLY FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /// @dev Must be implemented by AttackRegistry to resolve agreement state.
    function _getAgreementState(address agreementAddress) internal view virtual returns (IAttackRegistry.ContractState);
}
