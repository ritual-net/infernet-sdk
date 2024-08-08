// SPDX-License-Identifier: BSD-3-Clause-Clear
pragma solidity ^0.8.4;

import {Inbox} from "./Inbox.sol";
import {Fee} from "./payments/Fee.sol";
import {Registry} from "./Registry.sol";
import {Wallet} from "./payments/Wallet.sol";
import {BaseConsumer} from "./consumer/Base.sol";
import {IVerifier} from "./payments/IVerifier.sol";
import {WalletFactory} from "./payments/WalletFactory.sol";
import {ReentrancyGuard} from "solady/utils/ReentrancyGuard.sol";

/*//////////////////////////////////////////////////////////////
                            PUBLIC STRUCTS
//////////////////////////////////////////////////////////////*/

/// @notice A subscription is the fundamental unit of Infernet
/// @dev A subscription represents some request configuration for off-chain compute via containers on Infernet nodes
/// @dev A subscription with `frequency == 1` is a one-time subscription (a callback)
/// @dev A subscription with `frequency > 1` is a recurring subscription (many callbacks)
/// @dev Tightly-packed struct:
///      - [owner, activeAt, period, frequency]: [160, 32 32, 32] = 256
///      - [redundancy, containerId, lazy, verifier]: [16, 32, 8, 160] = 216
///      - [paymentAmount]: [256] = 256
///      - [paymentToken]: [160] = 160
///      - [wallet]: [160] = 160
struct Subscription {
    /// @notice Subscription owner + recipient
    /// @dev This is the address called to fulfill a subscription request and must inherit `BaseConsumer`
    address owner;
    /// @notice Timestamp when subscription is first active and an off-chain Infernet node can respond
    /// @dev When `period == 0`, the subscription is immediately active
    /// @dev When `period > 0`, subscription is active at `createdAt + period`
    /// @dev Cancelled subscriptions update `activeAt` to `type(uint32).max` effectively restricting all future submissions
    uint32 activeAt;
    /// @notice Time, in seconds, between each subscription interval
    /// @dev At worst, assuming subscription occurs once/year << uint32
    uint32 period;
    /// @notice Number of times a subscription is processed
    /// @dev At worst, assuming 30 req/min * 60 min * 24 hours * 365 days * 10 years << uint32
    uint32 frequency;
    /// @notice Number of unique nodes that can fulfill a subscription at each `interval`
    /// @dev uint16 allows for >255 nodes (uint8) but <65,535
    uint16 redundancy;
    /// @notice Container identifier used by off-chain Infernet nodes to determine which container is used to fulfill a subscription
    /// @dev Represented as fixed size hash of stringified list of containers
    /// @dev Can be used to specify a linear DAG of containers by seperating container names with a "," delimiter ("A,B,C")
    /// @dev Better represented by a string[] type but constrained to hash(string) to keep struct and functions simple
    bytes32 containerId;
    /// @notice `true` if container compute responses lazily stored as an `InboxItem`(s) in `Inbox`, else `false`
    /// @dev When `true`, container compute outputs are stored in `Inbox` and not delivered eagerly to a consumer
    /// @dev When `false`, container compute outputs are not stored in `Inbox` and are delivered eagerly to a consumer
    bool lazy;
    /// @notice Optional verifier contract to restrict subscription payment on the basis of proof verification
    /// @dev If `address(0)`, we assume that no proof contract is necessary, and disperse supplied payment immediately
    /// @dev If verifier contract is supplied, it must implement the `IVerifier` interface
    /// @dev Eager verifier contracts disperse payment immediately to relevant `Wallet`(s)
    /// @dev Lazy verifier contracts disperse payment after a delay (max. 1-week) to relevant `Wallet`(s)
    /// @dev Notice that consumer contracts can still independently implement their own 0-cost proof verification within their contracts
    address payable verifier;
    /// @notice Optional amount to pay in `paymentToken` each time a subscription is processed
    /// @dev If `0`, subscription has no associated payment
    /// @dev uint256 since we allow `paymentToken`(s) to have arbitrary ERC20 implementations (unknown `decimal`s)
    /// @dev In theory, this could be a {dynamic pricing mechanism, reverse auction, etc.} but kept simple for now (abstractions can be built later)
    uint256 paymentAmount;
    /// @notice Optional payment token
    /// @dev If `address(0)`, payment is in Ether (or no payment in conjunction with `paymentAmount == 0`)
    /// @dev Else, `paymentToken` must be an ERC20-compatible token contract
    address paymentToken;
    /// @notice Optional `Wallet` to pay for compute payments; `owner` must be approved spender
    /// @dev Defaults to `address(0)` when no payment specified
    address payable wallet;
}

/// @notice A ProofRequest is a request made to a verifier contract to validate some proof bytes
/// @dev Tightly-packed struct
///      - [expiry, nodeWallet]: [32, 160] = 192
///      - [consumerEscrowed]: [256] = 256
struct ProofRequest {
    /// @notice Proof request expiration
    /// @dev Set to block.timestamp (time of proof request initiation) + 1 week window
    uint32 expiry;
    /// @notice Address of node `Wallet` which has escrowed `paymentAmount` `paymentToken`
    Wallet nodeWallet;
    /// @notice Amount of `paymentToken` escrowed by the consumer as successful payment to `nodeWallet`
    /// @dev Because verifiers can update their fees, we have to keep a reference to the exact escrowed amount rather than calculate on-demand
    uint256 consumerEscrowed;
}

/// @title Coordinator
/// @notice Coordination layer between consuming smart contracts and off-chain Infernet nodes
/// @dev Implements `ReentrancyGuard` to prevent reentrancy in `deliverCompute`
/// @dev Allows creating and deleting `Subscription`(s)
/// @dev Allows any address (a `node`) to deliver susbcription outputs via off-chain container compute
contract Coordinator is ReentrancyGuard {
    /*//////////////////////////////////////////////////////////////
                               IMMUTABLE
    //////////////////////////////////////////////////////////////*/

    /// @notice Fee registry contract (used to collect protocol fee)
    Fee private immutable FEE;

    /// @notice Inbox contract (handles lazily storing subscription responses)
    Inbox private immutable INBOX;

    /// @notice Wallet factory contract (handles validity verification of `Wallet` contracts)
    WalletFactory private immutable WALLET_FACTORY;

    /*//////////////////////////////////////////////////////////////
                                MUTABLE
    //////////////////////////////////////////////////////////////*/

    /// @notice Current highest subscription ID
    /// @dev 1-indexed to allow using id as a mapping value (prevent 0-indexed default from being misused)
    /// @dev uint32 size(4.2B) should be sufficiently large
    uint32 public id = 1;

    /// @notice hash(subscriptionId, interval, caller) => has caller responded for (sub, interval)?
    mapping(bytes32 => bool) public nodeResponded;

    /// @notice hash(subscriptionId, interval) => Number of responses for (sub, interval)?
    /// @dev Limited to type(Subscription.redundancy) == uint16
    /// @dev Technically, this is not required and we can save an SLOAD if we simply add a uint48 to the subscription
    ///      struct that represents 32 bits of the interval -> 16 bits of redundancy count, reset each interval change
    ///      But, this is a little over the optimization:readability line and would make Subscriptions harder to grok
    mapping(bytes32 => uint16) public redundancyCount;

    /// @notice hash(subscriptionId, interval, caller) => proof request
    mapping(bytes32 => ProofRequest) public proofRequests;

    /// @notice subscriptionID => Subscription
    /// @dev 1-indexed, 0th-subscription is empty
    /// @dev Visibility restricted to `internal` because we expose an explicit `getSubscription` view function that returns `Subscription` struct
    mapping(uint32 => Subscription) internal subscriptions;

    /*//////////////////////////////////////////////////////////////
                                 EVENTS
    //////////////////////////////////////////////////////////////*/

    /// @notice Emitted when a new subscription is created
    /// @param id subscription ID
    event SubscriptionCreated(uint32 indexed id);

    /// @notice Emitted when a subscription is cancelled
    /// @param id subscription ID
    event SubscriptionCancelled(uint32 indexed id);

    /// @notice Emitted when a subscription is fulfilled
    /// @param id subscription ID
    /// @param node address of fulfilling node
    event SubscriptionFulfilled(uint32 indexed id, address indexed node);

    /*//////////////////////////////////////////////////////////////
                                 ERRORS
    //////////////////////////////////////////////////////////////*/

    /// @notice Thrown by `deliverCompute()` if attempting to use an invalid `wallet` or one not created by `WalletFactory`
    /// @dev 4-byte signature: `0x23455ba1`
    error InvalidWallet();

    /// @notice Thrown by `deliverCompute()` if attempting to deliver container compute response for non-current interval
    /// @dev E.g submitting tx for `interval` < current (period elapsed) or `interval` > current (too early to submit)
    /// @dev 4-byte signature: `0x4db310c3`
    error IntervalMismatch();

    /// @notice Thrown by `deliverCompute()` if `redundancy` has been met for current `interval`
    /// @dev E.g submitting 4th output tx for a subscription with `redundancy == 3`
    /// @dev 4-byte signature: `0x2f4ca85b`
    error IntervalCompleted();

    /// @notice Thrown by `finalizeProofVerification()` if called by a `msg.sender` that is unauthorized to finalize proof
    /// @dev When a proof request is expired, this can be any address; until then, this is the designated `verifier` address
    /// @dev 4-byte signature: `0xb9857aa1`
    error UnauthorizedVerifier();

    /// @notice Thrown by `deliverCompute()` if `node` has already responded this `interval`
    /// @dev 4-byte signature: `0x88a21e4f`
    error NodeRespondedAlready();

    /// @notice Thrown by `deliverCompute()` if attempting to access a subscription that does not exist
    /// @dev 4-byte signature: `0x1a00354f`
    error SubscriptionNotFound();

    /// @notice Thrown by `finalizeProofVerification()` if attempting to access a proof request that does not exist
    /// @dev 4-byte signature: `0x1d68b37c`
    error ProofRequestNotFound();

    /// @notice Thrown by `cancelSubscription()` if attempting to modify a subscription not owned by caller
    /// @dev 4-byte signature: `0xa7fba711`
    error NotSubscriptionOwner();

    /// @notice Thrown by `deliverCompute()` if attempting to deliver a completed subscription
    /// @dev 4-byte signature: `0xae6704a7`
    error SubscriptionCompleted();

    /// @notice Thrown by `deliverCompute()` if attempting to deliver a subscription before `activeAt`
    /// @dev 4-byte signature: `0xefb74efe`
    error SubscriptionNotActive();

    /// @notice Thrown by `deliverCompute` if attempting to pay a `IVerifier`-contract in a token it does not support receiving payments in
    /// @dev 4-byte signature: `0xe2372799`
    error UnsupportedVerifierToken();

    /*//////////////////////////////////////////////////////////////
                              CONSTRUCTOR
    //////////////////////////////////////////////////////////////*/

    /// @notice Initializes new Coordinator
    /// @param registry registry contract
    constructor(Registry registry) {
        // Collect fee contract from registry
        FEE = Fee(registry.FEE());
        // Collect inbox contract from registry
        INBOX = Inbox(registry.INBOX());
        // Collect wallet factory contract from registry
        WALLET_FACTORY = WalletFactory(registry.WALLET_FACTORY());
    }

    /*//////////////////////////////////////////////////////////////
                           INTERNAL FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /// @notice Given an input `amount`, returns the value of `fee` applied to it
    /// @param amount to calculate fee on top of
    /// @param fee to use in calculation
    /// @return fee amount
    function _calculateFee(uint256 amount, uint16 fee) internal pure returns (uint256) {
        // (amount * fee) / 1e4 scaling factor
        return amount * fee / 10_000;
    }

    /*//////////////////////////////////////////////////////////////
                               FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /// @notice Returns `Subscription` from `subscriptions` mapping, indexed by `subscriptionId`
    /// @dev Useful utility view function because by default public mappings with struct values return destructured parameters
    /// @param subscriptionId subscription ID to collect
    function getSubscription(uint32 subscriptionId) external view returns (Subscription memory) {
        return subscriptions[subscriptionId];
    }

    /// @notice Creates new subscription
    /// @param containerId compute container identifier used by off-chain Infernet node
    /// @param frequency max number of times to process subscription (i.e, `frequency == 1` is a one-time request)
    /// @param period period, in seconds, at which to progress each responding `interval`
    /// @param redundancy number of unique responding Infernet nodes
    /// @param lazy whether to lazily store subscription responses
    /// @param paymentToken If providing payment for compute, payment token address (address(0) for ETH, else ERC20 contract address)
    /// @param paymentAmount If providing payment for compute, payment in `paymentToken` per compute request fulfillment
    /// @param wallet If providing payment for compute, Infernet `Wallet` address; `msg.sender` must be approved spender
    /// @param verifier optional verifier contract to restrict payment based on response proof verification
    /// @return subscription ID
    function createSubscription(
        string memory containerId,
        uint32 frequency,
        uint32 period,
        uint16 redundancy,
        bool lazy,
        address paymentToken,
        uint256 paymentAmount,
        address wallet,
        address verifier
    ) external returns (uint32) {
        // Get subscription id and increment
        // Unlikely this will ever overflow so we can toss in unchecked
        uint32 subscriptionId;
        unchecked {
            subscriptionId = id++;
        }

        // Store new subscription
        subscriptions[subscriptionId] = Subscription({
            // If period is = 0 (one-time), active immediately
            // Else, next active at first period mark
            // Probably reasonable to keep the overflow protection here given adding 2 uint32's into a uint32
            activeAt: uint32(block.timestamp) + period,
            owner: msg.sender,
            redundancy: redundancy,
            frequency: frequency,
            period: period,
            containerId: keccak256(abi.encode(containerId)),
            lazy: lazy,
            verifier: payable(verifier),
            paymentAmount: paymentAmount,
            paymentToken: paymentToken,
            wallet: payable(wallet)
        });

        // Emit new subscription
        emit SubscriptionCreated(subscriptionId);

        // Explicitly return subscriptionId
        return subscriptionId;
    }

    /// @notice Cancel a subscription
    /// @dev Must be called by `subscriptions[subscriptionId].owner`
    /// @dev Cancels subscription by setting `Subscription` `activeAt` to maximum (technically, de-activating)
    /// @param subscriptionId subscription ID to cancel
    function cancelSubscription(uint32 subscriptionId) external {
        // Throw if owner of subscription is not caller
        if (subscriptions[subscriptionId].owner != msg.sender) {
            revert NotSubscriptionOwner();
        }

        // Set `activeAt` to max type(uint32)
        // While we could delete the subscription itself (and in previous versions of Infernet this was done),
        // it is net cheaper on average to simply invalidate via `activeAt` instead, to allow use of `Subscription`
        // parameters during verifier proof verification payout (since that path is to called with greater frequency)
        subscriptions[subscriptionId].activeAt = type(uint32).max;

        // Emit cancellation
        // Event can be emitted more than once if cancelling already cancelled subscription
        emit SubscriptionCancelled(subscriptionId);
    }

    /// @notice Calculates subscription `interval` based on `activeAt` and `period`
    /// @param activeAt when does a subscription start accepting callback responses
    /// @param period time, in seconds, between each subscription response `interval`
    /// @return current subscription interval
    function getSubscriptionInterval(uint32 activeAt, uint32 period) public view returns (uint32) {
        // If period is 0, we're always at interval 1
        if (period == 0) {
            return 1;
        }

        // Else, interval = ((block.timestamp - activeAt) / period) + 1
        // This is only called after validating block.timestamp >= activeAt so timestamp can't underflow
        // We also short-circuit above if period is zero so no need for division by zero checks
        unchecked {
            return ((uint32(block.timestamp) - activeAt) / period) + 1;
        }
    }

    /// @notice Allows any address (nodes) to deliver container compute responses for a subscription
    /// @dev Re-entering generally does not work because each node can only call `deliverCompute` once per subscription
    /// @dev But, you can call `deliverCompute` with a seperate `msg.sender` (in same delivery call) so we optimistically restrict with `nonReentrant`
    /// @dev When `Subscription`(s) request lazy responses, stores container output in `Inbox`
    /// @dev When `Subscription`(s) request eager responses, delivers container output directly via `BaseConsumer.rawReceiveCompute()`
    /// @param subscriptionId subscription ID to deliver
    /// @param deliveryInterval subscription `interval` to deliver
    /// @param input optional off-chain input recorded by Infernet node (empty, hashed input, processed input, or both)
    /// @param output optional off-chain container output (empty, hashed output, processed output, both, or fallback: all encodeable data)
    /// @param proof optional container execution proof (or arbitrary metadata)
    /// @param nodeWallet node wallet (used to receive payments, and put up escrow/slashing funds); msg.sender must be authorized spender of wallet
    function deliverCompute(
        uint32 subscriptionId,
        uint32 deliveryInterval,
        bytes calldata input,
        bytes calldata output,
        bytes calldata proof,
        address nodeWallet
    ) public nonReentrant {
        // In infernet-sdk v0.1.0, loading a subscription into memory was handled
        // piece-wise in assembly because a Subscription struct contained dynamic
        // types (forcing an explict, unbounded SLOAD cost to copy dynamic length /
        // word size bytes).

        // In infernet-sdk v0.2.0, we removed dynamic types in Subscription structs
        // allowing us to directly copy a subscription into memory. Notice: this is
        // still not the most optimized approach, given we pay up-front to SLOAD 2
        // slots, rather than loading 1 slot at a time (subsidizing costs in case
        // of failure conditions). Still, the additional gas overhead (~500 gas in most
        // failure cases) is better than poor developer UX and worse readability.

        // Collect subscription
        Subscription memory subscription = subscriptions[subscriptionId];

        // Revert if subscription does not exist
        if (subscription.owner == address(0)) {
            revert SubscriptionNotFound();
        }

        // Revert if subscription is not yet active
        if (uint32(block.timestamp) < subscription.activeAt) {
            revert SubscriptionNotActive();
        }

        // Calculate subscription interval
        uint32 interval = getSubscriptionInterval(subscription.activeAt, subscription.period);

        // Revert if not processing current interval
        if (interval != deliveryInterval) {
            revert IntervalMismatch();
        }

        // Revert if interval > frequency
        if (interval > subscription.frequency) {
            revert SubscriptionCompleted();
        }

        // Revert if redundancy requirements for this interval have been met
        bytes32 key = keccak256(abi.encode(subscriptionId, interval));
        uint16 numRedundantDeliveries = redundancyCount[key];
        if (numRedundantDeliveries == subscription.redundancy) {
            revert IntervalCompleted();
        }
        // Highly unlikely to overflow given incrementing by 1/node
        unchecked {
            redundancyCount[key] = numRedundantDeliveries + 1;
        }

        // Revert if node has already responded this interval
        key = keccak256(abi.encode(subscriptionId, interval, msg.sender));
        if (nodeResponded[key]) {
            revert NodeRespondedAlready();
        }
        nodeResponded[key] = true;

        // Handle payments (non-zero payment per subscription fulfillment)
        if (subscription.paymentAmount > 0) {
            // Check if node wallet is valid and created by WalletFactory
            // While this check in theory could be within the verification flow itself (when the node escrows funds),
            // we keep it here to preserve the readability given following check and early input sanitization
            if (!WALLET_FACTORY.isValidWallet(nodeWallet)) {
                revert InvalidWallet();
            }

            // Check if subscription wallet is valid and created by WalletFactory
            if (!WALLET_FACTORY.isValidWallet(subscription.wallet)) {
                revert InvalidWallet();
            }

            // Setup consumer wallet
            Wallet consumer = Wallet(subscription.wallet);

            // Setup initial payment amount
            uint256 tokenAvailable = subscription.paymentAmount;

            // Collect protocol fee and recipient
            uint16 protocolFee = FEE.FEE();
            address protocolFeeRecipient = FEE.FEE_RECIPIENT();

            // Calculate fee as function of subscription payment amount
            // Imposed as 2 * FEE * AMOUNT (rather than (AMOUNT*FEE + (AMOUNT*0.95 * FEE))); uniform application on base amount
            uint256 paidToProtocol = _calculateFee(subscription.paymentAmount, protocolFee * 2);

            // Deduct from temporary amount available and pay protocol
            tokenAvailable -= paidToProtocol;
            consumer.cTransfer(subscription.owner, subscription.paymentToken, protocolFeeRecipient, paidToProtocol);

            // If no verifier specified as precondition to payment fulfillment
            if (subscription.verifier == address(0)) {
                // Immediately process remaining payment from consumer to node
                consumer.cTransfer(subscription.owner, subscription.paymentToken, nodeWallet, tokenAvailable);
                // Else, verifier specified as precondition to payment fulfillment
            } else {
                // Setup verifier contract
                IVerifier verifier = IVerifier(subscription.verifier);

                // Check if verifier accepts `paymentToken`
                if (!verifier.isSupportedToken(subscription.paymentToken)) {
                    revert UnsupportedVerifierToken();
                }

                // Collect verifier fee
                uint256 verifierFee = verifier.fee(subscription.paymentToken);

                // Calculate protocol fee paid by verifier
                tokenAvailable -= verifierFee;
                paidToProtocol = _calculateFee(verifierFee, protocolFee);

                // Pay protocol on behalf of verifier
                consumer.cTransfer(subscription.owner, subscription.paymentToken, protocolFeeRecipient, paidToProtocol);

                // Pay verifier (verifier fee - paid protocol fee)
                consumer.cTransfer(
                    subscription.owner, subscription.paymentToken, verifier.getWallet(), verifierFee - paidToProtocol
                );

                // Setup node wallet
                Wallet node = Wallet(payable(nodeWallet));

                // Escrow slashable amount from node
                node.cLock(msg.sender, subscription.paymentToken, subscription.paymentAmount);

                // Escrow remaining payable amount (to node) from consumer
                consumer.cLock(subscription.owner, subscription.paymentToken, tokenAvailable);

                // Store new proof request
                proofRequests[key] = ProofRequest({
                    expiry: uint32(block.timestamp) + 1 weeks,
                    nodeWallet: node,
                    consumerEscrowed: tokenAvailable
                });

                // Initiate verifier verification
                verifier.requestProofVerification(subscriptionId, interval, msg.sender, proof);
            }
        }

        // If delivering subscription lazily
        if (subscription.lazy) {
            // First, we must store the container outputs in `Inbox`
            uint256 index = INBOX.writeViaCoordinator(
                subscription.containerId, msg.sender, subscriptionId, interval, input, output, proof
            );

            // Next, we can deliver the subscription w/:
            // 1. Nullifying container outputs (since we are storing outputs in the `Inbox`)
            // 2. Providing a pointer to the `Inbox` entry via `containerId`, `index`
            BaseConsumer(subscription.owner).rawReceiveCompute(
                subscriptionId,
                interval,
                numRedundantDeliveries + 1,
                msg.sender,
                "",
                "",
                "",
                subscription.containerId,
                index
            );
        } else {
            // Else, delivering subscription eagerly
            // We must ensure `containerId`, `index` are nullified since eagerly delivering container outputs
            BaseConsumer(subscription.owner).rawReceiveCompute(
                subscriptionId, interval, numRedundantDeliveries + 1, msg.sender, input, output, proof, bytes32(0), 0
            );
        }

        // Emit successful delivery
        emit SubscriptionFulfilled(subscriptionId, msg.sender);
    }

    /// @notice Inbound counterpart to `IVerifier.requestProofVerification()` to process proof verification
    /// @dev If called by `verifier`, accepts `valid` to process payout
    /// @dev Else, can be called by anyone after 1 week timeout to side in favor of node by default
    /// @param subscriptionId subscription ID for which proof verification was requested
    /// @param interval interval of subscription for which proof verification was requested
    /// @param node node in said interval for which proof verification was requested
    /// @param valid `true` if proof was valid, else `false`
    function finalizeProofVerification(uint32 subscriptionId, uint32 interval, address node, bool valid) external {
        // Collect proof request
        bytes32 key = keccak256(abi.encode(subscriptionId, interval, node));
        ProofRequest memory request = proofRequests[key];

        // If proof request does not exist, throw
        if (request.expiry == 0) {
            revert ProofRequestNotFound();
        }

        // Collect associated subscription
        Subscription memory sub = subscriptions[subscriptionId];

        // Unescrow wallets
        request.nodeWallet.cUnlock(node, sub.paymentToken, sub.paymentAmount);
        Wallet(sub.wallet).cUnlock(sub.owner, sub.paymentToken, request.consumerEscrowed);

        // If proof verification period is still active
        if (block.timestamp < request.expiry) {
            // If caller is not verifier, revert
            if (sub.verifier != msg.sender) {
                revert UnauthorizedVerifier();
            }

            // If proof is valid
            if (valid) {
                // Process payment to node
                Wallet(sub.wallet).cTransfer(
                    sub.owner, sub.paymentToken, address(request.nodeWallet), request.consumerEscrowed
                );
                // Else, if proof is not valid
            } else {
                // Slash node
                request.nodeWallet.cTransfer(node, sub.paymentToken, sub.wallet, sub.paymentAmount);
            }
            // Else, if proof verification period expired
        } else {
            // Process payment to node
            Wallet(sub.wallet).cTransfer(
                sub.owner, sub.paymentToken, address(request.nodeWallet), request.consumerEscrowed
            );
        }

        // Delete proof request (proof processed)
        delete proofRequests[key];
    }
}
