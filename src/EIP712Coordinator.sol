// SPDX-License-Identifier: BSD-3-Clause-Clear
pragma solidity ^0.8.4;

import {Registry} from "./Registry.sol";
import {ECDSA} from "solady/utils/ECDSA.sol";
import {EIP712} from "solady/utils/EIP712.sol";
import {Delegator} from "./pattern/Delegator.sol";
import {Coordinator, Subscription} from "./Coordinator.sol";

/// @title EIP712Coordinator
/// @notice Coordinator enhanced with ability to created subscriptions via off-chain EIP-712 signature
/// @dev Allows creating a subscription on behalf of a contract via delegatee EOA signature
/// @dev Allows nodes to atomically create subscriptions and deliver compute responses
contract EIP712Coordinator is EIP712, Coordinator {
    /*//////////////////////////////////////////////////////////////
                               CONSTANTS
    //////////////////////////////////////////////////////////////*/

    /// @notice EIP-712 signing domain major version
    string public constant EIP712_VERSION = "1";

    /// @notice EIP-712 signing domain name
    string public constant EIP712_NAME = "InfernetCoordinator";

    /// @notice EIP-712 struct(Subscription) typeHash
    bytes32 private constant EIP712_SUBSCRIPTION_TYPEHASH = keccak256(
        "Subscription(address owner,uint32 activeAt,uint32 period,uint32 frequency,uint16 redundancy,bytes32 containerId,bool lazy,address prover,uint256 paymentAmount,address paymentToken,address wallet)"
    );

    /// @notice EIP-712 struct(DelegateSubscription) typeHash
    /// @dev struct(DelegateSubscription) == { uint32 nonce, uint32 expiry, Subscription sub }
    /// @dev The `nonce` represents the nonce of the subscribing contract (sub-owner); prevents signature replay
    /// @dev The `expiry` is when the delegated subscription signature expires and can no longer be used
    bytes32 private constant EIP712_DELEGATE_SUBSCRIPTION_TYPEHASH = keccak256(
        "DelegateSubscription(uint32 nonce,uint32 expiry,Subscription sub)Subscription(address owner,uint32 activeAt,uint32 period,uint32 frequency,uint16 redundancy,bytes32 containerId,bool lazy,address prover,uint256 paymentAmount,address paymentToken,address wallet)"
    );

    /*//////////////////////////////////////////////////////////////
                                MUTABLE
    //////////////////////////////////////////////////////////////*/

    /// @notice Subscribing contract => maximum seen nonce
    /// @dev The nonce is a uint32 size(4.2B) which would take > 100 years of incrementing nonce per second to overflow
    mapping(address => uint32) public maxSubscriberNonce;

    /// @notice hash(subscribing contract, nonce) => subscriptionId
    /// @notice Allows lookup between a delegated subscription creation (unique(subscriber, nonce)) and subscriptionId
    mapping(bytes32 => uint32) public delegateCreatedIds;

    /*//////////////////////////////////////////////////////////////
                                 ERRORS
    //////////////////////////////////////////////////////////////*/

    /// @notice Thrown by `createSubscriptionDelegatee()` if subscription signature does not match contract delegatee
    /// @dev 4-byte signature: `0x10c74b03`
    error SignerMismatch();

    /// @notice Thrown by `createSubscriptionDelegatee()` if signature for delegated subscription has expired
    /// @dev 4-byte signature: `0x0819bdcd`
    error SignatureExpired();

    /*//////////////////////////////////////////////////////////////
                              CONSTRUCTOR
    //////////////////////////////////////////////////////////////*/

    /// @notice Initializes new EIP712Coordinator
    /// @param registry registry contract
    constructor(Registry registry) Coordinator(registry) {}

    /*//////////////////////////////////////////////////////////////
                           OVERRIDE FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /// @notice Overrides Solady.EIP712._domainNameAndVersion to return EIP712-compatible domain name, version
    function _domainNameAndVersion() internal pure override returns (string memory, string memory) {
        return (EIP712_NAME, EIP712_VERSION);
    }

    /// @notice Overrides Solady.EIP712._domainNameAndVersionMayChange to always return false since the domain params are not updateable
    function _domainNameAndVersionMayChange() internal pure override returns (bool) {
        return false;
    }

    /*//////////////////////////////////////////////////////////////
                               FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /// @notice Allows a delegatee to create a subscription on behalf of a subscribing contract (sub.owner)
    /// @dev Unlike `Coordinator.createSubscription()`, offers maximum flexibility to set subscription parameters
    /// @param nonce subscribing contract nonce (included in signature)
    /// @param expiry delegated subscription signature expiry (included in signature)
    /// @param sub subscription to create
    /// @param v ECDSA recovery id
    /// @param r ECDSA signature output (r)
    /// @param s ECDSA signature output (s)
    /// @return subscription ID (existing or newly-created)
    function createSubscriptionDelegatee(
        uint32 nonce,
        uint32 expiry,
        Subscription calldata sub,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) public returns (uint32) {
        // Check if subscription already exists via delegate-created lookup table
        bytes32 key = keccak256(abi.encode(sub.owner, nonce));
        uint32 subscriptionId = delegateCreatedIds[key];

        // If subscription exists, return existing subscriptionId
        // This implicitly prevents nonce replay because if the nonce was already used, a subscription would exist
        if (subscriptionId != 0) {
            return subscriptionId;
        }

        // Else, if subscription does not exist
        // First, verify that signature has not expired
        if (uint32(block.timestamp) >= expiry) {
            revert SignatureExpired();
        }

        // Generate EIP-712 data
        bytes32 digest = _hashTypedData(
            keccak256(
                // Encode(DelegateSubscription, nonce, expiry, sub)
                abi.encode(
                    EIP712_DELEGATE_SUBSCRIPTION_TYPEHASH,
                    nonce,
                    expiry,
                    // Encode(Subscription, sub)
                    keccak256(
                        abi.encode(
                            EIP712_SUBSCRIPTION_TYPEHASH,
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
                    )
                )
            )
        );

        // Get recovered signer from data
        // Throws `InvalidSignature()` (4-byte signature: `0x8baa579f`) if can't recover signer
        address recoveredSigner = ECDSA.recover(digest, v, r, s);

        // Collect delegated signer from subscribing contract
        address delegatedSigner = Delegator(sub.owner).getSigner();

        // Verify signatures (recoveredSigner should equal delegatedSigner)
        if (recoveredSigner != delegatedSigner) {
            revert SignerMismatch();
        }

        // By this point, the signer is verified and a net-new subscription can be created
        // Assign new subscription id
        // Unlikely this will ever overflow so we can toss in unchecked
        unchecked {
            subscriptionId = id++;
        }

        // Store provided subscription as-is
        subscriptions[subscriptionId] = sub;

        // Update delegate-created ID lookup table
        delegateCreatedIds[key] = subscriptionId;

        // Emit new subscription
        emit SubscriptionCreated(subscriptionId);

        // Update max known subscriber nonce (useful for off-chain signing utilities to prevent nonce-collision)
        if (nonce > maxSubscriberNonce[sub.owner]) {
            maxSubscriberNonce[sub.owner] = nonce;
        }

        // Explicitly return subscriptionId
        return subscriptionId;
    }

    /// @notice Allows nodes to (1) atomically create or collect subscription via signed EIP-712 message,
    ///         (2) deliver container compute responses for created or collected subscription
    /// @param nonce subscribing contract nonce (included in signature)
    /// @param expiry delegated subscription signature expiry (included in signature)
    /// @param sub subscription to create
    /// @param v ECDSA recovery id
    /// @param r ECDSA signature output (r)
    /// @param s ECDSA signature output (s)
    /// @param deliveryInterval subscription `interval`
    /// @param input optional off-chain input recorded by Infernet node (empty, hashed input, processed input, or both)
    /// @param output optional off-chain container output (empty, hashed output, processed output, both, or fallback: all encodeable data)
    /// @param proof optional container execution proof (or arbitrary metadata)
    /// @param nodeWallet node wallet (used to receive payments, and put up escrow/slashing funds); msg.sender must be authorized spender of wallet
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
        bytes calldata proof,
        address nodeWallet
    ) external {
        // Create subscriptionId via delegatee creation + or collect if subscription already exists
        uint32 subscriptionId = createSubscriptionDelegatee(nonce, expiry, sub, v, r, s);

        // Deliver subscription response
        deliverCompute(subscriptionId, deliveryInterval, input, output, proof, nodeWallet);
    }
}
