// SPDX-License-Identifier: BSD-3-Clause-Clear
pragma solidity ^0.8.4;

import {Inbox} from "../../src/Inbox.sol";
import {Registry} from "../../src/Registry.sol";
import {Subscription} from "../../src/Coordinator.sol";
import {StdAssertions} from "forge-std/StdAssertions.sol";
import {EIP712Coordinator} from "../../src/EIP712Coordinator.sol";

/// @title MockNode
/// @notice Mocks the functionality of an off-chain Infernet node
/// @dev Inherited functions contain state checks but not event or error checks and do not interrupt parent reverts (with reverting pre-checks)
contract MockNode is StdAssertions {
    /*//////////////////////////////////////////////////////////////
                               IMMUTABLE
    //////////////////////////////////////////////////////////////*/

    /// @notice Coordinator
    EIP712Coordinator private immutable COORDINATOR;

    /// @notice Inbox
    Inbox private immutable INBOX;

    /*//////////////////////////////////////////////////////////////
                              CONSTRUCTOR
    //////////////////////////////////////////////////////////////*/

    /// Creates new MockNode
    /// @param registry registry contract
    constructor(Registry registry) {
        // Collect Coordinator, Inbox from registry
        COORDINATOR = EIP712Coordinator(registry.COORDINATOR());
        INBOX = Inbox(registry.INBOX());
    }

    /*//////////////////////////////////////////////////////////////
                           INHERITED FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /// @dev Wrapper function (calling Coordinator with msg.sender == node)
    function deliverCompute(
        uint32 subscriptionId,
        uint32 deliveryInterval,
        bytes calldata input,
        bytes calldata output,
        bytes calldata proof
    ) external {
        COORDINATOR.deliverCompute(subscriptionId, deliveryInterval, input, output, proof, payable(address(0)));
    }

    /// @dev Wrapper function (calling Coordinator with msg.sender == node)
    function deliverComputeDelegatee(
        uint32 nonce,
        uint32 expiry,
        Subscription calldata sub,
        uint8 v,
        bytes32 r,
        bytes32 s,
        uint32 deliveryInterval,
        bytes calldata input,
        bytes calldata output,
        bytes calldata proof
    ) external {
        COORDINATOR.deliverComputeDelegatee(
            nonce, expiry, sub, v, r, s, deliveryInterval, input, output, proof, payable(address(0))
        );
    }

    /// @dev Wrapper function (calling Inbox with msg.sender == node)
    function write(bytes32 containerId, bytes calldata input, bytes calldata output, bytes calldata proof)
        external
        returns (uint256)
    {
        return INBOX.write(containerId, input, output, proof);
    }
}
