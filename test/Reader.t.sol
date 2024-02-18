// SPDX-License-Identifier: BSD-3-Clause-Clear
pragma solidity ^0.8.4;

import {Test} from "forge-std/Test.sol";
import {Registry} from "../src/Registry.sol";
import {MockNode} from "./mocks/MockNode.sol";
import {LibDeploy} from "./lib/LibDeploy.sol";
import {stdError} from "forge-std/stdError.sol";
import {Reader} from "../src/utility/Reader.sol";
import {NodeManager} from "../src/NodeManager.sol";
import {Subscription} from "../src/Coordinator.sol";
import {CoordinatorConstants} from "./Coordinator.t.sol";
import {EIP712Coordinator} from "../src/EIP712Coordinator.sol";
import {MockSubscriptionConsumer} from "./mocks/consumer/Subscription.sol";

/// @title ReaderTest
/// @notice Tests Reader implementation
/// @dev Inherits `CoordinatorConstants` to borrow {containerId, input, output, proof}-mocks
contract ReaderTest is Test, CoordinatorConstants {
    /*//////////////////////////////////////////////////////////////
                                INTERNAL
    //////////////////////////////////////////////////////////////*/

    /// @notice EIP712Coordinator
    EIP712Coordinator internal COORDINATOR;

    /// @notice Reader
    Reader internal READER;

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
        (Registry registry, NodeManager nodeManager, EIP712Coordinator coordinator,, Reader reader) =
            LibDeploy.deployContracts(initialNonce);

        // Assign to internal
        COORDINATOR = coordinator;
        READER = reader;

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
            vm.warp(nodeManager.cooldown());
            node.activateNode();
        }

        // Initialize mock subscription consumer
        SUBSCRIPTION = new MockSubscriptionConsumer(address(registry));
    }

    /*//////////////////////////////////////////////////////////////
                                 TESTS
    //////////////////////////////////////////////////////////////*/

    /// @notice Can read single subscription
    function testCanReadSingleSubscription() public {
        // Create subscription
        vm.warp(0);
        uint32 subId = SUBSCRIPTION.createMockSubscription(
            MOCK_CONTAINER_ID,
            1 gwei,
            uint32(COORDINATOR.DELIVERY_OVERHEAD_WEI()) + COLD_EAGER_DELIVERY_COST,
            3,
            1 minutes,
            1,
            false
        );

        // Read via `Reader` and direct via `Coordinator`
        Subscription[] memory read = READER.readSubscriptionBatch(subId, subId + 1);
        Subscription memory actual = COORDINATOR.getSubscription(subId);

        // Assert batch length
        assertEq(read.length, 1);

        // Assert subscription parameters
        assertEq(read[0].owner, actual.owner);
        assertEq(read[0].activeAt, actual.activeAt);
        assertEq(read[0].period, actual.period);
        assertEq(read[0].frequency, actual.frequency);
        assertEq(read[0].redundancy, actual.redundancy);
        assertEq(read[0].maxGasPrice, actual.maxGasPrice);
        assertEq(read[0].maxGasLimit, actual.maxGasLimit);
        assertEq(read[0].containerId, actual.containerId);
        assertEq(read[0].lazy, actual.lazy);
    }

    /// @notice TODO: Can read batch subscriptions

    /// @notice Can read cancelled or non-existent subscription
    function testReadCancelledOrNonExistentSubscription() public {
        // Create subscription
        vm.warp(0);
        uint32 subId = SUBSCRIPTION.createMockSubscription(
            MOCK_CONTAINER_ID,
            1 gwei,
            uint32(COORDINATOR.DELIVERY_OVERHEAD_WEI()) + COLD_EAGER_DELIVERY_COST,
            3,
            1 minutes,
            1,
            false
        );

        // Cancel subscription
        SUBSCRIPTION.cancelMockSubscription(subId);

        // Attempt to read {subId, subId + 1}
        Subscription[] memory read = READER.readSubscriptionBatch(subId, subId + 2);

        // Assert batch length
        assertEq(read.length, 2);

        // Assert subscription parameters are nullified
        for (uint256 i = 0; i < read.length; i++) {
            assertEq(read[0].owner, address(0));
            assertEq(read[0].activeAt, 0);
            assertEq(read[0].period, 0);
            assertEq(read[0].frequency, 0);
            assertEq(read[0].redundancy, 0);
            assertEq(read[0].maxGasPrice, 0);
            assertEq(read[0].maxGasLimit, 0);
            assertEq(read[0].containerId, bytes32(0));
            assertEq(read[0].lazy, false);
        }
    }

    /// @notice Cannot read batch subscriptons where `endId` < `startId`
    function testCannotReadBatchSubscriptionsWhereIdOverOrUnderflow() public {
        // Expect arithmetic error on `length` calculation
        vm.expectRevert(stdError.arithmeticError);
        // Attempt to batch read where `endId` < `startId`
        READER.readSubscriptionBatch(5, 0);
    }

    /// @notice Can read redundancy counts
    function testCanReadRedundancyCounts() public {
        // Create first subscription (frequency = 2, redundancy = 2)
        vm.warp(0);
        uint32 subOne = SUBSCRIPTION.createMockSubscription(
            MOCK_CONTAINER_ID,
            1 gwei,
            uint32(COORDINATOR.DELIVERY_OVERHEAD_WEI()) + COLD_EAGER_DELIVERY_COST,
            2,
            1 minutes,
            2,
            false
        );

        // Create second subscription (frequency = 1, redundancy = 1)
        uint32 subTwo = SUBSCRIPTION.createMockSubscription(
            MOCK_CONTAINER_ID,
            1 gwei,
            uint32(COORDINATOR.DELIVERY_OVERHEAD_WEI()) + COLD_EAGER_DELIVERY_COST,
            1,
            1 minutes,
            1,
            false
        );

        // Deliver (id: subOne, interval: 1) from Alice + Bob
        // Deliver (id: subTwo, interval: 1) from Alice
        vm.warp(1 minutes);
        ALICE.deliverCompute(subOne, 1, MOCK_INPUT, MOCK_OUTPUT, MOCK_PROOF);
        BOB.deliverCompute(subOne, 1, MOCK_INPUT, MOCK_OUTPUT, MOCK_PROOF);
        ALICE.deliverCompute(subTwo, 1, MOCK_INPUT, MOCK_OUTPUT, MOCK_PROOF);

        // Deliver (id: subOne, interval: 2) from Alice
        vm.warp(2 minutes);
        ALICE.deliverCompute(subOne, 2, MOCK_INPUT, MOCK_OUTPUT, MOCK_PROOF);

        // Assert correct batch reads
        uint32[] memory ids = new uint32[](4);
        uint32[] memory intervals = new uint32[](4);
        uint16[] memory expectedRedundancyCounts = new uint16[](4);

        // (id: subOne, interval: 1) == 2
        ids[0] = subOne;
        intervals[0] = 1;
        expectedRedundancyCounts[0] = 2;

        // (id: subOne, interval: 2) == 1
        ids[1] = subOne;
        intervals[1] = 2;
        expectedRedundancyCounts[1] = 1;

        // (id: subTwo, interval: 1) == 1
        ids[2] = subTwo;
        intervals[2] = 1;
        expectedRedundancyCounts[2] = 1;

        // (id: subTwo, interval: 2) == 0
        ids[3] = subTwo;
        intervals[3] = 2;
        expectedRedundancyCounts[3] = 0;

        uint16[] memory actual = READER.readRedundancyCountBatch(ids, intervals);
        for (uint256 i = 0; i < 4; i++) {
            assertEq(actual[i], expectedRedundancyCounts[i]);
        }
    }

    /// @notice Can read redundancy counts for a deleted subscription post-delivery
    function testCanReadRedundancyCountPostSubscriptionDeletion() public {
        // Create subscription
        vm.warp(0);
        uint32 subId = SUBSCRIPTION.createMockSubscription(
            MOCK_CONTAINER_ID,
            1 gwei,
            uint32(COORDINATOR.DELIVERY_OVERHEAD_WEI()) + COLD_EAGER_DELIVERY_COST,
            3,
            1 minutes,
            2,
            false
        );

        // Deliver subscription
        vm.warp(1 minutes);
        uint32 interval = 1;
        ALICE.deliverCompute(subId, interval, MOCK_INPUT, MOCK_OUTPUT, MOCK_PROOF);

        // Cancel partially fulfilled subscription
        SUBSCRIPTION.cancelMockSubscription(subId);

        // Assert redundancy count still returns 1 for (id: subId, interval: 1)
        uint32[] memory ids = new uint32[](1);
        uint32[] memory intervals = new uint32[](1);
        ids[0] = subId;
        intervals[0] = interval;
        uint16[] memory counts = READER.readRedundancyCountBatch(ids, intervals);

        // Assert batch length
        assertEq(counts.length, 1);

        // Assert count is 1
        assertEq(counts[0], 1);
    }

    /// @notice Non-existent redundancy count returns `0`
    function testFuzzNonExistentSubscriptionIntervalReturns0RedundancyCount(uint32 subscriptionId, uint32 interval)
        public
    {
        // Collect redundancy count
        uint32[] memory ids = new uint32[](1);
        uint32[] memory intervals = new uint32[](1);
        ids[0] = subscriptionId;
        intervals[0] = interval;
        uint16[] memory counts = READER.readRedundancyCountBatch(ids, intervals);

        // Assert batch length
        assertEq(counts.length, 1);

        // Assert count is 0
        assertEq(counts[0], 0);
    }

    /// @notice Cannot read redundancy counts when input array lengths mismatch
    function testCannotReadRedundancyCountWhenInputArrayLengthsMismatch() public {
        // Create dummy arrays with length mismatch
        uint32[] memory ids = new uint32[](2);
        uint32[] memory intervals = new uint32[](1);

        // Populate with dummy (id, interval)-pairs
        ids[0] = 0;
        ids[1] = 1;
        intervals[0] = 0;

        // Attempt to batch read (catching OOBError in external contract)
        vm.expectRevert();
        READER.readRedundancyCountBatch(ids, intervals);
    }
}
