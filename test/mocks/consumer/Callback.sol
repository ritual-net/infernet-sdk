// SPDX-License-Identifier: BSD-3-Clause-Clear
pragma solidity ^0.8.4;

import {MockBaseConsumer} from "./Base.sol";
import {LibStruct} from "../../lib/LibStruct.sol";
import {StdAssertions} from "forge-std/StdAssertions.sol";
import {CallbackConsumer} from "../../../src/consumer/Callback.sol";

/// @title MockCallbackConsumer
/// @notice Mocks CallbackConsumer
contract MockCallbackConsumer is MockBaseConsumer, CallbackConsumer, StdAssertions {
    /*//////////////////////////////////////////////////////////////
                              CONSTRUCTOR
    //////////////////////////////////////////////////////////////*/

    /// Create new MockCallbackConsumer
    /// @param _coordinator coordinator address
    constructor(address _coordinator) CallbackConsumer(_coordinator) {}

    /*//////////////////////////////////////////////////////////////
                           UTILITY FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /// @notice Create new mock callback request
    /// @dev Parameter interface conforms to same as `CallbackConsumer._requestCompute`
    /// @dev Augmented with checks
    /// @dev Checks returned subscription ID is serially conforming
    /// @dev Checks subscription stored in coordinator storage conforms to expected, given inputs
    function createMockRequest(
        string calldata containerId,
        bytes calldata inputs,
        uint48 maxGasPrice,
        uint32 maxGasLimit,
        uint16 redundancy
    ) external returns (uint32) {
        // Get current block timestamp
        uint256 currentTimestamp = block.timestamp;
        // Get expected subscription ID
        uint32 expectedSubscriptionID = COORDINATOR.id();

        // Request off-chain container compute
        uint32 actualSubscriptionID = _requestCompute(containerId, inputs, maxGasPrice, maxGasLimit, redundancy);

        // Assert ID expectations
        assertEq(expectedSubscriptionID, actualSubscriptionID);

        // Collect subscription from storage
        LibStruct.Subscription memory sub = LibStruct.getSubscription(COORDINATOR, actualSubscriptionID);

        // Assert subscription storage
        assertEq(sub.activeAt, currentTimestamp);
        assertEq(sub.owner, address(this));
        assertEq(sub.maxGasPrice, maxGasPrice);
        assertEq(sub.redundancy, redundancy);
        assertEq(sub.maxGasLimit, maxGasLimit);
        assertEq(sub.frequency, 1);
        assertEq(sub.period, 0);
        assertEq(sub.containerId, containerId);
        assertEq(sub.inputs, inputs);

        // Explicitly return subscription ID
        return actualSubscriptionID;
    }

    /*//////////////////////////////////////////////////////////////
                           INHERITED FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /// @notice Overrides internal function, pushing received response to delivered outputs map
    function _receiveCompute(
        uint32 subscriptionId,
        uint32 interval,
        uint16 redundancy,
        address node,
        bytes calldata input,
        bytes calldata output,
        bytes calldata proof
    ) internal override {
        // Log delivered output
        outputs[subscriptionId][interval][redundancy] = DeliveredOutput({
            subscriptionId: subscriptionId,
            interval: interval,
            redundancy: redundancy,
            node: node,
            input: input,
            output: output,
            proof: proof
        });
    }
}
