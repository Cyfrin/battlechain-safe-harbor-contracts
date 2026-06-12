// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import { Script, console2 } from "forge-std/Script.sol";
import { CreateX } from "test/mock/MockCreateX.sol";
import { BATTLECHAIN_SAFE_HARBOR_VERSION_TAG } from "src/Version.sol";

/// @title HelperConfig for BattleChain Safe Harbor Registry Deployments
/// @notice Provides deployment configuration for the BattleChain ecosystem
contract HelperConfig is Script {
    /*//////////////////////////////////////////////////////////////
                                 ERRORS
    //////////////////////////////////////////////////////////////*/
    error HelperConfig__InvalidChainId();

    /*//////////////////////////////////////////////////////////////
                                 STRUCTS
    //////////////////////////////////////////////////////////////*/
    struct NetworkConfig {
        address owner;
        address createx;
        address deployer; // The address that will deploy contracts (for CREATE3 guarded salts)
        address registryModerator; // The DAO multisig that approves attacks
        address treasury; // Receives bond fees immediately on collection
    }

    /*//////////////////////////////////////////////////////////////
                               CONSTANTS
    //////////////////////////////////////////////////////////////*/
    address public constant CREATEX_ADDRESS = 0xba5Ed099633D3B313e4D5F7bdc1305d3c28ba5Ed;
    uint256 public constant LOCAL_CHAIN_ID = 31_337;
    address public constant DEFAULT_ANVIL_OWNER = 0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266;

    // BattleChain ecosystem chain IDs
    uint256 public constant BATTLECHAIN_CHAIN_ID = 626;
    uint256 public constant BATTLECHAIN_TESTNET_ID = 627;
    uint256 public constant BATTLECHAIN_DEVNET_ID = 624;

    // BattleChain CAIP-2 chain identifiers
    string public constant BATTLECHAIN_CAIP2 = "eip155:626";
    string public constant BATTLECHAIN_TESTNET_CAIP2 = "eip155:627";
    string public constant BATTLECHAIN_DEVNET_CAIP2 = "eip155:624";

    /*//////////////////////////////////////////////////////////////
                         CREATEX SALT ENTROPY
    //////////////////////////////////////////////////////////////*/
    /// @dev Salt entropy values (11 bytes each) for CreateX guarded salts
    /// The full salt structure is: [deployer (20 bytes)][0x00 (1 byte)][entropy (11 bytes)]
    /// - deployer: restricts deployment to this address only
    /// - 0x00: allows same address across all chains (no cross-chain redeploy protection)
    /// - entropy: unique identifier for each contract, versioned via BATTLECHAIN_SAFE_HARBOR_VERSION_TAG
    bytes11 public constant REGISTRY_IMPL_ENTROPY = bytes11(
        keccak256(bytes(string.concat("BattleChain.SafeHarbor.Registry.Impl.", BATTLECHAIN_SAFE_HARBOR_VERSION_TAG)))
    );
    bytes11 public constant REGISTRY_PROXY_ENTROPY = bytes11(
        keccak256(bytes(string.concat("BattleChain.SafeHarbor.Registry.Proxy.", BATTLECHAIN_SAFE_HARBOR_VERSION_TAG)))
    );
    bytes11 public constant FACTORY_IMPL_ENTROPY = bytes11(
        keccak256(
            bytes(string.concat("BattleChain.SafeHarbor.AgreementFactory.Impl.", BATTLECHAIN_SAFE_HARBOR_VERSION_TAG))
        )
    );
    bytes11 public constant FACTORY_PROXY_ENTROPY = bytes11(
        keccak256(
            bytes(string.concat("BattleChain.SafeHarbor.AgreementFactory.Proxy.", BATTLECHAIN_SAFE_HARBOR_VERSION_TAG))
        )
    );
    bytes11 public constant ATTACK_REGISTRY_IMPL_ENTROPY = bytes11(
        keccak256(
            bytes(string.concat("BattleChain.SafeHarbor.AttackRegistry.Impl.", BATTLECHAIN_SAFE_HARBOR_VERSION_TAG))
        )
    );
    bytes11 public constant ATTACK_REGISTRY_PROXY_ENTROPY = bytes11(
        keccak256(
            bytes(string.concat("BattleChain.SafeHarbor.AttackRegistry.Proxy.", BATTLECHAIN_SAFE_HARBOR_VERSION_TAG))
        )
    );
    bytes11 public constant BATTLECHAIN_DEPLOYER_ENTROPY = bytes11(
        keccak256(
            bytes(string.concat("BattleChain.SafeHarbor.BattleChainDeployer.", BATTLECHAIN_SAFE_HARBOR_VERSION_TAG))
        )
    );

    /*//////////////////////////////////////////////////////////////
                            STATE VARIABLES
    //////////////////////////////////////////////////////////////*/
    NetworkConfig public activeNetworkConfig;
    address private deployedCreateX;

    /*//////////////////////////////////////////////////////////////
                              CONSTRUCTOR
    //////////////////////////////////////////////////////////////*/
    constructor() {
        if (block.chainid == BATTLECHAIN_CHAIN_ID) {
            activeNetworkConfig = getBattleChainConfig();
        } else if (block.chainid == BATTLECHAIN_TESTNET_ID) {
            activeNetworkConfig = getBattleChainTestnetConfig();
        } else if (block.chainid == BATTLECHAIN_DEVNET_ID) {
            activeNetworkConfig = getBattleChainDevnetConfig();
        } else if (block.chainid == LOCAL_CHAIN_ID) {
            activeNetworkConfig = getOrCreateAnvilConfig();
        } else {
            revert HelperConfig__InvalidChainId();
        }
    }

    /*//////////////////////////////////////////////////////////////
                           NETWORK CONFIGS
    //////////////////////////////////////////////////////////////*/
    /// @notice Gets the network config for the current chain
    function getNetworkConfig() public returns (NetworkConfig memory) {
        console2.log("Getting network config for chain ID:", block.chainid);
        if (block.chainid == LOCAL_CHAIN_ID && activeNetworkConfig.createx == address(0)) {
            activeNetworkConfig = getOrCreateAnvilConfig();
        }
        return activeNetworkConfig;
    }

    function getBattleChainConfig() public pure returns (NetworkConfig memory) {
        return NetworkConfig({
            owner: 0xfA26440c6DDc56C93A9248078e13a5eB050ADb1E, // New multisig
            createx: 0xa397f06F07251A3AEd53f6d3019A2a6cbd83E53e,
            deployer: 0x3846c3A30E62075Fa916216b35EF04B8F53931f6,
            registryModerator: 0x445d5685c4Ae71550Da0716b82B434AEA140E0c7, // New multisig
            treasury: 0x2B1731F5EedBa4141a66C6F81C5290BF61d3325c // New multisig
        });
    }

    function getBattleChainTestnetConfig() public pure returns (NetworkConfig memory) {
        return NetworkConfig({
            owner: 0x277D26a45Add5775F21256159F089769892CEa5B,
            createx: 0xf1Ebfaa992854ECcB01Ac1F60e5b5279095cca7F,
            deployer: 0x9f111F96520157bCaA3301d948bF7c68189e7AAa,
            registryModerator: 0x277D26a45Add5775F21256159F089769892CEa5B,
            treasury: 0xf6dBa02C01AF48Cf926579F77C9f874Ca640D91D
        });
    }

    function getBattleChainDevnetConfig() public pure returns (NetworkConfig memory) {
        return NetworkConfig({
            owner: address(0), // TODO: Set BattleChain devnet owner
            createx: CREATEX_ADDRESS,
            deployer: address(0), // TODO: Set BattleChain devnet deployer
            registryModerator: address(0), // TODO: Set BattleChain devnet DAO multisig
            treasury: address(0) // TODO: Set BattleChain devnet treasury
        });
    }

    /*//////////////////////////////////////////////////////////////
                             LOCAL CONFIG
    //////////////////////////////////////////////////////////////*/
    function getOrCreateAnvilConfig() public returns (NetworkConfig memory) {
        // If already deployed, return cached config
        if (deployedCreateX != address(0)) {
            return NetworkConfig({
                owner: DEFAULT_ANVIL_OWNER,
                createx: deployedCreateX,
                deployer: DEFAULT_ANVIL_OWNER,
                registryModerator: DEFAULT_ANVIL_OWNER,
                treasury: DEFAULT_ANVIL_OWNER
            });
        }

        // Note: block.number must be >= 32 for CreateX to work (it does block.number - 32)
        if (block.number < 100) {
            vm.roll(100);
        }

        // Deploy MockCreateX locally
        CreateX createx = new CreateX();
        deployedCreateX = address(createx);

        return NetworkConfig({
            owner: DEFAULT_ANVIL_OWNER,
            createx: deployedCreateX,
            deployer: DEFAULT_ANVIL_OWNER,
            registryModerator: DEFAULT_ANVIL_OWNER,
            treasury: DEFAULT_ANVIL_OWNER
        });
    }

    /*//////////////////////////////////////////////////////////////
                               HELPERS
    //////////////////////////////////////////////////////////////*/
    /// @notice Returns true if running on a local chain (anvil)
    function isLocalChain() public view returns (bool) {
        return block.chainid == LOCAL_CHAIN_ID;
    }

    /// @notice Returns the CAIP-2 chain identifier for the current chain
    /// @dev For local testing, defaults to BattleChain mainnet CAIP-2
    function getBattleChainCaip2ChainId() public view returns (string memory) {
        if (block.chainid == BATTLECHAIN_CHAIN_ID) {
            return BATTLECHAIN_CAIP2;
        } else if (block.chainid == BATTLECHAIN_TESTNET_ID) {
            return BATTLECHAIN_TESTNET_CAIP2;
        } else if (block.chainid == BATTLECHAIN_DEVNET_ID) {
            return BATTLECHAIN_DEVNET_CAIP2;
        } else {
            // For local testing, default to mainnet CAIP-2
            return BATTLECHAIN_CAIP2;
        }
    }

    /*//////////////////////////////////////////////////////////////
                             VALID CHAINS
    //////////////////////////////////////////////////////////////*/
    /// @notice Returns the list of valid CAIP-2 chain IDs for BattleChain Safe Harbor agreements
    /// @dev Only BattleChain ecosystem chains are valid
    function getValidChains() public pure returns (string[] memory) {
        string[] memory chains = new string[](3);
        chains[0] = "eip155:626"; // BattleChain Mainnet
        chains[1] = "eip155:627"; // BattleChain Testnet
        chains[2] = "eip155:624"; // BattleChain Devnet
        return chains;
    }
}
