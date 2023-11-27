// SPDX-License-Identifier: BSD-3-Clause-Clear
pragma solidity ^0.8.4;

import {console} from "forge-std/console.sol";
import {Test} from "forge-std/Test.sol";
import {LibSign} from "./lib/LibSign.sol";
import {LibStruct} from "./lib/LibStruct.sol";
import {MockNode} from "./mocks/MockNode.sol";
import {Coordinator} from "../src/Coordinator.sol";
import {EIP712Coordinator} from "../src/EIP712Coordinator.sol";
import {ICoordinatorEvents, CoordinatorConstants} from "./Coordinator.t.sol";
import {MockDelegatorCallbackConsumer} from "./mocks/consumer/DelegatorCallback.sol";

/// @title EIP712CoordinatorTest
/// @notice Tests EIP712Coordinator implementation
contract EIP712CoordinatorTest is Test, CoordinatorConstants, ICoordinatorEvents {
    /*//////////////////////////////////////////////////////////////
                               CONSTANTS
    //////////////////////////////////////////////////////////////*/

    /// @notice Cold cost of `CallbackConsumer.rawReceiveCompute`
    /// @dev Inputs: (uint32, uint32, uint16, MOCK_INPUT, MOCK_OUTPUT, MOCK_PROOF)
    /// @dev Overriden from CoordinatorConstants since state change order forces this to cost ~100 wei more
    uint32 constant CALLBACK_COST = 115_176 wei;

    /*//////////////////////////////////////////////////////////////
                                INTERNAL
    //////////////////////////////////////////////////////////////*/

    /// @notice EIP712Coordinator
    EIP712Coordinator internal COORDINATOR;

    /// @notice Mock node (Alice)
    MockNode internal ALICE;

    /// @notice Mock node (Bob)
    MockNode internal BOB;

    /// @notice Mock callback consumer (w/ assigned delegatee)
    MockDelegatorCallbackConsumer internal CALLBACK;

    /// @notice Delegatee address
    address internal DELEGATEE_ADDRESS;

    /// @notice Delegatee private key
    uint256 internal DELEGATEE_PRIVATE_KEY;

    /// @notice Backup delegatee address
    address internal BACKUP_DELEGATEE_ADDRESS;

    /// @notice Backup delegatee private key
    uint256 internal BACKUP_DELEGATEE_PRIVATE_KEY;

    /*//////////////////////////////////////////////////////////////
                                 SETUP
    //////////////////////////////////////////////////////////////*/

    function setUp() public {
        // Initialize coordinator
        COORDINATOR = new EIP712Coordinator();

        // Initalize mock nodes
        ALICE = new MockNode(COORDINATOR);
        BOB = new MockNode(COORDINATOR);

        // For each node
        MockNode[2] memory nodes = [ALICE, BOB];
        for (uint256 i = 0; i < 2; i++) {
            // Select node
            MockNode node = nodes[i];

            // Activate nodes
            vm.warp(0);
            node.registerNode(address(node));
            vm.warp(COORDINATOR.cooldown());
            node.activateNode();
        }

        // Create new delegatee
        DELEGATEE_PRIVATE_KEY = 0xA11CE;
        DELEGATEE_ADDRESS = vm.addr(DELEGATEE_PRIVATE_KEY);

        // Create new backup delegatee
        BACKUP_DELEGATEE_PRIVATE_KEY = 0xB0B;
        BACKUP_DELEGATEE_ADDRESS = vm.addr(BACKUP_DELEGATEE_PRIVATE_KEY);

        // Initialize mock callback consumer w/ assigned delegate
        CALLBACK = new MockDelegatorCallbackConsumer(
            address(COORDINATOR),
            DELEGATEE_ADDRESS
        );
    }

    /*//////////////////////////////////////////////////////////////
                           UTILITY FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /// @notice Creates new mock subscription with sane defaults
    function getMockSubscription() public view returns (Coordinator.Subscription memory) {
        return Coordinator.Subscription({
            activeAt: uint32(block.timestamp),
            owner: address(CALLBACK),
            maxGasPrice: 1 gwei,
            redundancy: 1,
            maxGasLimit: CALLBACK_COST + uint32(COORDINATOR.DELEGATEE_OVERHEAD_CREATE_WEI())
                + uint32(COORDINATOR.DELIVERY_OVERHEAD_WEI()),
            frequency: 1,
            period: 0,
            containerId: MOCK_CONTAINER_ID,
            inputs: MOCK_CONTAINER_INPUTS
        });
    }

    /// @notice Generates the hash of the fully encoded EIP-712 message, based on environment domain config
    /// @param nonce subscriber contract nonce
    /// @param expiry signature expiry
    /// @param sub subscription
    /// @return typed EIP-712 message hash
    function getMessage(uint32 nonce, uint32 expiry, Coordinator.Subscription memory sub)
        public
        view
        returns (bytes32)
    {
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
        Coordinator.Subscription memory sub = getMockSubscription();

        // Check max subscriber nonce
        uint32 maxSubscriberNonce = COORDINATOR.maxSubscriberNonce(sub.owner);

        // Generate signature expiry
        uint32 expiry = uint32(block.timestamp) + 30 minutes;

        // Get EIP-712 typed message
        bytes32 message = getMessage(nonce, expiry, sub);

        // Sign message from delegatee private key
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(DELEGATEE_PRIVATE_KEY, message);

        // Create subscription
        (uint32 subscriptionId,) = COORDINATOR.createSubscriptionDelegatee(0, expiry, sub, v, r, s);
        assertEq(subscriptionId, id);

        // Assert subscription data is correctly stored
        LibStruct.Subscription memory actual = LibStruct.getSubscription(COORDINATOR, id);
        assertEq(sub.activeAt, actual.activeAt);
        assertEq(sub.owner, actual.owner);
        assertEq(sub.maxGasPrice, actual.maxGasPrice);
        assertEq(sub.redundancy, actual.redundancy);
        assertEq(sub.maxGasLimit, actual.maxGasLimit);
        assertEq(sub.frequency, actual.frequency);
        assertEq(sub.period, actual.period);
        assertEq(sub.containerId, actual.containerId);
        assertEq(sub.inputs, actual.inputs);

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
        Coordinator.Subscription memory sub = getMockSubscription();

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
        Coordinator.Subscription memory sub = getMockSubscription();

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
        Coordinator.Subscription memory sub = getMockSubscription();

        // Generate signature expiry
        uint32 expiry = uint32(block.timestamp) + 30 minutes;

        // Get EIP-712 typed message
        bytes32 message = getMessage(0, expiry, sub);

        // Sign message from delegatee private key
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(DELEGATEE_PRIVATE_KEY, message);

        // Create subscription
        (uint32 subscriptionId,) = COORDINATOR.createSubscriptionDelegatee(0, expiry, sub, v, r, s);
        assertEq(subscriptionId, 1);

        // Assert subscription data is correctly stored
        LibStruct.Subscription memory actual = LibStruct.getSubscription(COORDINATOR, 1);
        assertEq(sub.activeAt, actual.activeAt);
        assertEq(sub.owner, actual.owner);
        assertEq(sub.maxGasPrice, actual.maxGasPrice);
        assertEq(sub.redundancy, actual.redundancy);
        assertEq(sub.maxGasLimit, actual.maxGasLimit);
        assertEq(sub.frequency, actual.frequency);
        assertEq(sub.period, actual.period);
        assertEq(sub.containerId, actual.containerId);
        assertEq(sub.inputs, actual.inputs);

        // Assert state is correctly updated
        assertEq(COORDINATOR.maxSubscriberNonce(address(CALLBACK)), 0);
        assertEq(COORDINATOR.delegateCreatedIds(keccak256(abi.encode(address(CALLBACK), uint32(0)))), 1);
    }

    /// @notice Cannot use valid delegated subscription from old signer
    function testCannotUseValidDelegatedSubscriptionFromOldSigner() public {
        // Create new dummy subscription
        Coordinator.Subscription memory sub = getMockSubscription();

        // Generate signature expiry
        uint32 expiry = uint32(block.timestamp) + 30 minutes;

        // Get EIP-712 typed message
        bytes32 message = getMessage(0, expiry, sub);

        // Sign message from delegatee private key
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(DELEGATEE_PRIVATE_KEY, message);

        // Update signer to backup delegatee
        CALLBACK.updateMockSigner(BACKUP_DELEGATEE_ADDRESS);

        // Create subscription with valid message and expect error
        vm.expectRevert(EIP712Coordinator.SignerMismatch.selector);
        COORDINATOR.createSubscriptionDelegatee(0, expiry, sub, v, r, s);
    }

    /// @notice Can use existing subscription created by old signer
    function testCanUseExistingDelegatedSubscriptionFromOldSigner() public {
        // Create new dummy subscription
        Coordinator.Subscription memory sub = getMockSubscription();

        // Generate signature expiry
        uint32 expiry = uint32(block.timestamp) + 30 minutes;

        // Get EIP-712 typed message
        bytes32 message = getMessage(0, expiry, sub);

        // Sign message from delegatee private key
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(DELEGATEE_PRIVATE_KEY, message);

        // Create subscription
        (uint32 subscriptionId,) = COORDINATOR.createSubscriptionDelegatee(0, expiry, sub, v, r, s);
        assertEq(subscriptionId, 1);

        // Update signer to backup delegatee
        CALLBACK.updateMockSigner(BACKUP_DELEGATEE_ADDRESS);

        // Creating subscription should return existing subscription (ID: 1)
        (subscriptionId,) = COORDINATOR.createSubscriptionDelegatee(0, expiry, sub, v, r, s);
        assertEq(subscriptionId, 1);
    }

    /// @notice Cannot create delegated subscription where nonce is reused
    function testCannotCreateDelegatedSubscriptionWhereNonceReused() public {
        // Setup nonce
        uint32 nonce = 0;

        // Create new dummy subscription
        Coordinator.Subscription memory sub = getMockSubscription();

        // Generate signature expiry
        uint32 expiry = uint32(block.timestamp) + 30 minutes;

        // Get EIP-712 typed message
        bytes32 message = getMessage(nonce, expiry, sub);

        // Sign message
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(DELEGATEE_PRIVATE_KEY, message);

        // Create subscription
        (uint32 subscriptionId,) = COORDINATOR.createSubscriptionDelegatee(nonce, expiry, sub, v, r, s);
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
        (subscriptionId,) = COORDINATOR.createSubscriptionDelegatee(nonce, expiry, sub, v, r, s);

        // Assert that we are instead simply returned the existing subscription
        assertEq(subscriptionId, 1);
        // Also, assert that the redundancy has not changed
        LibStruct.Subscription memory actual = LibStruct.getSubscription(COORDINATOR, subscriptionId);
        assertEq(actual.redundancy, oldRedundancy);

        // Now, ensure that we can't resign with a new delegatee and force nonce replay
        // Change the signing delegatee to the backup delegatee
        CALLBACK.updateMockSigner(BACKUP_DELEGATEE_ADDRESS);

        // Use same summy subscription with redundancy == 5, but sign with backup delegatee
        (v, r, s) = vm.sign(BACKUP_DELEGATEE_PRIVATE_KEY, message);

        // Create subscription (notice, with the same nonce)
        (subscriptionId,) = COORDINATOR.createSubscriptionDelegatee(nonce, expiry, sub, v, r, s);

        // Assert that we are instead simply returned the existing subscription
        assertEq(subscriptionId, 1);
        // Also, assert that the redundancy has not changed
        actual = LibStruct.getSubscription(COORDINATOR, subscriptionId);
        assertEq(actual.redundancy, oldRedundancy);
    }

    /// @notice Can create delegated subscription with out of order nonces
    function testCanCreateDelegatedSubscriptionWithUnorderedNonces() public {
        // Create subscription with nonce 10
        uint32 nonce = 10;
        Coordinator.Subscription memory sub = getMockSubscription();
        uint32 expiry = uint32(block.timestamp) + 30 minutes;
        bytes32 message = getMessage(nonce, expiry, sub);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(DELEGATEE_PRIVATE_KEY, message);
        (uint32 subscriptionId,) = COORDINATOR.createSubscriptionDelegatee(nonce, expiry, sub, v, r, s);
        assertEq(subscriptionId, 1);

        // Ensure maximum subscriber nonce is 10
        assertEq(COORDINATOR.maxSubscriberNonce(sub.owner), 10);

        // Create subscription with nonce 1
        nonce = 1;
        sub = getMockSubscription();
        expiry = uint32(block.timestamp) + 30 minutes;
        message = getMessage(nonce, expiry, sub);
        (v, r, s) = vm.sign(DELEGATEE_PRIVATE_KEY, message);
        (subscriptionId,) = COORDINATOR.createSubscriptionDelegatee(nonce, expiry, sub, v, r, s);
        assertEq(subscriptionId, 2);

        // Ensure maximum subscriber nonce is still 10
        assertEq(COORDINATOR.maxSubscriberNonce(sub.owner), 10);

        // Attempt to replay tx with nonce 10
        nonce = 10;
        sub = getMockSubscription();
        expiry = uint32(block.timestamp) + 30 minutes;
        message = getMessage(nonce, expiry, sub);
        (v, r, s) = vm.sign(DELEGATEE_PRIVATE_KEY, message);
        (subscriptionId,) = COORDINATOR.createSubscriptionDelegatee(nonce, expiry, sub, v, r, s);

        // Ensure that instead of a new subscription, existing subscription (ID: 1) is returned
        assertEq(subscriptionId, 1);
    }

    /// @notice Can get existing subscription via `createDelegateSubscription`
    /// @dev Also tests for preventing signature replay
    function testCanGetExistingSubscriptionViaEIP712() public {
        // Create mock subscription via delegate, nonce 0
        uint32 subscriptionId = createMockSubscriptionEIP712(0);

        // Immediately collect subscriptionId without any signature verifications
        (uint32 expectedSubscriptionId,) =
            COORDINATOR.createSubscriptionDelegatee(0, 0, getMockSubscription(), 0, "", "");
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
        LibStruct.Subscription memory actual = LibStruct.getSubscription(COORDINATOR, 1);
        assertEq(actual.owner, address(0));
    }

    /// @notice Can delegated deliver compute reponse, while creating new subscription
    function testCanAtomicCreateSubscriptionAndDeliverOutput() public {
        // Starting nonce
        uint32 nonce = COORDINATOR.maxSubscriberNonce(address(CALLBACK));

        // Create new dummy subscription
        Coordinator.Subscription memory sub = getMockSubscription();

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
        LibStruct.DeliveredOutput memory out =
            LibStruct.getDeliveredOutput(CALLBACK, subscriptionId, deliveryInterval, 1);
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

    /// @notice Cannot delegated deliver compute response for completed subscription
    function testCannotAtomicDeliverOutputForCompletedSubscription() public {
        // Starting nonce
        uint32 nonce = COORDINATOR.maxSubscriberNonce(address(CALLBACK));

        // Create new dummy subscription
        Coordinator.Subscription memory sub = getMockSubscription();

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
        Coordinator.Subscription memory sub = getMockSubscription();
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

    /// @notice Cannot deliver subscription where gas limit is too low
    function testCannotDeliverEIP712SubscriptionWhereGasLimitTooLow() public {
        // Starting nonce
        uint32 nonce = COORDINATOR.maxSubscriberNonce(address(CALLBACK));

        // Create new dummy subscription
        Coordinator.Subscription memory sub = getMockSubscription();

        // Purposefully reduce gasLimit of subscription down ~200 gwei
        sub.maxGasLimit -= 200;

        // Generate signature expiry
        uint32 expiry = uint32(block.timestamp) + 30 minutes;

        // Get EIP-712 typed message
        bytes32 message = getMessage(nonce, expiry, sub);

        // Sign message from delegatee private key
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(DELEGATEE_PRIVATE_KEY, message);

        // Create subscription and deliver response, expecting an out of gas revert
        vm.expectRevert(abi.encodeWithSelector(Coordinator.GasLimitExceeded.selector));
        ALICE.deliverComputeDelegatee(nonce, expiry, sub, v, r, s, 1, MOCK_INPUT, MOCK_OUTPUT, MOCK_PROOF);
    }

    /// @notice Can deliver compute response for already created subscription with reduced gas limit
    function testDeliverReducedGasCostSubscriptionCachedSubscription() public {
        // Create new subscription with redundancy = 2
        Coordinator.Subscription memory sub = getMockSubscription();
        sub.redundancy = 2;

        // Generate signature expiry
        uint32 expiry = uint32(block.timestamp) + 30 minutes;

        // Get signed data
        uint32 nonce = COORDINATOR.maxSubscriberNonce(address(CALLBACK));
        bytes32 message = getMessage(nonce, expiry, sub);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(DELEGATEE_PRIVATE_KEY, message);

        // Manually verifying the callstack is useful here to ensure that the overhead gas is being properly set
        // Measure direct delivery for creation + delivery
        uint256 inputOverhead = 35_000 wei;
        uint256 gasExpected = CALLBACK_COST + COORDINATOR.DELEGATEE_OVERHEAD_CREATE_WEI()
            + COORDINATOR.DELIVERY_OVERHEAD_WEI() + inputOverhead;
        uint256 startingGas = gasleft();
        ALICE.deliverComputeDelegatee(nonce, expiry, sub, v, r, s, 1, MOCK_INPUT, MOCK_OUTPUT, MOCK_PROOF);
        uint256 endingGas = gasleft();
        uint256 gasUsed = startingGas - endingGas;

        // Measure direct delivery for cached creation + delivery
        uint256 gasExpectedCached =
            CALLBACK_COST + COORDINATOR.DELEGATEE_OVERHEAD_CACHED_WEI() + COORDINATOR.DELIVERY_OVERHEAD_WEI();
        startingGas = gasleft();
        BOB.deliverComputeDelegatee(nonce, expiry, sub, v, r, s, 1, MOCK_INPUT, MOCK_OUTPUT, MOCK_PROOF);
        endingGas = gasleft();
        uint256 gasUsedCached = startingGas - endingGas;

        // Assert in ~approximate range (+/- 15K gas, actually copying calldata into memory is expensive)
        uint256 delta = 15_000 wei;
        assertApproxEqAbs(gasExpected, gasUsed, delta);
        assertApproxEqAbs(gasExpectedCached, gasUsedCached, delta);
    }
}
