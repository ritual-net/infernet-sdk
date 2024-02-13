// SPDX-License-Identifier: BSD-3-Clause-Clear
pragma solidity ^0.8.4;

import {MockBaseConsumer} from "./Base.sol";
import {LibStruct} from "../../lib/LibStruct.sol";
import {StdAssertions} from "forge-std/StdAssertions.sol";
import {SubscriptionConsumer} from "../../../src/consumer/Subscription.sol";

/// @title MockSubscriptionConsumer
/// @notice Mocks SubscriptionConsumer
contract MockSubscriptionConsumer is MockBaseConsumer, SubscriptionConsumer, StdAssertions {
    /*//////////////////////////////////////////////////////////////
                               CONSTANTS
    //////////////////////////////////////////////////////////////*/

    /// @notice Hard-coded container inputs
    bytes public constant CONTAINER_INPUTS = bytes("CONTAINER_INPUTS");

    /*//////////////////////////////////////////////////////////////
                              CONSTRUCTOR
    //////////////////////////////////////////////////////////////*/

    /// Create new MockSubscriptionConsumer
    /// @param registry registry address
    constructor(address registry) SubscriptionConsumer(registry) {}

    /*//////////////////////////////////////////////////////////////
                           UTILITY FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /// @notice Mock read interface to `Inbox` `InboxItem`(s)
    /// @param containerId compute container ID
    /// @param node delivering node address
    /// @param index item index
    /// @return `InboxItem` immutable creation timestamp
    /// @return Associated subscription ID (`0` if none)
    /// @return Associated subscription interval (`0` if none)
    /// @return Optional compute container input parameters
    /// @return Optional compute container output parameters
    /// @return Optional compute container proof parameters
    function readMockInbox(bytes32 containerId, address node, uint256 index)
        external
        view
        returns (uint32, uint32, uint32, bytes memory, bytes memory, bytes memory)
    {
        return _readInbox(containerId, node, index);
    }

    /// @notice Create new mock subscription
    /// @dev Parameter interface conforms to same as `SubscriptionConsumer._createContainerSubscription`
    /// @dev Augmented with checks
    /// @dev Checks returned subscription ID is serially conforming
    /// @dev Checks subscription stored in coordinator storage conforms to expected, given inputs
    function createMockSubscription(
        string calldata containerId,
        uint48 maxGasPrice,
        uint32 maxGasLimit,
        uint32 frequency,
        uint32 period,
        uint16 redundancy,
        bool lazy
    ) external returns (uint32) {
        // Get current block timestamp
        uint256 currentTimestamp = block.timestamp;
        // Get expected subscription id
        uint32 exepectedSubscriptionID = COORDINATOR.id();

        // Create new subscription
        uint32 actualSubscriptionID =
            _createComputeSubscription(containerId, maxGasPrice, maxGasLimit, frequency, period, redundancy, lazy);

        // Assert ID expectations
        assertEq(exepectedSubscriptionID, actualSubscriptionID);

        // Collect subscription from storage
        LibStruct.Subscription memory sub = LibStruct.getSubscription(COORDINATOR, actualSubscriptionID);

        // Assert subscription storage
        assertEq(sub.activeAt, currentTimestamp + period);
        assertEq(sub.owner, address(this));
        assertEq(sub.maxGasPrice, maxGasPrice);
        assertEq(sub.redundancy, redundancy);
        assertEq(sub.maxGasLimit, maxGasLimit);
        assertEq(sub.frequency, frequency);
        assertEq(sub.period, period);
        assertEq(sub.containerId, keccak256(abi.encode(containerId)));
        assertEq(sub.lazy, lazy);

        // Explicitly return subscription ID
        return actualSubscriptionID;
    }

    /// @notice Allows cancelling subscription
    /// @param subscriptionId to cancel
    /// @dev Augmented with checks
    /// @dev Asserts subscription owner is nullified after cancellation
    function cancelMockSubscription(uint32 subscriptionId) external {
        _cancelComputeSubscription(subscriptionId);

        // Get subscription owner & assert zeroed-out
        address expected = address(0);
        (address actual,,,,,,,,) = COORDINATOR.subscriptions(subscriptionId);
        assertEq(actual, expected);
    }

    /*//////////////////////////////////////////////////////////////
                           INHERITED FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /// @notice Override function to return container inputs
    /// @return container inputs
    function getContainerInputs(uint32 subscriptionId, uint32 interval, uint32 timestamp, address caller)
        external
        pure
        override
        returns (bytes memory)
    {
        return CONTAINER_INPUTS;
    }

    /// @notice Overrides internal function, pushing received response to delivered outputs map
    function _receiveCompute(
        uint32 subscriptionId,
        uint32 interval,
        uint16 redundancy,
        address node,
        bytes calldata input,
        bytes calldata output,
        bytes calldata proof,
        bytes32 containerId,
        uint256 index
    ) internal override {
        // Log delivered output
        outputs[subscriptionId][interval][redundancy] = DeliveredOutput({
            subscriptionId: subscriptionId,
            interval: interval,
            redundancy: redundancy,
            node: node,
            input: input,
            output: output,
            proof: proof,
            containerId: containerId,
            index: index
        });
    }
}
