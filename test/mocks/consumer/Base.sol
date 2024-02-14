// SPDX-License-Identifier: BSD-3-Clause-Clear
pragma solidity ^0.8.4;

/// @title MockBaseConsumer
/// @notice Mocks BaseConsumer contract
abstract contract MockBaseConsumer {
    /*//////////////////////////////////////////////////////////////
                                STRUCTS
    //////////////////////////////////////////////////////////////*/

    /// @notice Output delivered from node
    /// @param subscriptionId subscription ID
    /// @param interval subscription interval
    /// @param redundancy after this call succeeds, how many nodes will have delivered a response for this interval
    /// @param node responding node address
    /// @param input optional off-chain container input recorded by Infernet node (empty, hashed input, processed input, or both), empty for lazy subscriptions
    /// @param output optional off-chain container output (empty, hashed output, processed output, both, or fallback: all encodeable data), empty for lazy subscriptions
    /// @param proof optional off-chain container execution proof (or arbitrary metadata), empty for lazy subscriptions
    /// @param containerId if lazy subscription, subscription compute container ID, else empty
    /// @param index if lazy subscription, `Inbox` lazy store index, else empty
    struct DeliveredOutput {
        uint32 subscriptionId;
        uint32 interval;
        uint16 redundancy;
        address node;
        bytes input;
        bytes output;
        bytes proof;
        bytes32 containerId;
        uint256 index;
    }

    /*//////////////////////////////////////////////////////////////
                                MUTABLE
    //////////////////////////////////////////////////////////////*/

    /// @notice Subscription ID => Interval => Redundancy => DeliveredOutput
    mapping(uint32 => mapping(uint32 => mapping(uint16 => DeliveredOutput))) public outputs;
}
