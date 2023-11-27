// SPDX-License-Identifier: BSD-3-Clause-Clear
pragma solidity ^0.8.4;

import {Manager} from "./Manager.sol";
import {BaseConsumer} from "./consumer/Base.sol";

/// @title Coordinator
/// @notice Coordination layer between consuming smart contracts and off-chain Infernet nodes
/// @dev Allows creating and deleting `Subscription`(s)
/// @dev Allows nodes with `Manager.NodeStatus.Active` to deliver subscription outputs via off-chain container compute
contract Coordinator is Manager {
    /*//////////////////////////////////////////////////////////////
                                STRUCTS
    //////////////////////////////////////////////////////////////*/

    /// @notice A subscription is the fundamental unit of Infernet
    /// @dev A subscription represents some request configuration for off-chain compute via containers on Infernet nodes
    /// @dev A subscription with `frequency == 1` is a one-time subscription (a callback)
    /// @dev A subscription with `frequency > 1` is a recurring subscription (many callbacks)
    /// @dev Tightly-packed struct:
    ///      - [owner, activeAt, period, frequency]: [32, 160, 32, 32] = 256
    ///      - [redundancy, maxGasPrice, maxGasLimit]: [16, 48, 32] = 96
    struct Subscription {
        /// @notice Subscription owner + recipient
        /// @dev This is the address called to fulfill a subscription request and must inherit `BaseConsumer`
        /// @dev Default initializes to `address(0)`
        address owner;
        /// @notice Timestamp when subscription is first active and an off-chain Infernet node can respond
        /// @dev When `period == 0`, the subscription is immediately active
        /// @dev When `period > 0`, subscription is active at `createdAt + period`
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
        /// @notice Max gas price in wei paid by an Infernet node when fulfilling callback
        /// @dev uint40 caps out at ~1099 gwei, uint48 allows up to ~281K gwei
        uint48 maxGasPrice;
        /// @notice Max gas limit in wei used by an Infernet node when fulfilling callback
        /// @dev Must be at least equal to the gas limit of your receiving function execution + DELIVERY_OVERHEAD_WEI
        /// @dev uint24 is too small at ~16.7M (<30M mainnet gas limit), but uint32 is more than enough (~4.2B wei)
        uint32 maxGasLimit;
        /// @notice Container identifier used by off-chain Infernet nodes to determine which container is used to fulfill a subscription
        /// @dev Can be used to specify a linear DAG of containers by seperating container names with a "," delimiter ("A,B,C")
        /// @dev Better represented by a string[] type but constrained to string to keep struct and functions simple
        string containerId;
        /// @notice Optional container input parameters
        /// @dev If left empty, off-chain Infernet nodes call public view fn: `BaseConsumer(owner).getContainerInputs()`
        bytes inputs;
    }

    /*//////////////////////////////////////////////////////////////
                               CONSTANTS
    //////////////////////////////////////////////////////////////*/

    /// @notice Gas overhead in wei to deliver container compute responses
    /// @dev This is the additional cost of any validation checks performed within the `Coordinator`
    ///      before delivering responses to consumer contracts
    /// @dev A uint16 is sufficient but we are not packing variables so control plane cost is higher because of type
    ///      casting during operations. Thus, we can just stick to uint256
    uint256 public constant DELIVERY_OVERHEAD_WEI = 56_600 wei;

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
    ///      But, this is a little over the optimization:redability line and would make Subscriptions harder to grok
    mapping(bytes32 => uint16) public redundancyCount;

    /// @notice subscriptionID => Subscription
    /// @dev 1-indexed, 0th-subscription is empty
    mapping(uint32 => Subscription) public subscriptions;

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

    /// @notice Thrown by `deliverComputeWithOverhead()` if delivering tx with gasPrice > subscription maxGasPrice
    /// @dev E.g. submitting tx with gas price `10 gwei` when network basefee is `11 gwei`
    /// @dev 4-byte signature: `0x682bad5a`
    error GasPriceExceeded();

    /// @notice Thrown by `deliverComputeWithOverhead()` if delivering tx with consumed gas > subscription maxGasLimit
    /// @dev E.g. submitting tx with gas consumed `200_000 wei` when max allowed by subscription is `175_000 wei`
    /// @dev 4-byte signature: `0xbe9179a6`
    error GasLimitExceeded();

    /// @notice Thrown by `deliverComputeWithOverhead()` if attempting to deliver container compute response for non-current interval
    /// @dev E.g submitting tx for `interval` < current (period elapsed) or `interval` > current (too early to submit)
    /// @dev 4-byte signature: `0x4db310c3`
    error IntervalMismatch();

    /// @notice Thrown by `deliverComputeWithOverhead()` if `redundancy` has been met for current `interval`
    /// @dev E.g submitting 4th output tx for a subscription with `redundancy == 3`
    /// @dev 4-byte signature: `0x2f4ca85b`
    error IntervalCompleted();

    /// @notice Thrown by `deliverComputeWithOverhead()` if `node` has already responded this `interval`
    /// @dev 4-byte signature: `0x88a21e4f`
    error NodeRespondedAlready();

    /// @notice Thrown by `deliverComputeWithOverhead()` if attempting to access a subscription that does not exist
    /// @dev 4-byte signature: `0x1a00354f`
    error SubscriptionNotFound();

    /// @notice Thrown by `cancelSubscription()` if attempting to modify a subscription not owned by caller
    /// @dev 4-byte signature: `0xa7fba711`
    error NotSubscriptionOwner();

    /// @notice Thrown by `deliverComputeWithOverhead()` if attempting to deliver a completed subscription
    /// @dev 4-byte signature: `0xae6704a7`
    error SubscriptionCompleted();

    /// @notice Thrown by `deliverComputeWithOverhead()` if attempting to deliver a subscription before `activeAt`
    /// @dev 4-byte signature: `0xefb74efe`
    error SubscriptionNotActive();

    /*//////////////////////////////////////////////////////////////
                           INTERNAL FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /// @notice Internal counterpart to `deliverCompute()` w/ ability to set custom gas overhead allowance
    /// @dev When called by `deliverCompute()`, `callingOverheadWei == 0` because no additional overhead imposed
    /// @dev When called by `deliverComputeDelegatee()`, `DELEGATEE_OVERHEAD_*_WEI` is imposed
    /// @param subscriptionId subscription ID to deliver
    /// @param deliveryInterval subscription `interval` to deliver
    /// @param input optional off-chain input recorded by Infernet node (empty, hashed input, processed input, or both)
    /// @param output optional off-chain container output (empty, hashed output, processed output, both, or fallback: all encodeable data)
    /// @param proof optional container execution proof (or arbitrary metadata)
    /// @param callingOverheadWei additional overhead gas used for delivery
    function _deliverComputeWithOverhead(
        uint32 subscriptionId,
        uint32 deliveryInterval,
        bytes calldata input,
        bytes calldata output,
        bytes calldata proof,
        uint256 callingOverheadWei
    ) internal {
        // Naively, one would think that loading a subscription into memory via
        // `Subscription memory subscription = subscriptions[subscriptionId]`
        // would be cost-effective and most readable.

        // Unfortunately, this is not the case. This function makes no use of
        // `subscription.containerId` or `subscription.inputs`. Because these
        // are dynamic types, we are forced to pay to load into memory the length
        // + content of these parameters. In some cases (say, container input being
        // 100 uint256's), we are forced to pay 2 SLOAD (length slot containerId, inputs)
        // + N SLOAD (containerId + inputs byte length / word size) (for example, 100
        // SLOAD's in the case of 100 uint256's) + N MSTORE (copying into memory)
        // + memory expansion costs.

        // To avoid this, we can first access memory parameters selectively, copying
        // just the fixed size params (uint16, etc.) into memory by accessing state via
        // `subscriptions[subscriptionId].activeAt` syntax.

        // But, with this syntax, while we avoid the significant overhead of copying
        // from storage, into memory, the unnecessary dynamic parameters, we are now
        // forced to pay 100 gas for each non-first storage slot read (hot SLOAD).

        // For example, even if accessing two tightly-packed variables in slot 0, we must
        // pay COLD SLOAD + HOT SLOAD, rather than just COLD SLOAD + MLOAD.

        // To avoid this, we can drop down to assembly and:
        //      1. Manually SLOAD tightly-packed struct slots
        //      2. Unpack and MSTORE variables to avoid the hot SLOAD penalty since we
        //         only copy from storage into memory once (rather than for each variable)

        // Setup parameters in first slot
        // Note, we could load these variables right before they are used but the MSTORE is cheap and this is cleaner
        address subOwner;
        uint32 subActiveAt;
        uint32 subPeriod;
        uint32 subFrequency;

        // Store slot identifier for subscriptions[subscriptionId][slot 0]
        bytes32 storageSlot;
        assembly ("memory-safe") {
            // Load address of free-memory pointer
            let m := mload(0x40)

            // Store subscription ID to first free slot
            // uint32 automatically consumes full word
            mstore(m, subscriptionId)
            // Store subscriptions mapping storage slot (4) to 32 byte (1 word) offset
            mstore(add(m, 0x20), 4)

            // At this point, memory layout [0 -> 0x20 == subscriptionId, 0x20 -> 0x40 == 4]
            // Calculate mapping storage slot — hash(key, mapping slot)
            // Hash data from 0 -> 0x40 (2 words)
            storageSlot := keccak256(m, 0x40)

            // SLOAD struct data
            let data := sload(storageSlot)

            // Solidity packs structs right to left (least-significant bits a la little-endian)
            // MSTORE'ing tightly-packed variables from storage slot data
            // Erase first 96 bits via AND, grab last 160
            subOwner := and(data, 0xFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF)
            // Grab first 32 bits preceeding owner
            subActiveAt := and(shr(160, data), 0xFFFFFFFF)
            // Grab first 32 bits preceeding activeAt
            subPeriod := and(shr(192, data), 0xFFFFFFFF)
            // Grab first 32 bits from left
            subFrequency := shr(224, data)
        }

        // Revert if subscription does not exist
        if (subOwner == address(0)) {
            revert SubscriptionNotFound();
        }

        // Revert if subscription is not yet active
        if (block.timestamp < subActiveAt) {
            revert SubscriptionNotActive();
        }

        // Calculate subscription interval
        uint32 interval = getSubscriptionInterval(subActiveAt, subPeriod);

        // Revert if not processing curent interval
        if (interval != deliveryInterval) {
            revert IntervalMismatch();
        }

        // Revert if interval > frequency
        if (interval > subFrequency) {
            revert SubscriptionCompleted();
        }

        // Setup parameters in second slot
        uint16 subRedundancy;
        uint48 subMaxGasPrice;
        uint32 subMaxGasLimit;

        assembly ("memory-safe") {
            // SLOAD struct data
            // Second slot is simply offset from first by 1
            let data := sload(add(storageSlot, 1))

            // MSTORE'ing tightly-packed variables from storage slot data
            // Grab last 16 bits
            subRedundancy := and(data, 0xFFFF)
            // Grab first 48 bits preceeding redundancy
            subMaxGasPrice := and(shr(16, data), 0xFFFFFFFFFFFF)
            // Grab first 32 bits from left
            subMaxGasLimit := and(shr(64, data), 0xFFFFFFFF)
        }

        // Revert if tx gas price > max subscription allowed
        if (tx.gasprice > subMaxGasPrice) {
            revert GasPriceExceeded();
        }

        // Revert if redundancy requirements for this interval have been met
        bytes32 key = keccak256(abi.encode(subscriptionId, interval));
        uint16 numRedundantDeliveries = redundancyCount[key];
        if (numRedundantDeliveries == subRedundancy) {
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

        // Deliver container compute output to contract (measuring execution cost)
        uint256 startingGas = gasleft();
        BaseConsumer(subOwner).rawReceiveCompute(
            subscriptionId, interval, numRedundantDeliveries + 1, msg.sender, input, output, proof
        );
        uint256 endingGas = gasleft();

        // Revert if gas used > allowed, we can make unchecked:
        // Gas limit in most networks is usually much below uint256 max, and by this point a decent amount is spent
        // `callingOverheadWei`, `DELIVERY_OVERHEAD_WEI` both fit in under uint24's
        // Thus, this operation is unlikely to ever overflow ((uint256 - uint256) + (uint16 + uint24))
        // Unless the bounds are along the lines of: {startingGas: UINT256_MAX, endingGas: << (callingOverheadWei + DELIVERY_OVERHEAD_WEI)}
        uint256 executionCost;
        unchecked {
            executionCost = startingGas - endingGas + callingOverheadWei + DELIVERY_OVERHEAD_WEI;
        }
        if (executionCost > subMaxGasLimit) {
            revert GasLimitExceeded();
        }

        // Emit successful delivery
        emit SubscriptionFulfilled(subscriptionId, msg.sender);
    }

    /*//////////////////////////////////////////////////////////////
                               FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /// @notice Creates new subscription
    /// @param containerId compute container identifier used by off-chain Infernet node
    /// @param inputs optional container inputs
    /// @param maxGasPrice max gas price in wei paid by an Infernet node when fulfilling callback
    /// @param maxGasLimit max gas limit in wei paid by an Infernet node in callback tx
    /// @param frequency max number of times to process subscription (i.e, `frequency == 1` is a one-time request)
    /// @param period period, in seconds, at which to progress each responding `interval`
    /// @param redundancy number of unique responding Infernet nodes
    /// @return subscription ID
    function createSubscription(
        string memory containerId,
        bytes calldata inputs,
        uint48 maxGasPrice,
        uint32 maxGasLimit,
        uint32 frequency,
        uint32 period,
        uint16 redundancy
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
            maxGasPrice: maxGasPrice,
            redundancy: redundancy,
            maxGasLimit: maxGasLimit,
            frequency: frequency,
            period: period,
            containerId: containerId,
            inputs: inputs
        });

        // Emit new subscription
        emit SubscriptionCreated(subscriptionId);

        // Explicitly return subscriptionId
        return subscriptionId;
    }

    /// @notice Cancel a subscription
    /// @dev Must be called by `subscriptions[subscriptionId].owner`
    /// @param subscriptionId subscription ID to cancel
    function cancelSubscription(uint32 subscriptionId) external {
        // Throw if owner of subscription is not caller
        if (subscriptions[subscriptionId].owner != msg.sender) {
            revert NotSubscriptionOwner();
        }

        // Nullify subscription
        delete subscriptions[subscriptionId];

        // Emit cancellation
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

    /// @notice Allows nodes with `Manager.NodeStatus.Active` to deliver container compute responses for a subscription
    /// @dev Re-entering does not work because only active nodes (max 1 response) can call `deliverCompute`
    /// @dev Re-entering and delivering via a seperate node `msg.sender` works but is ignored in favor of explicit `maxGasLimit`
    /// @dev For containers without succinctly-verifiable proofs, the `proof` field can be repurposed for arbitrary metadata
    /// @dev Enforces an overhead delivery cost of `DELIVERY_OVERHEAD_WEI` and `0` additional overhead
    /// @param subscriptionId subscription ID to deliver
    /// @param deliveryInterval subscription `interval` to deliver
    /// @param input optional off-chain container input recorded by Infernet node (empty, hashed input, processed input, or both)
    /// @param output optional off-chain container output (empty, hashed output, processed output, both, or fallback: all encodeable data)
    /// @param proof optional off-chain container execution proof (or arbitrary metadata)
    function deliverCompute(
        uint32 subscriptionId,
        uint32 deliveryInterval,
        bytes calldata input,
        bytes calldata output,
        bytes calldata proof
    ) external onlyActiveNode {
        _deliverComputeWithOverhead(subscriptionId, deliveryInterval, input, output, proof, 0);
    }
}
