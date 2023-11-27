// SPDX-License-Identifier: BSD-3-Clause-Clear
pragma solidity ^0.8.4;

import {Coordinator} from "../../src/Coordinator.sol";
import {MockBaseConsumer} from "../mocks/consumer/Base.sol";

/// @title LibStruct
/// @notice Useful helpers to (1) coerce native getters to structs, (2) re-export common structs
library LibStruct {
    /*//////////////////////////////////////////////////////////////
                                STRUCTS
    //////////////////////////////////////////////////////////////*/

    /// @notice Reexported Coordinator.Subscription
    /// @dev While still tightly-packed, ordering of variables is not identical to preserve test equality pre-change
    struct Subscription {
        uint32 activeAt;
        address owner;
        uint48 maxGasPrice;
        uint16 redundancy;
        uint32 maxGasLimit;
        uint32 frequency;
        uint32 period;
        string containerId;
        bytes inputs;
    }

    /// @notice Reexported MockBaseConsumer.DeliveredOutput
    struct DeliveredOutput {
        uint32 subscriptionId;
        uint32 interval;
        uint16 redundancy;
        address node;
        bytes input;
        bytes output;
        bytes proof;
    }

    /*//////////////////////////////////////////////////////////////
                           UTILITY FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /// @notice Coerce Coordinator.subscriptions to LibStruct.Subscription
    /// @param coordinator coordinator
    /// @param subscriptionId subscriptionId
    /// @return LibStruct.Subscription
    function getSubscription(Coordinator coordinator, uint32 subscriptionId)
        external
        view
        returns (LibStruct.Subscription memory)
    {
        // Collect subscription from storage
        (
            address owner,
            uint32 activeAt,
            uint32 period,
            uint32 frequency,
            uint16 redundancy,
            uint48 maxGasPrice,
            uint32 maxGasLimit,
            string memory containerId,
            bytes memory inputs
        ) = coordinator.subscriptions(subscriptionId);

        // Return created struct
        return LibStruct.Subscription(
            activeAt, owner, maxGasPrice, redundancy, maxGasLimit, frequency, period, containerId, inputs
        );
    }

    /// @notice Coerce MockBaseConsumer.outputs to LibStruct.DeliveredOutput
    /// @param consumer consumer
    /// @param subId subscription ID
    /// @param interval subscription interval
    /// @param redundancy # node response
    function getDeliveredOutput(MockBaseConsumer consumer, uint32 subId, uint32 interval, uint16 redundancy)
        external
        view
        returns (LibStruct.DeliveredOutput memory)
    {
        // Collect delivered output from storage
        (
            uint32 id,
            uint32 subInterval,
            uint16 subRedundancy,
            address node,
            bytes memory input,
            bytes memory output,
            bytes memory proof
        ) = consumer.outputs(subId, interval, redundancy);

        // Return created struct
        return LibStruct.DeliveredOutput(id, subInterval, subRedundancy, node, input, output, proof);
    }
}
