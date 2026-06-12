// SPDX-License-Identifier: MIT
pragma solidity 0.8.34;

import { IBattleChainSafeHarborRegistry } from "src/interface/IBattleChainSafeHarborRegistry.sol";
import { IAgreementFactory } from "src/interface/IAgreementFactory.sol";
import { BATTLECHAIN_SAFE_HARBOR_VERSION } from "src/Version.sol";
import { Ownable2StepUpgradeable } from "@openzeppelin/contracts-upgradeable/access/Ownable2StepUpgradeable.sol";
import { UUPSUpgradeable } from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";

/// @title The BattleChain Safe Harbor Registry. See www.battlechain.com for details.
/// @custom:security-contact security@battlechain.com
// aderyn-ignore-next-line(contract-locks-ether)
contract BattleChainSafeHarborRegistry is UUPSUpgradeable, Ownable2StepUpgradeable, IBattleChainSafeHarborRegistry {
    /*//////////////////////////////////////////////////////////////
                                 ERRORS
    //////////////////////////////////////////////////////////////*/
    error BattleChainSafeHarborRegistry__NoAgreement();
    error BattleChainSafeHarborRegistry__ZeroAddress();
    error BattleChainSafeHarborRegistry__RenounceDisabled();

    /*//////////////////////////////////////////////////////////////
                            STATE VARIABLES
    //////////////////////////////////////////////////////////////*/
    string constant VERSION = BATTLECHAIN_SAFE_HARBOR_VERSION;
    mapping(address entity => address details) private s_agreements;
    mapping(string caip2ChainId => bool valid) private s_validChains;

    /// @dev The agreement factory address
    address private s_agreementFactory;

    /// @dev The attack registry address
    address private s_attackRegistry;

    /// @dev Reserved storage for future upgrades (50 - 4 used slots = 46)
    // aderyn-ignore-next-line(unused-state-variable)
    uint256[46] private __gap;

    /*//////////////////////////////////////////////////////////////
                                 EVENTS
    //////////////////////////////////////////////////////////////*/
    event BattleChainSafeHarborAdoption(address indexed entity, address newDetails);
    event ChainValiditySet(string caip2ChainId, bool valid);
    event AgreementFactorySet(address indexed factory);
    event AttackRegistrySet(address indexed attackRegistry);

    /*//////////////////////////////////////////////////////////////
                              INITIALIZER
    //////////////////////////////////////////////////////////////*/
    constructor() {
        _disableInitializers();
    }

    function initialize(
        address owner,
        string[] memory initialValidChains,
        address agreementFactory,
        address attackRegistry
    )
        external
        initializer
    {
        // owner == address(0) is checked downstream in __Ownable_init_unchained
        // (reverts with OwnableInvalidOwner)
        if (agreementFactory == address(0)) {
            revert BattleChainSafeHarborRegistry__ZeroAddress();
        }
        if (attackRegistry == address(0)) {
            revert BattleChainSafeHarborRegistry__ZeroAddress();
        }
        __Ownable_init_unchained(owner);
        emit AgreementFactorySet(agreementFactory);
        s_agreementFactory = agreementFactory;
        emit AttackRegistrySet(attackRegistry);
        s_attackRegistry = attackRegistry;

        uint256 length = initialValidChains.length;
        // aderyn-ignore-next-line(costly-loop)
        for (uint256 i; i < length; ++i) {
            emit ChainValiditySet(initialValidChains[i], true);
            s_validChains[initialValidChains[i]] = true;
        }
    }

    /*//////////////////////////////////////////////////////////////
                  USER-FACING STATE-CHANGING FUNCTIONS
    //////////////////////////////////////////////////////////////*/
    /// @notice Function that sets a list of chains as valid in the registry.
    /// @param caip2ChainIds The CAIP-2 IDs of the chains to mark as valid.
    // aderyn-ignore-next-line(centralization-risk)
    function setValidChains(string[] calldata caip2ChainIds) external onlyOwner {
        // aderyn-ignore-next-line(costly-loop)
        for (uint256 i; i < caip2ChainIds.length; ++i) {
            emit ChainValiditySet(caip2ChainIds[i], true);
            s_validChains[caip2ChainIds[i]] = true;
        }
    }

    /// @notice Function that marks a list of chains as invalid in the registry.
    /// @param caip2ChainIds The CAIP-2 IDs of the chains to mark as invalid.
    // aderyn-ignore-next-line(centralization-risk)
    function setInvalidChains(string[] calldata caip2ChainIds) external onlyOwner {
        // aderyn-ignore-next-line(costly-loop)
        for (uint256 i; i < caip2ChainIds.length; ++i) {
            emit ChainValiditySet(caip2ChainIds[i], false);
            s_validChains[caip2ChainIds[i]] = false;
        }
    }

    /// @notice Set the agreement factory address.
    /// @param factory The new agreement factory address.
    // aderyn-ignore-next-line(centralization-risk)
    function setAgreementFactory(address factory) external onlyOwner {
        if (factory == address(0)) {
            revert BattleChainSafeHarborRegistry__ZeroAddress();
        }
        emit AgreementFactorySet(factory);
        s_agreementFactory = factory;
    }

    /// @notice Set the attack registry address.
    /// @param attackRegistryAddr The new attack registry address.
    // aderyn-ignore-next-line(centralization-risk)
    function setAttackRegistry(address attackRegistryAddr) external onlyOwner {
        if (attackRegistryAddr == address(0)) {
            revert BattleChainSafeHarborRegistry__ZeroAddress();
        }
        emit AttackRegistrySet(attackRegistryAddr);
        s_attackRegistry = attackRegistryAddr;
    }

    /// @notice Adds an existing agreement to the registry for the sender.
    /// @param agreementAddress The address of the agreement to adopt.
    /// @dev This mapping records the adopter's safe harbor agreement and is authoritative for
    ///      Eligible Funds Rescue (Urgent Blackhat Exploit) coverage. It does NOT bind which
    ///      agreement governs an Eligible Stress Test Exploit on BattleChain — for attack-mode
    ///      coverage, the Binding Agreement is resolved via AttackRegistry.
    function adoptSafeHarbor(address agreementAddress) external {
        emit BattleChainSafeHarborAdoption(msg.sender, agreementAddress);
        s_agreements[msg.sender] = agreementAddress;
    }

    /*//////////////////////////////////////////////////////////////
                   INTERNAL STATE-CHANGING FUNCTIONS
    //////////////////////////////////////////////////////////////*/
    // aderyn-ignore-next-line(centralization-risk,empty-block)
    function _authorizeUpgrade(address newImplementation) internal override onlyOwner { }

    function renounceOwnership() public pure override {
        revert BattleChainSafeHarborRegistry__RenounceDisabled();
    }

    /*//////////////////////////////////////////////////////////////
                    USER-FACING READ-ONLY FUNCTIONS
    //////////////////////////////////////////////////////////////*/
    /// @notice Returns the agreement the adopter recorded via `adoptSafeHarbor`. Authoritative
    ///         for Eligible Funds Rescue coverage but NOT for Eligible Stress Test Exploits — for
    ///         attack-mode coverage, resolve the Binding Agreement via AttackRegistry. The two
    ///         registries can diverge.
    /// @param adopter The adopter to query.
    /// @return The agreement address recorded for the adopter.
    function getAgreement(address adopter) external view returns (address) {
        address agreement = s_agreements[adopter];

        if (agreement != address(0)) {
            return agreement;
        }

        revert BattleChainSafeHarborRegistry__NoAgreement();
    }

    /// @notice Function that returns if a chain is valid.
    /// @param _caip2ChainId The CAIP-2 ID of the chain to check.
    /// @return bool True if the chain is valid, false otherwise.
    function isChainValid(string calldata _caip2ChainId) external view returns (bool) {
        return s_validChains[_caip2ChainId];
    }

    /// @notice Checks that the agreement was created by the configured factory. Returns true for
    ///         ANY factory-deployed agreement — a `true` return does not establish that the
    ///         agreement binds any specific contract. Do not use as a substitute for resolving
    ///         the Binding Agreement via AttackRegistry.
    /// @param agreementAddress The agreement address to check.
    /// @return True if the agreement was created by the configured factory.
    function isAgreementValid(address agreementAddress) external view returns (bool) {
        if (s_agreementFactory == address(0)) {
            return false;
        }
        return IAgreementFactory(s_agreementFactory).isAgreementContract(agreementAddress);
    }

    /// @notice Get the agreement factory address.
    /// @return The agreement factory address.
    function getAgreementFactory() external view returns (address) {
        return s_agreementFactory;
    }

    /// @notice Get the attack registry address.
    /// @return The attack registry address.
    function getAttackRegistry() external view returns (address) {
        return s_attackRegistry;
    }

    /// @notice Returns the version of the BattleChain Safe Harbor Registry contract.
    function version() external pure returns (string memory) {
        return VERSION;
    }
}
