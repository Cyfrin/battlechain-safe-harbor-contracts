// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import { Script, console } from "forge-std/Script.sol";
import { HelperConfig } from "./HelperConfig.s.sol";
import { ICreateX } from "createx/ICreateX.sol";
import { AttackRegistry } from "src/AttackRegistry.sol";
import { BattleChainDeployer } from "src/BattleChainDeployer.sol";
import { ERC1967Proxy } from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

/// @title DeployAttackRegistry
/// @notice Deployment script for AttackRegistry using CREATE3 for deterministic addresses
/// @dev Uses CreateX guarded salts: only the designated deployer can deploy to the computed addresses
contract DeployAttackRegistry is Script {
    /*//////////////////////////////////////////////////////////////
                                ERRORS
    //////////////////////////////////////////////////////////////*/
    error AddressMismatch(address expected, address actual);
    error DeployerMismatch(address expected, address actual);
    error RegistryModeratorNotSet();
    error SafeHarborRegistryNotSet();
    error AgreementFactoryNotSet();

    /*//////////////////////////////////////////////////////////////
                            STATE VARIABLES
    //////////////////////////////////////////////////////////////*/
    HelperConfig public helperConfig;
    HelperConfig.NetworkConfig public networkConfig;
    bool private _initialized;

    /*//////////////////////////////////////////////////////////////
                          DEPLOYED ADDRESSES
    //////////////////////////////////////////////////////////////*/
    address public attackRegistryImpl;
    address public attackRegistryProxy;
    address public battleChainDeployer;

    /// @notice Sets the BattleChainDeployer address (for testing with mocks)
    function setBattleChainDeployerAddress(address _battleChainDeployer) external {
        battleChainDeployer = _battleChainDeployer;
    }

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
    /// @notice Deploy AttackRegistry with safeHarborRegistry and agreementFactory addresses
    /// @param safeHarborRegistry The address of the SafeHarborRegistry (must be deployed first)
    /// @param agreementFactory The address of the AgreementFactory (must be deployed first)
    function run(address safeHarborRegistry, address agreementFactory) external {
        initialize();

        // Validate required addresses
        if (networkConfig.registryModerator == address(0)) {
            revert RegistryModeratorNotSet();
        }
        if (safeHarborRegistry == address(0)) {
            revert SafeHarborRegistryNotSet();
        }
        if (agreementFactory == address(0)) {
            revert AgreementFactoryNotSet();
        }

        console.log("Deploying AttackRegistry...");
        console.log("Chain ID:", block.chainid);
        console.log("Owner:", networkConfig.owner);
        console.log("Deployer:", networkConfig.deployer);
        console.log("Registry Moderator:", networkConfig.registryModerator);
        console.log("Safe Harbor Registry:", safeHarborRegistry);
        console.log("Agreement Factory:", agreementFactory);
        console.log("CreateX:", networkConfig.createx);

        // Pre-flight: compute expected addresses and log them
        (address expectedImpl, address expectedProxy, address expectedBattleChainDeployer) =
            computeExpectedAddresses(networkConfig.deployer);
        console.log("Expected AttackRegistry Implementation:", expectedImpl);
        console.log("Expected AttackRegistry Proxy:", expectedProxy);
        console.log("Expected BattleChainDeployer:", expectedBattleChainDeployer);

        vm.startBroadcast();

        // Verify the broadcaster matches the configured deployer
        if (msg.sender != networkConfig.deployer) {
            revert DeployerMismatch(networkConfig.deployer, msg.sender);
        }

        // Deploy AttackRegistry Implementation
        attackRegistryImpl = deployAttackRegistryImplementation();
        if (attackRegistryImpl != expectedImpl) {
            revert AddressMismatch(expectedImpl, attackRegistryImpl);
        }
        console.log("AttackRegistry Implementation deployed at:", attackRegistryImpl);

        // Deploy BattleChainDeployer (uses pre-computed proxy address)
        battleChainDeployer = deployBattleChainDeployer(expectedProxy);
        if (battleChainDeployer != expectedBattleChainDeployer) {
            revert AddressMismatch(expectedBattleChainDeployer, battleChainDeployer);
        }
        console.log("BattleChainDeployer deployed at:", battleChainDeployer);

        // Deploy AttackRegistry Proxy (initialize wires up BattleChainDeployer)
        attackRegistryProxy = deployAttackRegistryProxy(safeHarborRegistry, agreementFactory);
        if (attackRegistryProxy != expectedProxy) {
            revert AddressMismatch(expectedProxy, attackRegistryProxy);
        }
        console.log("AttackRegistry Proxy deployed at:", attackRegistryProxy);

        vm.stopBroadcast();
    }

    /*//////////////////////////////////////////////////////////////
                         DEPLOYMENT FUNCTIONS
    //////////////////////////////////////////////////////////////*/
    /// @notice Deploys the AttackRegistry implementation using CREATE3
    function deployAttackRegistryImplementation() public returns (address) {
        ICreateX createx = ICreateX(networkConfig.createx);

        // AttackRegistry implementation has no constructor args (uses initializer)
        bytes memory initCode = type(AttackRegistry).creationCode;

        // Build guarded salt: [deployer (20 bytes)][0x00 (1 byte)][entropy (11 bytes)]
        bytes32 guardedSalt = buildGuardedSalt(networkConfig.deployer, helperConfig.ATTACK_REGISTRY_IMPL_ENTROPY());

        // Deploy using CREATE3 with guarded salt
        address deployed = createx.deployCreate3(guardedSalt, initCode);
        attackRegistryImpl = deployed;

        return deployed;
    }

    /// @notice Deploys the ERC1967Proxy for the AttackRegistry using CREATE3
    /// @param safeHarborRegistry The address of the SafeHarborRegistry
    /// @param agreementFactory The address of the AgreementFactory
    function deployAttackRegistryProxy(address safeHarborRegistry, address agreementFactory) public returns (address) {
        ICreateX createx = ICreateX(networkConfig.createx);

        // Encode the initialize call
        bytes memory initData = abi.encodeWithSelector(
            AttackRegistry.initialize.selector,
            networkConfig.owner,
            networkConfig.registryModerator,
            safeHarborRegistry,
            agreementFactory,
            battleChainDeployer,
            networkConfig.treasury
        );

        // Encode proxy constructor arguments (implementation, initData)
        bytes memory initCode =
            abi.encodePacked(type(ERC1967Proxy).creationCode, abi.encode(attackRegistryImpl, initData));

        // Build guarded salt: [deployer (20 bytes)][0x00 (1 byte)][entropy (11 bytes)]
        bytes32 guardedSalt = buildGuardedSalt(networkConfig.deployer, helperConfig.ATTACK_REGISTRY_PROXY_ENTROPY());

        // Deploy using CREATE3 with guarded salt
        address deployed = createx.deployCreate3(guardedSalt, initCode);
        attackRegistryProxy = deployed;

        return deployed;
    }

    /// @notice Deploys the BattleChainDeployer using CREATE3
    /// @param attackRegistryProxyAddress The pre-computed address of the AttackRegistry proxy
    function deployBattleChainDeployer(address attackRegistryProxyAddress) public returns (address) {
        ICreateX createx = ICreateX(networkConfig.createx);

        // BattleChainDeployer constructor takes the AttackRegistry address
        bytes memory initCode =
            abi.encodePacked(type(BattleChainDeployer).creationCode, abi.encode(attackRegistryProxyAddress));

        // Build guarded salt: [deployer (20 bytes)][0x00 (1 byte)][entropy (11 bytes)]
        bytes32 guardedSalt = buildGuardedSalt(networkConfig.deployer, helperConfig.BATTLECHAIN_DEPLOYER_ENTROPY());

        // Deploy using CREATE3 with guarded salt
        address deployed = createx.deployCreate3(guardedSalt, initCode);
        battleChainDeployer = deployed;

        return deployed;
    }

    /*//////////////////////////////////////////////////////////////
                           HELPER FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /// @notice Builds a guarded salt for CreateX CREATE3 deployment
    /// @dev Salt structure: [deployer (20 bytes)][0x00 (1 byte)][entropy (11 bytes)]
    /// @param deployer The address that is allowed to deploy using this salt
    /// @param entropy The unique 11-byte identifier for this contract
    /// @return salt The 32-byte guarded salt
    function buildGuardedSalt(address deployer, bytes11 entropy) public pure returns (bytes32 salt) {
        salt = bytes32(abi.encodePacked(deployer, bytes1(0x00), entropy));
    }

    /// @notice Computes the guarded salt that CreateX will use internally
    /// @dev CreateX hashes the salt with msg.sender when the first 20 bytes match msg.sender
    /// @param deployer The deployer address embedded in the salt
    /// @param entropy The entropy portion of the salt
    /// @return guardedSalt The salt that CreateX will actually use for CREATE3
    function computeGuardedSalt(address deployer, bytes11 entropy) public pure returns (bytes32 guardedSalt) {
        bytes32 inputSalt = buildGuardedSalt(deployer, entropy);
        guardedSalt = keccak256(abi.encodePacked(bytes32(uint256(uint160(deployer))), inputSalt));
    }

    /// @notice Computes the expected addresses for the deployed contracts
    /// @param deployer The address that will deploy the contracts
    function computeExpectedAddresses(address deployer)
        public
        view
        returns (address expectedImpl, address expectedProxy, address expectedBattleChainDeployer)
    {
        ICreateX createx = ICreateX(networkConfig.createx);

        // Compute the guarded salts that CreateX will use
        bytes32 implGuardedSalt = computeGuardedSalt(deployer, helperConfig.ATTACK_REGISTRY_IMPL_ENTROPY());
        bytes32 proxyGuardedSalt = computeGuardedSalt(deployer, helperConfig.ATTACK_REGISTRY_PROXY_ENTROPY());
        bytes32 battleChainDeployerGuardedSalt =
            computeGuardedSalt(deployer, helperConfig.BATTLECHAIN_DEPLOYER_ENTROPY());

        // Compute CREATE3 addresses using the guarded salts
        expectedImpl = createx.computeCreate3Address(implGuardedSalt);
        expectedProxy = createx.computeCreate3Address(proxyGuardedSalt);
        expectedBattleChainDeployer = createx.computeCreate3Address(battleChainDeployerGuardedSalt);
    }
}
