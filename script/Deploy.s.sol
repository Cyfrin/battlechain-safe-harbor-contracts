// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import { Script, console } from "forge-std/Script.sol";
import { HelperConfig } from "./HelperConfig.s.sol";
import { ICreateX } from "createx/ICreateX.sol";
import { BattleChainSafeHarborRegistry } from "src/BattleChainSafeHarborRegistry.sol";
import { AgreementFactory } from "src/AgreementFactory.sol";
import { ERC1967Proxy } from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

/// @title DeployBattleChainSafeHarbor
/// @notice Deployment script for BattleChain Safe Harbor Registry using CREATE3 for deterministic addresses
/// @dev Uses CreateX guarded salts: only the designated deployer can deploy to the computed addresses
contract DeployBattleChainSafeHarbor is Script {
    /*//////////////////////////////////////////////////////////////
                                ERRORS
    //////////////////////////////////////////////////////////////*/
    error AddressMismatch(address expected, address actual);
    error DeployerMismatch(address expected, address actual);

    /*//////////////////////////////////////////////////////////////
                            STATE VARIABLES
    //////////////////////////////////////////////////////////////*/
    HelperConfig public helperConfig;
    HelperConfig.NetworkConfig public networkConfig;
    bool private _initialized;

    /*//////////////////////////////////////////////////////////////
                          DEPLOYED ADDRESSES
    //////////////////////////////////////////////////////////////*/
    address public registryImpl;
    address public registryProxy;
    address public agreementFactoryImpl;
    address public agreementFactoryProxy;

    /*//////////////////////////////////////////////////////////////
                            INITIALIZATION
    //////////////////////////////////////////////////////////////*/
    /// @notice Initializes the deployer with HelperConfig
    /// @dev Must be called before deployment functions
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
                           MAIN ENTRY POINT
    //////////////////////////////////////////////////////////////*/
    function run() external {
        initialize();

        console.log("Deploying BattleChain Safe Harbor...");
        console.log("Chain ID:", block.chainid);
        console.log("Owner:", networkConfig.owner);
        console.log("Deployer:", networkConfig.deployer);
        console.log("CreateX:", networkConfig.createx);

        // Pre-flight: compute expected addresses and log them
        (address expectedRegImpl, address expectedRegProxy, address expectedFactoryImpl, address expectedFactoryProxy) =
            computeExpectedAddresses(networkConfig.deployer);
        console.log("Expected Registry Implementation:", expectedRegImpl);
        console.log("Expected Registry Proxy:", expectedRegProxy);
        console.log("Expected AgreementFactory Implementation:", expectedFactoryImpl);
        console.log("Expected AgreementFactory Proxy:", expectedFactoryProxy);

        vm.startBroadcast();

        // Verify the broadcaster matches the configured deployer
        // This ensures the guarded salt will produce the expected addresses
        if (msg.sender != networkConfig.deployer) {
            revert DeployerMismatch(networkConfig.deployer, msg.sender);
        }

        // Deploy Registry Implementation
        registryImpl = deployRegistryImplementation();
        if (registryImpl != expectedRegImpl) {
            revert AddressMismatch(expectedRegImpl, registryImpl);
        }
        console.log("Registry Implementation deployed at:", registryImpl);

        // Deploy Registry Proxy (also sets valid chains during initialization)
        registryProxy = deployRegistryProxy();
        if (registryProxy != expectedRegProxy) {
            revert AddressMismatch(expectedRegProxy, registryProxy);
        }
        console.log("Registry Proxy deployed at:", registryProxy);

        // Deploy AgreementFactory Implementation
        agreementFactoryImpl = deployAgreementFactoryImplementation();
        if (agreementFactoryImpl != expectedFactoryImpl) {
            revert AddressMismatch(expectedFactoryImpl, agreementFactoryImpl);
        }
        console.log("AgreementFactory Implementation deployed at:", agreementFactoryImpl);

        // Deploy AgreementFactory Proxy
        agreementFactoryProxy = deployAgreementFactoryProxy();
        if (agreementFactoryProxy != expectedFactoryProxy) {
            revert AddressMismatch(expectedFactoryProxy, agreementFactoryProxy);
        }
        console.log("AgreementFactory Proxy deployed at:", agreementFactoryProxy);

        vm.stopBroadcast();
    }

    /*//////////////////////////////////////////////////////////////
                         DEPLOYMENT FUNCTIONS
    //////////////////////////////////////////////////////////////*/
    /// @notice Deploys the BattleChainSafeHarborRegistry implementation using CREATE3
    function deployRegistryImplementation() public returns (address) {
        ICreateX createx = ICreateX(networkConfig.createx);

        // Registry implementation has no constructor args (uses initializer)
        bytes memory initCode = type(BattleChainSafeHarborRegistry).creationCode;

        // Build guarded salt: [deployer (20 bytes)][0x00 (1 byte)][entropy (11 bytes)]
        bytes32 guardedSalt = buildGuardedSalt(networkConfig.deployer, helperConfig.REGISTRY_IMPL_ENTROPY());

        // Deploy using CREATE3 with guarded salt
        address deployed = createx.deployCreate3(guardedSalt, initCode);
        registryImpl = deployed;

        return deployed;
    }

    /// @notice Deploys the ERC1967Proxy for the registry using CREATE3
    function deployRegistryProxy() public returns (address) {
        ICreateX createx = ICreateX(networkConfig.createx);

        // Get valid chains from helper config
        string[] memory validChains = helperConfig.getValidChains();

        // Pre-compute factory and attack registry proxy addresses so we can pass them during initialization
        bytes32 factoryGuardedSalt = computeGuardedSalt(networkConfig.deployer, helperConfig.FACTORY_PROXY_ENTROPY());
        address expectedFactoryProxy = createx.computeCreate3Address(factoryGuardedSalt);

        bytes32 attackRegistryGuardedSalt =
            computeGuardedSalt(networkConfig.deployer, helperConfig.ATTACK_REGISTRY_PROXY_ENTROPY());
        address expectedAttackRegistryProxy = createx.computeCreate3Address(attackRegistryGuardedSalt);

        // Encode the initialize call with owner, valid chains, pre-computed factory, and attack registry
        bytes memory initData = abi.encodeWithSelector(
            BattleChainSafeHarborRegistry.initialize.selector,
            networkConfig.owner,
            validChains,
            expectedFactoryProxy,
            expectedAttackRegistryProxy
        );

        // Encode proxy constructor arguments (implementation, initData)
        bytes memory initCode = abi.encodePacked(type(ERC1967Proxy).creationCode, abi.encode(registryImpl, initData));

        // Build guarded salt: [deployer (20 bytes)][0x00 (1 byte)][entropy (11 bytes)]
        bytes32 guardedSalt = buildGuardedSalt(networkConfig.deployer, helperConfig.REGISTRY_PROXY_ENTROPY());

        // Deploy using CREATE3 with guarded salt
        address deployed = createx.deployCreate3(guardedSalt, initCode);
        registryProxy = deployed;

        return deployed;
    }

    /// @notice Deploys the AgreementFactory implementation using CREATE3
    function deployAgreementFactoryImplementation() public returns (address) {
        ICreateX createx = ICreateX(networkConfig.createx);

        // Factory implementation has no constructor args (uses initializer)
        bytes memory initCode = type(AgreementFactory).creationCode;

        // Build guarded salt: [deployer (20 bytes)][0x00 (1 byte)][entropy (11 bytes)]
        bytes32 guardedSalt = buildGuardedSalt(networkConfig.deployer, helperConfig.FACTORY_IMPL_ENTROPY());

        // Deploy using CREATE3 with guarded salt
        address deployed = createx.deployCreate3(guardedSalt, initCode);
        agreementFactoryImpl = deployed;

        return deployed;
    }

    /// @notice Deploys the ERC1967Proxy for the AgreementFactory using CREATE3
    function deployAgreementFactoryProxy() public returns (address) {
        ICreateX createx = ICreateX(networkConfig.createx);

        // Get BattleChain CAIP-2 chain ID
        string memory battleChainCaip2 = helperConfig.getBattleChainCaip2ChainId();

        // Encode the initialize call with owner, registry, and CAIP-2 chain ID
        bytes memory initData = abi.encodeWithSelector(
            AgreementFactory.initialize.selector, networkConfig.owner, registryProxy, battleChainCaip2
        );

        // Encode proxy constructor arguments (implementation, initData)
        bytes memory initCode =
            abi.encodePacked(type(ERC1967Proxy).creationCode, abi.encode(agreementFactoryImpl, initData));

        // Build guarded salt: [deployer (20 bytes)][0x00 (1 byte)][entropy (11 bytes)]
        bytes32 guardedSalt = buildGuardedSalt(networkConfig.deployer, helperConfig.FACTORY_PROXY_ENTROPY());

        // Deploy using CREATE3 with guarded salt
        address deployed = createx.deployCreate3(guardedSalt, initCode);
        agreementFactoryProxy = deployed;

        return deployed;
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

    /// @notice Computes the expected addresses for the deployed contracts
    /// @param deployer The address that will deploy the contracts
    function computeExpectedAddresses(address deployer)
        public
        view
        returns (
            address expectedRegImpl,
            address expectedRegProxy,
            address expectedFactoryImpl,
            address expectedFactoryProxy
        )
    {
        ICreateX createx = ICreateX(networkConfig.createx);

        // Compute the guarded salts that CreateX will use
        bytes32 regImplGuardedSalt = computeGuardedSalt(deployer, helperConfig.REGISTRY_IMPL_ENTROPY());
        bytes32 regProxyGuardedSalt = computeGuardedSalt(deployer, helperConfig.REGISTRY_PROXY_ENTROPY());
        bytes32 factoryImplGuardedSalt = computeGuardedSalt(deployer, helperConfig.FACTORY_IMPL_ENTROPY());
        bytes32 factoryProxyGuardedSalt = computeGuardedSalt(deployer, helperConfig.FACTORY_PROXY_ENTROPY());

        // Compute CREATE3 addresses using the guarded salts
        expectedRegImpl = createx.computeCreate3Address(regImplGuardedSalt);
        expectedRegProxy = createx.computeCreate3Address(regProxyGuardedSalt);
        expectedFactoryImpl = createx.computeCreate3Address(factoryImplGuardedSalt);
        expectedFactoryProxy = createx.computeCreate3Address(factoryProxyGuardedSalt);
    }
}
