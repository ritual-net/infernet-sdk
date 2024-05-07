// SPDX-License-Identifier: BSD-3-Clause-Clear
pragma solidity ^0.8.4;

import {Subscription} from "../../src/Coordinator.sol";

/// @title LibSign
/// @notice Useful helpers to create and verify EIP-712 signatures
/// @dev Purposefully does not inherit and use Solady helpers to force manual cross-verification
library LibSign {
    /*//////////////////////////////////////////////////////////////
                               CONSTANTS
    //////////////////////////////////////////////////////////////*/

    /// @notice EIP-712 Subscription typeHash
    bytes32 private constant SUBSCRIPTION_TYPEHASH = keccak256(
        "Subscription(address owner,uint32 activeAt,uint32 period,uint32 frequency,uint16 redundancy,bytes32 containerId,bool lazy,address prover,uint256 paymentAmount,address paymentToken,address wallet)"
    );

    /// @notice EIP-712 DelegateSubscription typeHash
    bytes32 private constant DELEGATE_SUBSCRIPTION_TYPEHASH = keccak256(
        "DelegateSubscription(uint32 nonce,uint32 expiry,Subscription sub)Subscription(address owner,uint32 activeAt,uint32 period,uint32 frequency,uint16 redundancy,bytes32 containerId,bool lazy,address prover,uint256 paymentAmount,address paymentToken,address wallet)"
    );

    /*//////////////////////////////////////////////////////////////
                           UTILITY FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /// @notice Generates EIP-712 domain seperator given name, version, and verifyingContract
    /// @param name signing domain name
    /// @param version major version of signing domain
    /// @param verifyingContract address of contract verifying signature
    /// @return domain seperator
    function getDomainSeperator(string memory name, string memory version, address verifyingContract)
        public
        view
        returns (bytes32)
    {
        return keccak256(
            abi.encode(
                // EIP712Domain
                keccak256("EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)"),
                keccak256(bytes(name)),
                keccak256(bytes(version)),
                block.chainid,
                verifyingContract
            )
        );
    }

    /// @notice Generates structHash of a Subscription
    /// @param sub subscription
    /// @return structHash(subscription)
    function getStructHash(Subscription memory sub) public pure returns (bytes32) {
        return keccak256(
            abi.encode(
                SUBSCRIPTION_TYPEHASH,
                sub.owner,
                sub.activeAt,
                sub.period,
                sub.frequency,
                sub.redundancy,
                sub.containerId,
                sub.lazy,
                sub.prover,
                sub.paymentAmount,
                sub.paymentToken,
                sub.wallet
            )
        );
    }

    /// @notice Generates structHash of a DelegateSubscription
    /// @param nonce subscriber contract nonce
    /// @param expiry signature expiry
    /// @param sub subscription
    /// @return structHash(struct(nonce, sub))
    function getStructHash(uint32 nonce, uint32 expiry, Subscription memory sub) public pure returns (bytes32) {
        return keccak256(abi.encode(DELEGATE_SUBSCRIPTION_TYPEHASH, nonce, expiry, getStructHash(sub)));
    }

    /// @notice Generates the hash of the fully encoded EIP-712 message, based on provided domain config
    /// @param name signing domain name
    /// @param version major version of signing domain
    /// @param verifyingContract address of contract verifying signature
    /// @param nonce subscriber contract nonce
    /// @param expiry signature expiry
    /// @param sub subscription
    /// @return typed EIP-712 message hash
    function getTypedMessageHash(
        string memory name,
        string memory version,
        address verifyingContract,
        uint32 nonce,
        uint32 expiry,
        Subscription memory sub
    ) external view returns (bytes32) {
        return keccak256(
            abi.encodePacked(
                "\x19\x01", getDomainSeperator(name, version, verifyingContract), getStructHash(nonce, expiry, sub)
            )
        );
    }
}
