// SPDX-License-Identifier: BSD-3-Clause-Clear
pragma solidity ^0.8.4;

import {Test} from "forge-std/Test.sol";
import {Manager} from "../src/Manager.sol";
import {LibStruct} from "./lib/LibStruct.sol";
import {MockNode} from "./mocks/MockNode.sol";
import {Ownable} from "solady/auth/Ownable.sol";
import {Coordinator} from "../src/Coordinator.sol";
import {BaseConsumer} from "../src/consumer/Base.sol";
import {MockBaseConsumer} from "./mocks/consumer/Base.sol";
import {EIP712Coordinator} from "../src/EIP712Coordinator.sol";
import {MockCallbackConsumer} from "./mocks/consumer/Callback.sol";
import {MockSubscriptionConsumer} from "./mocks/consumer/Subscription.sol";

/// @title ICoordinatorEvents
/// @notice Events emitted by Coordinator
interface ICoordinatorEvents {
    event SubscriptionCreated(uint32 indexed id);
    event SubscriptionCancelled(uint32 indexed id);
    event SubscriptionFulfilled(uint32 indexed id, address indexed node);
}

/// @title CoordinatorConstants
/// @notice Base constants setup to inherit for Coordinator subtests
abstract contract CoordinatorConstants {
    /*//////////////////////////////////////////////////////////////
                               CONSTANTS
    //////////////////////////////////////////////////////////////*/

    /// @notice Mock compute container ID
    string constant MOCK_CONTAINER_ID = "container";

    /// @notice Mock container inputs
    bytes constant MOCK_CONTAINER_INPUTS = "inputs";

    /// @notice Mock delivered container input
    /// @dev Example of a hashed input (encoding hash(MOCK_CONTAINER_INPUTS) into input) field
    bytes constant MOCK_INPUT = abi.encode(keccak256(abi.encode(MOCK_CONTAINER_INPUTS)));

    /// @notice Mock delivered container compute output
    bytes constant MOCK_OUTPUT = "output";

    /// @notice Mock delivered proof
    bytes constant MOCK_PROOF = "proof";

    /// @notice Cold cost of CallbackConsumer.rawReceiveCompute
    /// @dev Inputs: (uint32, uint32, uint16, MOCK_INPUT, MOCK_OUTPUT, MOCK_PROOF)
    uint32 constant COLD_DELIVERY_COST_CALLBACK = 115_076 wei;

    /// @notice Cold cost of SubscriptionConsumer.rawReceiveCompute
    /// @dev Inputs: (uint32, uint32, uint16, MOCK_INPUT, MOCK_OUTPUT, MOCK_PROOF)
    uint32 constant COLD_DELIVERY_COST_SUBSCRIPTION = 115_160 wei;
}

/// @title CoordinatorTest
/// @notice Base setup to inherit for Coordinator subtests
abstract contract CoordinatorTest is Test, CoordinatorConstants, ICoordinatorEvents {
    /*//////////////////////////////////////////////////////////////
                                INTERNAL
    //////////////////////////////////////////////////////////////*/

    /// @notice Coordinator
    Coordinator internal COORDINATOR;

    /// @notice Mock node (Alice)
    MockNode internal ALICE;

    /// @notice Mock node (Bob)
    MockNode internal BOB;

    /// @notice Mock node (Charlie)
    MockNode internal CHARLIE;

    /// @notice Mock callback consumer
    MockCallbackConsumer internal CALLBACK;

    /// @notice Mock subscription consumer
    MockSubscriptionConsumer internal SUBSCRIPTION;

    /*//////////////////////////////////////////////////////////////
                                 SETUP
    //////////////////////////////////////////////////////////////*/

    function setUp() public {
        // Initialize coordinator
        COORDINATOR = new Coordinator();

        // Initalize mock nodes
        // Forcefully cast to EIP712Coordinator (not using additional functionality in current tests)
        ALICE = new MockNode(EIP712Coordinator(address(COORDINATOR)));
        BOB = new MockNode(EIP712Coordinator(address(COORDINATOR)));
        CHARLIE = new MockNode(EIP712Coordinator(address(COORDINATOR)));

        // For each node
        MockNode[3] memory nodes = [ALICE, BOB, CHARLIE];
        for (uint256 i = 0; i < 3; i++) {
            // Select node
            MockNode node = nodes[i];

            // Activate node
            vm.warp(0);
            node.registerNode(address(node));
            vm.warp(COORDINATOR.cooldown());
            node.activateNode();
        }

        // Initialize mock callback consumer
        CALLBACK = new MockCallbackConsumer(
            address(COORDINATOR)
        );

        // Initialize mock subscription consumer
        SUBSCRIPTION = new MockSubscriptionConsumer(
            address(COORDINATOR)
        );
    }
}

/// @title CoordinatorGeneralTest
/// @notice General coordinator tests
contract CoordinatorGeneralTest is CoordinatorTest {
    /// @notice Cannot be reassigned a subscription ID
    function testCannotBeReassignedSubscriptionID() public {
        // Create new callback subscription
        uint32 id = CALLBACK.createMockRequest(MOCK_CONTAINER_ID, MOCK_CONTAINER_INPUTS, 1 gwei, 100_000, 1);
        assertEq(id, 1);

        // Create new subscriptions
        CALLBACK.createMockRequest(MOCK_CONTAINER_ID, MOCK_CONTAINER_INPUTS, 1 gwei, 100_000, 1);
        CALLBACK.createMockRequest(MOCK_CONTAINER_ID, MOCK_CONTAINER_INPUTS, 1 gwei, 100_000, 1);
        CALLBACK.createMockRequest(MOCK_CONTAINER_ID, MOCK_CONTAINER_INPUTS, 1 gwei, 100_000, 1);

        // Assert head
        assertEq(COORDINATOR.id(), 5);

        // Delete subscriptions
        vm.startPrank(address(CALLBACK));
        COORDINATOR.cancelSubscription(1);
        COORDINATOR.cancelSubscription(3);

        // Assert head
        assertEq(COORDINATOR.id(), 5);

        // Create new subscription
        id = CALLBACK.createMockRequest(MOCK_CONTAINER_ID, MOCK_CONTAINER_INPUTS, 1 gwei, 100_000, 1);
        assertEq(id, 5);
        assertEq(COORDINATOR.id(), 6);
    }

    /// @notice Cannot receive response from non-coordinator contract
    function testCannotReceiveResponseFromNonCoordinator() public {
        // Expect revert sending from address(this)
        vm.expectRevert(BaseConsumer.NotCoordinator.selector);
        CALLBACK.rawReceiveCompute(1, 1, 1, address(this), MOCK_INPUT, MOCK_OUTPUT, MOCK_PROOF);
    }
}

/// @title CoordinatorCallbackTest
/// @notice Coordinator tests specific to usage by CallbackConsumer
contract CoordinatorCallbackTest is CoordinatorTest {
    /// @notice Can create callback (one-time subscription)
    function testCanCreateCallback() public {
        vm.warp(0);

        // Get expected subscription ID
        uint32 expected = COORDINATOR.id();

        // Create new callback
        vm.expectEmit(address(COORDINATOR));
        emit SubscriptionCreated(expected);
        uint32 actual = CALLBACK.createMockRequest(MOCK_CONTAINER_ID, MOCK_CONTAINER_INPUTS, 1 gwei, 100_000, 1);

        // Assert subscription ID is correctly stored
        assertEq(expected, actual);

        // Assert subscription data is correctly stored
        LibStruct.Subscription memory sub = LibStruct.getSubscription(COORDINATOR, actual);
        assertEq(sub.activeAt, 0);
        assertEq(sub.owner, address(CALLBACK));
        assertEq(sub.maxGasPrice, 1 gwei);
        assertEq(sub.redundancy, 1);
        assertEq(sub.maxGasLimit, 100_000);
        assertEq(sub.frequency, 1);
        assertEq(sub.period, 0);
        assertEq(sub.containerId, MOCK_CONTAINER_ID);
        assertEq(sub.inputs, MOCK_CONTAINER_INPUTS);
    }

    /// @notice Cannot deliver callback response if maxGasPrice too low
    function testCannotDeliverCallbackMaxGasPriceTooLow() public {
        // Create new subscription with 1 gwei max fee
        uint32 subId = CALLBACK.createMockRequest(MOCK_CONTAINER_ID, MOCK_CONTAINER_INPUTS, 1 gwei, 100_000, 1);

        // Set tx gas price to 1gwei + 1wei
        vm.txGasPrice(1 gwei + 1 wei);

        // Attempt to deliver new subscription
        vm.expectRevert(Coordinator.GasPriceExceeded.selector);
        ALICE.deliverCompute(subId, 1, "", "", "");
    }

    /// @notice Cannot deliver callback response if incorrect interval
    function testFuzzCannotDeliverCallbackIfIncorrectInterval(uint32 interval) public {
        // Check non-correct intervals
        vm.assume(interval != 1);

        // Create new callback request
        uint32 subId = CALLBACK.createMockRequest(MOCK_CONTAINER_ID, MOCK_CONTAINER_INPUTS, 1 gwei, 100_000, 1);

        // Attempt to deliver callback request w/ incorrect interval
        vm.expectRevert(Coordinator.IntervalMismatch.selector);
        ALICE.deliverCompute(subId, interval, "", "", "");
    }

    /// @notice Can deliver callback response successfully
    function testCanDeliverCallbackResponse() public {
        // Create new callback request
        uint32 subId = CALLBACK.createMockRequest(
            MOCK_CONTAINER_ID,
            MOCK_CONTAINER_INPUTS,
            1 gwei,
            uint32(COORDINATOR.DELIVERY_OVERHEAD_WEI()) + COLD_DELIVERY_COST_CALLBACK,
            1
        );

        // Deliver callback request
        vm.expectEmit(address(COORDINATOR));
        emit SubscriptionFulfilled(subId, address(ALICE));
        ALICE.deliverCompute(subId, 1, MOCK_INPUT, MOCK_OUTPUT, MOCK_PROOF);

        // Assert delivery
        LibStruct.DeliveredOutput memory out = LibStruct.getDeliveredOutput(CALLBACK, subId, 1, 1);
        assertEq(out.subscriptionId, subId);
        assertEq(out.interval, 1);
        assertEq(out.redundancy, 1);
        assertEq(out.node, address(ALICE));
        assertEq(out.input, MOCK_INPUT);
        assertEq(out.output, MOCK_OUTPUT);
        assertEq(out.proof, MOCK_PROOF);
    }

    /// @notice Can deliver callback response once, across two unique nodes
    function testCanDeliverCallbackResponseOnceAcrossTwoNodes() public {
        // Create new callback request w/ redundancy = 2
        uint16 redundancy = 2;
        uint32 subId = CALLBACK.createMockRequest(
            MOCK_CONTAINER_ID,
            MOCK_CONTAINER_INPUTS,
            1 gwei,
            uint32(COORDINATOR.DELIVERY_OVERHEAD_WEI()) + COLD_DELIVERY_COST_CALLBACK,
            redundancy
        );

        // Deliver callback request from two nodes
        ALICE.deliverCompute(subId, 1, MOCK_INPUT, MOCK_OUTPUT, MOCK_PROOF);
        BOB.deliverCompute(subId, 1, MOCK_INPUT, MOCK_OUTPUT, MOCK_PROOF);

        // Assert delivery
        address[2] memory nodes = [address(ALICE), address(BOB)];
        for (uint16 r = 1; r <= 2; r++) {
            LibStruct.DeliveredOutput memory out = LibStruct.getDeliveredOutput(CALLBACK, subId, 1, r);
            assertEq(out.subscriptionId, subId);
            assertEq(out.interval, 1);
            assertEq(out.redundancy, r);
            assertEq(out.node, nodes[r - 1]);
            assertEq(out.input, MOCK_INPUT);
            assertEq(out.output, MOCK_OUTPUT);
            assertEq(out.proof, MOCK_PROOF);
        }
    }

    /// @notice Cannot deliver callback response twice from same node
    function testCannotDeliverCallbackResponseFromSameNodeTwice() public {
        // Create new callback request w/ redundancy = 2
        uint16 redundancy = 2;
        uint32 subId = CALLBACK.createMockRequest(
            MOCK_CONTAINER_ID,
            MOCK_CONTAINER_INPUTS,
            1 gwei,
            uint32(COORDINATOR.DELIVERY_OVERHEAD_WEI()) + COLD_DELIVERY_COST_CALLBACK,
            redundancy
        );

        // Deliver callback request from Alice twice
        ALICE.deliverCompute(subId, 1, MOCK_INPUT, MOCK_OUTPUT, MOCK_PROOF);
        vm.expectRevert(Coordinator.NodeRespondedAlready.selector);
        ALICE.deliverCompute(subId, 1, MOCK_INPUT, MOCK_OUTPUT, MOCK_PROOF);
    }

    /// @notice Cannot deliver callback with insufficient gas limit
    function testCannotDeliverCallbackWithInsufficientGasLimit() public {
        // Create new callback request with maxGasLimit < 100 wei less than necessary
        vm.warp(0);
        uint32 subId = CALLBACK.createMockRequest(
            MOCK_CONTAINER_ID,
            MOCK_CONTAINER_INPUTS,
            1 gwei,
            uint32(COORDINATOR.DELIVERY_OVERHEAD_WEI()) + COLD_DELIVERY_COST_CALLBACK - 100,
            1
        );

        // Ensure that fulfilling callback fails
        vm.warp(1 minutes);
        vm.expectRevert(abi.encodeWithSelector(Coordinator.GasLimitExceeded.selector));
        ALICE.deliverCompute(subId, 1, MOCK_INPUT, MOCK_OUTPUT, MOCK_PROOF);
    }

    /// @notice Callback gas limit constant is approximately correct
    function testCallbackGasLimitIsApproximatelyCorrect() public {
        // Calculate approximate expected gas consumed
        uint256 expectedGasConsumed = uint32(COORDINATOR.DELIVERY_OVERHEAD_WEI()) + COLD_DELIVERY_COST_CALLBACK;
        uint256 threePercentDelta = ((expectedGasConsumed * 103) / 100) - expectedGasConsumed;

        // Create new callback request with appropriate maxGasLimit
        vm.warp(0);
        uint32 subId = CALLBACK.createMockRequest(
            MOCK_CONTAINER_ID,
            MOCK_CONTAINER_INPUTS,
            1 gwei,
            uint32(COORDINATOR.DELIVERY_OVERHEAD_WEI()) + COLD_DELIVERY_COST_CALLBACK,
            1
        );

        // Deliver callback directly as Alice and measure gas consumed
        vm.warp(1 minutes);
        vm.startPrank(address(ALICE));
        uint256 startingGas = gasleft();
        COORDINATOR.deliverCompute(subId, 1, MOCK_INPUT, MOCK_OUTPUT, MOCK_PROOF);
        uint256 endingGas = gasleft();
        uint256 actualGasConsumed = startingGas - endingGas;

        // Ensure that gas consumed via direct delivery is ~approximately same as what we'd mathematically expect
        assertApproxEqAbs(actualGasConsumed, expectedGasConsumed, threePercentDelta);
    }
}

/// @title CoordinatorSubscriptionTest
/// @notice Coordintor tests specific to usage by SubscriptionConsumer
contract CoordinatorSubscriptionTest is CoordinatorTest {
    /// @notice Can read container inputs
    function testCanReadContainerInputs() public {
        bytes memory expected = SUBSCRIPTION.CONTAINER_INPUTS();
        bytes memory actual = SUBSCRIPTION.getContainerInputs(0, 0, 0, address(this));
        assertEq(expected, actual);
    }

    /// @notice Can cancel a subscription
    function testCanCancelSubscription() public {
        // Create subscription
        uint32 subId = SUBSCRIPTION.createMockSubscription(
            MOCK_CONTAINER_ID,
            1 gwei,
            uint32(COORDINATOR.DELIVERY_OVERHEAD_WEI()) + COLD_DELIVERY_COST_SUBSCRIPTION,
            3,
            1 minutes,
            1
        );

        // Cancel subscription and expect event emission
        vm.expectEmit(address(COORDINATOR));
        emit SubscriptionCancelled(subId);
        SUBSCRIPTION.cancelMockSubscription(subId);
    }

    /// @notice Can cancel a subscription that has been fulfilled at least once
    function testCanCancelFulfilledSubscription() public {
        // Create subscription
        vm.warp(0);
        uint32 subId = SUBSCRIPTION.createMockSubscription(
            MOCK_CONTAINER_ID,
            1 gwei,
            uint32(COORDINATOR.DELIVERY_OVERHEAD_WEI()) + COLD_DELIVERY_COST_SUBSCRIPTION,
            3,
            1 minutes,
            1
        );

        // Fulfill at least once
        vm.warp(60);
        ALICE.deliverCompute(subId, 1, MOCK_INPUT, MOCK_OUTPUT, MOCK_PROOF);

        // Cancel subscription
        SUBSCRIPTION.cancelMockSubscription(subId);
    }

    /// @notice Cannot cancel a subscription that does not exist
    function testCannotCancelNonExistentSubscription() public {
        // Try to delete subscription without creating
        vm.expectRevert(Coordinator.NotSubscriptionOwner.selector);
        SUBSCRIPTION.cancelMockSubscription(1);
    }

    /// @notice Cannot cancel a subscription that has already been cancelled
    function testCannotCancelCancelledSubscription() public {
        // Create and cancel subscription
        uint32 subId = SUBSCRIPTION.createMockSubscription(
            MOCK_CONTAINER_ID,
            1 gwei,
            uint32(COORDINATOR.DELIVERY_OVERHEAD_WEI()) + COLD_DELIVERY_COST_SUBSCRIPTION,
            3,
            1 minutes,
            1
        );
        SUBSCRIPTION.cancelMockSubscription(subId);

        // Attempt to cancel subscription again
        vm.expectRevert(Coordinator.NotSubscriptionOwner.selector);
        SUBSCRIPTION.cancelMockSubscription(subId);
    }

    /// @notice Cannot cancel a subscription you do not own
    function testCannotCancelUnownedSubscription() public {
        // Create callback subscription
        uint32 subId = CALLBACK.createMockRequest(
            MOCK_CONTAINER_ID,
            MOCK_CONTAINER_INPUTS,
            1 gwei,
            uint32(COORDINATOR.DELIVERY_OVERHEAD_WEI()) + COLD_DELIVERY_COST_SUBSCRIPTION,
            1
        );

        // Attempt to cancel subscription from SUBSCRIPTION consumer
        vm.expectRevert(Coordinator.NotSubscriptionOwner.selector);
        SUBSCRIPTION.cancelMockSubscription(subId);
    }

    /// @notice Subscription intervals are properly calculated
    function testFuzzSubscriptionIntervalsAreCorrect(uint32 blockTime, uint32 frequency, uint32 period) public {
        // In the interest of testing time, upper bounding frequency loops + having at minimum 1 frequency
        vm.assume(frequency > 1 && frequency < 32);
        // Prevent upperbound overflow
        vm.assume(uint256(blockTime) + (uint256(frequency) * uint256(period)) < 2 ** 32 - 1);

        // Subscription activeAt timestamp
        uint32 activeAt = blockTime + period;

        // If period == 0, interval is always 1
        if (period == 0) {
            uint32 actual = COORDINATOR.getSubscriptionInterval(activeAt, period);
            assertEq(1, actual);
            return;
        }

        // Else, verify each manual interval
        // blockTime -> blockTime + period = underflow (this should never be called since we verify block.timestamp >= activeAt)
        // blockTime + N * period = N
        uint32 expected = 1;
        for (uint32 start = blockTime + period; start < (blockTime) + (frequency * period); start += period) {
            // Set current time
            vm.warp(start);

            // Check subscription interval
            uint32 actual = COORDINATOR.getSubscriptionInterval(activeAt, period);
            assertEq(expected, actual);

            // Check subscription interval 1s before if not first iteration
            if (expected != 1) {
                vm.warp(start - 1);
                actual = COORDINATOR.getSubscriptionInterval(activeAt, period);
                assertEq(expected - 1, actual);
            }

            // Increment expected for next cycle
            expected++;
        }
    }

    /// @notice Cannot deliver response for subscription that does not exist
    function testCannotDeliverResponseForNonExistentSubscription() public {
        // Attempt to deliver output for subscription without creating
        vm.expectRevert(Coordinator.SubscriptionNotFound.selector);
        ALICE.deliverCompute(1, 1, MOCK_INPUT, MOCK_OUTPUT, MOCK_PROOF);
    }

    /// @notice Cannot deliver response for non-active subscription
    function testCannotDeliverResponseNonActiveSubscription() public {
        // Create new subscription at time = 0
        vm.warp(0);
        uint32 subId = SUBSCRIPTION.createMockSubscription(
            MOCK_CONTAINER_ID,
            1 gwei,
            uint32(COORDINATOR.DELIVERY_OVERHEAD_WEI()) + COLD_DELIVERY_COST_SUBSCRIPTION,
            3,
            1 minutes,
            1
        );

        // Expect subscription to be inactive till time = 60
        vm.expectRevert(Coordinator.SubscriptionNotActive.selector);
        ALICE.deliverCompute(subId, 1, MOCK_INPUT, MOCK_OUTPUT, MOCK_PROOF);

        // Ensure subscription is active at time = 60
        // Force failure at next conditional (gas price)
        vm.txGasPrice(1 gwei + 1 wei);
        vm.warp(1 minutes);
        vm.expectRevert(Coordinator.GasPriceExceeded.selector);
        ALICE.deliverCompute(subId, 1, MOCK_INPUT, MOCK_OUTPUT, MOCK_PROOF);
    }

    /// @notice Cannot deliver response for completed subscription
    function testCannotDeliverResponseForCompletedSubscription() public {
        // Create new subscription at time = 0
        vm.warp(0);
        uint32 subId = SUBSCRIPTION.createMockSubscription(
            MOCK_CONTAINER_ID,
            1 gwei,
            uint32(COORDINATOR.DELIVERY_OVERHEAD_WEI()) + COLD_DELIVERY_COST_SUBSCRIPTION,
            2, // frequency = 2
            1 minutes,
            1
        );

        // Expect failure at any time prior to t = 60s
        vm.warp(1 minutes - 1);
        vm.expectRevert(Coordinator.SubscriptionNotActive.selector);
        ALICE.deliverCompute(subId, 1, MOCK_INPUT, MOCK_OUTPUT, MOCK_PROOF);

        // Deliver first response at time t = 60s
        vm.warp(1 minutes);
        ALICE.deliverCompute(subId, 1, MOCK_INPUT, MOCK_OUTPUT, MOCK_PROOF);

        // Deliver second response at time t = 120s
        vm.warp(2 minutes);
        ALICE.deliverCompute(subId, 2, MOCK_INPUT, MOCK_OUTPUT, MOCK_PROOF);

        // Expect revert because interval > frequency
        vm.warp(3 minutes);
        vm.expectRevert(Coordinator.SubscriptionCompleted.selector);
        ALICE.deliverCompute(subId, 3, MOCK_INPUT, MOCK_OUTPUT, MOCK_PROOF);
    }

    /// @notice Cannot deliver response if incorrect interval
    function testCannotDeliverResponseIncorrectInterval() public {
        // Create new subscription at time = 0
        vm.warp(0);
        uint32 subId = SUBSCRIPTION.createMockSubscription(
            MOCK_CONTAINER_ID,
            1 gwei,
            uint32(COORDINATOR.DELIVERY_OVERHEAD_WEI()) + COLD_DELIVERY_COST_SUBSCRIPTION,
            2, // frequency = 2
            1 minutes,
            1
        );

        // Successfully deliver at t = 60s, interval = 1
        vm.warp(1 minutes);
        ALICE.deliverCompute(subId, 1, MOCK_INPUT, MOCK_OUTPUT, MOCK_PROOF);

        // Unsuccesfully deliver at t = 120s, interval = 1 (expected = 2)
        vm.warp(2 minutes);
        vm.expectRevert(Coordinator.IntervalMismatch.selector);
        ALICE.deliverCompute(subId, 1, MOCK_INPUT, MOCK_OUTPUT, MOCK_PROOF);
    }

    /// @notice Cannot deliver response delayed (after interval passed)
    function testCannotDeliverResponseDelayed() public {
        // Create new subscription at time = 0
        vm.warp(0);
        uint32 subId = SUBSCRIPTION.createMockSubscription(
            MOCK_CONTAINER_ID,
            1 gwei,
            uint32(COORDINATOR.DELIVERY_OVERHEAD_WEI()) + COLD_DELIVERY_COST_SUBSCRIPTION,
            2, // frequency = 2
            1 minutes,
            1
        );

        // Attempt to deliver interval = 1 at time = 120s
        vm.warp(2 minutes);
        vm.expectRevert(Coordinator.IntervalMismatch.selector);
        ALICE.deliverCompute(subId, 1, MOCK_INPUT, MOCK_OUTPUT, MOCK_PROOF);
    }

    /// @notice Cannot deliver response early (before interval arrived)
    function testCannotDeliverResponseEarly() public {
        // Create new subscription at time = 0
        vm.warp(0);
        uint32 subId = SUBSCRIPTION.createMockSubscription(
            MOCK_CONTAINER_ID,
            1 gwei,
            uint32(COORDINATOR.DELIVERY_OVERHEAD_WEI()) + COLD_DELIVERY_COST_SUBSCRIPTION,
            2, // frequency = 2
            1 minutes,
            1
        );

        // Attempt to deliver interval = 2 at time < 120s
        vm.warp(2 minutes - 1);
        vm.expectRevert(Coordinator.IntervalMismatch.selector);
        ALICE.deliverCompute(subId, 2, MOCK_INPUT, MOCK_OUTPUT, MOCK_PROOF);
    }

    /// @notice Cannot deliver response if redundancy maxxed out
    function testCannotDeliverMaxRedundancyResponse() public {
        // Create new subscription at time = 0
        vm.warp(0);
        uint32 subId = SUBSCRIPTION.createMockSubscription(
            MOCK_CONTAINER_ID,
            1 gwei,
            uint32(COORDINATOR.DELIVERY_OVERHEAD_WEI()) + COLD_DELIVERY_COST_SUBSCRIPTION,
            2, // frequency = 2
            1 minutes,
            2 // redundancy = 2
        );

        // Deliver from Alice
        vm.warp(1 minutes);
        ALICE.deliverCompute(subId, 1, MOCK_INPUT, MOCK_OUTPUT, MOCK_PROOF);

        // Deliver from Bob
        BOB.deliverCompute(subId, 1, MOCK_INPUT, MOCK_OUTPUT, MOCK_PROOF);

        // Attempt to deliver from Charlie, expect failure
        vm.expectRevert(Coordinator.IntervalCompleted.selector);
        CHARLIE.deliverCompute(subId, 1, MOCK_INPUT, MOCK_OUTPUT, MOCK_PROOF);
    }

    /// @notice Cannot deliver response if already delivered in current interval
    function testCannotDeliverResponseIfAlreadyDeliveredInCurrentInterval() public {
        // Create new subscription at time = 0
        vm.warp(0);
        uint32 subId = SUBSCRIPTION.createMockSubscription(
            MOCK_CONTAINER_ID,
            1 gwei,
            uint32(COORDINATOR.DELIVERY_OVERHEAD_WEI()) + COLD_DELIVERY_COST_SUBSCRIPTION,
            2, // frequency = 2
            1 minutes,
            2 // redundancy = 2
        );

        // Deliver from Alice
        vm.warp(1 minutes);
        ALICE.deliverCompute(subId, 1, MOCK_INPUT, MOCK_OUTPUT, MOCK_PROOF);

        // Attempt to deliver from Alice again
        vm.expectRevert(Coordinator.NodeRespondedAlready.selector);
        ALICE.deliverCompute(subId, 1, MOCK_INPUT, MOCK_OUTPUT, MOCK_PROOF);
    }

    /// @notice Cannot deliver response from non-node
    function testCannotDeliverResponseFromNonNode() public {
        // Create new subscription at time = 0
        vm.warp(0);
        uint32 subId = SUBSCRIPTION.createMockSubscription(
            MOCK_CONTAINER_ID,
            1 gwei,
            uint32(COORDINATOR.DELIVERY_OVERHEAD_WEI()) + COLD_DELIVERY_COST_SUBSCRIPTION,
            2, // frequency = 2
            1 minutes,
            2 // redundancy = 2
        );

        // Attempt to deliver from non-node
        vm.expectRevert(Manager.NodeNotActive.selector);
        COORDINATOR.deliverCompute(subId, 1, MOCK_INPUT, MOCK_OUTPUT, MOCK_PROOF);
    }

    /// @notice Cannot deliver subscription with insufficient gas limit
    function testCannotDeliverSubscriptionWithInsufficientGasLimit() public {
        // Create new subscription with maxGasLimit < 100 wei less than necessary
        vm.warp(0);
        uint32 subId = SUBSCRIPTION.createMockSubscription(
            MOCK_CONTAINER_ID,
            1 gwei,
            uint32(COORDINATOR.DELIVERY_OVERHEAD_WEI()) + COLD_DELIVERY_COST_SUBSCRIPTION - 100 wei,
            2, // frequency = 2
            1 minutes,
            2 // redundancy = 2
        );

        // Ensure that fulfilling subscription fails
        vm.warp(1 minutes);
        vm.expectRevert(abi.encodeWithSelector(Coordinator.GasLimitExceeded.selector));
        ALICE.deliverCompute(subId, 1, MOCK_INPUT, MOCK_OUTPUT, MOCK_PROOF);
    }

    /// @notice Subscription gas limit constant is approximately correct
    function testSubscriptionGasLimitIsApproximatelyCorrect() public {
        // Calculate approximate expected gas consumed
        uint256 expectedGasConsumed = uint32(COORDINATOR.DELIVERY_OVERHEAD_WEI()) + COLD_DELIVERY_COST_SUBSCRIPTION;
        uint256 threePercentDelta = ((expectedGasConsumed * 103) / 100) - expectedGasConsumed;

        // Create new subscription request with appropriate maxGasLimit
        vm.warp(0);
        uint32 subId = SUBSCRIPTION.createMockSubscription(
            MOCK_CONTAINER_ID,
            1 gwei,
            uint32(COORDINATOR.DELIVERY_OVERHEAD_WEI()) + COLD_DELIVERY_COST_SUBSCRIPTION,
            2, // frequency = 2
            1 minutes,
            2 // redundancy = 2
        );

        // Deliver subscription directly as Alice and measure gas consumed
        vm.warp(1 minutes);
        vm.startPrank(address(ALICE));
        uint256 startingGas = gasleft();
        COORDINATOR.deliverCompute(subId, 1, MOCK_INPUT, MOCK_OUTPUT, MOCK_PROOF);
        uint256 endingGas = gasleft();
        uint256 actualGasConsumed = startingGas - endingGas;

        // Ensure that gas consumed via direct delivery is ~approximately same as what we'd mathematically expect
        assertApproxEqAbs(actualGasConsumed, expectedGasConsumed, threePercentDelta);
    }
}
