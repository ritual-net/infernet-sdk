// SPDX-License-Identifier: BSD-3-Clause-Clear
pragma solidity ^0.8.4;

/// @title Delegator
/// @notice Exposes a `signer` address that allows an authorized EOA to sign off on actions on behalf of a contract
/// @dev Allows developers to create Coordinator subscriptions off-chain, on behalf of a contract, by signing a
///      `DelegateSubscription` from `signer` and submitting to `EIP712Coordinator.createSubscriptionDelegatee()`
abstract contract Delegator {
    /*//////////////////////////////////////////////////////////////
                                MUTABLE
    //////////////////////////////////////////////////////////////*/

    /// @notice Authorized address with signing privileges
    /// @dev Recommended to use an EOA so that it can sign EIP-712 messages
    /// @dev Visibility is `public` to automatically generate and expose a getter
    address public signer;

    /*//////////////////////////////////////////////////////////////
                              CONSTRUCTOR
    //////////////////////////////////////////////////////////////*/

    /// @notice Initialize new Delegator
    /// @param signer_ authorized address
    constructor(address signer_) {
        signer = signer_;
    }

    /*//////////////////////////////////////////////////////////////
                           INTERNAL FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /// @notice Update delegated signer
    /// @dev No event is emitted given contract is meant to be inherited
    /// @param newSigner new delegated signer address
    function _updateSigner(address newSigner) internal {
        signer = newSigner;
    }
}
