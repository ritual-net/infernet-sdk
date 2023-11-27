// SPDX-License-Identifier: BSD-3-Clause-Clear
pragma solidity ^0.8.4;

import {BaseConsumer} from "./Base.sol";

/// @title CallbackConsumer
/// @notice Allows creating one-time requests for off-chain container compute, delivered via callback
/// @dev Inherits `BaseConsumer` to inherit functions to receive container compute responses
abstract contract CallbackConsumer is BaseConsumer {
    /*//////////////////////////////////////////////////////////////
                              CONSTRUCTOR
    //////////////////////////////////////////////////////////////*/

    /// @notice Initialize new CallbackConsumer
    /// @param coordinator coordinator address
    constructor(address coordinator) BaseConsumer(coordinator) {}

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
        return COORDINATOR.createSubscription(
            containerId,
            inputs,
            maxGasPrice,
            maxGasLimit,
            1, // frequency == 1, one-time subscription
            0, // period == 0, available to be responded to immediately
            redundancy
        );
    }
}
