// SPDX-License-Identifier: BSD-3-Clause-Clear
pragma solidity ^0.8.4;

import {Test} from "forge-std/Test.sol";
import {LibSign} from "./lib/LibSign.sol";
import {Registry} from "../src/Registry.sol";
import {LibDeploy} from "./lib/LibDeploy.sol";
import {MockNode} from "./mocks/MockNode.sol";
import {Inbox, InboxItem} from "../src/Inbox.sol";
import {Allowlist} from "../src/pattern/Allowlist.sol";
import {DeliveredOutput} from "./mocks/consumer/Base.sol";
import {EIP712Coordinator} from "../src/EIP712Coordinator.sol";
import {Coordinator, Subscription} from "../src/Coordinator.sol";
import {ICoordinatorEvents, CoordinatorConstants} from "./Coordinator.t.sol";
import {MockDelegatorCallbackConsumer} from "./mocks/consumer/DelegatorCallback.sol";
import {MockDelegatorSubscriptionConsumer} from "./mocks/consumer/DelegatorSubscription.sol";
import {MockAllowlistDelegatorSubscriptionConsumer} from "./mocks/consumer/AllowlistDelegatorSubscription.sol";

/// @title EIP712CoordinatorTest
/// @notice Tests EIP712Coordinator implementation
contract EIP712CoordinatorTest is Test, CoordinatorConstants, ICoordinatorEvents {
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

    /// @notice Mock callback consumer (w/ assigned delegatee)
    MockDelegatorCallbackConsumer private CALLBACK;

    /// @notice Mock subscription consumer (w/ assigned delegatee)
    MockDelegatorSubscriptionConsumer private SUBSCRIPTION;

    /// @notice Mock subscription consumer (w/ Allowlist & assigned delegatee)
    MockAllowlistDelegatorSubscriptionConsumer private ALLOWLIST_SUBSCRIPTION;

    /// @notice Delegatee address
    address private DELEGATEE_ADDRESS;

    /// @notice Delegatee private key
    uint256 private DELEGATEE_PRIVATE_KEY;

    /// @notice Backup delegatee address
    address private BACKUP_DELEGATEE_ADDRESS;

    /// @notice Backup delegatee private key
    uint256 private BACKUP_DELEGATEE_PRIVATE_KEY;

    /*//////////////////////////////////////////////////////////////
                                 SETUP
    //////////////////////////////////////////////////////////////*/

    function setUp() public {
        // Initialize contracts
        uint256 initialNonce = vm.getNonce(address(this));
        (Registry registry, EIP712Coordinator coordinator, Inbox inbox,) = LibDeploy.deployContracts(initialNonce);

        // Assign to internal
        COORDINATOR = coordinator;
        INBOX = inbox;

        // Initalize mock nodes
        ALICE = new MockNode(registry);
        BOB = new MockNode(registry);

        // Create new delegatee
        DELEGATEE_PRIVATE_KEY = 0xA11CE;
        DELEGATEE_ADDRESS = vm.addr(DELEGATEE_PRIVATE_KEY);

        // Create new backup delegatee
        BACKUP_DELEGATEE_PRIVATE_KEY = 0xB0B;
        BACKUP_DELEGATEE_ADDRESS = vm.addr(BACKUP_DELEGATEE_PRIVATE_KEY);

        // Initialize mock callback consumer w/ assigned delegatee
        CALLBACK = new MockDelegatorCallbackConsumer(address(registry), DELEGATEE_ADDRESS);

        // Initialize mock subscription consumer w/ assigned delegatee
        SUBSCRIPTION = new MockDelegatorSubscriptionConsumer(address(registry), DELEGATEE_ADDRESS);

        // Initialize mock subscription consumer w/ Allowlist & assigned delegatee
        // Add only Alice as initially allowed node
        address[] memory initialAllowed = new address[](1);
        initialAllowed[0] = address(ALICE);
        ALLOWLIST_SUBSCRIPTION =
            new MockAllowlistDelegatorSubscriptionConsumer(address(registry), DELEGATEE_ADDRESS, initialAllowed);
    }

    /*//////////////////////////////////////////////////////////////
                           UTILITY FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /// @notice Creates new mock subscription with sane defaults
    function getMockSubscription() public view returns (Subscription memory) {
        return Subscription({
            activeAt: uint32(block.timestamp),
            owner: address(CALLBACK),
            redundancy: 1,
            frequency: 1,
            period: 0,
            containerId: HASHED_MOCK_CONTAINER_ID,
            lazy: false,
            prover: address(0),
            paymentAmount: 0,
            paymentToken: address(0),
            wallet: address(0)
        });
    }

    /// @notice Generates the hash of the fully encoded EIP-712 message, based on environment domain config
    /// @param nonce subscriber contract nonce
    /// @param expiry signature expiry
    /// @param sub subscription
    /// @return typed EIP-712 message hash
    function getMessage(uint32 nonce, uint32 expiry, Subscription memory sub) public view returns (bytes32) {
        return LibSign.getTypedMessageHash(
            COORDINATOR.EIP712_NAME(), COORDINATOR.EIP712_VERSION(), address(COORDINATOR), nonce, expiry, sub
        );
    }

    /// @notice Mocks subscription creation via EIP712 delegate process
    /// @param nonce subscriber contract nonce
    /// @return subscriptionId
    function createMockSubscriptionEIP712(uint32 nonce) public returns (uint32) {
        // Check initial subscriptionId
        uint32 id = COORDINATOR.id();

        // Create new dummy subscription
        Subscription memory sub = getMockSubscription();

        // Check max subscriber nonce
        uint32 maxSubscriberNonce = COORDINATOR.maxSubscriberNonce(sub.owner);

        // Generate signature expiry
        uint32 expiry = uint32(block.timestamp) + 30 minutes;

        // Get EIP-712 typed message
        bytes32 message = getMessage(nonce, expiry, sub);

        // Sign message from delegatee private key
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(DELEGATEE_PRIVATE_KEY, message);

        // Create subscription
        uint32 subscriptionId = COORDINATOR.createSubscriptionDelegatee(0, expiry, sub, v, r, s);
        assertEq(subscriptionId, id);

        // Assert subscription data is correctly stored
        Subscription memory actual = COORDINATOR.getSubscription(id);
        assertEq(sub.activeAt, actual.activeAt);
        assertEq(sub.owner, actual.owner);
        assertEq(sub.redundancy, actual.redundancy);
        assertEq(sub.frequency, actual.frequency);
        assertEq(sub.period, actual.period);
        assertEq(sub.containerId, actual.containerId);

        // Assert state is correctly updated
        if (nonce > maxSubscriberNonce) {
            assertEq(COORDINATOR.maxSubscriberNonce(address(CALLBACK)), nonce);
        } else {
            assertEq(COORDINATOR.maxSubscriberNonce(address(CALLBACK)), maxSubscriberNonce);
        }
        assertEq(COORDINATOR.delegateCreatedIds(keccak256(abi.encode(address(CALLBACK), nonce))), subscriptionId);

        // Explicitly return new subscriptionId
        return subscriptionId;
    }

    /*//////////////////////////////////////////////////////////////
                                 TESTS
    //////////////////////////////////////////////////////////////*/

    function testCannotCreateDelegatedSubscriptionWhereSignatureExpired() public {
        // Create new dummy subscription
        Subscription memory sub = getMockSubscription();

        // Generate signature expiry
        uint32 expiry = uint32(block.timestamp) + 30 minutes;

        // Get EIP-712 typed message
        bytes32 message = getMessage(0, expiry, sub);

        // Sign message from delegatee private key
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(DELEGATEE_PRIVATE_KEY, message);

        // Warp time forward past signature expiry
        vm.warp(expiry + 1 seconds);

        // Create subscription via delegate and expect error
        vm.expectRevert(EIP712Coordinator.SignatureExpired.selector);
        COORDINATOR.createSubscriptionDelegatee(0, expiry, sub, v, r, s);
    }

    /// @notice Cannot create delegated subscription where signature does not match
    function testFuzzCannotCreateDelegatedSubscriptionWhereSignatureMismatch(uint256 privateKey) public {
        // Ensure signer private key is not actual delegatee private key
        vm.assume(privateKey != DELEGATEE_PRIVATE_KEY);
        // Ensure signer private key < secp256k1 curve order
        vm.assume(privateKey < SECP256K1_ORDER);
        // Ensure signer private key != 0
        vm.assume(privateKey != 0);

        // Create new dummy subscription
        Subscription memory sub = getMockSubscription();

        // Generate signature expiry
        uint32 expiry = uint32(block.timestamp) + 30 minutes;

        // Get EIP-712 typed message
        bytes32 message = getMessage(0, expiry, sub);

        // Sign message from new private key
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(privateKey, message);

        // Create subscription via delegate and expect error
        vm.expectRevert(EIP712Coordinator.SignerMismatch.selector);
        COORDINATOR.createSubscriptionDelegatee(0, expiry, sub, v, r, s);
    }

    /// @notice Can create new subscription via EIP712 signature
    function testCanCreateNewSubscriptionViaEIP712() public {
        // Create new dummy subscription
        Subscription memory sub = getMockSubscription();

        // Generate signature expiry
        uint32 expiry = uint32(block.timestamp) + 30 minutes;

        // Get EIP-712 typed message
        bytes32 message = getMessage(0, expiry, sub);

        // Sign message from delegatee private key
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(DELEGATEE_PRIVATE_KEY, message);

        // Create subscription
        uint32 subscriptionId = COORDINATOR.createSubscriptionDelegatee(0, expiry, sub, v, r, s);
        assertEq(subscriptionId, 1);

        // Assert subscription data is correctly stored
        Subscription memory actual = COORDINATOR.getSubscription(1);
        assertEq(sub.activeAt, actual.activeAt);
        assertEq(sub.owner, actual.owner);
        assertEq(sub.redundancy, actual.redundancy);
        assertEq(sub.frequency, actual.frequency);
        assertEq(sub.period, actual.period);
        assertEq(sub.containerId, actual.containerId);

        // Assert state is correctly updated
        assertEq(COORDINATOR.maxSubscriberNonce(address(CALLBACK)), 0);
        assertEq(COORDINATOR.delegateCreatedIds(keccak256(abi.encode(address(CALLBACK), uint32(0)))), 1);
    }

    /// @notice Cannot use valid delegated subscription from old signer
    function testCannotUseValidDelegatedSubscriptionFromOldSigner() public {
        // Create new dummy subscription
        Subscription memory sub = getMockSubscription();

        // Generate signature expiry
        uint32 expiry = uint32(block.timestamp) + 30 minutes;

        // Get EIP-712 typed message
        bytes32 message = getMessage(0, expiry, sub);

        // Sign message from delegatee private key
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(DELEGATEE_PRIVATE_KEY, message);

        // Update signer to backup delegatee
        CALLBACK.updateMockSigner(BACKUP_DELEGATEE_ADDRESS);
        assertEq(CALLBACK.getSigner(), BACKUP_DELEGATEE_ADDRESS);

        // Create subscription with valid message and expect error
        vm.expectRevert(EIP712Coordinator.SignerMismatch.selector);
        COORDINATOR.createSubscriptionDelegatee(0, expiry, sub, v, r, s);
    }

    /// @notice Can use existing subscription created by old signer
    function testCanUseExistingDelegatedSubscriptionFromOldSigner() public {
        // Create new dummy subscription
        Subscription memory sub = getMockSubscription();

        // Generate signature expiry
        uint32 expiry = uint32(block.timestamp) + 30 minutes;

        // Get EIP-712 typed message
        bytes32 message = getMessage(0, expiry, sub);

        // Sign message from delegatee private key
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(DELEGATEE_PRIVATE_KEY, message);

        // Create subscription
        uint32 subscriptionId = COORDINATOR.createSubscriptionDelegatee(0, expiry, sub, v, r, s);
        assertEq(subscriptionId, 1);

        // Update signer to backup delegatee
        CALLBACK.updateMockSigner(BACKUP_DELEGATEE_ADDRESS);
        assertEq(CALLBACK.getSigner(), BACKUP_DELEGATEE_ADDRESS);

        // Creating subscription should return existing subscription (ID: 1)
        subscriptionId = COORDINATOR.createSubscriptionDelegatee(0, expiry, sub, v, r, s);
        assertEq(subscriptionId, 1);
    }

    /// @notice Cannot create delegated subscription where nonce is reused
    function testCannotCreateDelegatedSubscriptionWhereNonceReused() public {
        // Setup nonce
        uint32 nonce = 0;

        // Create new dummy subscription
        Subscription memory sub = getMockSubscription();

        // Generate signature expiry
        uint32 expiry = uint32(block.timestamp) + 30 minutes;

        // Get EIP-712 typed message
        bytes32 message = getMessage(nonce, expiry, sub);

        // Sign message
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(DELEGATEE_PRIVATE_KEY, message);

        // Create subscription
        uint32 subscriptionId = COORDINATOR.createSubscriptionDelegatee(nonce, expiry, sub, v, r, s);
        assertEq(subscriptionId, 1);

        // Create second dummy subscription and set redundancy to 5 (identifier param)
        sub = getMockSubscription();
        uint16 oldRedundancy = sub.redundancy;
        sub.redundancy = 5;

        // Get EIP-712 typed message
        message = getMessage(nonce, expiry, sub);

        // Sign message
        (v, r, s) = vm.sign(DELEGATEE_PRIVATE_KEY, message);

        // Create subscription (notice, with the same nonce)
        subscriptionId = COORDINATOR.createSubscriptionDelegatee(nonce, expiry, sub, v, r, s);

        // Assert that we are instead simply returned the existing subscription
        assertEq(subscriptionId, 1);
        // Also, assert that the redundancy has not changed
        Subscription memory actual = COORDINATOR.getSubscription(subscriptionId);
        assertEq(actual.redundancy, oldRedundancy);

        // Now, ensure that we can't resign with a new delegatee and force nonce replay
        // Change the signing delegatee to the backup delegatee
        CALLBACK.updateMockSigner(BACKUP_DELEGATEE_ADDRESS);
        assertEq(CALLBACK.getSigner(), BACKUP_DELEGATEE_ADDRESS);

        // Use same summy subscription with redundancy == 5, but sign with backup delegatee
        (v, r, s) = vm.sign(BACKUP_DELEGATEE_PRIVATE_KEY, message);

        // Create subscription (notice, with the same nonce)
        subscriptionId = COORDINATOR.createSubscriptionDelegatee(nonce, expiry, sub, v, r, s);

        // Assert that we are instead simply returned the existing subscription
        assertEq(subscriptionId, 1);
        // Also, assert that the redundancy has not changed
        actual = COORDINATOR.getSubscription(subscriptionId);
        assertEq(actual.redundancy, oldRedundancy);
    }

    /// @notice Can create delegated subscription with out of order nonces
    function testCanCreateDelegatedSubscriptionWithUnorderedNonces() public {
        // Create subscription with nonce 10
        uint32 nonce = 10;
        Subscription memory sub = getMockSubscription();
        uint32 expiry = uint32(block.timestamp) + 30 minutes;
        bytes32 message = getMessage(nonce, expiry, sub);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(DELEGATEE_PRIVATE_KEY, message);
        uint32 subscriptionId = COORDINATOR.createSubscriptionDelegatee(nonce, expiry, sub, v, r, s);
        assertEq(subscriptionId, 1);

        // Ensure maximum subscriber nonce is 10
        assertEq(COORDINATOR.maxSubscriberNonce(sub.owner), 10);

        // Create subscription with nonce 1
        nonce = 1;
        sub = getMockSubscription();
        expiry = uint32(block.timestamp) + 30 minutes;
        message = getMessage(nonce, expiry, sub);
        (v, r, s) = vm.sign(DELEGATEE_PRIVATE_KEY, message);
        subscriptionId = COORDINATOR.createSubscriptionDelegatee(nonce, expiry, sub, v, r, s);
        assertEq(subscriptionId, 2);

        // Ensure maximum subscriber nonce is still 10
        assertEq(COORDINATOR.maxSubscriberNonce(sub.owner), 10);

        // Attempt to replay tx with nonce 10
        nonce = 10;
        sub = getMockSubscription();
        expiry = uint32(block.timestamp) + 30 minutes;
        message = getMessage(nonce, expiry, sub);
        (v, r, s) = vm.sign(DELEGATEE_PRIVATE_KEY, message);
        subscriptionId = COORDINATOR.createSubscriptionDelegatee(nonce, expiry, sub, v, r, s);

        // Ensure that instead of a new subscription, existing subscription (ID: 1) is returned
        assertEq(subscriptionId, 1);
    }

    /// @notice Can get existing subscription via `createDelegateSubscription`
    /// @dev Also tests for preventing signature replay
    function testCanGetExistingSubscriptionViaEIP712() public {
        // Create mock subscription via delegate, nonce 0
        uint32 subscriptionId = createMockSubscriptionEIP712(0);

        // Immediately collect subscriptionId without any signature verifications
        uint32 expectedSubscriptionId = COORDINATOR.createSubscriptionDelegatee(0, 0, getMockSubscription(), 0, "", "");
        assertEq(subscriptionId, expectedSubscriptionId);
    }

    /// @notice Can cancel subscription created via delegate
    function testCanCancelSubscriptionCreatedViaDelegate() public {
        // Create mock subscription via delegate, nonce 0
        uint32 subscriptionId = createMockSubscriptionEIP712(0);

        // Attempt to cancel from Callback contract
        vm.startPrank(address(CALLBACK));
        COORDINATOR.cancelSubscription(subscriptionId);

        // Assert cancelled status
        Subscription memory actual = COORDINATOR.getSubscription(1);
        assertEq(actual.owner, address(0));
    }

    /// @notice Can delegated deliver compute reponse, while creating new subscription
    function testCanAtomicCreateSubscriptionAndDeliverOutput() public {
        // Starting nonce
        uint32 nonce = COORDINATOR.maxSubscriberNonce(address(CALLBACK));

        // Create new dummy subscription
        Subscription memory sub = getMockSubscription();

        // Generate signature expiry
        uint32 expiry = uint32(block.timestamp) + 30 minutes;

        // Get EIP-712 typed message
        bytes32 message = getMessage(nonce, expiry, sub);

        // Sign message from delegatee private key
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(DELEGATEE_PRIVATE_KEY, message);

        // Create subscription and deliver response, via deliverComputeDelegatee
        uint32 subscriptionId = 1;
        uint32 deliveryInterval = 1;
        ALICE.deliverComputeDelegatee(
            nonce, expiry, sub, v, r, s, deliveryInterval, MOCK_INPUT, MOCK_OUTPUT, MOCK_PROOF
        );

        // Get response
        DeliveredOutput memory out = CALLBACK.getDeliveredOutput(subscriptionId, deliveryInterval, 1);
        assertEq(out.subscriptionId, subscriptionId);
        assertEq(out.interval, deliveryInterval);
        assertEq(out.redundancy, 1);
        assertEq(out.input, MOCK_INPUT);
        assertEq(out.output, MOCK_OUTPUT);
        assertEq(out.proof, MOCK_PROOF);

        // Ensure subscription completion is tracked
        bytes32 key = keccak256(abi.encode(subscriptionId, deliveryInterval, address(ALICE)));
        assertEq(COORDINATOR.nodeResponded(key), true);
    }

    /// @notice Can delegated deliver compute response, while creating new lazy subscription
    function testCanAtomicCreateLazySubscriptionAndDeliverOutput() public {
        // Starting nonce
        uint32 nonce = COORDINATOR.maxSubscriberNonce(address(CALLBACK));

        // Create new dummy subscription
        Subscription memory sub = getMockSubscription();

        // Modify dummy subscription to be lazy
        sub.owner = address(SUBSCRIPTION);
        sub.lazy = true;

        // Generate signature expiry
        uint32 expiry = uint32(block.timestamp) + 30 minutes;

        // Get EIP-712 typed message
        bytes32 message = getMessage(nonce, expiry, sub);

        // Sign message from delegatee private key
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(DELEGATEE_PRIVATE_KEY, message);

        // Create subscription and deliver response, via deliverComputeDelegatee
        uint32 subscriptionId = 1;
        uint32 deliveryInterval = 1;
        ALICE.deliverComputeDelegatee(
            nonce, expiry, sub, v, r, s, deliveryInterval, MOCK_INPUT, MOCK_OUTPUT, MOCK_PROOF
        );

        // Get response
        DeliveredOutput memory out = SUBSCRIPTION.getDeliveredOutput(subscriptionId, deliveryInterval, 1);
        assertEq(out.subscriptionId, subscriptionId);
        assertEq(out.interval, deliveryInterval);
        assertEq(out.redundancy, 1);
        assertEq(out.input, "");
        assertEq(out.output, "");
        assertEq(out.proof, "");
        assertEq(out.containerId, HASHED_MOCK_CONTAINER_ID);
        assertEq(out.index, 0);

        // Ensure response is stored in inbox
        InboxItem memory item = INBOX.read(HASHED_MOCK_CONTAINER_ID, address(ALICE), 0);
        assertEq(item.timestamp, block.timestamp);
        assertEq(item.subscriptionId, subscriptionId);
        assertEq(item.interval, deliveryInterval);
        assertEq(item.input, MOCK_INPUT);
        assertEq(item.output, MOCK_OUTPUT);
        assertEq(item.proof, MOCK_PROOF);

        // Ensure subscription completion is tracked
        bytes32 key = keccak256(abi.encode(subscriptionId, deliveryInterval, address(ALICE)));
        assertEq(COORDINATOR.nodeResponded(key), true);
    }

    /// @notice Cannot delegated deliver compute response for completed subscription
    function testCannotAtomicDeliverOutputForCompletedSubscription() public {
        // Starting nonce
        uint32 nonce = COORDINATOR.maxSubscriberNonce(address(CALLBACK));

        // Create new dummy subscription
        Subscription memory sub = getMockSubscription();

        // Generate signature expiry
        uint32 expiry = uint32(block.timestamp) + 30 minutes;

        // Get EIP-712 typed message
        bytes32 message = getMessage(nonce, expiry, sub);

        // Sign message from delegatee private key
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(DELEGATEE_PRIVATE_KEY, message);

        // Create subscription and deliver response, via deliverComputeDelegatee
        uint32 subscriptionId = 1;
        uint32 deliveryInterval = 1;
        ALICE.deliverComputeDelegatee(
            nonce, expiry, sub, v, r, s, deliveryInterval, MOCK_INPUT, MOCK_OUTPUT, MOCK_PROOF
        );

        // Attempt to deliver from Bob via delegatee
        vm.expectRevert(Coordinator.IntervalCompleted.selector);
        BOB.deliverComputeDelegatee(nonce, expiry, sub, v, r, s, deliveryInterval, MOCK_INPUT, MOCK_OUTPUT, MOCK_PROOF);

        // Attempt to delivery from Bob direct
        vm.expectRevert(Coordinator.IntervalCompleted.selector);
        BOB.deliverCompute(subscriptionId, deliveryInterval, MOCK_INPUT, MOCK_OUTPUT, MOCK_PROOF);
    }

    /// @notice Can delegated deliver compute response for existing subscription
    function testCanDelegatedDeliverComputeResponseForExistingSubscription() public {
        // Starting nonce
        uint32 nonce = COORDINATOR.maxSubscriberNonce(address(CALLBACK));

        // Create new dummy subscription
        Subscription memory sub = getMockSubscription();
        // Modify dummy subscription to allow > 1 redundancy
        sub.redundancy = 2;

        // Generate signature expiry
        uint32 expiry = uint32(block.timestamp) + 30 minutes;

        // Get EIP-712 typed message
        bytes32 message = getMessage(nonce, expiry, sub);

        // Sign message from delegatee private key
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(DELEGATEE_PRIVATE_KEY, message);

        // Delivery from Alice
        uint32 subscriptionId = 1;
        uint32 deliveryInterval = 1;
        ALICE.deliverComputeDelegatee(
            nonce, expiry, sub, v, r, s, deliveryInterval, MOCK_INPUT, MOCK_OUTPUT, MOCK_PROOF
        );

        // Ensure subscription completion is tracked
        bytes32 key = keccak256(abi.encode(subscriptionId, deliveryInterval, address(ALICE)));
        assertEq(COORDINATOR.nodeResponded(key), true);

        // Deliver from Bob
        BOB.deliverComputeDelegatee(nonce, expiry, sub, v, r, s, deliveryInterval, MOCK_INPUT, MOCK_OUTPUT, MOCK_PROOF);

        // Ensure subscription completion is tracked
        key = keccak256(abi.encode(subscriptionId, deliveryInterval, address(BOB)));
        assertEq(COORDINATOR.nodeResponded(key), true);

        // Expect revert if trying to deliver again
        vm.expectRevert(Coordinator.IntervalCompleted.selector);
        BOB.deliverComputeDelegatee(nonce, expiry, sub, v, r, s, deliveryInterval, MOCK_INPUT, MOCK_OUTPUT, MOCK_PROOF);
    }

    /// @notice Can deliver delegated subscription response as an allowed node
    function testCanDeliverDelegatedResponseAsAllowedNode() public {
        // Starting nonce
        uint32 nonce = COORDINATOR.maxSubscriberNonce(address(ALLOWLIST_SUBSCRIPTION));

        // Create new dummy subscription w/ redundancy == 2
        Subscription memory sub = getMockSubscription();
        sub.owner = address(ALLOWLIST_SUBSCRIPTION);
        sub.redundancy = 2;

        // Generate signature expiry
        uint32 expiry = uint32(block.timestamp) + 30 minutes;

        // Get EIP-712 typed message
        bytes32 message = getMessage(nonce, expiry, sub);

        // Sign message from delegatee private key
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(DELEGATEE_PRIVATE_KEY, message);

        // Create subscription and deliver response, via deliverComputeDelegatee (via allowed node Alice)
        ALICE.deliverComputeDelegatee(nonce, expiry, sub, v, r, s, 1, MOCK_INPUT, MOCK_OUTPUT, MOCK_PROOF);

        // Attempt but fail to deliver response from Bob (unallowed node)
        vm.expectRevert(Allowlist.NodeNotAllowed.selector);
        BOB.deliverComputeDelegatee(nonce, expiry, sub, v, r, s, 1, MOCK_INPUT, MOCK_OUTPUT, MOCK_PROOF);
    }

    /// @notice Creating new subscription as unallowed node fails upon delivering response
    function testCannotCreateNewDelegatedSubscriptionAtomicallyAsUnallowedNode() public {
        // Starting nonce
        uint32 nonce = COORDINATOR.maxSubscriberNonce(address(ALLOWLIST_SUBSCRIPTION));

        // Create new dummy subscription
        Subscription memory sub = getMockSubscription();
        sub.owner = address(ALLOWLIST_SUBSCRIPTION);

        // Generate signature expiry
        uint32 expiry = uint32(block.timestamp) + 30 minutes;

        // Get EIP-712 typed message
        bytes32 message = getMessage(nonce, expiry, sub);

        // Sign message from delegatee private key
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(DELEGATEE_PRIVATE_KEY, message);

        // Create subscription and deliver response via Bob
        // Expect failure given unallowed node causes atomic tx reversion
        vm.expectRevert(Allowlist.NodeNotAllowed.selector);
        BOB.deliverComputeDelegatee(nonce, expiry, sub, v, r, s, 1, MOCK_INPUT, MOCK_OUTPUT, MOCK_PROOF);

        // Ensure subscription was not created (no serial nonce increment from subscription creation)
        uint32 finalNonce = COORDINATOR.maxSubscriberNonce(address(ALLOWLIST_SUBSCRIPTION));
        assertEq(nonce, finalNonce);
    }
}
