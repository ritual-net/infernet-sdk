// SPDX-License-Identifier: BSD-3-Clause-Clear
pragma solidity ^0.8.4;

import {Test} from "forge-std/Test.sol";
import {Registry} from "../src/Registry.sol";
import {MockNode} from "./mocks/MockNode.sol";
import {LibDeploy} from "./lib/LibDeploy.sol";
import {MockToken} from "./mocks/MockToken.sol";
import {Wallet} from "../src/payments/Wallet.sol";
import {Inbox, InboxItem} from "../src/Inbox.sol";
import {BaseConsumer} from "../src/consumer/Base.sol";
import {MockProtocol} from "./mocks/MockProtocol.sol";
import {Allowlist} from "../src/pattern/Allowlist.sol";
import {DeliveredOutput} from "./mocks/consumer/Base.sol";
import {MockAtomicVerifier} from "./mocks/verifier/Atomic.sol";
import {EIP712Coordinator} from "../src/EIP712Coordinator.sol";
import {WalletFactory} from "../src/payments/WalletFactory.sol";
import {Coordinator, Subscription} from "../src/Coordinator.sol";
import {MockCallbackConsumer} from "./mocks/consumer/Callback.sol";
import {MockOptimisticVerifier} from "./mocks/verifier/Optimistic.sol";
import {MockSubscriptionConsumer} from "./mocks/consumer/Subscription.sol";
import {MockAllowlistSubscriptionConsumer} from "./mocks/consumer/AllowlistSubscription.sol";

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
    string internal constant MOCK_CONTAINER_ID = "container";

    /// @notice Mock compute container ID hashed
    bytes32 internal constant HASHED_MOCK_CONTAINER_ID = keccak256(abi.encode(MOCK_CONTAINER_ID));

    /// @notice Mock container inputs
    bytes internal constant MOCK_CONTAINER_INPUTS = "inputs";

    /// @notice Mock delivered container input
    /// @dev Example of a hashed input (encoding hash(MOCK_CONTAINER_INPUTS) into input) field
    bytes internal constant MOCK_INPUT = abi.encode(keccak256(abi.encode(MOCK_CONTAINER_INPUTS)));

    /// @notice Mock delivered container compute output
    bytes internal constant MOCK_OUTPUT = "output";

    /// @notice Mock delivered proof
    bytes internal constant MOCK_PROOF = "proof";

    /// @notice Mock protocol fee (5.11%)
    uint16 internal constant MOCK_PROTOCOL_FEE = 511;

    /// @notice Zero address
    address internal constant ZERO_ADDRESS = address(0);

    /// @notice Mock empty payment token
    address internal constant NO_PAYMENT_TOKEN = ZERO_ADDRESS;

    /// @notice Mock empty wallet
    address internal constant NO_WALLET = ZERO_ADDRESS;

    /// @notice Mock empty verifier contract
    address internal constant NO_VERIFIER = ZERO_ADDRESS;
}

/// @title CoordinatorTest
/// @notice Base setup to inherit for Coordinator subtests
abstract contract CoordinatorTest is Test, CoordinatorConstants, ICoordinatorEvents {
    /*//////////////////////////////////////////////////////////////
                                INTERNAL
    //////////////////////////////////////////////////////////////*/

    /// @notice Mock protocol wallet
    MockProtocol internal PROTOCOL;

    /// @notice Registry
    Registry internal REGISTRY;

    /// @notice Coordinator
    Coordinator internal COORDINATOR;

    /// @notice Inbox
    Inbox internal INBOX;

    /// @notice Wallet factory
    WalletFactory internal WALLET_FACTORY;

    /// @notice Mock ERC20 token
    MockToken internal TOKEN;

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

    /// @notice Mock subscription consumer w/ Allowlist
    MockAllowlistSubscriptionConsumer internal ALLOWLIST_SUBSCRIPTION;

    /// @notice Mock atomic verifier
    MockAtomicVerifier internal ATOMIC_VERIFIER;

    /// @notice Mock optimistic verifier
    MockOptimisticVerifier internal OPTIMISTIC_VERIFIER;

    /*//////////////////////////////////////////////////////////////
                                 SETUP
    //////////////////////////////////////////////////////////////*/

    function setUp() public {
        // Create mock protocol wallet
        uint256 initialNonce = vm.getNonce(address(this));
        address mockProtocolWalletAddress = vm.computeCreateAddress(address(this), initialNonce + 6);

        // Initialize contracts
        (Registry registry, EIP712Coordinator coordinator, Inbox inbox,,, WalletFactory walletFactory) =
            LibDeploy.deployContracts(address(this), initialNonce, mockProtocolWalletAddress, MOCK_PROTOCOL_FEE);

        // Initialize mock protocol wallet
        PROTOCOL = new MockProtocol(registry);

        // Create mock token
        TOKEN = new MockToken();

        // Assign to internal (overriding EIP712Coordinator -> isolated Coordinator for tests)
        REGISTRY = registry;
        COORDINATOR = Coordinator(coordinator);
        INBOX = inbox;
        WALLET_FACTORY = walletFactory;

        // Initalize mock nodes
        ALICE = new MockNode(registry);
        BOB = new MockNode(registry);
        CHARLIE = new MockNode(registry);

        // Initialize mock callback consumer
        CALLBACK = new MockCallbackConsumer(address(registry));

        // Initialize mock subscription consumer
        SUBSCRIPTION = new MockSubscriptionConsumer(address(registry));

        // Initialize mock subscription consumer w/ Allowlist
        // Add only Alice as initially allowed node
        address[] memory initialAllowed = new address[](1);
        initialAllowed[0] = address(ALICE);
        ALLOWLIST_SUBSCRIPTION = new MockAllowlistSubscriptionConsumer(address(registry), initialAllowed);

        // Initialize mock verifiers
        ATOMIC_VERIFIER = new MockAtomicVerifier(registry);
        OPTIMISTIC_VERIFIER = new MockOptimisticVerifier(registry);
    }
}

/// @title CoordinatorGeneralTest
/// @notice General coordinator tests
contract CoordinatorGeneralTest is CoordinatorTest {
    /// @notice Cannot be reassigned a subscription ID
    function testCannotBeReassignedSubscriptionID() public {
        // Create new callback subscription
        uint32 id = CALLBACK.createMockRequest(
            MOCK_CONTAINER_ID, MOCK_CONTAINER_INPUTS, 1, NO_PAYMENT_TOKEN, 0, NO_WALLET, NO_VERIFIER
        );
        assertEq(id, 1);

        // Create new subscriptions
        CALLBACK.createMockRequest(
            MOCK_CONTAINER_ID, MOCK_CONTAINER_INPUTS, 1, NO_PAYMENT_TOKEN, 0, NO_WALLET, NO_VERIFIER
        );
        CALLBACK.createMockRequest(
            MOCK_CONTAINER_ID, MOCK_CONTAINER_INPUTS, 1, NO_PAYMENT_TOKEN, 0, NO_WALLET, NO_VERIFIER
        );
        CALLBACK.createMockRequest(
            MOCK_CONTAINER_ID, MOCK_CONTAINER_INPUTS, 1, NO_PAYMENT_TOKEN, 0, NO_WALLET, NO_VERIFIER
        );

        // Assert head
        assertEq(COORDINATOR.id(), 5);

        // Delete subscriptions
        vm.startPrank(address(CALLBACK));
        COORDINATOR.cancelSubscription(1);
        COORDINATOR.cancelSubscription(3);

        // Assert head
        assertEq(COORDINATOR.id(), 5);

        // Create new subscription
        id = CALLBACK.createMockRequest(
            MOCK_CONTAINER_ID, MOCK_CONTAINER_INPUTS, 1, NO_PAYMENT_TOKEN, 0, NO_WALLET, NO_VERIFIER
        );
        assertEq(id, 5);
        assertEq(COORDINATOR.id(), 6);
    }

    /// @notice Cannot receive response from non-coordinator contract
    function testCannotReceiveResponseFromNonCoordinator() public {
        // Expect revert sending from address(this)
        vm.expectRevert(BaseConsumer.NotCoordinator.selector);
        CALLBACK.rawReceiveCompute(1, 1, 1, address(this), MOCK_INPUT, MOCK_OUTPUT, MOCK_PROOF, bytes32(0), 0);
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
        uint32 actual = CALLBACK.createMockRequest(
            MOCK_CONTAINER_ID, MOCK_CONTAINER_INPUTS, 1, NO_PAYMENT_TOKEN, 0, NO_WALLET, NO_VERIFIER
        );

        // Assert subscription ID is correctly stored
        assertEq(expected, actual);

        // Assert subscription data is correctly stored
        Subscription memory sub = COORDINATOR.getSubscription(actual);
        assertEq(sub.activeAt, 0);
        assertEq(sub.owner, address(CALLBACK));
        assertEq(sub.redundancy, 1);
        assertEq(sub.frequency, 1);
        assertEq(sub.period, 0);
        assertEq(sub.containerId, HASHED_MOCK_CONTAINER_ID);
        assertEq(sub.lazy, false);

        // Assert subscription inputs are correctly stord
        assertEq(CALLBACK.getContainerInputs(actual, 0, 0, address(0)), MOCK_CONTAINER_INPUTS);
    }

    /// @notice Cannot deliver callback response if incorrect interval
    function testFuzzCannotDeliverCallbackIfIncorrectInterval(uint32 interval) public {
        // Check non-correct intervals
        vm.assume(interval != 1);

        // Create new callback request
        uint32 subId = CALLBACK.createMockRequest(
            MOCK_CONTAINER_ID, MOCK_CONTAINER_INPUTS, 1, NO_PAYMENT_TOKEN, 0, NO_WALLET, NO_VERIFIER
        );

        // Attempt to deliver callback request w/ incorrect interval
        vm.expectRevert(Coordinator.IntervalMismatch.selector);
        ALICE.deliverCompute(subId, interval, "", "", "", NO_WALLET);
    }

    /// @notice Can deliver callback response successfully
    function testCanDeliverCallbackResponse() public {
        // Create new callback request
        uint32 subId = CALLBACK.createMockRequest(
            MOCK_CONTAINER_ID, MOCK_CONTAINER_INPUTS, 1, NO_PAYMENT_TOKEN, 0, NO_WALLET, NO_VERIFIER
        );

        // Deliver callback request
        vm.expectEmit(address(COORDINATOR));
        emit SubscriptionFulfilled(subId, address(ALICE));
        ALICE.deliverCompute(subId, 1, MOCK_INPUT, MOCK_OUTPUT, MOCK_PROOF, NO_WALLET);

        // Assert delivery
        DeliveredOutput memory out = CALLBACK.getDeliveredOutput(subId, 1, 1);
        assertEq(out.subscriptionId, subId);
        assertEq(out.interval, 1);
        assertEq(out.redundancy, 1);
        assertEq(out.node, address(ALICE));
        assertEq(out.input, MOCK_INPUT);
        assertEq(out.output, MOCK_OUTPUT);
        assertEq(out.proof, MOCK_PROOF);
        assertEq(out.containerId, bytes32(0));
        assertEq(out.index, 0);
    }

    /// @notice Can deliver callback response once, across two unique nodes
    function testCanDeliverCallbackResponseOnceAcrossTwoNodes() public {
        // Create new callback request w/ redundancy = 2
        uint16 redundancy = 2;
        uint32 subId = CALLBACK.createMockRequest(
            MOCK_CONTAINER_ID, MOCK_CONTAINER_INPUTS, redundancy, NO_PAYMENT_TOKEN, 0, NO_WALLET, NO_VERIFIER
        );

        // Deliver callback request from two nodes
        ALICE.deliverCompute(subId, 1, MOCK_INPUT, MOCK_OUTPUT, MOCK_PROOF, NO_WALLET);
        BOB.deliverCompute(subId, 1, MOCK_INPUT, MOCK_OUTPUT, MOCK_PROOF, NO_WALLET);

        // Assert delivery
        address[2] memory nodes = [address(ALICE), address(BOB)];
        for (uint16 r = 1; r <= 2; r++) {
            DeliveredOutput memory out = CALLBACK.getDeliveredOutput(subId, 1, r);
            assertEq(out.subscriptionId, subId);
            assertEq(out.interval, 1);
            assertEq(out.redundancy, r);
            assertEq(out.node, nodes[r - 1]);
            assertEq(out.input, MOCK_INPUT);
            assertEq(out.output, MOCK_OUTPUT);
            assertEq(out.proof, MOCK_PROOF);
            assertEq(out.containerId, bytes32(0));
            assertEq(out.index, 0);
        }
    }

    /// @notice Cannot deliver callback response twice from same node
    function testCannotDeliverCallbackResponseFromSameNodeTwice() public {
        // Create new callback request w/ redundancy = 2
        uint16 redundancy = 2;
        uint32 subId = CALLBACK.createMockRequest(
            MOCK_CONTAINER_ID, MOCK_CONTAINER_INPUTS, redundancy, NO_PAYMENT_TOKEN, 0, NO_WALLET, NO_VERIFIER
        );

        // Deliver callback request from Alice twice
        ALICE.deliverCompute(subId, 1, MOCK_INPUT, MOCK_OUTPUT, MOCK_PROOF, NO_WALLET);
        vm.expectRevert(Coordinator.NodeRespondedAlready.selector);
        ALICE.deliverCompute(subId, 1, MOCK_INPUT, MOCK_OUTPUT, MOCK_PROOF, NO_WALLET);
    }

    /// @notice Delivered callbacks are not stored in Inbox
    function testCallbackDeliveryDoesNotStoreDataInInbox() public {
        // Create new callback request
        uint32 subId = CALLBACK.createMockRequest(
            MOCK_CONTAINER_ID, MOCK_CONTAINER_INPUTS, 1, NO_PAYMENT_TOKEN, 0, NO_WALLET, NO_VERIFIER
        );

        // Deliver callback request from Alice
        ALICE.deliverCompute(subId, 1, MOCK_INPUT, MOCK_OUTPUT, MOCK_PROOF, NO_WALLET);

        // Expect revert (indexOOBError but in external contract)
        vm.expectRevert();
        INBOX.read(HASHED_MOCK_CONTAINER_ID, address(ALICE), 0);
    }
}

/// @title CoordinatorSubscriptionTest
/// @notice Coordinator tests specific to usage by SubscriptionConsumer
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
            MOCK_CONTAINER_ID, 3, 1 minutes, 1, false, NO_PAYMENT_TOKEN, 0, NO_WALLET, NO_VERIFIER
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
            MOCK_CONTAINER_ID, 3, 1 minutes, 1, false, NO_PAYMENT_TOKEN, 0, NO_WALLET, NO_VERIFIER
        );

        // Fulfill at least once
        vm.warp(60);
        ALICE.deliverCompute(subId, 1, MOCK_INPUT, MOCK_OUTPUT, MOCK_PROOF, NO_WALLET);

        // Cancel subscription
        SUBSCRIPTION.cancelMockSubscription(subId);
    }

    /// @notice Cannot cancel a subscription that does not exist
    function testCannotCancelNonExistentSubscription() public {
        // Try to delete subscription without creating
        vm.expectRevert(Coordinator.NotSubscriptionOwner.selector);
        SUBSCRIPTION.cancelMockSubscription(1);
    }

    /// @notice Can cancel a subscription that has already been cancelled
    function testCanCancelCancelledSubscription() public {
        // Create and cancel subscription
        uint32 subId = SUBSCRIPTION.createMockSubscription(
            MOCK_CONTAINER_ID, 3, 1 minutes, 1, false, NO_PAYMENT_TOKEN, 0, NO_WALLET, NO_VERIFIER
        );
        SUBSCRIPTION.cancelMockSubscription(subId);

        // Attempt to cancel subscription again
        SUBSCRIPTION.cancelMockSubscription(subId);
    }

    /// @notice Cannot cancel a subscription you do not own
    function testCannotCancelUnownedSubscription() public {
        // Create callback subscription
        uint32 subId = CALLBACK.createMockRequest(
            MOCK_CONTAINER_ID, MOCK_CONTAINER_INPUTS, 1, NO_PAYMENT_TOKEN, 0, NO_WALLET, NO_VERIFIER
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
        ALICE.deliverCompute(1, 1, MOCK_INPUT, MOCK_OUTPUT, MOCK_PROOF, NO_WALLET);
    }

    /// @notice Cannot deliver response for non-active subscription
    function testCannotDeliverResponseNonActiveSubscription() public {
        // Create new subscription at time = 0
        vm.warp(0);
        uint32 subId = SUBSCRIPTION.createMockSubscription(
            MOCK_CONTAINER_ID, 3, 1 minutes, 1, false, NO_PAYMENT_TOKEN, 0, NO_WALLET, NO_VERIFIER
        );

        // Expect subscription to be inactive till time = 60
        vm.expectRevert(Coordinator.SubscriptionNotActive.selector);
        ALICE.deliverCompute(subId, 1, MOCK_INPUT, MOCK_OUTPUT, MOCK_PROOF, NO_WALLET);

        // Ensure subscription can be fulfilled when active
        // Force failure at next conditional (gas price)
        vm.warp(1 minutes);
        ALICE.deliverCompute(subId, 1, MOCK_INPUT, MOCK_OUTPUT, MOCK_PROOF, NO_WALLET);
    }

    /// @notice Cannot deliver response for completed subscription
    function testCannotDeliverResponseForCompletedSubscription() public {
        // Create new subscription at time = 0
        vm.warp(0);
        uint32 subId = SUBSCRIPTION.createMockSubscription(
            MOCK_CONTAINER_ID,
            2, // frequency = 2
            1 minutes,
            1,
            false,
            NO_PAYMENT_TOKEN,
            0,
            NO_WALLET,
            NO_VERIFIER
        );

        // Expect failure at any time prior to t = 60s
        vm.warp(1 minutes - 1);
        vm.expectRevert(Coordinator.SubscriptionNotActive.selector);
        ALICE.deliverCompute(subId, 1, MOCK_INPUT, MOCK_OUTPUT, MOCK_PROOF, NO_WALLET);

        // Deliver first response at time t = 60s
        vm.warp(1 minutes);
        ALICE.deliverCompute(subId, 1, MOCK_INPUT, MOCK_OUTPUT, MOCK_PROOF, NO_WALLET);

        // Deliver second response at time t = 120s
        vm.warp(2 minutes);
        ALICE.deliverCompute(subId, 2, MOCK_INPUT, MOCK_OUTPUT, MOCK_PROOF, NO_WALLET);

        // Expect revert because interval > frequency
        vm.warp(3 minutes);
        vm.expectRevert(Coordinator.SubscriptionCompleted.selector);
        ALICE.deliverCompute(subId, 3, MOCK_INPUT, MOCK_OUTPUT, MOCK_PROOF, NO_WALLET);
    }

    /// @notice Cannot deliver response if incorrect interval
    function testCannotDeliverResponseIncorrectInterval() public {
        // Create new subscription at time = 0
        vm.warp(0);
        uint32 subId = SUBSCRIPTION.createMockSubscription(
            MOCK_CONTAINER_ID,
            2, // frequency = 2
            1 minutes,
            1,
            false,
            NO_PAYMENT_TOKEN,
            0,
            NO_WALLET,
            NO_VERIFIER
        );

        // Successfully deliver at t = 60s, interval = 1
        vm.warp(1 minutes);
        ALICE.deliverCompute(subId, 1, MOCK_INPUT, MOCK_OUTPUT, MOCK_PROOF, NO_WALLET);

        // Unsuccesfully deliver at t = 120s, interval = 1 (expected = 2)
        vm.warp(2 minutes);
        vm.expectRevert(Coordinator.IntervalMismatch.selector);
        ALICE.deliverCompute(subId, 1, MOCK_INPUT, MOCK_OUTPUT, MOCK_PROOF, NO_WALLET);
    }

    /// @notice Cannot deliver response delayed (after interval passed)
    function testCannotDeliverResponseDelayed() public {
        // Create new subscription at time = 0
        vm.warp(0);
        uint32 subId = SUBSCRIPTION.createMockSubscription(
            MOCK_CONTAINER_ID,
            2, // frequency = 2
            1 minutes,
            1,
            false,
            NO_PAYMENT_TOKEN,
            0,
            NO_WALLET,
            NO_VERIFIER
        );

        // Attempt to deliver interval = 1 at time = 120s
        vm.warp(2 minutes);
        vm.expectRevert(Coordinator.IntervalMismatch.selector);
        ALICE.deliverCompute(subId, 1, MOCK_INPUT, MOCK_OUTPUT, MOCK_PROOF, NO_WALLET);
    }

    /// @notice Cannot deliver response early (before interval arrived)
    function testCannotDeliverResponseEarly() public {
        // Create new subscription at time = 0
        vm.warp(0);
        uint32 subId = SUBSCRIPTION.createMockSubscription(
            MOCK_CONTAINER_ID,
            2, // frequency = 2
            1 minutes,
            1,
            false,
            NO_PAYMENT_TOKEN,
            0,
            NO_WALLET,
            NO_VERIFIER
        );

        // Attempt to deliver interval = 2 at time < 120s
        vm.warp(2 minutes - 1);
        vm.expectRevert(Coordinator.IntervalMismatch.selector);
        ALICE.deliverCompute(subId, 2, MOCK_INPUT, MOCK_OUTPUT, MOCK_PROOF, NO_WALLET);
    }

    /// @notice Cannot deliver response if redundancy maxxed out
    function testCannotDeliverMaxRedundancyResponse() public {
        // Create new subscription at time = 0
        vm.warp(0);
        uint32 subId = SUBSCRIPTION.createMockSubscription(
            MOCK_CONTAINER_ID,
            2, // frequency = 2
            1 minutes,
            2, // redundancy = 2
            false,
            NO_PAYMENT_TOKEN,
            0,
            NO_WALLET,
            NO_VERIFIER
        );

        // Deliver from Alice
        vm.warp(1 minutes);
        ALICE.deliverCompute(subId, 1, MOCK_INPUT, MOCK_OUTPUT, MOCK_PROOF, NO_WALLET);

        // Deliver from Bob
        BOB.deliverCompute(subId, 1, MOCK_INPUT, MOCK_OUTPUT, MOCK_PROOF, NO_WALLET);

        // Attempt to deliver from Charlie, expect failure
        vm.expectRevert(Coordinator.IntervalCompleted.selector);
        CHARLIE.deliverCompute(subId, 1, MOCK_INPUT, MOCK_OUTPUT, MOCK_PROOF, NO_WALLET);
    }

    /// @notice Cannot deliver response if already delivered in current interval
    function testCannotDeliverResponseIfAlreadyDeliveredInCurrentInterval() public {
        // Create new subscription at time = 0
        vm.warp(0);
        uint32 subId = SUBSCRIPTION.createMockSubscription(
            MOCK_CONTAINER_ID,
            2, // frequency = 2
            1 minutes,
            2, // redundancy = 2
            false,
            NO_PAYMENT_TOKEN,
            0,
            NO_WALLET,
            NO_VERIFIER
        );

        // Deliver from Alice
        vm.warp(1 minutes);
        ALICE.deliverCompute(subId, 1, MOCK_INPUT, MOCK_OUTPUT, MOCK_PROOF, NO_WALLET);

        // Attempt to deliver from Alice again
        vm.expectRevert(Coordinator.NodeRespondedAlready.selector);
        ALICE.deliverCompute(subId, 1, MOCK_INPUT, MOCK_OUTPUT, MOCK_PROOF, NO_WALLET);
    }
}

/// @title CoordinatorEagerSubscriptionTest
/// @notice Coordinator tests specific to usage by SubscriptionConsumer w/ eager fulfillment
contract CoordinatorEagerSubscriptionTest is CoordinatorTest {
    /// @notice Eager subscription delivery does not store outputs in inbox
    function testEagerSubscriptionDeliveryDoesNotStoreOutputsInInbox() public {
        // Create new eager subscription
        vm.warp(0);
        uint32 subId = SUBSCRIPTION.createMockSubscription(
            MOCK_CONTAINER_ID,
            2, // frequency = 2
            1 minutes,
            2, // redundancy = 2
            false,
            NO_PAYMENT_TOKEN,
            0,
            NO_WALLET,
            NO_VERIFIER
        );

        // Fulfill subscription as Alice
        vm.warp(1 minutes);
        ALICE.deliverCompute(subId, 1, MOCK_INPUT, MOCK_OUTPUT, MOCK_PROOF, NO_WALLET);

        // Verify exact rawReceiveCompute inputs
        DeliveredOutput memory out = SUBSCRIPTION.getDeliveredOutput(subId, 1, 1);
        assertEq(out.subscriptionId, subId);
        assertEq(out.interval, 1);
        assertEq(out.redundancy, 1);
        assertEq(out.node, address(ALICE));
        assertEq(out.input, MOCK_INPUT);
        assertEq(out.output, MOCK_OUTPUT);
        assertEq(out.proof, MOCK_PROOF);
        assertEq(out.containerId, bytes32(0));
        assertEq(out.index, 0);

        // Expect revert (indexOOBError but in external contract)
        vm.expectRevert();
        INBOX.read(HASHED_MOCK_CONTAINER_ID, address(ALICE), 0);
    }
}

/// @title CoordinatorLazySubscriptionTest
/// @notice Coordinator tests specific to usage by SubscriptionConsumer w/ lazy fulfillment
contract CoordinatorLazySubscriptionTest is CoordinatorTest {
    /// @notice Lazy subscription delivery stores outputs in inbox
    function testLazySubscriptionDeliveryStoresOutputsInInbox() public {
        // Create new lazy subscription
        vm.warp(0);
        uint32 subId = SUBSCRIPTION.createMockSubscription(
            MOCK_CONTAINER_ID, 1, 1 minutes, 1, true, NO_PAYMENT_TOKEN, 0, NO_WALLET, NO_VERIFIER
        );

        // Deliver lazy subscription from Alice
        vm.warp(1 minutes);
        ALICE.deliverCompute(subId, 1, MOCK_INPUT, MOCK_OUTPUT, MOCK_PROOF, NO_WALLET);

        // Verify exact rawReceiveCompute inputs
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

        // Verify data is stored in inbox
        InboxItem memory item = INBOX.read(HASHED_MOCK_CONTAINER_ID, address(ALICE), 0);
        assertEq(item.timestamp, 1 minutes);
        assertEq(item.subscriptionId, subId);
        assertEq(item.interval, 1);
        assertEq(item.input, MOCK_INPUT);
        assertEq(item.output, MOCK_OUTPUT);
        assertEq(item.proof, MOCK_PROOF);
    }

    /// @notice Can deliver lazy and eager subscription responses to same contract
    function testCanDeliverLazyAndEagerSubscriptionToSameContract() public {
        // Create new eager subscription
        vm.warp(0);
        uint32 subIdEager = SUBSCRIPTION.createMockSubscription(
            MOCK_CONTAINER_ID, 1, 1 minutes, 1, false, NO_PAYMENT_TOKEN, 0, NO_WALLET, NO_VERIFIER
        );

        // Create new lazy subscription
        uint32 subIdLazy = SUBSCRIPTION.createMockSubscription(
            MOCK_CONTAINER_ID, 1, 1 minutes, 1, true, NO_PAYMENT_TOKEN, 0, NO_WALLET, NO_VERIFIER
        );

        // Deliver lazy and eager subscriptions
        vm.warp(1 minutes);
        ALICE.deliverCompute(subIdEager, 1, MOCK_INPUT, MOCK_OUTPUT, MOCK_PROOF, NO_WALLET);
        ALICE.deliverCompute(subIdLazy, 1, MOCK_INPUT, MOCK_OUTPUT, MOCK_PROOF, NO_WALLET);

        // Verify eager rawReceiveCompute inputs
        DeliveredOutput memory out = SUBSCRIPTION.getDeliveredOutput(subIdEager, 1, 1);
        assertEq(out.subscriptionId, subIdEager);
        assertEq(out.interval, 1);
        assertEq(out.redundancy, 1);
        assertEq(out.node, address(ALICE));
        assertEq(out.input, MOCK_INPUT);
        assertEq(out.output, MOCK_OUTPUT);
        assertEq(out.proof, MOCK_PROOF);
        assertEq(out.containerId, bytes32(0));
        assertEq(out.index, 0);

        // Veirfy lazy rawReceiveCompute inputs
        out = SUBSCRIPTION.getDeliveredOutput(subIdLazy, 1, 1);
        assertEq(out.subscriptionId, subIdLazy);
        assertEq(out.interval, 1);
        assertEq(out.redundancy, 1);
        assertEq(out.node, address(ALICE));
        assertEq(out.input, "");
        assertEq(out.output, "");
        assertEq(out.proof, "");
        assertEq(out.containerId, HASHED_MOCK_CONTAINER_ID);
        assertEq(out.index, 0);

        // Ensure first index item in inbox is subIdLazy
        InboxItem memory item = INBOX.read(HASHED_MOCK_CONTAINER_ID, address(ALICE), 0);
        assertEq(item.timestamp, 1 minutes);
        assertEq(item.subscriptionId, subIdLazy);
        assertEq(item.interval, 1);
        assertEq(item.input, MOCK_INPUT);
        assertEq(item.output, MOCK_OUTPUT);
        assertEq(item.proof, MOCK_PROOF);
    }

    /// @notice Can delivery lazy subscriptions more than once
    function testCanDeliverLazySubscriptionsMoreThanOnce() public {
        // Create new lazy subscription w/ frequency = 2, redundancy = 2
        vm.warp(0);
        uint32 subId = SUBSCRIPTION.createMockSubscription(
            MOCK_CONTAINER_ID, 2, 1 minutes, 2, true, NO_PAYMENT_TOKEN, 0, NO_WALLET, NO_VERIFIER
        );

        // Deliver first interval from {Alice, Bob}
        vm.warp(1 minutes);
        ALICE.deliverCompute(subId, 1, MOCK_INPUT, MOCK_OUTPUT, MOCK_PROOF, NO_WALLET);
        BOB.deliverCompute(subId, 1, MOCK_INPUT, MOCK_OUTPUT, MOCK_PROOF, NO_WALLET);

        // Deliver second interval from {Alice, Bob}
        vm.warp(2 minutes);
        ALICE.deliverCompute(subId, 2, MOCK_INPUT, MOCK_OUTPUT, MOCK_PROOF, NO_WALLET);
        BOB.deliverCompute(subId, 2, MOCK_INPUT, MOCK_OUTPUT, MOCK_PROOF, NO_WALLET);

        // Verify inbox stores correct {timestamp, subscriptionId, interval}
        // Alice 0th-index (first interval response)
        InboxItem memory item = INBOX.read(HASHED_MOCK_CONTAINER_ID, address(ALICE), 0);
        assertEq(item.timestamp, 1 minutes);
        assertEq(item.subscriptionId, 1);
        assertEq(item.interval, 1);

        // Bob 0th-index (first interval response)
        item = INBOX.read(HASHED_MOCK_CONTAINER_ID, address(BOB), 0);
        assertEq(item.timestamp, 1 minutes);
        assertEq(item.subscriptionId, 1);
        assertEq(item.interval, 1);

        // Alice 1st-index (second interval response)
        item = INBOX.read(HASHED_MOCK_CONTAINER_ID, address(ALICE), 1);
        assertEq(item.timestamp, 2 minutes);
        assertEq(item.subscriptionId, 1);
        assertEq(item.interval, 2);

        // Bob 1st-index (second interval response)
        item = INBOX.read(HASHED_MOCK_CONTAINER_ID, address(BOB), 1);
        assertEq(item.timestamp, 2 minutes);
        assertEq(item.subscriptionId, 1);
        assertEq(item.interval, 2);
    }
}

/// @title CoordinatorAllowlistSubscriptionTest
/// @notice Coordinator tests specific to usage by SubscriptionConsumer w/ Allowlist
/// @dev We test Allowlist functionality via just a `SubscriptionConsumer` base (rather than redundantly testing a `CallbackConsumer` base too)
contract CoordinatorAllowlistSubscriptionTest is CoordinatorTest {
    /// @notice Initial allowlist is set correctly at contract creation
    function testInitialAllowlistCorrectlySet() public {
        // Ensure Alice is an allowed node
        assertTrue(ALLOWLIST_SUBSCRIPTION.isAllowedNode(address(ALICE)));

        // Ensure Bob and Charlie are not allowed nodes
        assertFalse(ALLOWLIST_SUBSCRIPTION.isAllowedNode(address(BOB)));
        assertFalse(ALLOWLIST_SUBSCRIPTION.isAllowedNode(address(CHARLIE)));
    }

    /// @notice Allowlist can be updated
    function testFuzzAllowlistCanBeUpdated(address[] memory nodes, bool[] memory statuses) public {
        // Bound array length to smallest of two fuzzed arrays
        uint256 arrayLen = nodes.length > statuses.length ? statuses.length : nodes.length;

        // Use fuzzed length to generated bounded nodes/statuses array
        address[] memory boundedNodes = new address[](arrayLen);
        bool[] memory boundedStatuses = new bool[](arrayLen);
        for (uint256 i = 0; i < arrayLen; i++) {
            boundedNodes[i] = nodes[i];
            boundedStatuses[i] = statuses[i];
        }

        // Unallow Alice to begin (default initialized)
        address[] memory removeAliceNodes = new address[](1);
        removeAliceNodes[0] = address(ALICE);
        bool[] memory removeAliceStatus = new bool[](1);
        removeAliceStatus[0] = false;
        ALLOWLIST_SUBSCRIPTION.updateMockAllowlist(removeAliceNodes, removeAliceStatus);

        // Ensure Alice is no longer an allowed node
        assertFalse(ALLOWLIST_SUBSCRIPTION.isAllowedNode(address(ALICE)));

        // Update Allowlist with bounded fuzzed arrays
        ALLOWLIST_SUBSCRIPTION.updateMockAllowlist(boundedNodes, boundedStatuses);

        // Ensure Allowlist is updated against fuzzed values
        for (uint256 i = 0; i < arrayLen; i++) {
            // Nested iteration since we may have duplicated status updates and want to select just the latest
            // E.g: [addr0, addr1, addr0], [true, false, false] — addr0 is duplicated but status is just the latest applied (false)
            bool lastStatus = boundedStatuses[i];
            // Reverse iterate for latest occurence up to current index
            for (uint256 j = arrayLen - 1; j >= i; j--) {
                if (boundedNodes[i] == boundedNodes[j]) {
                    lastStatus = boundedStatuses[j];
                    break;
                }
            }

            assertEq(ALLOWLIST_SUBSCRIPTION.isAllowedNode(boundedNodes[i]), lastStatus);
        }
    }

    /// @notice Delivering response from an allowed node succeeds
    function testCanDeliverResponseFromAllowedNode() public {
        // Create subscription
        vm.warp(0);
        uint32 subId = ALLOWLIST_SUBSCRIPTION.createMockSubscription(
            MOCK_CONTAINER_ID, 1, 1 minutes, 1, false, NO_PAYMENT_TOKEN, 0, NO_WALLET, NO_VERIFIER
        );

        // Successfully fulfill from Alice
        vm.warp(1 minutes);
        ALICE.deliverCompute(subId, 1, MOCK_INPUT, MOCK_OUTPUT, MOCK_PROOF, NO_WALLET);
    }

    /// @notice Delivering response from an unallowed node fails
    function testFuzzCannotDeliverResponseFromUnallowedNode(address unallowedNode) public {
        // Ensure unallowed node is not Alice (default allowed at contract creation)
        vm.assume(unallowedNode != address(ALICE));

        // Create subscription
        vm.warp(0);
        uint32 subId = ALLOWLIST_SUBSCRIPTION.createMockSubscription(
            MOCK_CONTAINER_ID, 1, 1 minutes, 1, false, NO_PAYMENT_TOKEN, 0, NO_WALLET, NO_VERIFIER
        );

        // Attempt to fulfill from an unallowed node
        vm.warp(1 minutes);
        vm.startPrank(unallowedNode);

        // Expect `NodeNotAllowed` revert
        vm.expectRevert(Allowlist.NodeNotAllowed.selector);
        COORDINATOR.deliverCompute(subId, 1, MOCK_INPUT, MOCK_OUTPUT, MOCK_PROOF, payable(address(0)));
        vm.stopPrank();
    }

    /// @notice Delivering response from an allowed node across intervals succeeds
    function testCanDeliverResponseFromAllowedNodeAcrossIntervals() public {
        // Create subscription w/ frequency == 2
        vm.warp(0);
        uint32 subId = ALLOWLIST_SUBSCRIPTION.createMockSubscription(
            MOCK_CONTAINER_ID, 2, 1 minutes, 1, false, NO_PAYMENT_TOKEN, 0, NO_WALLET, NO_VERIFIER
        );

        // Fulfill once from Alice
        vm.warp(1 minutes);
        ALICE.deliverCompute(subId, 1, MOCK_INPUT, MOCK_OUTPUT, MOCK_PROOF, NO_WALLET);

        // Fulfill second time from Alice
        vm.warp(2 minutes);
        ALICE.deliverCompute(subId, 2, MOCK_INPUT, MOCK_OUTPUT, MOCK_PROOF, NO_WALLET);
    }

    /// @notice Delivering response from an allowed node across intervals where the node is unallowed in some intervals fails
    function testCanDeliverResponseFromNodeInAllowedIntervalsOnly() public {
        // Setup statuses array
        bool[10] memory statuses = [false, true, false, false, true, true, true, false, false, true];

        // Create subscription w/ frequency 10
        vm.warp(0);
        uint32 subId = ALLOWLIST_SUBSCRIPTION.createMockSubscription(
            MOCK_CONTAINER_ID, 10, 1 minutes, 1, false, NO_PAYMENT_TOKEN, 0, NO_WALLET, NO_VERIFIER
        );

        // Deliver response from Alice successfully or unsuccessfully depending on status in interval
        // Setup nodes array with just Alice (to correspond with each status update at each interval)
        address[] memory nodesArr = new address[](1);
        nodesArr[0] = address(ALICE);

        // For each (status, interval)-pair
        for (uint256 i = 0; i < statuses.length; i++) {
            // Setup delivery interval
            uint32 interval = uint32(i) + 1;

            // Warp to time of submission
            vm.warp(interval * 60);

            // Update Alice status according to statuses array
            bool newAliceStatus = statuses[i];
            bool[] memory statusArr = new bool[](1);
            statusArr[0] = newAliceStatus;
            ALLOWLIST_SUBSCRIPTION.updateMockAllowlist(nodesArr, statusArr);

            // Verify update is successful
            assertEq(ALLOWLIST_SUBSCRIPTION.isAllowedNode(address(ALICE)), newAliceStatus);

            // If status is unallowed, expect revert
            if (!newAliceStatus) {
                vm.expectRevert(Allowlist.NodeNotAllowed.selector);
            }
            ALICE.deliverCompute(subId, interval, MOCK_INPUT, MOCK_OUTPUT, MOCK_PROOF, NO_WALLET);
        }
    }

    /// @notice Delivering lazy subscription response from an unallowed node does not store authenticated `InboxItem` in `Inbox`
    function testInboxIsNotUpdatedOnUnallowedNodeFailedResponseDelivery() public {
        // Create subscription (w/ lazy = true)
        vm.warp(0);
        uint32 subId = ALLOWLIST_SUBSCRIPTION.createMockSubscription(
            MOCK_CONTAINER_ID, 1, 1 minutes, 1, true, NO_PAYMENT_TOKEN, 0, NO_WALLET, NO_VERIFIER
        );

        // Attempt to deliver from Bob expecting failure
        vm.warp(1 minutes);
        vm.expectRevert(Allowlist.NodeNotAllowed.selector);
        BOB.deliverCompute(subId, 1, MOCK_INPUT, MOCK_OUTPUT, MOCK_PROOF, NO_WALLET);

        // Ensure inbox item does not exist
        // Array out-of-bounds access since atomic tx execution previously failed
        vm.expectRevert();
        INBOX.read(HASHED_MOCK_CONTAINER_ID, address(BOB), 0);
    }
}

/// @title CoordinatorEagerPaymentNoProofTest
/// @notice Coordinator tests specific to eager subscriptions with payments but no proofs
contract CoordinatorEagerPaymentNoProofTest is CoordinatorTest {
    /// @notice Subscription can be fulfilled with ETH payment
    function testSubscriptionCanBeFulfilledWithETHPayment() public {
        // Create new wallet with Alice as owner
        address aliceWallet = WALLET_FACTORY.createWallet(address(ALICE));

        // Create new wallet with Bob as owner
        address bobWallet = WALLET_FACTORY.createWallet(address(BOB));

        // Fund alice wallet with 1 ether
        vm.deal(aliceWallet, 1 ether);

        // Create new one-time subscription with 1 eth payout
        uint32 subId = CALLBACK.createMockRequest(
            MOCK_CONTAINER_ID, MOCK_INPUT, 1, ZERO_ADDRESS, 1 ether, aliceWallet, NO_VERIFIER
        );

        // Allow CALLBACK consumer to spend alice wallet balance up to 1 ether
        vm.prank(address(ALICE));
        Wallet(payable(aliceWallet)).approve(address(CALLBACK), ZERO_ADDRESS, 1 ether);

        // Verify initial balances and allowances
        assertEq(aliceWallet.balance, 1 ether);

        // Execute response fulfillment from Bob
        BOB.deliverCompute(subId, 1, MOCK_INPUT, MOCK_OUTPUT, MOCK_PROOF, bobWallet);

        // Assert new balances
        assertEq(aliceWallet.balance, 0 ether);
        assertEq(bobWallet.balance, 0.8978 ether);
        assertEq(PROTOCOL.getEtherBalance(), 0.1022 ether);

        // Assert consumed allowance
        assertEq(Wallet(payable(aliceWallet)).allowance(address(CALLBACK), ZERO_ADDRESS), 0 ether);
    }

    /// @notice Subscription can be fulfilled with ERC20 payment
    function testSubscriptionCanBeFulfilledWithERC20() public {
        // Create new wallet with Alice as owner
        address aliceWallet = WALLET_FACTORY.createWallet(address(ALICE));

        // Create new wallet with Bob as owner
        address bobWallet = WALLET_FACTORY.createWallet(address(BOB));

        // Mint 100 tokens to alice wallet
        TOKEN.mint(aliceWallet, 100e6);

        // Create new one-time subscription with 50e6 payout
        uint32 subId =
            CALLBACK.createMockRequest(MOCK_CONTAINER_ID, MOCK_INPUT, 1, address(TOKEN), 50e6, aliceWallet, NO_VERIFIER);

        // Allow CALLBACK consumer to spend alice wallet balance up to 90e6 tokens
        vm.prank(address(ALICE));
        Wallet(payable(aliceWallet)).approve(address(CALLBACK), address(TOKEN), 90e6);

        // Verify initial balances and allowances
        assertEq(TOKEN.balanceOf(aliceWallet), 100e6);

        // Execute response fulfillment from Bob
        BOB.deliverCompute(subId, 1, MOCK_INPUT, MOCK_OUTPUT, MOCK_PROOF, bobWallet);

        // Assert new balances
        assertEq(TOKEN.balanceOf(aliceWallet), 50e6);
        assertEq(TOKEN.balanceOf(bobWallet), 44_890_000);
        assertEq(PROTOCOL.getTokenBalance(address(TOKEN)), 5_110_000);

        // Assert consumed allowance
        assertEq(Wallet(payable(aliceWallet)).allowance(address(CALLBACK), address(TOKEN)), 40e6);
    }

    /// @notice Subscription can be fulfilled across intervals with ERC20 payment
    function testSubscriptionCanBeFulfilledAcrossIntervalsWithERC20Payment() public {
        // Create new wallet with Alice as owner
        address aliceWallet = WALLET_FACTORY.createWallet(address(ALICE));

        // Create new wallet with Bob as owner
        address bobWallet = WALLET_FACTORY.createWallet(address(BOB));

        // Mint 100 tokens to alice wallet
        TOKEN.mint(aliceWallet, 100e6);

        // Create new two-time subscription with 40e6 payout
        vm.warp(0 minutes);
        uint32 subId = SUBSCRIPTION.createMockSubscription(
            MOCK_CONTAINER_ID, 2, 1 minutes, 1, false, address(TOKEN), 40e6, aliceWallet, NO_VERIFIER
        );

        // Allow CALLBACK consumer to spend alice wallet balance up to 90e6 tokens
        vm.prank(address(ALICE));
        Wallet(payable(aliceWallet)).approve(address(SUBSCRIPTION), address(TOKEN), 90e6);

        // Verify initial balances and allowances
        assertEq(TOKEN.balanceOf(aliceWallet), 100e6);

        // Execute response fulfillment from Bob
        vm.warp(1 minutes);
        BOB.deliverCompute(subId, 1, MOCK_INPUT, MOCK_OUTPUT, MOCK_PROOF, bobWallet);

        // Execute response fulfillment from Charlie (notice that for no proof submissions there is no collateral so we can use any wallet)
        vm.warp(2 minutes);
        CHARLIE.deliverCompute(subId, 2, MOCK_INPUT, MOCK_OUTPUT, MOCK_PROOF, bobWallet);

        // Assert new balances
        assertEq(TOKEN.balanceOf(aliceWallet), 20e6);
        assertEq(TOKEN.balanceOf(bobWallet), (40e6 * 2) - (4_088_000 * 2));
        assertEq(PROTOCOL.getTokenBalance(address(TOKEN)), 4_088_000 * 2);

        // Assert consumed allowance
        assertEq(Wallet(payable(aliceWallet)).allowance(address(SUBSCRIPTION), address(TOKEN)), 10e6);
    }

    /// @notice Subscription cannot be fulfilled with an invalid `Wallet` not created by `WalletFactory`
    function testSubscriptionCannotBeFulfilledWithInvalidWalletProvenance() public {
        // Create new wallet for Alice directly
        Wallet aliceWallet = new Wallet(REGISTRY, address(ALICE));

        // Create new wallet with Bob as owner
        address bobWallet = WALLET_FACTORY.createWallet(address(BOB));

        // Create new one-time subscription with 50e6 payout
        uint32 subId = CALLBACK.createMockRequest(
            MOCK_CONTAINER_ID, MOCK_INPUT, 1, address(TOKEN), 50e6, address(aliceWallet), NO_VERIFIER
        );

        // Execute response fulfillment from Bob, expecting failure
        vm.expectRevert(Coordinator.InvalidWallet.selector);
        BOB.deliverCompute(subId, 1, MOCK_INPUT, MOCK_OUTPUT, MOCK_PROOF, bobWallet);
    }

    /// @notice Subscription cannot be fulfilled with an invalid `nodeWallet` not created by `WalletFactory`
    function testSubscriptionCannotBeFulfilledWithInvalidNodeWalletProvenance() public {
        // Create new wallet with Alice as owner
        address aliceWallet = WALLET_FACTORY.createWallet(address(ALICE));

        // Create new one-time subscription with 50e6 payout
        uint32 subId =
            CALLBACK.createMockRequest(MOCK_CONTAINER_ID, MOCK_INPUT, 1, address(TOKEN), 50e6, aliceWallet, NO_VERIFIER);

        // Execute response fulfillment from Bob using address(BOB) as nodeWallet
        vm.expectRevert(Coordinator.InvalidWallet.selector);
        BOB.deliverCompute(subId, 1, MOCK_INPUT, MOCK_OUTPUT, MOCK_PROOF, address(BOB));
    }

    /// @notice Subscription cannot be fulfilled if `Wallet` does not approve consumer
    function testSubscriptionCannotBeFulfilledIfSpenderNoAllowance() public {
        // Create new wallets
        address aliceWallet = WALLET_FACTORY.createWallet(address(ALICE));
        address bobWallet = WALLET_FACTORY.createWallet(address(BOB));

        // Fund alice wallet with 1 ether
        vm.deal(aliceWallet, 1 ether);

        // Create new one-time subscription with 1 eth payout
        uint32 subId = CALLBACK.createMockRequest(
            MOCK_CONTAINER_ID, MOCK_INPUT, 1, ZERO_ADDRESS, 1 ether, aliceWallet, NO_VERIFIER
        );

        // Verify CALLBACK has 0 allowance to spend on aliceWallet
        assertEq(Wallet(payable(aliceWallet)).allowance(address(CALLBACK), ZERO_ADDRESS), 0 ether);

        // Execute response fulfillment from Bob expecting failure when paying protocol fee
        vm.expectRevert(Wallet.InsufficientAllowance.selector);
        BOB.deliverCompute(subId, 1, MOCK_INPUT, MOCK_OUTPUT, MOCK_PROOF, bobWallet);
    }

    /// @notice Subscription cannot be fulfilled if `Wallet` only partially approves consumer
    function testSubscriptionCannotBeFulfilledIfSpenderPartialAllowance() public {
        // Create new wallets
        address aliceWallet = WALLET_FACTORY.createWallet(address(ALICE));
        address bobWallet = WALLET_FACTORY.createWallet(address(BOB));

        // Fund alice wallet with 1 ether
        vm.deal(aliceWallet, 1 ether);

        // Create new one-time subscription with 1 eth payout
        uint32 subId = CALLBACK.createMockRequest(
            MOCK_CONTAINER_ID, MOCK_INPUT, 1, ZERO_ADDRESS, 1 ether, aliceWallet, NO_VERIFIER
        );

        // Increase callback allowance to just under 1 ether
        vm.startPrank(address(ALICE));
        Wallet(payable(aliceWallet)).approve(address(CALLBACK), ZERO_ADDRESS, 1 ether - 1 wei);

        // Execute response fulfillment from Bob expecting failure when paying protocol fee
        vm.expectRevert(Wallet.InsufficientAllowance.selector);
        BOB.deliverCompute(subId, 1, MOCK_INPUT, MOCK_OUTPUT, MOCK_PROOF, bobWallet);
    }
}

/// @title CoordinatorLazyPaymentNoProofTest
/// @notice Coordinator tests specific to lazy subscriptions with payments but no proofs
contract CoordinatorLazyPaymentNoProofTest is CoordinatorTest {
    /// @notice Subscription can be fulfilled with ETH payment
    function testLazySubscriptionCanBeFulfilledWithPayment() public {
        // Create new wallets
        address aliceWallet = WALLET_FACTORY.createWallet(address(ALICE));
        address bobWallet = WALLET_FACTORY.createWallet(address(BOB));

        // Mint 100 tokens to alice wallet
        TOKEN.mint(aliceWallet, 100e6);

        // Create new one-time subscription with 40e6 payout
        vm.warp(0 minutes);
        uint32 subId = SUBSCRIPTION.createMockSubscription(
            MOCK_CONTAINER_ID,
            1,
            1 minutes,
            1,
            true, // lazy == true
            address(TOKEN),
            40e6,
            aliceWallet,
            NO_VERIFIER
        );

        // Allow CALLBACK consumer to spend alice wallet balance up to 90e6 tokens
        vm.prank(address(ALICE));
        Wallet(payable(aliceWallet)).approve(address(SUBSCRIPTION), address(TOKEN), 90e6);

        // Verify initial balances and allowances
        assertEq(TOKEN.balanceOf(aliceWallet), 100e6);

        // Execute response fulfillment from Bob
        vm.warp(1 minutes);
        BOB.deliverCompute(subId, 1, MOCK_INPUT, MOCK_OUTPUT, MOCK_PROOF, bobWallet);

        // Assert new balances
        assertEq(TOKEN.balanceOf(aliceWallet), 60e6);
        assertEq(TOKEN.balanceOf(bobWallet), 35_912_000);
        assertEq(PROTOCOL.getTokenBalance(address(TOKEN)), 4_088_000);

        // Assert consumed allowance
        assertEq(Wallet(payable(aliceWallet)).allowance(address(SUBSCRIPTION), address(TOKEN)), 50e6);
    }
}

/// @title CoordinatorEagerPaymentProofTest
/// @notice Coordinator tests specific to eager subscriptions with payments and proofs
contract CoordinatorEagerPaymentProofTest is CoordinatorTest {
    /// @notice Subscription cannot be fulfilled if node is not approved to spend from wallet
    function testSubscriptionCannotBeFulfilledIfNodeNotApprovedToSpendFromWallet() public {
        // Create new wallets
        address aliceWallet = WALLET_FACTORY.createWallet(address(ALICE));
        address bobWallet = WALLET_FACTORY.createWallet(address(BOB));

        // Mint 50 tokens to alice wallet
        TOKEN.mint(aliceWallet, 50e6);

        // Mint 50 tokens to bob wallet (ensuring node has sufficient funds to put up for escrow)
        TOKEN.mint(bobWallet, 50e6);

        // Create new one-time subscription with 40e6 payout
        uint32 subId = CALLBACK.createMockRequest(
            MOCK_CONTAINER_ID,
            MOCK_INPUT,
            1,
            address(TOKEN),
            50e6,
            aliceWallet,
            // Specify atomic verifier
            address(ATOMIC_VERIFIER)
        );

        // Allow CALLBACK consumer to spend alice wallet balance up to 50e6 tokens
        vm.prank(address(ALICE));
        Wallet(payable(aliceWallet)).approve(address(CALLBACK), address(TOKEN), 50e6);

        // Verify initial balances and allowances
        assertEq(TOKEN.balanceOf(aliceWallet), 50e6);
        assertEq(TOKEN.balanceOf(bobWallet), 50e6);

        // Setup atomic verifier approved token + fee (5 tokens)
        ATOMIC_VERIFIER.updateSupportedToken(address(TOKEN), true);
        ATOMIC_VERIFIER.updateFee(address(TOKEN), 5e6);

        // Ensure that atomic verifier will return true for proof verification
        ATOMIC_VERIFIER.setNextValidityTrue();

        // Execute response fulfillment from Charlie expecting it to fail given no authorization to Bob's wallet
        vm.warp(1 minutes);
        vm.expectRevert(Wallet.InsufficientAllowance.selector);
        CHARLIE.deliverCompute(subId, 1, MOCK_INPUT, MOCK_OUTPUT, MOCK_PROOF, bobWallet);
    }

    /// @notice Subscription cannot be fulfilled if node wallet has insufficient funds for escrow
    function testSubscriptionCannotBeFulfilledIfNodeWalletHasInsufficientFundsForEscrow() public {
        // Create new wallets
        address aliceWallet = WALLET_FACTORY.createWallet(address(ALICE));
        address bobWallet = WALLET_FACTORY.createWallet(address(BOB));

        // Mint 50 tokens to alice wallet (but not to Bob's wallet)
        TOKEN.mint(aliceWallet, 50e6);

        // Create new one-time subscription with 40e6 payout
        uint32 subId = CALLBACK.createMockRequest(
            MOCK_CONTAINER_ID,
            MOCK_INPUT,
            1,
            address(TOKEN),
            50e6,
            aliceWallet,
            // Specify atomic verifier
            address(ATOMIC_VERIFIER)
        );

        // Allow CALLBACK consumer to spend alice wallet balance up to 50e6 tokens
        vm.prank(address(ALICE));
        Wallet(payable(aliceWallet)).approve(address(CALLBACK), address(TOKEN), 50e6);

        // Allow BOB to sepnd bob wallet balance up to 50e6 tokens
        vm.prank(address(BOB));
        Wallet(payable(bobWallet)).approve(address(BOB), address(TOKEN), 50e6);

        // Verify initial balances and allowances
        assertEq(TOKEN.balanceOf(aliceWallet), 50e6);
        assertEq(TOKEN.balanceOf(bobWallet), 0e6);

        // Setup atomic verifier approved token + fee (5 tokens)
        ATOMIC_VERIFIER.updateSupportedToken(address(TOKEN), true);
        ATOMIC_VERIFIER.updateFee(address(TOKEN), 5e6);

        // Ensure that atomic verifier will return true for proof verification
        ATOMIC_VERIFIER.setNextValidityTrue();

        // Execute response fulfillment expecting it to fail given not enough unlocked funds
        vm.warp(1 minutes);
        vm.expectRevert(Wallet.InsufficientFunds.selector);
        BOB.deliverCompute(subId, 1, MOCK_INPUT, MOCK_OUTPUT, MOCK_PROOF, bobWallet);
    }

    /// @notice Subscription can be fulfilled with ERC20 payment when proof validates correctly
    function testSubscriptionFulfillmentWithEagerProofValidatingTrue() public {
        // Create new wallets
        address aliceWallet = WALLET_FACTORY.createWallet(address(ALICE));
        address bobWallet = WALLET_FACTORY.createWallet(address(BOB));

        // Mint 50 tokens to wallets
        TOKEN.mint(aliceWallet, 50e6);
        TOKEN.mint(bobWallet, 50e6);

        // Create new one-time subscription with 40e6 payout
        uint32 subId = CALLBACK.createMockRequest(
            MOCK_CONTAINER_ID,
            MOCK_INPUT,
            1,
            address(TOKEN),
            40e6,
            aliceWallet,
            // Specify atomic verifier
            address(ATOMIC_VERIFIER)
        );

        // Allow CALLBACK consumer to spend alice wallet balance up to 50e6 tokens
        vm.prank(address(ALICE));
        Wallet(payable(aliceWallet)).approve(address(CALLBACK), address(TOKEN), 50e6);

        // Allow Bob to spend bob wallet balance up to 50e6 tokens
        vm.prank(address(BOB));
        Wallet(payable(bobWallet)).approve(address(BOB), address(TOKEN), 50e6);

        // Verify initial balances and allowances
        assertEq(TOKEN.balanceOf(aliceWallet), 50e6);
        assertEq(TOKEN.balanceOf(bobWallet), 50e6);

        // Setup atomic verifier approved token + fee (5 tokens)
        ATOMIC_VERIFIER.updateSupportedToken(address(TOKEN), true);
        ATOMIC_VERIFIER.updateFee(address(TOKEN), 5e6);

        // Ensure that atomic verifier will return true for proof verification
        ATOMIC_VERIFIER.setNextValidityTrue();

        // Execute response fulfillment from Bob
        vm.warp(1 minutes);
        BOB.deliverCompute(subId, 1, MOCK_INPUT, MOCK_OUTPUT, MOCK_PROOF, bobWallet);

        // Assert new balances
        assertEq(TOKEN.balanceOf(aliceWallet), 10e6); // -40
        assertEq(TOKEN.balanceOf(bobWallet), 80_912_000); // 50 (initial) + (40 - (40 * 5.11% * 2) - (5))
        assertEq(TOKEN.balanceOf(address(ATOMIC_VERIFIER)), 4_744_500); // (5 - (5 * 5.11%))
        assertEq(PROTOCOL.getTokenBalance(address(TOKEN)), 4_343_500);

        // Assert consumed allowance
        assertEq(Wallet(payable(aliceWallet)).allowance(address(CALLBACK), address(TOKEN)), 10e6);
        assertEq(Wallet(payable(bobWallet)).allowance(address(BOB), address(TOKEN)), 50e6);
    }

    /// @notice Node operator is slashed when proof validates incorrectly
    function testSubscriptionFulfillmentWithEagerProofValidatingFalse() public {
        // Create new wallets
        address aliceWallet = WALLET_FACTORY.createWallet(address(ALICE));
        address bobWallet = WALLET_FACTORY.createWallet(address(BOB));

        // Mint 1 ether to Alice and Bob
        vm.deal(address(aliceWallet), 1 ether);
        vm.deal(address(bobWallet), 1 ether);

        // Create new one-time subscription with 1 ether payout
        uint32 subId = CALLBACK.createMockRequest(
            MOCK_CONTAINER_ID,
            MOCK_INPUT,
            1,
            ZERO_ADDRESS,
            1 ether,
            aliceWallet,
            // Specify atomic verifier
            address(ATOMIC_VERIFIER)
        );

        // Allow CALLBACK consumer to spend alice wallet balance up to 1 ether
        vm.prank(address(ALICE));
        Wallet(payable(aliceWallet)).approve(address(CALLBACK), ZERO_ADDRESS, 1 ether);

        // Allow Bob to spend bob wallet balance up to 1 ether
        vm.prank(address(BOB));
        Wallet(payable(bobWallet)).approve(address(BOB), ZERO_ADDRESS, 1 ether);

        // Verify initial balances and allowances
        assertEq(aliceWallet.balance, 1 ether);
        assertEq(bobWallet.balance, 1 ether);

        // Setup atomic verifier approved token + fee (0.111 ether)
        ATOMIC_VERIFIER.updateSupportedToken(ZERO_ADDRESS, true);
        ATOMIC_VERIFIER.updateFee(ZERO_ADDRESS, 111e15);

        // Ensure that atomic verifier will return false for proof verification
        ATOMIC_VERIFIER.setNextValidityFalse();

        // Execute response fulfillment from Bob
        vm.warp(1 minutes);
        BOB.deliverCompute(subId, 1, MOCK_INPUT, MOCK_OUTPUT, MOCK_PROOF, bobWallet);

        // Assert new balances
        // Alice --> 1 ether - protocol fee (0.1022 ether) - verifier fee (0.111 ether) + slashed (1 ether) = 1.7868 ether
        assertEq(aliceWallet.balance, 17_868e14);
        // Bob --> -1 ether
        assertEq(bobWallet.balance, 0 ether);
        // verifier --> +0.111 * (1 - 0.0511) ether = 0.1053279 ether
        assertEq(ATOMIC_VERIFIER.getEtherBalance(), 1_053_279e11);
        // Protocol --> feeFromConsumer (0.1022 ether) + feeFromVerifier (0.0056721 ether) = 0.1078721 ether
        assertEq(PROTOCOL.getEtherBalance(), 1_078_721e11);

        // Assert consumed allowance
        assertEq(Wallet(payable(aliceWallet)).allowance(address(CALLBACK), ZERO_ADDRESS), 7868e14);
        assertEq(Wallet(payable(bobWallet)).allowance(address(BOB), ZERO_ADDRESS), 0 ether);
    }
}

/// @title CoordinatorLazyPaymentProofTest
/// @notice Coordinator tests specific to lazy subscriptions with payments and proofs
contract CoordinatorLazyPaymentProofTest is CoordinatorTest {
    /// @notice Subscription cannot be fulfilled with incorrect proof verification
    function testSubscriptionCannotBeFinalizedWithIncorrectProofValidation() public {
        // Create new wallets
        address aliceWallet = WALLET_FACTORY.createWallet(address(ALICE));
        address bobWallet = WALLET_FACTORY.createWallet(address(BOB));

        // Mint 1 ether to Alice and Bob
        vm.deal(address(aliceWallet), 1 ether);
        vm.deal(address(bobWallet), 1 ether);

        // Create new one-time subscription with 1 ether payout
        uint32 subId = CALLBACK.createMockRequest(
            MOCK_CONTAINER_ID,
            MOCK_INPUT,
            1,
            ZERO_ADDRESS,
            1 ether,
            aliceWallet,
            // Specify optimistic verifier
            address(OPTIMISTIC_VERIFIER)
        );

        // Allow CALLBACK consumer to spend alice wallet balance up to 1 ether
        vm.prank(address(ALICE));
        Wallet(payable(aliceWallet)).approve(address(CALLBACK), ZERO_ADDRESS, 1 ether);

        // Allow Bob to spend bob wallet balance up to 1 ether
        vm.prank(address(BOB));
        Wallet(payable(bobWallet)).approve(address(BOB), ZERO_ADDRESS, 1 ether);

        // Verify initial balances and allowances
        assertEq(aliceWallet.balance, 1 ether);
        assertEq(bobWallet.balance, 1 ether);

        // Setup optimistic verifier approved token + fee (0.1 ether)
        OPTIMISTIC_VERIFIER.updateSupportedToken(ZERO_ADDRESS, true);
        OPTIMISTIC_VERIFIER.updateFee(ZERO_ADDRESS, 1e17);

        // Execute response fulfillment from Bob
        BOB.deliverCompute(subId, 1, MOCK_INPUT, MOCK_OUTPUT, MOCK_PROOF, bobWallet);

        // Attempt to fulfill with incorrect proof verification data
        vm.expectRevert(Coordinator.ProofRequestNotFound.selector);
        OPTIMISTIC_VERIFIER.mockDeliverProof(subId + 1, 1, address(BOB), true);
    }

    /// @notice Subscription can be fulfilled with payment when proof validates correctly
    function testLazySubscriptionWithProofCanBeFulfilledWhenProofValidatesCorrectlyInTime() public {
        // Create new wallets
        address aliceWallet = WALLET_FACTORY.createWallet(address(ALICE));
        address bobWallet = WALLET_FACTORY.createWallet(address(BOB));

        // Mint 1 ether to Alice and Bob
        vm.deal(address(aliceWallet), 1 ether);
        vm.deal(address(bobWallet), 1 ether);

        // Create new one-time subscription with 1 ether payout
        uint32 subId = CALLBACK.createMockRequest(
            MOCK_CONTAINER_ID,
            MOCK_INPUT,
            1,
            ZERO_ADDRESS,
            1 ether,
            aliceWallet,
            // Specify optimistic verifier
            address(OPTIMISTIC_VERIFIER)
        );

        // Allow CALLBACK consumer to spend alice wallet balance up to 1 ether
        vm.prank(address(ALICE));
        Wallet(payable(aliceWallet)).approve(address(CALLBACK), ZERO_ADDRESS, 1 ether);

        // Allow Bob to spend bob wallet balance up to 1 ether
        vm.prank(address(BOB));
        Wallet(payable(bobWallet)).approve(address(BOB), ZERO_ADDRESS, 1 ether);

        // Verify initial balances and allowances
        assertEq(aliceWallet.balance, 1 ether);
        assertEq(bobWallet.balance, 1 ether);

        // Setup optimistic verifier approved token + fee (0.1 ether)
        OPTIMISTIC_VERIFIER.updateSupportedToken(ZERO_ADDRESS, true);
        OPTIMISTIC_VERIFIER.updateFee(ZERO_ADDRESS, 1e17);

        // Execute response fulfillment from Bob
        BOB.deliverCompute(subId, 1, MOCK_INPUT, MOCK_OUTPUT, MOCK_PROOF, bobWallet);

        // Assert immediate balances
        // Alice -> 1 ether - protocol fee (0.1022 ether) - verifier fee (0.1 ether)
        // Alice --> allowance: 0 ether
        assertEq(aliceWallet.balance, 7978e14);
        assertEq(Wallet(payable(aliceWallet)).allowance(address(CALLBACK), ZERO_ADDRESS), 0);
        // Bob --> 1 ether
        // Bob --> allowance: 0 ether
        assertEq(bobWallet.balance, 1 ether);
        assertEq(Wallet(payable(bobWallet)).allowance(address(BOB), ZERO_ADDRESS), 0);
        // verifier --> 0.1 * (1 - 0.0511) ether = 0.09489 ether
        assertEq(OPTIMISTIC_VERIFIER.getEtherBalance(), 9489e13);
        // Protocol --> feeFromConsumer (0.1022 ether) + feeFromVerifier (0.00511 ether) = 0.10731 ether
        assertEq(PROTOCOL.getEtherBalance(), 10_731e13);

        // Fast forward 1 day and trigger optimistic response with valid: true
        vm.warp(1 days);
        OPTIMISTIC_VERIFIER.mockDeliverProof(subId, 1, address(BOB), true);

        // Assert new balances
        // Alice --> 0 ether
        assertEq(aliceWallet.balance, 0 ether);
        assertEq(Wallet(payable(aliceWallet)).allowance(address(CALLBACK), ZERO_ADDRESS), 0);
        // Bob --> 1 ether + 7978e14 ether
        // Bob --> allowance: 1 ether
        assertEq(bobWallet.balance, 17_978e14);
        assertEq(Wallet(payable(bobWallet)).allowance(address(BOB), ZERO_ADDRESS), 1 ether);
        // verifier, protocol stay same
        assertEq(OPTIMISTIC_VERIFIER.getEtherBalance(), 9489e13);
        assertEq(PROTOCOL.getEtherBalance(), 10_731e13);
    }

    /// @notice Subscription can be fulfilled when proof validates correctly, even after subscription is cancelled
    function testPaymentCanBeFulfilledEvenWhenSubscriptionIsCancelled() public {
        // Create new wallets
        address aliceWallet = WALLET_FACTORY.createWallet(address(ALICE));
        address bobWallet = WALLET_FACTORY.createWallet(address(BOB));

        // Mint 1 ether to Alice and Bob
        vm.deal(address(aliceWallet), 1 ether);
        vm.deal(address(bobWallet), 1 ether);

        // Create new one-time subscription with 1 ether payout
        uint32 subId = CALLBACK.createMockRequest(
            MOCK_CONTAINER_ID,
            MOCK_INPUT,
            1,
            ZERO_ADDRESS,
            1 ether,
            aliceWallet,
            // Specify optimistic verifier
            address(OPTIMISTIC_VERIFIER)
        );

        // Allow CALLBACK consumer to spend alice wallet balance up to 1 ether
        vm.prank(address(ALICE));
        Wallet(payable(aliceWallet)).approve(address(CALLBACK), ZERO_ADDRESS, 1 ether);

        // Allow Bob to spend bob wallet balance up to 1 ether
        vm.prank(address(BOB));
        Wallet(payable(bobWallet)).approve(address(BOB), ZERO_ADDRESS, 1 ether);

        // Verify initial balances and allowances
        assertEq(aliceWallet.balance, 1 ether);
        assertEq(bobWallet.balance, 1 ether);

        // Setup optimistic verifier approved token + fee (0.1 ether)
        OPTIMISTIC_VERIFIER.updateSupportedToken(ZERO_ADDRESS, true);
        OPTIMISTIC_VERIFIER.updateFee(ZERO_ADDRESS, 1e17);

        // Execute response fulfillment from Bob
        BOB.deliverCompute(subId, 1, MOCK_INPUT, MOCK_OUTPUT, MOCK_PROOF, bobWallet);

        // Cancel subscription
        vm.prank(address(CALLBACK));
        COORDINATOR.cancelSubscription(subId);

        // Assert subscription is cancelled
        Subscription memory sub = COORDINATOR.getSubscription(subId);
        assertEq(sub.activeAt, type(uint32).max);

        // Fast forward 1 day and trigger optimistic response with valid: true
        vm.warp(1 days);
        OPTIMISTIC_VERIFIER.mockDeliverProof(subId, 1, address(BOB), true);

        // Assert new balances
        // Alice --> 0 ether
        assertEq(aliceWallet.balance, 0 ether);
        assertEq(Wallet(payable(aliceWallet)).allowance(address(CALLBACK), ZERO_ADDRESS), 0);
        // Bob --> 1 ether + 7978e14 ether
        // Bob --> allowance: 1 ether
        assertEq(bobWallet.balance, 17_978e14);
        assertEq(Wallet(payable(bobWallet)).allowance(address(BOB), ZERO_ADDRESS), 1 ether);
        // verifier, protocol stay same
        assertEq(OPTIMISTIC_VERIFIER.getEtherBalance(), 9489e13);
        assertEq(PROTOCOL.getEtherBalance(), 10_731e13);
    }

    /// @notice Node operator is slashed when proof validates incorrectly
    function testLazySubscriptionWithProofCanBeFulfilledWhenNodeIsSlashedInTime() public {
        // Create new wallets
        address aliceWallet = WALLET_FACTORY.createWallet(address(ALICE));
        address bobWallet = WALLET_FACTORY.createWallet(address(BOB));

        // Mint 1 ether to Alice and Bob
        vm.deal(address(aliceWallet), 1 ether);
        vm.deal(address(bobWallet), 1 ether);

        // Create new one-time subscription with 1 ether payout
        uint32 subId = CALLBACK.createMockRequest(
            MOCK_CONTAINER_ID,
            MOCK_INPUT,
            1,
            ZERO_ADDRESS,
            1 ether,
            aliceWallet,
            // Specify optimistic verifier
            address(OPTIMISTIC_VERIFIER)
        );

        // Allow CALLBACK consumer to spend alice wallet balance up to 1 ether
        vm.prank(address(ALICE));
        Wallet(payable(aliceWallet)).approve(address(CALLBACK), ZERO_ADDRESS, 1 ether);

        // Allow Bob to spend bob wallet balance up to 1 ether
        vm.prank(address(BOB));
        Wallet(payable(bobWallet)).approve(address(BOB), ZERO_ADDRESS, 1 ether);

        // Verify initial balances and allowances
        assertEq(aliceWallet.balance, 1 ether);
        assertEq(bobWallet.balance, 1 ether);

        // Setup optimistic verifier approved token + fee (0.1 ether)
        OPTIMISTIC_VERIFIER.updateSupportedToken(ZERO_ADDRESS, true);
        OPTIMISTIC_VERIFIER.updateFee(ZERO_ADDRESS, 1e17);

        // Execute response fulfillment from Bob
        BOB.deliverCompute(subId, 1, MOCK_INPUT, MOCK_OUTPUT, MOCK_PROOF, bobWallet);

        // Assert immediate balances
        // Alice -> 1 ether - protocol fee (0.1022 ether) - verifier fee (0.1 ether)
        // Alice --> allowance: 0 ether
        assertEq(aliceWallet.balance, 7978e14);
        assertEq(Wallet(payable(aliceWallet)).allowance(address(CALLBACK), ZERO_ADDRESS), 0);
        // Bob --> 1 ether
        // Bob --> allowance: 0 ether
        assertEq(bobWallet.balance, 1 ether);
        assertEq(Wallet(payable(bobWallet)).allowance(address(BOB), ZERO_ADDRESS), 0);
        // verifier --> 0.1 * (1 - 0.0511) ether = 0.09489 ether
        assertEq(OPTIMISTIC_VERIFIER.getEtherBalance(), 9489e13);
        // Protocol --> feeFromConsumer (0.1022 ether) + feeFromVerifier (0.00511 ether) = 0.10731 ether
        assertEq(PROTOCOL.getEtherBalance(), 10_731e13);

        // Fast forward 1 day and trigger optimistic response with valid: false
        vm.warp(1 days);
        OPTIMISTIC_VERIFIER.mockDeliverProof(subId, 1, address(BOB), false);

        // Assert new balances
        // Alice --> 1 ether - protocol fee (0.1022 ether) - verifier fee (0.1 ether) + 1 ether (slashed from node)
        // Alice --> allowance: 1 ether - protocol fee (0.1022 ether) - verifier fee (0.1 ether)
        assertEq(aliceWallet.balance, 17_978e14);
        assertEq(Wallet(payable(aliceWallet)).allowance(address(CALLBACK), ZERO_ADDRESS), 7978e14);
        // Bob --> 0 ether
        // Bob --> allowance: 0 ether
        assertEq(bobWallet.balance, 0);
        assertEq(Wallet(payable(bobWallet)).allowance(address(BOB), ZERO_ADDRESS), 0 ether);
        // verifier, protocol stay same
        assertEq(OPTIMISTIC_VERIFIER.getEtherBalance(), 9489e13);
        assertEq(PROTOCOL.getEtherBalance(), 10_731e13);
    }

    /// @notice Subscription can be fulfilled with ERC20 payment when proof request time expires
    function testLazySubscriptionCanBeFulfilledWhenProofWindowExpires() public {
        // Create new wallets
        address aliceWallet = WALLET_FACTORY.createWallet(address(ALICE));
        address bobWallet = WALLET_FACTORY.createWallet(address(BOB));

        // Mint 1 ether to Alice and Bob
        vm.deal(address(aliceWallet), 1 ether);
        vm.deal(address(bobWallet), 1 ether);

        // Create new one-time subscription with 1 ether payout
        vm.warp(0);
        uint32 subId = CALLBACK.createMockRequest(
            MOCK_CONTAINER_ID,
            MOCK_INPUT,
            1,
            ZERO_ADDRESS,
            1 ether,
            aliceWallet,
            // Specify optimistic verifier
            address(OPTIMISTIC_VERIFIER)
        );

        // Allow CALLBACK consumer to spend alice wallet balance up to 1 ether
        vm.prank(address(ALICE));
        Wallet(payable(aliceWallet)).approve(address(CALLBACK), ZERO_ADDRESS, 1 ether);

        // Allow Bob to spend bob wallet balance up to 1 ether
        vm.prank(address(BOB));
        Wallet(payable(bobWallet)).approve(address(BOB), ZERO_ADDRESS, 1 ether);

        // Verify initial balances and allowances
        assertEq(aliceWallet.balance, 1 ether);
        assertEq(bobWallet.balance, 1 ether);

        // Setup optimistic verifier approved token + fee (0.1 ether)
        OPTIMISTIC_VERIFIER.updateSupportedToken(ZERO_ADDRESS, true);
        OPTIMISTIC_VERIFIER.updateFee(ZERO_ADDRESS, 1e17);

        // Execute response fulfillment from Bob
        BOB.deliverCompute(subId, 1, MOCK_INPUT, MOCK_OUTPUT, MOCK_PROOF, bobWallet);

        // Assert immediate balances
        // Alice -> 1 ether - protocol fee (0.1022 ether) - verifier fee (0.1 ether)
        // Alice --> allowance: 0 ether
        assertEq(aliceWallet.balance, 7978e14);
        assertEq(Wallet(payable(aliceWallet)).allowance(address(CALLBACK), ZERO_ADDRESS), 0);
        // Bob --> 1 ether
        // Bob --> allowance: 0 ether
        assertEq(bobWallet.balance, 1 ether);
        assertEq(Wallet(payable(bobWallet)).allowance(address(BOB), ZERO_ADDRESS), 0);
        // verifier --> 0.1 * (1 - 0.0511) ether = 0.09489 ether
        assertEq(OPTIMISTIC_VERIFIER.getEtherBalance(), 9489e13);
        // Protocol --> feeFromConsumer (0.1022 ether) + feeFromVerifier (0.00511 ether) = 0.10731 ether
        assertEq(PROTOCOL.getEtherBalance(), 10_731e13);

        // Fast forward 1 week and trigger forced proof verification
        vm.warp(1 weeks);
        COORDINATOR.finalizeProofVerification(subId, 1, address(BOB), true);

        // Assert new balances
        // Alice --> 0 ether
        assertEq(aliceWallet.balance, 0 ether);
        assertEq(Wallet(payable(aliceWallet)).allowance(address(CALLBACK), ZERO_ADDRESS), 0);
        // Bob --> 1 ether + 7978e14 ether
        // Bob --> allowance: 1 ether
        assertEq(bobWallet.balance, 17_978e14);
        assertEq(Wallet(payable(bobWallet)).allowance(address(BOB), ZERO_ADDRESS), 1 ether);
        // verifier, protocol stay same
        assertEq(OPTIMISTIC_VERIFIER.getEtherBalance(), 9489e13);
        assertEq(PROTOCOL.getEtherBalance(), 10_731e13);
    }

    /// @notice Multiple subscriptions can be fulfilled in parallel with lazy payout duration
    function testMultipleSubscriptionsCanBeFullfilledInParallelToLazyProof() public {
        // Create new wallets
        address aliceWallet = WALLET_FACTORY.createWallet(address(ALICE));
        address bobWallet = WALLET_FACTORY.createWallet(address(BOB));

        // Mint 2 ether to Alice and Bob
        vm.deal(address(aliceWallet), 2 ether);
        vm.deal(address(bobWallet), 2 ether);

        // Create new recurring subscription with 1 ether payout
        vm.warp(0);
        uint32 subId = SUBSCRIPTION.createMockSubscription(
            MOCK_CONTAINER_ID,
            2,
            1 days,
            1,
            true,
            ZERO_ADDRESS,
            1 ether,
            aliceWallet,
            // Specify optimistic verifier
            address(OPTIMISTIC_VERIFIER)
        );

        // Setup optimistic verifier approved token + fee (0.1 ether)
        OPTIMISTIC_VERIFIER.updateSupportedToken(ZERO_ADDRESS, true);
        OPTIMISTIC_VERIFIER.updateFee(ZERO_ADDRESS, 1e17);

        // Allow CALLBACK consumer to spend alice wallet balance up to 2 ether
        vm.prank(address(ALICE));
        Wallet(payable(aliceWallet)).approve(address(SUBSCRIPTION), ZERO_ADDRESS, 2 ether);

        // Allow Bob to spend bob wallet balance up to 2 ether
        vm.prank(address(BOB));
        Wallet(payable(bobWallet)).approve(address(BOB), ZERO_ADDRESS, 2 ether);

        // Verify initial balances
        assertEq(aliceWallet.balance, 2 ether);
        assertEq(bobWallet.balance, 2 ether);

        // Deliver first subscription from Bob
        vm.warp(1 days);
        BOB.deliverCompute(subId, 1, MOCK_INPUT, MOCK_OUTPUT, MOCK_PROOF, bobWallet);

        // During optimistic window, process as false
        vm.warp(1 days + 1 hours);
        OPTIMISTIC_VERIFIER.mockDeliverProof(subId, 1, address(BOB), false);

        // Deliver second subscription from Bob
        vm.warp(2 days);
        BOB.deliverCompute(subId, 2, MOCK_INPUT, MOCK_OUTPUT, MOCK_PROOF, bobWallet);

        // Fast forward past optimistic window, processing in favor of Bob
        vm.warp(10 days);
        COORDINATOR.finalizeProofVerification(subId, 2, address(BOB), true);

        // Assert new balances
        assertEq(aliceWallet.balance, 17_978e14);
        assertEq(Wallet(payable(aliceWallet)).allowance(address(SUBSCRIPTION), ZERO_ADDRESS), 7978e14);
        assertEq(bobWallet.balance, 17_978e14);
        assertEq(Wallet(payable(bobWallet)).allowance(address(BOB), ZERO_ADDRESS), 1 ether);
        assertEq(OPTIMISTIC_VERIFIER.getEtherBalance(), 18_978e13);
        assertEq(PROTOCOL.getEtherBalance(), 21_462e13);
    }
}
