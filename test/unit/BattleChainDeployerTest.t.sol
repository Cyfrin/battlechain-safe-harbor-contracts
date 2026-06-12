// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import { Test } from "forge-std/Test.sol";
import { BattleChainDeployer } from "src/BattleChainDeployer.sol";
import { CreateX } from "src/CreateX.sol";
import { AttackRegistry } from "src/AttackRegistry.sol";
import { ERC1967Proxy } from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

/// @dev Minimal contract used as deployment payload in tests
contract SimpleContract {
    uint256 public value;

    constructor() payable {
        value = 42;
    }

    function initialize(uint256 _value) external {
        value = _value;
    }
}

/// @title BattleChainDeployerTest
/// @notice Tests that all BattleChainDeployer overloads register exactly once.
///         Delegating overloads that internally call another overload via virtual
///         dispatch will double-register and revert until the bug is fixed.
contract BattleChainDeployerTest is Test {
    BattleChainDeployer deployer;
    AttackRegistry attackRegistry;
    SimpleContract implementation;

    address owner = makeAddr("owner");

    function setUp() public {
        // Deploy AttackRegistry implementation
        AttackRegistry arImpl = new AttackRegistry();

        // Pre-compute proxy address so BattleChainDeployer can reference it.
        // Next two CREATEs: nonce → BattleChainDeployer, nonce+1 → ERC1967Proxy
        uint64 nonce = vm.getNonce(address(this));
        address predictedProxy = vm.computeCreateAddress(address(this), nonce + 1);

        // Deploy BattleChainDeployer pointing at the future proxy address
        deployer = new BattleChainDeployer(predictedProxy);

        // Deploy AttackRegistry proxy — lands at predictedProxy
        attackRegistry = AttackRegistry(
            address(
                new ERC1967Proxy(
                    address(arImpl),
                    abi.encodeCall(
                        AttackRegistry.initialize,
                        (owner, owner, address(1), address(1), address(deployer), owner)
                    )
                )
            )
        );
        assertEq(address(attackRegistry), predictedProxy, "proxy address mismatch");

        // Deploy an implementation for clone tests
        implementation = new SimpleContract();
    }

    /*//////////////////////////////////////////////////////////////
                              HELPERS
    //////////////////////////////////////////////////////////////*/

    function _initCode() internal pure returns (bytes memory) {
        return type(SimpleContract).creationCode;
    }

    function _initData() internal pure returns (bytes memory) {
        return abi.encodeCall(SimpleContract.initialize, (100));
    }

    function _zeroValues() internal pure returns (CreateX.Values memory) {
        return CreateX.Values({ constructorAmount: 0, initCallAmount: 0 });
    }

    /// @dev Salt with zero-address prefix + no redeploy protection.
    ///      Passes CreateX._guard as (ZeroAddress, False).
    function _salt() internal pure returns (bytes32) {
        return bytes32(0);
    }

    /*//////////////////////////////////////////////////////////////
        LEAF OVERLOADS — actually deploy, _registerDeployment once
    //////////////////////////////////////////////////////////////*/

    function testDeployCreate() public {
        address c = deployer.deployCreate(_initCode());
        assertTrue(c != address(0));
    }

    function testDeployCreateAndInit_4arg() public {
        address c = deployer.deployCreateAndInit(
            _initCode(), _initData(), _zeroValues(), address(this)
        );
        assertTrue(c != address(0));
    }

    function testDeployCreateClone() public {
        address c = deployer.deployCreateClone(
            address(implementation), _initData()
        );
        assertTrue(c != address(0));
    }

    function testDeployCreate2_withSalt() public {
        address c = deployer.deployCreate2(_salt(), _initCode());
        assertTrue(c != address(0));
    }

    function testDeployCreate2AndInit_5arg() public {
        address c = deployer.deployCreate2AndInit(
            _salt(), _initCode(), _initData(), _zeroValues(), address(this)
        );
        assertTrue(c != address(0));
    }

    function testDeployCreate2Clone_3arg() public {
        address c = deployer.deployCreate2Clone(
            _salt(), address(implementation), _initData()
        );
        assertTrue(c != address(0));
    }

    function testDeployCreate3_withSalt() public {
        address c = deployer.deployCreate3(_salt(), _initCode());
        assertTrue(c != address(0));
    }

    function testDeployCreate3AndInit_5arg() public {
        address c = deployer.deployCreate3AndInit(
            _salt(), _initCode(), _initData(), _zeroValues(), address(this)
        );
        assertTrue(c != address(0));
    }

    /*//////////////////////////////////////////////////////////////
        DELEGATING OVERLOADS — double-register bug
        These delegate to another overload via virtual dispatch.
        The leaf override registers once, then the delegating override
        tries to register the same address again, causing a revert.
        These tests expect success and will FAIL until the bug is fixed.
    //////////////////////////////////////////////////////////////*/

    // deployCreateAndInit(initCode, data, values)
    //   -> deployCreateAndInit(initCode, data, values, msg.sender)
    function testDeployCreateAndInit_3arg() public {
        address c = deployer.deployCreateAndInit(
            _initCode(), _initData(), _zeroValues()
        );
        assertTrue(c != address(0));
    }

    // deployCreate2(initCode)
    //   -> deployCreate2(_generateSalt(), initCode)
    function testDeployCreate2_noSalt() public {
        address c = deployer.deployCreate2(_initCode());
        assertTrue(c != address(0));
    }

    // deployCreate2AndInit(salt, initCode, data, values)
    //   -> deployCreate2AndInit(salt, initCode, data, values, msg.sender)
    function testDeployCreate2AndInit_4argWithSalt() public {
        address c = deployer.deployCreate2AndInit(
            _salt(), _initCode(), _initData(), _zeroValues()
        );
        assertTrue(c != address(0));
    }

    // deployCreate2AndInit(initCode, data, values, refundAddress)
    //   -> deployCreate2AndInit(_generateSalt(), initCode, data, values, refundAddress)
    function testDeployCreate2AndInit_4argWithRefund() public {
        address c = deployer.deployCreate2AndInit(
            _initCode(), _initData(), _zeroValues(), address(this)
        );
        assertTrue(c != address(0));
    }

    // deployCreate2AndInit(initCode, data, values)
    //   -> deployCreate2AndInit(_generateSalt(), initCode, data, values, msg.sender)
    function testDeployCreate2AndInit_3arg() public {
        address c = deployer.deployCreate2AndInit(
            _initCode(), _initData(), _zeroValues()
        );
        assertTrue(c != address(0));
    }

    // deployCreate2Clone(implementation, data)
    //   -> deployCreate2Clone(_generateSalt(), implementation, data)
    function testDeployCreate2Clone_2arg() public {
        address c = deployer.deployCreate2Clone(
            address(implementation), _initData()
        );
        assertTrue(c != address(0));
    }

    // deployCreate3(initCode)
    //   -> deployCreate3(_generateSalt(), initCode)
    function testDeployCreate3_noSalt() public {
        address c = deployer.deployCreate3(_initCode());
        assertTrue(c != address(0));
    }

    // deployCreate3AndInit(salt, initCode, data, values)
    //   -> deployCreate3AndInit(salt, initCode, data, values, msg.sender)
    function testDeployCreate3AndInit_4argWithSalt() public {
        address c = deployer.deployCreate3AndInit(
            _salt(), _initCode(), _initData(), _zeroValues()
        );
        assertTrue(c != address(0));
    }

    // deployCreate3AndInit(initCode, data, values, refundAddress)
    //   -> deployCreate3AndInit(_generateSalt(), initCode, data, values, refundAddress)
    function testDeployCreate3AndInit_4argWithRefund() public {
        address c = deployer.deployCreate3AndInit(
            _initCode(), _initData(), _zeroValues(), address(this)
        );
        assertTrue(c != address(0));
    }

    // deployCreate3AndInit(initCode, data, values)
    //   -> deployCreate3AndInit(_generateSalt(), initCode, data, values, msg.sender)
    function testDeployCreate3AndInit_3arg() public {
        address c = deployer.deployCreate3AndInit(
            _initCode(), _initData(), _zeroValues()
        );
        assertTrue(c != address(0));
    }
}
