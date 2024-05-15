// SPDX-License-Identifier: BSD-3-Clause-Clear
pragma solidity ^0.8.4;

/// @title Delegator
/// @notice Exposes a `signer` address (via `getSigner()`) that allows an authorized EOA to sign off on actions on behalf of a contract
/// @dev Allows developers to create Coordinator subscriptions off-chain, on behalf of a contract, by signing a
///      `DelegateSubscription` from `signer` and submitting to `EIP712Coordinator.createSubscriptionDelegatee()`
/// @dev In theory, this could use EIP-1271 standard signature validation but that enables a contract owner to override
///      what is a valid signature, which is more of a shotgun than just imposing a signer be specified
abstract contract Delegator {
    /*//////////////////////////////////////////////////////////////
                                MUTABLE
    //////////////////////////////////////////////////////////////*/

    /// @notice Authorized address with signing privileges
    /// @dev Recommended to use an EOA so that it can sign EIP-712 messages
    /// @dev Visibility is `private` to prevent downstream direct modification outside of via `_updateSigner()`
    address private signer;

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

    /*//////////////////////////////////////////////////////////////
                               FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /// @notice Get delegated signer
    /// @return authorized signer address
    function getSigner() external view returns (address) {
        return signer;
    }
}
