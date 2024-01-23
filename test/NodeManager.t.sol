// SPDX-License-Identifier: BSD-3-Clause-Clear
pragma solidity ^0.8.4;

import {Test} from "forge-std/Test.sol";
import {Registry} from "../src/Registry.sol";
import {MockNode} from "./mocks/MockNode.sol";
import {Ownable} from "solady/auth/Ownable.sol";
import {NodeManager} from "../src/NodeManager.sol";
import {EIP712Coordinator} from "../src/EIP712Coordinator.sol";

/// @title INodeManagerEvents
/// @notice Events emitted by NodeManager
interface INodeManagerEvents {
    event NodeActivated(address indexed node);
    event NodeDeactivated(address indexed node);
    event NodeRegistered(address indexed node, address indexed registerer, uint32 cooldownStart);
}

/// @title NodeManagerTest
/// @notice Tests NodeManager implementation
contract NodeManagerTest is Test, INodeManagerEvents {
    /*//////////////////////////////////////////////////////////////
                                INTERNAL
    //////////////////////////////////////////////////////////////*/

    /// @notice NodeManager
    NodeManager internal NODE_MANAGER;

    /// @notice Mock node (Alice)
    MockNode internal ALICE;

    /// @notice Mock node (Bob)
    MockNode internal BOB;

    /*//////////////////////////////////////////////////////////////
                                 SETUP
    //////////////////////////////////////////////////////////////*/

    function setUp() public {
        // Precompute addresses for {NodeManager, Coordinator}
        uint256 registryDeployNonce = 1;
        address nodeManagerAddress = vm.computeCreateAddress(address(this), registryDeployNonce + 1);
        address coordinatorAddress = vm.computeCreateAddress(address(this), registryDeployNonce + 2);

        // Initialize registry
        Registry registry = new Registry(nodeManagerAddress, coordinatorAddress);

        // Initialize node manager
        NODE_MANAGER = new NodeManager();

        // Initialize mock nodes
        ALICE = new MockNode(registry);
        BOB = new MockNode(registry);
    }

    /*//////////////////////////////////////////////////////////////
                                 TESTS
    //////////////////////////////////////////////////////////////*/

    /// @notice Check can register inactive node
    function testCanRegisterInactiveNode() public {
        uint256 startTimestamp = 10 minutes;
        vm.warp(startTimestamp);

        // Make calls as Alice
        address aliceAddress = address(ALICE);
        vm.startPrank(aliceAddress);

        // Ensure starting cooldown is at timestamp 0
        assertEq(ALICE.cooldownStart(), 0);
        assertEq(BOB.cooldownStart(), 0);

        // Register Alice by self
        vm.expectEmit(address(NODE_MANAGER));
        emit NodeRegistered(aliceAddress, aliceAddress, uint32(startTimestamp));
        NODE_MANAGER.registerNode(aliceAddress);

        // Check new node statuses
        ALICE.assertNodeStatus(NodeManager.NodeStatus.Registered);
        BOB.assertNodeStatus(NodeManager.NodeStatus.Inactive);

        // Check cooldown start timestamps
        assertEq(ALICE.cooldownStart(), startTimestamp);
        assertEq(BOB.cooldownStart(), 0);
    }

    /// @notice Check can register inactive node via proxy
    function testCanRegisterInactiveNodeViaProxy() public {
        uint256 startTimestamp = 10 minutes;
        vm.warp(startTimestamp);

        // Make calls as Bob
        address bobAddress = address(BOB);
        address aliceAddress = address(ALICE);
        vm.startPrank(bobAddress);

        // Ensure starting cooldown is at timestamp 0
        assertEq(ALICE.cooldownStart(), 0);
        assertEq(BOB.cooldownStart(), 0);

        // Register Alice with Bob as registrar
        vm.expectEmit(address(NODE_MANAGER));
        emit NodeRegistered(aliceAddress, bobAddress, uint32(startTimestamp));
        NODE_MANAGER.registerNode(aliceAddress);

        // Check new node statuses
        ALICE.assertNodeStatus(NodeManager.NodeStatus.Registered);
        BOB.assertNodeStatus(NodeManager.NodeStatus.Inactive);

        // Check cooldown start timestamps
        assertEq(ALICE.cooldownStart(), startTimestamp);
        assertEq(BOB.cooldownStart(), 0);
    }

    /// @notice Check registered node cannot re-register
    function testCannotReregisterNode() public {
        // Register Alice
        ALICE.registerNode(address(ALICE));
        ALICE.assertNodeStatus(NodeManager.NodeStatus.Registered);

        // Ensure revert if trying to register again
        vm.expectRevert(
            abi.encodeWithSelector(
                NodeManager.NodeNotRegisterable.selector, address(ALICE), uint8(NodeManager.NodeStatus.Registered)
            )
        );
        ALICE.registerNode(address(ALICE));
    }

    /// @notice Check cannot register node if node is Active
    function testCannotRegisterActiveNode() public {
        // Register Alice
        ALICE.registerNode(address(ALICE));

        vm.warp(block.timestamp + NODE_MANAGER.cooldown());
        // Activate Alice
        ALICE.activateNode();

        // Ensure revert if trying to register
        vm.expectRevert(
            abi.encodeWithSelector(
                NodeManager.NodeNotRegisterable.selector, address(ALICE), uint8(NodeManager.NodeStatus.Active)
            )
        );
        ALICE.registerNode(address(ALICE));
    }

    /// @notice Check can activate a node
    function testActivateNode() public {
        uint256 startTimestamp = 10 minutes;
        vm.warp(startTimestamp);

        // Register Alice
        ALICE.registerNode(address(ALICE));

        vm.warp(startTimestamp + NODE_MANAGER.cooldown());
        // Activate Alice
        vm.expectEmit(address(NODE_MANAGER));
        emit NodeActivated(address(ALICE));
        ALICE.activateNode();

        // Check states
        assertEq(NODE_MANAGER.isActiveNode(address(ALICE)), true);
        assertEq(ALICE.cooldownStart(), 0);
        ALICE.assertNodeStatus(NodeManager.NodeStatus.Active);
    }

    /// @notice Check cannot activate node before cooldown has elapsed
    function testFuzzCannotActivateNodeBeforeCooldownElapsed(uint256 elapsed) public {
        uint256 startTimestamp = 10 minutes;
        vm.warp(startTimestamp);

        // Force elapsed to be under cooldown
        vm.assume(elapsed < NODE_MANAGER.cooldown());

        // Register Alice
        ALICE.registerNode(address(ALICE));

        vm.warp(startTimestamp + elapsed);
        // Ensure revert when attempting to activate Alice
        vm.expectRevert(abi.encodeWithSelector(NodeManager.CooldownActive.selector, startTimestamp));
        ALICE.activateNode();
    }

    /// @notice Check cannot activate node if node is inactive
    function testCannotActivateInactiveNode() public {
        // Attempt to activate without registering
        vm.expectRevert(
            abi.encodeWithSelector(NodeManager.NodeNotActivateable.selector, uint8(NodeManager.NodeStatus.Inactive))
        );
        ALICE.activateNode();
    }

    /// @notice Check cannot re-activate node
    function testCannotReactivateNode() public {
        // Activate Alice
        ALICE.registerNode(address(ALICE));
        vm.warp(block.timestamp + NODE_MANAGER.cooldown());
        ALICE.activateNode();

        // Attempt to re-activate Alice
        vm.expectRevert(
            abi.encodeWithSelector(NodeManager.NodeNotActivateable.selector, uint8(NodeManager.NodeStatus.Active))
        );
        ALICE.activateNode();
    }

    /// @notice Check active nodes return true when checking `isActiveNode()`
    function testCanCallOnlyActiveNodeFnAsActiveNode() public {
        // Activate Alice
        ALICE.registerNode(address(ALICE));
        vm.warp(block.timestamp + NODE_MANAGER.cooldown());
        ALICE.activateNode();

        // Check `isActiveNode()`
        assertEq(NODE_MANAGER.isActiveNode(address(ALICE)), true);
    }

    /// @notice Check inactive nodes return false when checking `isActiveNode()`
    function testInactiveNodesReturnFalseWithIsActiveNode() public {
        assertEq(NODE_MANAGER.isActiveNode(address(ALICE)), false);
    }

    /// @notice Check registered nodes return false when checking `isActiveNode()`
    function testRegisteredNodesReturnFalseWithIsActiveNode() public {
        ALICE.registerNode(address(ALICE));
        assertEq(NODE_MANAGER.isActiveNode(addess(ALICE)), false);
    }

    /// @notice Check that node can go to an inactive state from inactive
    function testCanDeactivateInactiveNode() public {
        ALICE.assertNodeStatus(NodeManager.NodeStatus.Inactive);
        vm.expectEmit(address(NODE_MANAGER));
        emit NodeDeactivated(address(ALICE));
        ALICE.deactivateNode();
        ALICE.assertNodeStatus(NodeManager.NodeStatus.Inactive);
    }

    /// @notice Check that node can go to an inactive state from registered
    function testCanDeactivateRegisteredNode() public {
        // Register Alice
        ALICE.registerNode(address(ALICE));
        ALICE.assertNodeStatus(NodeManager.NodeStatus.Registered);

        // Deactive Alice
        vm.expectEmit(address(NODE_MANAGER));
        emit NodeDeactivated(address(ALICE));
        ALICE.deactivateNode();
        ALICE.assertNodeStatus(NodeManager.NodeStatus.Inactive);
    }

    /// @notice Check that node can go to an inactive state from Active
    function testCanDeactivateActiveNode() public {
        // Activate Alice
        ALICE.registerNode(address(ALICE));
        vm.warp(block.timestamp + NODE_MANAGER.cooldown());
        ALICE.activateNode();

        // Deactivate node
        vm.expectEmit(address(NODE_MANAGER));
        emit NodeDeactivated(address(ALICE));
        ALICE.deactivateNode();
        ALICE.assertNodeStatus(NodeManager.NodeStatus.Inactive);
    }

    function testActivateNodeMustReadministerCooldownIfReactivating() public {
        uint256 startTimestamp = 10 minutes;
        vm.warp(startTimestamp);

        // Register Alice
        ALICE.registerNode(address(ALICE));

        // Assert Alice status and cooldown
        ALICE.assertNodeStatus(NodeManager.NodeStatus.Registered);
        assertEq(ALICE.cooldownStart(), startTimestamp);

        vm.warp(startTimestamp + NODE_MANAGER.cooldown());
        // Activate Alice
        ALICE.activateNode();

        // Assert Alice status and nullifed cooldown
        ALICE.assertNodeStatus(NodeManager.NodeStatus.Active);
        assertEq(ALICE.cooldownStart(), 0);

        // Deactive Alice
        ALICE.deactivateNode();

        // Assert Alice status and nullified cooldown
        ALICE.assertNodeStatus(NodeManager.NodeStatus.Inactive);
        assertEq(ALICE.cooldownStart(), 0);

        // Re-register Alice
        ALICE.registerNode(address(ALICE));

        // Assert Alice status and new cooldown
        ALICE.assertNodeStatus(NodeManager.NodeStatus.Registered);
        uint256 newCooldownStart = startTimestamp + NODE_MANAGER.cooldown();
        assertEq(ALICE.cooldownStart(), newCooldownStart);

        // Expect re-activation to fail if not administering full cooldown
        vm.warp(newCooldownStart + NODE_MANAGER.cooldown() - 1 seconds);
        vm.expectRevert(abi.encodeWithSelector(NodeManager.CooldownActive.selector, newCooldownStart));
        ALICE.activateNode();

        // Expect re-activation to succeed if complying with new cooldown
        vm.warp(newCooldownStart + NODE_MANAGER.cooldown());
        ALICE.activateNode();

        // Assert Alice status and new cooldown
        ALICE.assertNodeStatus(NodeManager.NodeStatus.Active);
        assertEq(ALICE.cooldownStart(), 0);
    }
}
