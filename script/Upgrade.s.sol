// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import { Script, console } from "forge-std/Script.sol";
import { HelperConfig } from "./HelperConfig.s.sol";
import { ICreateX } from "createx/ICreateX.sol";
import { UUPSUpgradeable } from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import { BattleChainSafeHarborRegistry } from "src/BattleChainSafeHarborRegistry.sol";
import { AgreementFactory } from "src/AgreementFactory.sol";
import { AttackRegistry } from "src/AttackRegistry.sol";

/// @title UpgradeBattleChainSafeHarbor
/// @notice Upgrade script for the BattleChain Safe Harbor contracts: Registry, AgreementFactory,
///         and AttackRegistry.
/// @dev Implementation addresses are CREATE3 guarded-salt deployments keyed on
///      BATTLECHAIN_SAFE_HARBOR_VERSION — bump src/Version.sol before running.
///
///      The flow is split in two because the implementation deployer and the proxy owner are
///      different accounts on live networks (on mainnet the owner is a multisig):
///      1. `deployImplementations()` — broadcast as the configured deployer
///      2. `upgradeProxies(...)` — broadcast as the proxy owner, or execute the calldata
///         logged by step 1 from the owner multisig
contract UpgradeBattleChainSafeHarbor is Script {
    /*//////////////////////////////////////////////////////////////
                                ERRORS
    //////////////////////////////////////////////////////////////*/
    error AddressMismatch(address expected, address actual);
    error DeployerMismatch(address expected, address actual);
    error OwnerMismatch(address expected, address actual);
    error ImplementationNotDeployed(address expected);

    /*//////////////////////////////////////////////////////////////
                            STATE VARIABLES
    //////////////////////////////////////////////////////////////*/
    HelperConfig public helperConfig;
    HelperConfig.NetworkConfig public networkConfig;
    bool private _initialized;

    /*//////////////////////////////////////////////////////////////
                          DEPLOYED ADDRESSES
    //////////////////////////////////////////////////////////////*/
    address public newRegistryImpl;
    address public newFactoryImpl;
    address public newAttackRegistryImpl;

    /*//////////////////////////////////////////////////////////////
                            INITIALIZATION
    //////////////////////////////////////////////////////////////*/
    /// @notice Initializes the upgrader with HelperConfig
    function initialize() public {
        if (!_initialized) {
            helperConfig = new HelperConfig();
            networkConfig = helperConfig.getNetworkConfig();
            _initialized = true;
        }
    }

    /// @notice Initializes with an existing HelperConfig
    function initialize(HelperConfig _helperConfig) public {
        if (!_initialized) {
            helperConfig = _helperConfig;
            networkConfig = helperConfig.getNetworkConfig();
            _initialized = true;
        }
    }

    /*//////////////////////////////////////////////////////////////
                        STEP 1: DEPLOY IMPLEMENTATIONS
    //////////////////////////////////////////////////////////////*/
    /// @notice Deploys new implementations for all three upgradeable contracts
    /// @dev Must be broadcast by the configured deployer (CreateX guarded salts are
    ///      permissioned to that address). Logs the per-proxy `upgradeToAndCall` calldata
    ///      so the owner multisig can execute step 2.
    function deployImplementations() external returns (address, address, address) {
        initialize();

        console.log("Deploying new implementations...");
        console.log("Chain ID:", block.chainid);
        console.log("Deployer:", networkConfig.deployer);

        address expectedRegistryImpl =
            computeExpectedAddress(networkConfig.deployer, helperConfig.REGISTRY_IMPL_ENTROPY());
        address expectedFactoryImpl =
            computeExpectedAddress(networkConfig.deployer, helperConfig.FACTORY_IMPL_ENTROPY());
        address expectedAttackRegistryImpl =
            computeExpectedAddress(networkConfig.deployer, helperConfig.ATTACK_REGISTRY_IMPL_ENTROPY());
        console.log("Expected Registry Implementation:", expectedRegistryImpl);
        console.log("Expected AgreementFactory Implementation:", expectedFactoryImpl);
        console.log("Expected AttackRegistry Implementation:", expectedAttackRegistryImpl);

        vm.startBroadcast();

        // Verify the broadcaster matches the configured deployer
        if (msg.sender != networkConfig.deployer) {
            revert DeployerMismatch(networkConfig.deployer, msg.sender);
        }

        newRegistryImpl = deployImplementation(
            type(BattleChainSafeHarborRegistry).creationCode, helperConfig.REGISTRY_IMPL_ENTROPY()
        );
        if (newRegistryImpl != expectedRegistryImpl) {
            revert AddressMismatch(expectedRegistryImpl, newRegistryImpl);
        }

        newFactoryImpl =
            deployImplementation(type(AgreementFactory).creationCode, helperConfig.FACTORY_IMPL_ENTROPY());
        if (newFactoryImpl != expectedFactoryImpl) {
            revert AddressMismatch(expectedFactoryImpl, newFactoryImpl);
        }

        newAttackRegistryImpl =
            deployImplementation(type(AttackRegistry).creationCode, helperConfig.ATTACK_REGISTRY_IMPL_ENTROPY());
        if (newAttackRegistryImpl != expectedAttackRegistryImpl) {
            revert AddressMismatch(expectedAttackRegistryImpl, newAttackRegistryImpl);
        }

        vm.stopBroadcast();

        console.log("New Registry Implementation deployed at:", newRegistryImpl);
        console.log("New AgreementFactory Implementation deployed at:", newFactoryImpl);
        console.log("New AttackRegistry Implementation deployed at:", newAttackRegistryImpl);

        console.log("Owner calldata for Registry proxy:");
        console.logBytes(abi.encodeCall(UUPSUpgradeable.upgradeToAndCall, (newRegistryImpl, bytes(""))));
        console.log("Owner calldata for AgreementFactory proxy:");
        console.logBytes(abi.encodeCall(UUPSUpgradeable.upgradeToAndCall, (newFactoryImpl, bytes(""))));
        console.log("Owner calldata for AttackRegistry proxy:");
        console.logBytes(abi.encodeCall(UUPSUpgradeable.upgradeToAndCall, (newAttackRegistryImpl, bytes(""))));

        return (newRegistryImpl, newFactoryImpl, newAttackRegistryImpl);
    }

    /*//////////////////////////////////////////////////////////////
                        STEP 2: UPGRADE PROXIES
    //////////////////////////////////////////////////////////////*/
    /// @notice Upgrades the three proxies to the implementations deployed in step 1
    /// @dev Must be broadcast by the proxy owner. On networks where the owner is a multisig,
    ///      execute the calldata logged by `deployImplementations` from the multisig instead.
    /// @param registryProxy The BattleChainSafeHarborRegistry proxy
    /// @param factoryProxy The AgreementFactory proxy
    /// @param attackRegistryProxy The AttackRegistry proxy
    function upgradeProxies(address registryProxy, address factoryProxy, address attackRegistryProxy) external {
        initialize();

        console.log("Upgrading proxies...");
        console.log("Chain ID:", block.chainid);
        console.log("Owner:", networkConfig.owner);

        address registryImpl = expectedImplementation(helperConfig.REGISTRY_IMPL_ENTROPY());
        address factoryImpl = expectedImplementation(helperConfig.FACTORY_IMPL_ENTROPY());
        address attackRegistryImpl = expectedImplementation(helperConfig.ATTACK_REGISTRY_IMPL_ENTROPY());

        vm.startBroadcast();

        // Verify the broadcaster matches the configured owner
        if (msg.sender != networkConfig.owner) {
            revert OwnerMismatch(networkConfig.owner, msg.sender);
        }

        upgradeProxy(registryProxy, registryImpl);
        upgradeProxy(factoryProxy, factoryImpl);
        upgradeProxy(attackRegistryProxy, attackRegistryImpl);

        vm.stopBroadcast();

        console.log("Registry version:", BattleChainSafeHarborRegistry(registryProxy).version());
        console.log("AgreementFactory version:", AgreementFactory(factoryProxy).version());
        console.log("AttackRegistry version:", AttackRegistry(attackRegistryProxy).version());
    }

    /*//////////////////////////////////////////////////////////////
                         UPGRADE FUNCTIONS
    //////////////////////////////////////////////////////////////*/
    /// @notice Deploys an implementation using CREATE3 with a guarded salt
    /// @param initCode The creation code of the implementation (no constructor args)
    /// @param entropy The entropy portion of the salt for this version
    function deployImplementation(bytes memory initCode, bytes11 entropy) public returns (address) {
        ICreateX createx = ICreateX(networkConfig.createx);

        // Build guarded salt: [deployer (20 bytes)][0x00 (1 byte)][entropy (11 bytes)]
        bytes32 guardedSalt = buildGuardedSalt(networkConfig.deployer, entropy);

        // Deploy using CREATE3 with guarded salt
        return createx.deployCreate3(guardedSalt, initCode);
    }

    /// @notice Upgrades the proxy to a new implementation
    /// @param proxy The proxy address
    /// @param newImpl The new implementation address
    function upgradeProxy(address proxy, address newImpl) public {
        // Upgrade with no additional initialization data
        UUPSUpgradeable(proxy).upgradeToAndCall(newImpl, "");
    }

    /// @notice Computes the expected implementation address and verifies it has code
    /// @param entropy The entropy portion of the salt for this version
    function expectedImplementation(bytes11 entropy) public view returns (address impl) {
        impl = computeExpectedAddress(networkConfig.deployer, entropy);
        if (impl.code.length == 0) {
            revert ImplementationNotDeployed(impl);
        }
    }

    /*//////////////////////////////////////////////////////////////
                           HELPER FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /// @notice Builds a guarded salt for CreateX CREATE3 deployment
    /// @dev Salt structure: [deployer (20 bytes)][0x00 (1 byte)][entropy (11 bytes)]
    ///      - First 20 bytes = deployer address: enables permissioned deploy protection
    ///      - Byte 21 = 0x00: disables cross-chain redeploy protection (same address on all chains)
    ///      - Last 11 bytes = entropy: unique identifier for the contract
    /// @param deployer The address that is allowed to deploy using this salt
    /// @param entropy The unique 11-byte identifier for this contract
    /// @return salt The 32-byte guarded salt
    function buildGuardedSalt(address deployer, bytes11 entropy) public pure returns (bytes32 salt) {
        // Pack: [deployer (20 bytes)][0x00 (1 byte)][entropy (11 bytes)]
        salt = bytes32(abi.encodePacked(deployer, bytes1(0x00), entropy));
    }

    /// @notice Computes the guarded salt that CreateX will use internally
    /// @dev CreateX hashes the salt with msg.sender when the first 20 bytes match msg.sender
    ///      Formula: guardedSalt = keccak256(abi.encodePacked(deployer, salt))
    /// @param deployer The deployer address embedded in the salt
    /// @param entropy The entropy portion of the salt
    /// @return guardedSalt The salt that CreateX will actually use for CREATE3
    function computeGuardedSalt(address deployer, bytes11 entropy) public pure returns (bytes32 guardedSalt) {
        bytes32 inputSalt = buildGuardedSalt(deployer, entropy);
        // CreateX formula for MsgSender + False (no cross-chain protection):
        // guardedSalt = keccak256(abi.encodePacked(bytes32(uint256(uint160(msg.sender))), salt))
        guardedSalt = keccak256(abi.encodePacked(bytes32(uint256(uint160(deployer))), inputSalt));
    }

    /// @notice Computes the expected address for a new implementation
    /// @param deployer The address that will deploy the contract
    /// @param entropy The entropy portion of the salt
    function computeExpectedAddress(address deployer, bytes11 entropy) public view returns (address) {
        ICreateX createx = ICreateX(networkConfig.createx);
        bytes32 guardedSalt = computeGuardedSalt(deployer, entropy);
        return createx.computeCreate3Address(guardedSalt);
    }
}
