// SPDX-License-Identifier: BSD-3-Clause-Clear
pragma solidity ^0.8.4;

import {MockSubscriptionConsumer} from "./Subscription.sol";
import {Delegator} from "../../../src/pattern/Delegator.sol";

/// @title MockDelegatorSubscriptionConsumer
/// @notice Mocks SubscriptionConsumer w/ delegator set to an address
/// @dev Does not contain `updateSigner` function mock because already tested via `MockDelegatorCallbackConsumer`
contract MockDelegatorSubscriptionConsumer is Delegator, MockSubscriptionConsumer {
    /*//////////////////////////////////////////////////////////////
                              CONSTRUCTOR
    //////////////////////////////////////////////////////////////*/

    /// Create new MockDelegatorSubscriptionConsumer
    /// @param registry registry address
    /// @param signer delegated signer address
    constructor(address registry, address signer) MockSubscriptionConsumer(registry) Delegator(signer) {}
}
