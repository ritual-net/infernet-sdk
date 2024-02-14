// SPDX-License-Identifier: BSD-3-Clause-Clear
pragma solidity ^0.8.4;

import {BaseConsumer} from "./Base.sol";

/// @title CallbackConsumer
/// @notice Allows creating one-time requests for off-chain container compute, delivered via callback
/// @dev Inherits `BaseConsumer` to inherit functions to receive container compute responses and emit container inputs
abstract contract CallbackConsumer is BaseConsumer {
    /*//////////////////////////////////////////////////////////////
                                MUTABLE
    //////////////////////////////////////////////////////////////*/

    /// @notice subscriptionId => callback input data
    /// @dev Could be restricted to `private` visibility but kept `internal` for better testing support
    mapping(uint32 => bytes) internal subscriptionInputs;

    /*//////////////////////////////////////////////////////////////
                              CONSTRUCTOR
    //////////////////////////////////////////////////////////////*/

    /// @notice Initialize new CallbackConsumer
    /// @param registry registry address
    constructor(address registry) BaseConsumer(registry) {}

    /*//////////////////////////////////////////////////////////////
                           INTERNAL FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /// @notice Creates a one-time request for off-chain container compute via callback
    /// @dev Under the hood, creates a new subscription at the Infernet coordinator, with `period == 0` and
    ///      `frequency == 1`, effectively initializing a subscription valid immediately and only for 1 interval
    /// @param containerId compute container identifier(s) used by off-chain Infernet node
    /// @param inputs optional container inputs
    /// @param maxGasPrice max gas price in wei paid by Infernet node when fulfilling callback
    /// @param maxGasLimit max gas limit in wei used by Infernet node in callback tx
    /// @param redundancy number of unique responding Infernet nodes
    /// @return subscription ID of newly-created one-time subscription
    function _requestCompute(
        string memory containerId,
        bytes memory inputs,
        uint48 maxGasPrice,
        uint32 maxGasLimit,
        uint16 redundancy
    ) internal returns (uint32) {
        // Create one-time subscription at coordinator
        uint32 subscriptionId = COORDINATOR.createSubscription(
            containerId,
            maxGasPrice,
            maxGasLimit,
            1, // frequency == 1, one-time subscription
            0, // period == 0, available to be responded to immediately
            redundancy,
            false // lazy == false, always eagerly await subscription response
        );

        // Store inputs by subscriptionId (to be retrieved by off-chain Infernet nodes)
        subscriptionInputs[subscriptionId] = inputs;

        // Return subscriptionId
        return subscriptionId;
    }

    /*//////////////////////////////////////////////////////////////
                           OVERRIDE FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /// @notice View function to broadcast dynamic container inputs to off-chain Infernet nodes
    /// @dev Modified from `BaseConsumer` to expose callback input data, indexed by subscriptionId
    /// @param subscriptionId subscription ID to collect container inputs for
    /// @param interval subscription interval to collect container inputs for
    /// @param timestamp timestamp at which container inputs are collected
    /// @param caller calling address
    function getContainerInputs(uint32 subscriptionId, uint32 interval, uint32 timestamp, address caller)
        external
        view
        override
        returns (bytes memory)
    {
        // {interval, timestamp, caller} unnecessary for simple callback request
        return subscriptionInputs[subscriptionId];
    }
}
