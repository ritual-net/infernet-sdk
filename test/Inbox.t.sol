// SPDX-License-Identifier: BSD-3-Clause-Clear
pragma solidity ^0.8.4;

import {Test} from "forge-std/Test.sol";
import {Registry} from "../src/Registry.sol";
import {LibDeploy} from "./lib/LibDeploy.sol";
import {MockNode} from "./mocks/MockNode.sol";
import {Inbox, InboxItem} from "../src/Inbox.sol";
import {CoordinatorConstants} from "./Coordinator.t.sol";
import {DeliveredOutput} from "./mocks/consumer/Base.sol";
import {Coordinated} from "../src/utility/Coordinated.sol";
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
    EIP712Coordinator private COORDINATOR;

    /// @notice Inbox
    Inbox private INBOX;

    /// @notice Mock node (Alice)
    MockNode private ALICE;

    /// @notice Mock node (Bob)
    MockNode private BOB;

    /// @notice Mock subscription consumer
    MockSubscriptionConsumer private SUBSCRIPTION;

    /*//////////////////////////////////////////////////////////////
                                 SETUP
    //////////////////////////////////////////////////////////////*/

    function setUp() public {
        // Initialize contracts
        uint256 initialNonce = vm.getNonce(address(this));
        (Registry registry, EIP712Coordinator coordinator, Inbox inbox,,,) =
            LibDeploy.deployContracts(address(this), initialNonce, address(0), 0);

        // Assign to internal
        COORDINATOR = coordinator;
        INBOX = inbox;

        // Initialize mock nodes
        ALICE = new MockNode(registry);
        BOB = new MockNode(registry);

        // Initialize mock subscription consumer
        SUBSCRIPTION = new MockSubscriptionConsumer(address(registry));
    }

    /*//////////////////////////////////////////////////////////////
                                 TESTS
    //////////////////////////////////////////////////////////////*/

    /// @notice Nodes can store data to inbox
    function testFuzzNodesCanStoreDataToInbox(
        address node,
        uint32 timestamp,
        bytes32 containerId,
        bytes calldata input,
        bytes calldata output,
        bytes calldata proof
    ) public {
        // Assume address cannot be an existing MockNode
        vm.assume(node != address(ALICE));
        vm.assume(node != address(BOB));

        // Mock node address for full execution
        vm.startPrank(node);

        // Warp time to specified timestamp
        vm.warp(timestamp);

        // Write data to inbox (checking for correctly emitted event)
        vm.expectEmit(address(INBOX));
        emit NewInboxItem(containerId, node, 0);
        INBOX.write(containerId, input, output, proof);

        // Verify correct write via direct read
        InboxItem memory item = INBOX.read(containerId, node, 0);
        assertEq(item.timestamp, timestamp);
        assertEq(item.subscriptionId, 0);
        assertEq(item.interval, 0);
        assertEq(item.input, input);
        assertEq(item.output, output);
        assertEq(item.proof, proof);

        // Verify correct write via consumer with mock reader
        item = SUBSCRIPTION.readMockInbox(containerId, node, 0);
        assertEq(item.timestamp, timestamp);
        assertEq(item.subscriptionId, 0);
        assertEq(item.interval, 0);
        assertEq(item.input, input);
        assertEq(item.output, output);
        assertEq(item.proof, proof);
    }

    /// @notice Nodes can store data to inbox multiple times with different containerId's
    function testNodesCanStoreDataMultipleTimesDifferentPath() public {
        // Warp to initial timestamp
        uint256 initialTimestamp = 0;
        vm.warp(initialTimestamp);

        // Setup mock containerIds
        bytes32[] memory mockContainerIds = new bytes32[](2);
        mockContainerIds[0] = bytes32("1");
        mockContainerIds[1] = bytes32("2");

        for (uint256 i = 0; i < 2; i++) {
            // Collect mockContainerId
            bytes32 mockContainerId = mockContainerIds[i];

            // Write to {mockContainerIds[i], ALICE, 0}
            vm.expectEmit(address(INBOX));
            emit NewInboxItem(mockContainerId, address(ALICE), 0);
            ALICE.write(mockContainerId, MOCK_INPUT, MOCK_OUTPUT, MOCK_PROOF);

            // Verify written data
            InboxItem memory item = INBOX.read(mockContainerId, address(ALICE), 0);
            assertEq(item.timestamp, initialTimestamp);
            assertEq(item.subscriptionId, 0);
            assertEq(item.interval, 0);
            assertEq(item.input, MOCK_INPUT);
            assertEq(item.output, MOCK_OUTPUT);
            assertEq(item.proof, MOCK_PROOF);
        }
    }

    /// @notice Nodes can store data to inbox multiple times with same containerId's
    function testNodesCanStoreDataMultipleTimesSamePath() public {
        // Warp to initial timestamp
        uint256 initialTimestamp = 0;
        vm.warp(initialTimestamp);

        for (uint256 i = 0; i < 2; i++) {
            // Write to {containerId, ALICE, i}
            vm.expectEmit(address(INBOX));
            emit NewInboxItem(HASHED_MOCK_CONTAINER_ID, address(ALICE), i);
            ALICE.write(HASHED_MOCK_CONTAINER_ID, MOCK_INPUT, MOCK_OUTPUT, MOCK_PROOF);

            // Verify written data
            InboxItem memory item = INBOX.read(HASHED_MOCK_CONTAINER_ID, address(ALICE), i);
            assertEq(item.timestamp, initialTimestamp);
            assertEq(item.subscriptionId, 0);
            assertEq(item.interval, 0);
            assertEq(item.input, MOCK_INPUT);
            assertEq(item.output, MOCK_OUTPUT);
            assertEq(item.proof, MOCK_PROOF);
        }
    }

    /// @notice Nodes can store subscription data lazily
    function testNodesCanDeliverLazySubscription() public {
        // Warp to initial timestamp
        uint256 initialTimestamp = 0;
        vm.warp(initialTimestamp);

        // Create new subscription (replicating callback because frequency = 1)
        uint32 subId = SUBSCRIPTION.createMockSubscription(
            MOCK_CONTAINER_ID,
            1,
            1 minutes,
            1,
            true, // lazy
            NO_PAYMENT_TOKEN,
            0,
            NO_WALLET,
            NO_VERIFIER
        );

        // Deliver subscription from ALICE
        vm.warp(1 minutes);
        vm.expectEmit(address(INBOX));
        emit NewInboxItem(HASHED_MOCK_CONTAINER_ID, address(ALICE), 0);
        ALICE.deliverCompute(subId, 1, MOCK_INPUT, MOCK_OUTPUT, MOCK_PROOF, NO_WALLET);

        // Verify output is lazily delivered to subscriber
        DeliveredOutput memory out = SUBSCRIPTION.getDeliveredOutput(subId, 1, 1);
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
        InboxItem memory item = INBOX.read(HASHED_MOCK_CONTAINER_ID, address(ALICE), 0);
        assertEq(item.timestamp, initialTimestamp + 1 minutes);
        assertEq(item.subscriptionId, subId);
        assertEq(item.interval, 1);
        assertEq(item.input, MOCK_INPUT);
        assertEq(item.output, MOCK_OUTPUT);
        assertEq(item.proof, MOCK_PROOF);
    }

    /// @notice Nodes can store data via coordinator and directly for same containerId
    function testNodesCanDeliverDataViaCoordinatorAndDirectSamePath() public {
        // Warp to initial timestamp
        uint256 initialTimestamp = 0;
        vm.warp(initialTimestamp);

        // Write to {containerId, ALICE, 0}
        ALICE.write(HASHED_MOCK_CONTAINER_ID, MOCK_INPUT, MOCK_OUTPUT, MOCK_PROOF);

        // Create new subscription (replicating callback because frequency = 1)
        uint32 subId = SUBSCRIPTION.createMockSubscription(
            MOCK_CONTAINER_ID,
            1,
            1 minutes,
            1,
            true, // lazy
            NO_PAYMENT_TOKEN,
            0,
            NO_WALLET,
            NO_VERIFIER
        );

        // Deliver subscription from ALICE
        vm.warp(1 minutes);
        ALICE.deliverCompute(subId, 1, MOCK_INPUT, MOCK_OUTPUT, MOCK_PROOF, NO_WALLET);

        // Verify written data from direct write
        InboxItem memory item = INBOX.read(HASHED_MOCK_CONTAINER_ID, address(ALICE), 0);
        assertEq(item.timestamp, initialTimestamp);
        assertEq(item.subscriptionId, 0);
        assertEq(item.interval, 0);
        assertEq(item.input, MOCK_INPUT);
        assertEq(item.output, MOCK_OUTPUT);
        assertEq(item.proof, MOCK_PROOF);

        // Verify written data from authenticated write
        item = INBOX.read(HASHED_MOCK_CONTAINER_ID, address(ALICE), 1);
        assertEq(item.timestamp, 1 minutes);
        assertEq(item.subscriptionId, 1);
        assertEq(item.interval, 1);
        assertEq(item.input, MOCK_INPUT);
        assertEq(item.output, MOCK_OUTPUT);
        assertEq(item.proof, MOCK_PROOF);
    }

    /// @notice Multiple nodes can store data to the same containerId
    function testMultipleNodesCanStoreDataToInbox() public {
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
            vm.expectEmit(address(INBOX));
            emit NewInboxItem(HASHED_MOCK_CONTAINER_ID, address(node), 0);
            node.write(HASHED_MOCK_CONTAINER_ID, MOCK_INPUT, MOCK_OUTPUT, MOCK_PROOF);

            // Verify written data
            InboxItem memory item = INBOX.read(HASHED_MOCK_CONTAINER_ID, address(node), 0);
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
        vm.expectRevert(Coordinated.NotCoordinator.selector);
        INBOX.writeViaCoordinator(HASHED_MOCK_CONTAINER_ID, nonCoordinator, 1, 1, MOCK_INPUT, MOCK_OUTPUT, MOCK_PROOF);
    }

    /// @notice Mock node cannot call `writeViaCoordinator`
    function testNodeCannotCallAuthenticatedWrite() public {
        // Attempt to write data to inbox as ALICE
        vm.startPrank(address(ALICE));
        vm.expectRevert(Coordinated.NotCoordinator.selector);
        INBOX.writeViaCoordinator(HASHED_MOCK_CONTAINER_ID, address(ALICE), 1, 1, MOCK_INPUT, MOCK_OUTPUT, MOCK_PROOF);
    }

    /// @notice Coordinator can call `writeViaCoordinator`
    function testFuzzOnlyCoordinatorCanCallAuthenticatedWrite(
        uint32 timestamp,
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
        InboxItem memory item = INBOX.read(containerId, node, 0);
        assertEq(item.timestamp, timestamp);
        assertEq(item.subscriptionId, subscriptionId);
        assertEq(item.interval, interval);
        assertEq(item.input, input);
        assertEq(item.output, output);
        assertEq(item.proof, proof);

        // Verify correct write via consumer with inherited InboxReader
        item = SUBSCRIPTION.readMockInbox(containerId, node, 0);
        assertEq(item.timestamp, timestamp);
        assertEq(item.subscriptionId, subscriptionId);
        assertEq(item.interval, interval);
        assertEq(item.input, input);
        assertEq(item.output, output);
        assertEq(item.proof, proof);
    }

    /// @notice Correct immutable timestamp data is stored when writing data
    function testFuzzCorrectImmutableTimestampStored(uint32 timestamp) public {
        // Warp to timestamp
        vm.warp(timestamp);

        // Write to inbox as ALICE
        ALICE.write(HASHED_MOCK_CONTAINER_ID, MOCK_INPUT, MOCK_OUTPUT, MOCK_PROOF);

        // Verify correctly stored timestamp
        InboxItem memory item = INBOX.read(HASHED_MOCK_CONTAINER_ID, address(ALICE), 0);
        assertEq(item.timestamp, timestamp);
    }

    /// @notice Inbox items are ordered serially by time
    /// @dev This is largely a redundant test because time moves forward and so do array indices
    function testFuzzInboxItemsAreOrderedSeriallyByTime(uint32 startTimestamp) public {
        // Assume start timestamp + 10 is less than max uint32
        // Note: Best practice to use bound vs vm.assume here
        uint256 castStartTimestamp = bound(startTimestamp, 0, type(uint32).max - 10);

        // Iterate and write to inbox as ALICE
        for (uint256 ts = castStartTimestamp; ts < castStartTimestamp + 10; ts++) {
            // Warp to timestamp
            vm.warp(ts);

            // Write to inbox as ALICE
            ALICE.write(HASHED_MOCK_CONTAINER_ID, MOCK_INPUT, MOCK_OUTPUT, MOCK_PROOF);
        }

        // Verify that inbox items are ordered serially by time
        for (uint256 i = 0; i < 10; i++) {
            InboxItem memory item = INBOX.read(HASHED_MOCK_CONTAINER_ID, address(ALICE), i);
            assertEq(item.timestamp, castStartTimestamp + i);
        }
    }
}
