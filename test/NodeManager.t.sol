// SPDX-License-Identifier: BSD-3-Clause-Clear
pragma solidity ^0.8.4;

import {Test} from "forge-std/Test.sol";
import {NodeManager} from "../src/NodeManager.sol";
import {Registry} from "../src/Registry.sol";
import {MockNode} from "./mocks/MockNode.sol";
import {Ownable} from "solady/auth/Ownable.sol";
import {MockNodeManager} from "./mocks/MockNodeManager.sol";
import {EIP712Coordinator} from "../src/EIP712Coordinator.sol";

/// @title IManagerEvents
/// @notice Events emitted by Manager
interface IManagerEvents {
    event NodeActivated(address indexed node);
    event NodeDeactivated(address indexed node);
    event NodeRegistered(address indexed node, address indexed registerer, uint32 cooldownStart);
}

/// @title ManagerTest
/// @notice Tests Manager implementation
contract NodeManagerTest is Test, IManagerEvents {
    /*//////////////////////////////////////////////////////////////
                                INTERNAL
    //////////////////////////////////////////////////////////////*/

    /// @notice Manager
    MockNodeManager internal MANAGER;

    /// @notice Mock node (Alice)
    MockNode internal ALICE;

    /// @notice Mock node (Bob)
    MockNode internal BOB;

    /*//////////////////////////////////////////////////////////////
                                 SETUP
    //////////////////////////////////////////////////////////////*/

    function setUp() public {
        // Initialize coordinator
        address managerAddr = vm.computeCreateAddress(address(this), 2);
        address coordinatorAddr = vm.computeCreateAddress(address(this), 3);
        Registry registry = new Registry(managerAddr, coordinatorAddr);

        // Initialize manager
        MANAGER = new MockNodeManager();

        // Initialize mock nodes
        // Overriding manager to parent type of EIP712Coordinator
        ALICE = new MockNode(EIP712Coordinator(address(registry)), MANAGER);
        BOB = new MockNode(EIP712Coordinator(address(registry)), MANAGER);
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
        vm.expectEmit(address(MANAGER));
        emit NodeRegistered(aliceAddress, aliceAddress, uint32(startTimestamp));
        MANAGER.registerNode(aliceAddress);

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
        vm.expectEmit(address(MANAGER));
        emit NodeRegistered(aliceAddress, bobAddress, uint32(startTimestamp));
        MANAGER.registerNode(aliceAddress);

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

        vm.warp(block.timestamp + MANAGER.cooldown());
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

        vm.warp(startTimestamp + MANAGER.cooldown());
        // Activate Alice
        vm.expectEmit(address(MANAGER));
        emit NodeActivated(address(ALICE));
        ALICE.activateNode();

        // Check states
        assertEq(ALICE.isActiveNode(), true);
        assertEq(ALICE.cooldownStart(), 0);
        ALICE.assertNodeStatus(NodeManager.NodeStatus.Active);
    }

    /// @notice Check cannot activate node before cooldown has elapsed
    function testFuzzCannotActivateNodeBeforeCooldownElapsed(uint256 elapsed) public {
        uint256 startTimestamp = 10 minutes;
        vm.warp(startTimestamp);

        // Force elapsed to be under cooldown
        vm.assume(elapsed < MANAGER.cooldown());

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
        vm.warp(block.timestamp + MANAGER.cooldown());
        ALICE.activateNode();

        // Attempt to re-activate Alice
        vm.expectRevert(
            abi.encodeWithSelector(NodeManager.NodeNotActivateable.selector, uint8(NodeManager.NodeStatus.Active))
        );
        ALICE.activateNode();
    }

    /// @notice Check that active nodes can call onlyActiveNode functions
    function testCanCallOnlyActiveNodeFnAsActiveNode() public {
        // Activate Alice
        ALICE.registerNode(address(ALICE));
        vm.warp(block.timestamp + MANAGER.cooldown());
        ALICE.activateNode();

        // Attempt to call onlyActiveNode-modified function
        assertEq(ALICE.isActiveNode(), true);
    }

    /// @notice Check inactive nodes cannot call onlyActiveNode functions
    function testCannnotCallOnlyActiveNodeFnAsInactiveNode() public {
        vm.expectRevert(NodeManager.NodeNotActive.selector);
        ALICE.isActiveNode();
    }

    /// @notice Check registered nodes cannot call onlyActiveNode functions
    function testCannotCallOnlyActiveNodeFnAsRegisteredNode() public {
        ALICE.registerNode(address(ALICE));
        vm.expectRevert(NodeManager.NodeNotActive.selector);
        ALICE.isActiveNode();
    }

    /// @notice Check that node can go to an inactive state from inactive
    function testCanDeactivateInactiveNode() public {
        ALICE.assertNodeStatus(NodeManager.NodeStatus.Inactive);
        vm.expectEmit(address(MANAGER));
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
        vm.expectEmit(address(MANAGER));
        emit NodeDeactivated(address(ALICE));
        ALICE.deactivateNode();
        ALICE.assertNodeStatus(NodeManager.NodeStatus.Inactive);
    }

    /// @notice Check that node can go to an inactive state from Active
    function testCanDeactivateActiveNode() public {
        // Activate Alice
        ALICE.registerNode(address(ALICE));
        vm.warp(block.timestamp + MANAGER.cooldown());
        ALICE.activateNode();

        // Deactivate node
        vm.expectEmit(address(MANAGER));
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

        vm.warp(startTimestamp + MANAGER.cooldown());
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
        uint256 newCooldownStart = startTimestamp + MANAGER.cooldown();
        assertEq(ALICE.cooldownStart(), newCooldownStart);

        // Expect re-activation to fail if not administering full cooldown
        vm.warp(newCooldownStart + MANAGER.cooldown() - 1 seconds);
        vm.expectRevert(abi.encodeWithSelector(NodeManager.CooldownActive.selector, newCooldownStart));
        ALICE.activateNode();

        // Expect re-activation to succeed if complying with new cooldown
        vm.warp(newCooldownStart + MANAGER.cooldown());
        ALICE.activateNode();

        // Assert Alice status and new cooldown
        ALICE.assertNodeStatus(NodeManager.NodeStatus.Active);
        assertEq(ALICE.cooldownStart(), 0);
    }
}
