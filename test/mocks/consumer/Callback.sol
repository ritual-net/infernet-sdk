// SPDX-License-Identifier: BSD-3-Clause-Clear
pragma solidity ^0.8.4;

import {Subscription} from "../../../src/Coordinator.sol";
import {StdAssertions} from "forge-std/StdAssertions.sol";
import {MockBaseConsumer, DeliveredOutput} from "./Base.sol";
import {CallbackConsumer} from "../../../src/consumer/Callback.sol";

/// @title MockCallbackConsumer
/// @notice Mocks CallbackConsumer
contract MockCallbackConsumer is MockBaseConsumer, CallbackConsumer, StdAssertions {
    /*//////////////////////////////////////////////////////////////
                              CONSTRUCTOR
    //////////////////////////////////////////////////////////////*/

    /// @notice Create new MockCallbackConsumer
    /// @param registry registry address
    constructor(address registry) CallbackConsumer(registry) {}

    /*//////////////////////////////////////////////////////////////
                           UTILITY FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /// @notice Create new mock callback request
    /// @dev Parameter interface conforms to same as `CallbackConsumer._requestCompute`
    /// @dev Augmented with checks
    /// @dev Checks returned subscription ID is serially conforming
    /// @dev Checks subscription stored in coordinator storage conforms to expected, given inputs
    function createMockRequest(
        string memory containerId,
        bytes memory inputs,
        uint16 redundancy,
        address paymentToken,
        uint256 paymentAmount,
        address wallet,
        address prover
    ) external returns (uint32) {
        // Get current block timestamp
        uint256 currentTimestamp = block.timestamp;
        // Get expected subscription ID
        uint32 expectedSubscriptionID = COORDINATOR.id();

        // Request off-chain container compute
        uint32 actualSubscriptionID =
            _requestCompute(containerId, inputs, redundancy, paymentToken, paymentAmount, wallet, prover);

        // Assert ID expectations
        assertEq(expectedSubscriptionID, actualSubscriptionID);

        // Collect subscription from storage
        Subscription memory sub = COORDINATOR.getSubscription(actualSubscriptionID);

        // Assert subscription storage
        assertEq(sub.activeAt, currentTimestamp);
        assertEq(sub.owner, address(this));
        assertEq(sub.redundancy, redundancy);
        assertEq(sub.frequency, 1);
        assertEq(sub.period, 0);
        assertEq(sub.containerId, keccak256(abi.encode(containerId)));
        assertEq(sub.lazy, false);
        assertEq(sub.paymentToken, paymentToken);
        assertEq(sub.paymentAmount, paymentAmount);
        assertEq(sub.wallet, wallet);
        assertEq(sub.prover, prover);
        assertEq(subscriptionInputs[actualSubscriptionID], inputs);

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
