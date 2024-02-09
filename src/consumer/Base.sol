// SPDX-License-Identifier: BSD-3-Clause-Clear
pragma solidity ^0.8.4;

import {Registry} from "../Registry.sol";
import {Coordinator} from "../Coordinator.sol";

/// @title BaseConsumer
/// @notice Handles receiving container compute responses from Infernet coordinator
/// @notice Handles exposing container inputs to Infernet nodes via `getContainerInputs()`
/// @dev Contains a single public entrypoint `rawReceiveCompute` callable by only the Infernet coordinator. Once
///      call origin is verified, parameters are proxied to internal function `_receiveCompute`
abstract contract BaseConsumer {
    /*//////////////////////////////////////////////////////////////
                               IMMUTABLE
    //////////////////////////////////////////////////////////////*/

    /// @notice Infernet Coordinator
    /// @dev Internal visibility since COORDINATOR is consumed by inheriting contracts
    Coordinator internal immutable COORDINATOR;

    /*//////////////////////////////////////////////////////////////
                                 ERRORS
    //////////////////////////////////////////////////////////////*/

    /// @notice Thrown if attempting to call `rawReceiveCompute` from a `msg.sender != address(COORDINATOR)`
    /// @dev 4-byte signature: `0x9ec853e6`
    error NotCoordinator();

    /*//////////////////////////////////////////////////////////////
                              CONSTRUCTOR
    //////////////////////////////////////////////////////////////*/

    /// @notice Initialize new BaseConsumer
    /// @param registry registry address
    constructor(address registry) {
        // Setup Coordinator (via address from canonical registry)
        COORDINATOR = Coordinator(Registry(registry).COORDINATOR());
    }

    /*//////////////////////////////////////////////////////////////
                           VIRTUAL FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /// @notice Callback entrypoint to receive container compute responses from validated Coordinator source
    /// @dev Called by `rawReceiveCompute` once validated that `msg.sender == address(COORDINATOR)`
    /// @dev Same function parameters as `rawReceiveCompute`
    /// @param subscriptionId id of subscription being responded to
    /// @param interval subscription interval
    /// @param redundancy after this call succeeds, how many nodes will have delivered a response for this interval
    /// @param node address of responding Infernet node
    /// @param input optional off-chain container input recorded by Infernet node (empty, hashed input, processed input, or both)
    /// @param output optional off-chain container output (empty, hashed output, processed output, both, or fallback: all encodeable data)
    /// @param proof optional off-chain container execution proof (or arbitrary metadata)
    function _receiveCompute(
        uint32 subscriptionId,
        uint32 interval,
        uint16 redundancy,
        address node,
        bytes calldata input,
        bytes calldata output,
        bytes calldata proof
    ) internal virtual {}

    /// @notice View function to broadcast dynamic container inputs to off-chain Infernet nodes
    /// @dev Develpers can modify this function to return dynamic inputs
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
                               FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /// @notice Callback entrypoint called by Infernet Coordinator to return container compute responses
    /// @dev Callable only by `address(COORDINATOR)`, else throws `NotCoordinator()` error
    /// @param subscriptionId id of subscription being responded to
    /// @param interval subscription interval
    /// @param redundancy after this call succeeds, how many nodes will have delivered a response for this interval
    /// @param node address of responding Infernet node
    /// @param input optional off-chain container input recorded by Infernet node (empty, hashed input, processed input, or both)
    /// @param output optional off-chain container output (empty, hashed output, processed output, both, or fallback: all encodeable data)
    /// @param proof optional off-chain container execution proof (or arbitrary metadata)
    function rawReceiveCompute(
        uint32 subscriptionId,
        uint32 interval,
        uint16 redundancy,
        address node,
        bytes calldata input,
        bytes calldata output,
        bytes calldata proof
    ) external {
        // Ensure caller is coordinator
        if (msg.sender != address(COORDINATOR)) {
            revert NotCoordinator();
        }

        // Call internal receive function, since caller is validated
        _receiveCompute(subscriptionId, interval, redundancy, node, input, output, proof);
    }
}
