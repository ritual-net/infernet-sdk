// SPDX-License-Identifier: BSD-3-Clause-Clear
pragma solidity ^0.8.4;

import {BaseConsumer} from "./Base.sol";

/// @title SubscriptionConsumer
/// @notice Allows creating recurring subscriptions for off-chain container compute
/// @dev Inherits `BaseConsumer` to inherit functions to receive container compute responses
abstract contract SubscriptionConsumer is BaseConsumer {
    /*//////////////////////////////////////////////////////////////
                              CONSTRUCTOR
    //////////////////////////////////////////////////////////////*/

    /// @notice Initialize new SubscriptionConsumer
    /// @param coordinator coordinator address
    constructor(address coordinator) BaseConsumer(coordinator) {}

    /*//////////////////////////////////////////////////////////////
                           VIRTUAL FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /// @notice View function to broadcast dynamic container inputs to off-chain Infernet nodes
    /// @dev If `Coordinator.subscription[id].inputs == bytes("")`, a off-chain node will call `getContainerInputs()`
    ///      to retrieve inputs. Develpers can modify this function to return dynamic inputs
    /// @param subscriptionId subscription ID to collect container inputs for
    /// @param interval subscription interval to collect container inputs for
    /// @param timestamp timestamp at which container inputs are collected
    /// @param caller calling address
    function getContainerInputs(uint32 subscriptionId, uint32 interval, uint32 timestamp, address caller)
        external
        view
        virtual
        returns (bytes memory)
    {}

    /*//////////////////////////////////////////////////////////////
                           INTERNAL FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /// @notice Creates a recurring request for off-chain container compute via callback response
    /// @param containerId compute container identifier(s) used by off-chain Infernet node
    /// @param maxGasPrice max gas price in wei paid by Infernet node when fulfilling callback
    /// @param maxGasLimit max gas limit in wei paid by Infernet node in callback tx
    /// @param frequency max number of times to process subscription (i.e, `frequency == 1` is a one-time request)
    /// @param period period, in seconds, at which to progress each responding `interval`
    /// @param redundancy number of unique responding Infernet nodes
    /// @return subscription ID of newly-created subscription
    function _createComputeSubscription(
        string memory containerId,
        uint48 maxGasPrice,
        uint32 maxGasLimit,
        uint32 frequency,
        uint32 period,
        uint16 redundancy
    ) internal returns (uint32) {
        return COORDINATOR.createSubscription(
            containerId,
            "", // Infernet nodes call `getContainerInputs()` to retrieve dynamic inputs
            maxGasPrice,
            maxGasLimit,
            frequency,
            period,
            redundancy
        );
    }

    /// @notice Cancels a created subscription
    /// @dev Can only cancel owned subscriptions (`address(this) == Coordinator.subscriptions[subscriptionId].owner`)
    /// @param subscriptionId ID of subscription to cancel
    function _cancelComputeSubscription(uint32 subscriptionId) internal {
        COORDINATOR.cancelSubscription(subscriptionId);
    }
}
