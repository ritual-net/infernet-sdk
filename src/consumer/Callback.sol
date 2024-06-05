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
    /// @dev Could be restricted to `private` visibility but kept `internal` for better testing/downstream modification support
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
    /// @param redundancy number of unique responding Infernet nodes
    /// @param paymentToken If providing payment for compute, payment token address (address(0) for ETH, else ERC20 contract address)
    /// @param paymentAmount If providing payment for compute, payment in `paymentToken` per compute request fulfillment
    /// @param wallet If providing payment for compute, Infernet `Wallet` address; this contract must be approved spender of `Wallet`
    /// @param verifier optional verifier contract to restrict payment based on response proof verification
    /// @return subscription ID of newly-created one-time subscription
    function _requestCompute(
        string memory containerId,
        bytes memory inputs,
        uint16 redundancy,
        address paymentToken,
        uint256 paymentAmount,
        address wallet,
        address verifier
    ) internal returns (uint32) {
        // Create one-time subscription at coordinator
        uint32 subscriptionId = COORDINATOR.createSubscription(
            containerId,
            1, // frequency == 1, one-time subscription
            0, // period == 0, available to be responded to immediately
            redundancy,
            false, // lazy == false, always eagerly await subscription response
            // Optional payment for compute
            paymentToken,
            paymentAmount,
            wallet,
            // Optional proof verification
            verifier
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
