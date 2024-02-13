// SPDX-License-Identifier: BSD-3-Clause-Clear
pragma solidity ^0.8.4;

import {Inbox} from "../src/Inbox.sol";
import {Test} from "forge-std/Test.sol";
import {Registry} from "../src/Registry.sol";
import {LibDeploy} from "./lib/LibDeploy.sol";
import {LibStruct} from "./lib/LibStruct.sol";
import {MockNode} from "./mocks/MockNode.sol";
import {NodeManager} from "../src/NodeManager.sol";
import {CoordinatorConstants} from "./Coordinator.t.sol";
import {EIP712Coordinator} from "../src/EIP712Coordinator.sol";
import {MockSubscriptionConsumer} from "./mocks/consumer/Subscription.sol";

/// @title IInboxEvents
/// @notice Events emitted by Inbox
interface IInboxEvents {
    event NewInboxItem(bytes32 indexed containerId, address indexed node, uint256 index);
}

/// @title InboxTest
/// @notice Tests Inbox implementation
/// @dev Inherits `CoordinatorConstants` to borrow {containerId, input, output, proof}-mocks
contract InboxTest is Test, IInboxEvents, CoordinatorConstants {
    /*//////////////////////////////////////////////////////////////
                                INTERNAL
    //////////////////////////////////////////////////////////////*/

    /// @notice EIP712Coordinator
    EIP712Coordinator internal COORDINATOR;

    /// @notice NodeManager
    NodeManager internal NODE_MANAGER;

    /// @notice Inbox
    Inbox internal INBOX;

    /// @notice Mock node (Alice)
    MockNode internal ALICE;

    /// @notice Mock node (Bob)
    MockNode internal BOB;

    /// @notice Mock subscription consumer
    MockSubscriptionConsumer internal SUBSCRIPTION;

    /*//////////////////////////////////////////////////////////////
                                 SETUP
    //////////////////////////////////////////////////////////////*/

    function setUp() public {
        // Initialize contracts
        uint256 initialNonce = vm.getNonce(address(this));
        (Registry registry, NodeManager nodeManager, EIP712Coordinator coordinator, Inbox inbox) =
            LibDeploy.deployContracts(initialNonce);

        // Assign to internal
        COORDINATOR = coordinator;
        NODE_MANAGER = nodeManager;
        INBOX = inbox;

        // Initialize mock nodes
        ALICE = new MockNode(registry);
        BOB = new MockNode(registry);

        // For each node
        MockNode[2] memory nodes = [ALICE, BOB];
        for (uint256 i = 0; i < 2; i++) {
            // Select node
            MockNode node = nodes[i];

            // Activate nodes
            vm.warp(0);
            node.registerNode(address(node));
            vm.warp(NODE_MANAGER.cooldown());
            node.activateNode();
        }

        // Initialize mock subscription consumer
        SUBSCRIPTION = new MockSubscriptionConsumer(address(registry));
    }

    /*//////////////////////////////////////////////////////////////
                                 TESTS
    //////////////////////////////////////////////////////////////*/

    /// @notice Active nodes can store data to inbox
    function testFuzzActiveNodesCanStoreDataToInbox(
        address node,
        uint256 timestamp,
        bytes32 containerId,
        bytes calldata input,
        bytes calldata output,
        bytes calldata proof
    ) public {
        // Mock node address for full execution
        vm.startPrank(node);

        // Register and activate node
        vm.warp(0);
        NODE_MANAGER.registerNode(node);
        vm.warp(NODE_MANAGER.cooldown());
        NODE_MANAGER.activateNode();

        // Warp time to specified timestamp
        vm.warp(timestamp);

        // Write data to inbox (checking for correctly emitted event)
        vm.expectEmit(address(INBOX));
        emit NewInboxItem(containerId, node, 0);
        INBOX.write(containerId, input, output, proof);

        // Verify correct write via direct read
        LibStruct.InboxItem memory item = LibStruct.getInboxItem(INBOX, containerId, node, 0);
        assertEq(item.timestamp, timestamp);
        assertEq(item.subscriptionId, 0);
        assertEq(item.interval, 0);
        assertEq(item.input, input);
        assertEq(item.output, output);
        assertEq(item.proof, proof);

        // Verify correct write via consumer with inherited InboxReader
        (
            uint32 readTimestamp,
            uint32 readSubscriptionId,
            uint32 readInterval,
            bytes memory readInput,
            bytes memory readOutput,
            bytes memory readProof
        ) = SUBSCRIPTION.readMockInbox(containerId, node, 0);
        assertEq(readTimestamp, timestamp);
        assertEq(readSubscriptionId, 0);
        assertEq(readInterval, 0);
        assertEq(readInput, input);
        assertEq(readOutput, output);
        assertEq(readProof, proof);
    }

    /// @notice Inactive nodes cannot store data to inbox
    function testFuzzInactiveNodesCannotStoreDataToInbox(address node) public {
        // Assume address cannot be an active node (ALICE, BOB)
        vm.assume(node != address(ALICE));
        vm.assume(node != address(BOB));

        // Attempt to write data to inbox as inactive node
        vm.startPrank(node);
        vm.expectRevert(Inbox.NodeNotActive.selector);
        INBOX.write(HASHED_MOCK_CONTAINER_ID, MOCK_INPUT, MOCK_OUTPUT, MOCK_PROOF);
    }

    /// @notice Registered nodes cannot store data to inbox
    function testFuzzRegisteredNodesCannotStoreDataToInbox(address node) public {
        // Assume address cannot be an active node (ALICE, BOB)
        vm.assume(node != address(ALICE));
        vm.assume(node != address(BOB));

        // Mock node address for full execution
        vm.startPrank(node);

        // Register node
        vm.warp(0);
        NODE_MANAGER.registerNode(node);

        // Attempt to write data to inbox as registered node
        vm.expectRevert(Inbox.NodeNotActive.selector);
        INBOX.write(HASHED_MOCK_CONTAINER_ID, MOCK_INPUT, MOCK_OUTPUT, MOCK_PROOF);
    }

    /// @notice Active nodes can store data to inbox multiple times with different containerId's
    function testActiveNodesCanStoreDataMultipleTimesDifferentPath() public {
        // Warp to initial timestamp
        uint256 initialTimestamp = 0;
        vm.warp(initialTimestamp);

        // Setup mock containerIds
        bytes32[] memory mockContainerIds = new bytes32[](2);
        mockContainerIds[0] = "1";
        mockContainerIds[1] = "2";

        for (uint256 i = 0; i < 2; i++) {
            // Collect mockContainerId
            bytes32 mockContainerId = mockContainerIds[i];

            // Write to {mockContainerIds[i], ALICE, 0}
            vm.expectEmit(address(ALICE));
            emit NewInboxItem(mockContainerId, address(ALICE), 0);
            ALICE.write(mockContainerId, MOCK_INPUT, MOCK_OUTPUT, MOCK_PROOF);

            // Verify written data
            LibStruct.InboxItem memory item = LibStruct.getInboxItem(INBOX, mockContainerId, address(ALICE), 0);
            assertEq(item.timestamp, initialTimestamp);
            assertEq(item.subscriptionId, 0);
            assertEq(item.interval, 0);
            assertEq(item.input, MOCK_INPUT);
            assertEq(item.output, MOCK_OUTPUT);
            assertEq(item.proof, MOCK_PROOF);
        }
    }

    /// @notice Active nodes can store data to inbox multiple times with same containerId's
    function testActiveNodesCanStoreDataMultipleTimesSamePath() public {
        // Warp to initial timestamp
        uint256 initialTimestamp = 0;
        vm.warp(initialTimestamp);

        for (uint256 i = 0; i < 2; i++) {
            // Write to {containerId, ALICE, i}
            vm.expectEmit(address(ALICE));
            emit NewInboxItem(HASHED_MOCK_CONTAINER_ID, address(ALICE), i);
            ALICE.write(HASHED_MOCK_CONTAINER_ID, MOCK_INPUT, MOCK_OUTPUT, MOCK_PROOF);

            // Verify written data
            LibStruct.InboxItem memory item = LibStruct.getInboxItem(INBOX, HASHED_MOCK_CONTAINER_ID, address(ALICE), i);
            assertEq(item.timestamp, initialTimestamp);
            assertEq(item.subscriptionId, 0);
            assertEq(item.interval, 0);
            assertEq(item.input, MOCK_INPUT);
            assertEq(item.output, MOCK_OUTPUT);
            assertEq(item.proof, MOCK_PROOF);
        }
    }

    /// @notice Active nodes can store subscription data lazily
    function testActiveNodesCanDeliverLazySubscription() public {
        // Warp to initial timestamp
        uint256 initialTimestamp = 0;
        vm.warp(initialTimestamp);

        // Create new subscription (replicating callback because frequency = 1)
        uint32 subId = SUBSCRIPTION.createMockSubscription(
            MOCK_CONTAINER_ID,
            1 gwei,
            uint32(COORDINATOR.DELIVERY_OVERHEAD_WEI()) + COLD_DELIVERY_COST,
            1,
            1 minutes,
            1,
            true // lazy
        );

        // Deliver subscription from ALICE
        vm.warp(1 minutes);
        vm.expectEmit(address(INBOX));
        emit NewInboxItem(HASHED_MOCK_CONTAINER_ID, address(ALICE), 0);
        ALICE.deliverCompute(subId, 1, MOCK_INPUT, MOCK_OUTPUT, MOCK_PROOF);

        // Verify output is lazily delivered to subscriber
        LibStruct.DeliveredOutput memory out = LibStruct.getDeliveredOutput(SUBSCRIPTION, subId, 1, 1);
        assertEq(out.subscriptionId, subId);
        assertEq(out.interval, 1);
        assertEq(out.redundancy, 1);
        assertEq(out.node, address(ALICE));
        assertEq(out.input, "");
        assertEq(out.output, "");
        assertEq(out.proof, "");
        assertEq(out.containerId, HASHED_MOCK_CONTAINER_ID);
        assertEq(out.index, 0);

        // Verify written data
        LibStruct.InboxItem memory item = LibStruct.getInboxItem(INBOX, HASHED_MOCK_CONTAINER_ID, address(ALICE), 0);
        assertEq(item.timestamp, initialTimestamp + 1 minutes);
        assertEq(item.subscriptionId, subId);
        assertEq(item.interval, 1);
        assertEq(item.input, MOCK_INPUT);
        assertEq(item.output, MOCK_OUTPUT);
        assertEq(item.proof, MOCK_PROOF);
    }

    /// @notice Active nodes can store data via coordinator and directly for same containerId
    function testActiveNodesCanDeliverDataViaCoordinatorAndDirectSamePath() public {
        // Warp to initial timestamp
        uint256 initialTimestamp = 0;
        vm.warp(initialTimestamp);

        // Write to {containerId, ALICE, 0}
        ALICE.write(HASHED_MOCK_CONTAINER_ID, MOCK_INPUT, MOCK_OUTPUT, MOCK_PROOF);

        // Create new subscription (replicating callback because frequency = 1)
        uint32 subId = SUBSCRIPTION.createMockSubscription(
            MOCK_CONTAINER_ID,
            1 gwei,
            uint32(COORDINATOR.DELIVERY_OVERHEAD_WEI()) + COLD_DELIVERY_COST,
            1,
            1 minutes,
            1,
            true // lazy
        );

        // Deliver subscription from ALICE
        vm.warp(1 minutes);
        ALICE.deliverCompute(subId, 1, MOCK_INPUT, MOCK_OUTPUT, MOCK_PROOF);

        // Verify written data from direct write
        LibStruct.InboxItem memory item = LibStruct.getInboxItem(INBOX, HASHED_MOCK_CONTAINER_ID, address(ALICE), 0);
        assertEq(item.timestamp, initialTimestamp);
        assertEq(item.subscriptionId, 0);
        assertEq(item.interval, 0);
        assertEq(item.input, MOCK_INPUT);
        assertEq(item.output, MOCK_OUTPUT);
        assertEq(item.proof, MOCK_PROOF);

        // Verify written data from authenticated write
        item = LibStruct.getInboxItem(INBOX, HASHED_MOCK_CONTAINER_ID, address(ALICE), 1);
        assertEq(item.timestamp, 1 minutes);
        assertEq(item.subscriptionId, 1);
        assertEq(item.interval, 1);
        assertEq(item.input, MOCK_INPUT);
        assertEq(item.output, MOCK_OUTPUT);
        assertEq(item.proof, MOCK_PROOF);
    }

    /// @notice Multiple active nodes can store data to the same containerId
    function testMultipleActiveNodesCanStoreDataToInbox() public {
        // Warp to initial timestamp
        uint256 initialTimestamp = 0;
        vm.warp(initialTimestamp);

        // Setup delivering nodes
        MockNode[] memory nodes = new MockNode[](2);
        nodes[0] = ALICE;
        nodes[1] = BOB;

        for (uint256 i = 0; i < 2; i++) {
            // Collect node
            MockNode node = nodes[i];

            // Write to {containerId, node, 0}
            vm.expectEmit(address(node));
            emit NewInboxItem(HASHED_MOCK_CONTAINER_ID, address(node), i);
            node.write(HASHED_MOCK_CONTAINER_ID, MOCK_INPUT, MOCK_OUTPUT, MOCK_PROOF);

            // Verify written data
            LibStruct.InboxItem memory item = LibStruct.getInboxItem(INBOX, HASHED_MOCK_CONTAINER_ID, address(node), 0);
            assertEq(item.timestamp, initialTimestamp);
            assertEq(item.subscriptionId, 0);
            assertEq(item.interval, 0);
            assertEq(item.input, MOCK_INPUT);
            assertEq(item.output, MOCK_OUTPUT);
            assertEq(item.proof, MOCK_PROOF);
        }
    }

    /// @notice Non-coordinator address cannot call `writeViaCoordinator`
    function testFuzzNonCoordinatorAddressCannotCallAuthenticatedWrite(address nonCoordinator) public {
        // Assume address cannot be coordinator itself
        vm.assume(nonCoordinator != address(COORDINATOR));

        // Attempt to write data to inbox as coordinator
        vm.startPrank(nonCoordinator);
        vm.expectRevert(Inbox.NotCoordinator.selector);
        INBOX.writeViaCoordinator(HASHED_MOCK_CONTAINER_ID, nonCoordinator, 1, 1, MOCK_INPUT, MOCK_OUTPUT, MOCK_PROOF);
    }

    /// @notice Mock node cannot call `writeViaCoordinator`
    function testActiveNodeCannotCallAuthenticatedWrite() public {
        // Attempt to write data to inbox as ALICE
        vm.startPrank(address(ALICE));
        vm.expectRevert(Inbox.NotCoordinator.selector);
        INBOX.writeViaCoordinator(HASHED_MOCK_CONTAINER_ID, address(ALICE), 1, 1, MOCK_INPUT, MOCK_OUTPUT, MOCK_PROOF);
    }

    /// @notice Coordinator can call `writeViaCoordinator`
    function testFuzzOnlyCoordinatorCanCallAuthenticatedWrite(
        uint256 timestamp,
        bytes32 containerId,
        address node,
        uint32 subscriptionId,
        uint32 interval,
        bytes calldata input,
        bytes calldata output,
        bytes calldata proof
    ) public {
        // Warp to timestamp
        vm.warp(timestamp);

        // Mock coordinator address for full execution
        vm.startPrank(address(COORDINATOR));

        // Write data to inbox as coordinator via authenticated write
        vm.expectEmit(address(INBOX));
        emit NewInboxItem(containerId, node, 0);
        INBOX.writeViaCoordinator(containerId, node, subscriptionId, interval, input, output, proof);

        // Verify correct write via direct read
        LibStruct.InboxItem memory item = LibStruct.getInboxItem(INBOX, containerId, node, 0);
        assertEq(item.timestamp, timestamp);
        assertEq(item.subscriptionId, subscriptionId);
        assertEq(item.interval, interval);
        assertEq(item.input, input);
        assertEq(item.output, output);
        assertEq(item.proof, proof);

        // Verify correct write via consumer with inherited InboxReader
        (
            uint32 readTimestamp,
            uint32 readSubscriptionId,
            uint32 readInterval,
            bytes memory readInput,
            bytes memory readOutput,
            bytes memory readProof
        ) = SUBSCRIPTION.readMockInbox(containerId, node, 0);
        assertEq(readTimestamp, timestamp);
        assertEq(readSubscriptionId, subscriptionId);
        assertEq(readInterval, interval);
        assertEq(readInput, input);
        assertEq(readOutput, output);
        assertEq(readProof, proof);
    }

    /// @notice Correct immutable timestamp data is stored when writing data
    function testFuzzCorrectImmutableTimestampStored(uint256 timestamp) public {
        // Warp to timestamp
        vm.warp(timestamp);

        // Write to inbox as ALICE
        ALICE.write(HASHED_MOCK_CONTAINER_ID, MOCK_INPUT, MOCK_OUTPUT, MOCK_PROOF);

        // Verify correctly stored timestamp
        LibStruct.InboxItem memory item = LibStruct.getInboxItem(INBOX, HASHED_MOCK_CONTAINER_ID, address(ALICE), 0);
        assertEq(item.timestamp, timestamp);
    }

    /// @notice Inbox items are ordered serially by time
    /// @dev This is largely a redundant test because time moves forward and so do array indices
    function testFuzzInboxItemsAreOrderedSeriallyByTime(uint256 startTimestamp) public {
        // Assume start timestamp + 10 is less than or equal to max uint256
        vm.assume(startTimestamp + 10 <= UINT256_MAX);

        // Iterate and write to inbox as ALICE
        for (uint256 timestamp = startTimestamp; timestamp < startTimestamp + 10; timestamp++) {
            // Warp to timestamp
            vm.warp(timestamp);

            // Write to inbox as ALICE
            ALICE.write(HASHED_MOCK_CONTAINER_ID, MOCK_INPUT, MOCK_OUTPUT, MOCK_PROOF);
        }

        // Verify that inbox items are ordered serially by time
        for (uint256 i = 0; i < 10; i++) {
            LibStruct.InboxItem memory item = LibStruct.getInboxItem(INBOX, HASHED_MOCK_CONTAINER_ID, address(ALICE), i);
            assertEq(item.timestamp, startTimestamp + i);
        }
    }
}
