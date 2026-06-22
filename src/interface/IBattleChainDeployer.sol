// SPDX-License-Identifier: MIT
// aderyn-ignore-next-line(unspecific-solidity-pragma,push-zero-opcode)
pragma solidity ^0.8.24;

/// @title IBattleChainDeployer
/// @notice Interface for the deploy and address-computation surface exposed by
///         BattleChainDeployer (inherited from CreateX plus its registration overrides).
/// @dev Kept self-contained (no bare `src/` imports) so downstream libraries can import it
///      directly. The `Values` struct mirrors `CreateX.Values`.
interface IBattleChainDeployer {
    /// @notice Struct for the `payable` amounts in a deploy-and-initialise call.
    struct Values {
        uint256 constructorAmount;
        uint256 initCallAmount;
    }

    /*//////////////////////////////////////////////////////////////
                                CREATE
    //////////////////////////////////////////////////////////////*/
    function deployCreate(bytes memory initCode) external payable returns (address newContract);

    function deployCreateAndInit(
        bytes memory initCode,
        bytes memory data,
        Values memory values,
        address refundAddress
    )
        external
        payable
        returns (address newContract);

    function deployCreateAndInit(
        bytes memory initCode,
        bytes memory data,
        Values memory values
    )
        external
        payable
        returns (address newContract);

    function deployCreateClone(
        address implementation,
        bytes memory data
    )
        external
        payable
        returns (address proxy);

    /*//////////////////////////////////////////////////////////////
                                CREATE2
    //////////////////////////////////////////////////////////////*/
    function deployCreate2(bytes32 salt, bytes memory initCode) external payable returns (address newContract);

    function deployCreate2(bytes memory initCode) external payable returns (address newContract);

    function deployCreate2AndInit(
        bytes32 salt,
        bytes memory initCode,
        bytes memory data,
        Values memory values,
        address refundAddress
    )
        external
        payable
        returns (address newContract);

    function deployCreate2AndInit(
        bytes32 salt,
        bytes memory initCode,
        bytes memory data,
        Values memory values
    )
        external
        payable
        returns (address newContract);

    function deployCreate2AndInit(
        bytes memory initCode,
        bytes memory data,
        Values memory values,
        address refundAddress
    )
        external
        payable
        returns (address newContract);

    function deployCreate2AndInit(
        bytes memory initCode,
        bytes memory data,
        Values memory values
    )
        external
        payable
        returns (address newContract);

    function deployCreate2Clone(
        bytes32 salt,
        address implementation,
        bytes memory data
    )
        external
        payable
        returns (address proxy);

    function deployCreate2Clone(
        address implementation,
        bytes memory data
    )
        external
        payable
        returns (address proxy);

    /*//////////////////////////////////////////////////////////////
                                CREATE3
    //////////////////////////////////////////////////////////////*/
    function deployCreate3(bytes32 salt, bytes memory initCode) external payable returns (address newContract);

    function deployCreate3(bytes memory initCode) external payable returns (address newContract);

    function deployCreate3AndInit(
        bytes32 salt,
        bytes memory initCode,
        bytes memory data,
        Values memory values,
        address refundAddress
    )
        external
        payable
        returns (address newContract);

    function deployCreate3AndInit(
        bytes32 salt,
        bytes memory initCode,
        bytes memory data,
        Values memory values
    )
        external
        payable
        returns (address newContract);

    function deployCreate3AndInit(
        bytes memory initCode,
        bytes memory data,
        Values memory values,
        address refundAddress
    )
        external
        payable
        returns (address newContract);

    function deployCreate3AndInit(
        bytes memory initCode,
        bytes memory data,
        Values memory values
    )
        external
        payable
        returns (address newContract);

    /*//////////////////////////////////////////////////////////////
                          ADDRESS COMPUTATION
    //////////////////////////////////////////////////////////////*/
    function computeCreateAddress(address deployer, uint256 nonce) external view returns (address computedAddress);

    function computeCreateAddress(uint256 nonce) external view returns (address computedAddress);

    function computeCreate2Address(
        bytes32 salt,
        bytes32 initCodeHash,
        address deployer
    )
        external
        pure
        returns (address computedAddress);

    function computeCreate2Address(
        bytes32 salt,
        bytes32 initCodeHash
    )
        external
        view
        returns (address computedAddress);

    function computeCreate3Address(bytes32 salt, address deployer) external pure returns (address computedAddress);

    function computeCreate3Address(bytes32 salt) external view returns (address computedAddress);
}
