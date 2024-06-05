// SPDX-License-Identifier: BSD-3-Clause-Clear
pragma solidity ^0.8.4;

import {BaseVerifier} from "./Base.sol";
import {Registry} from "../../../src/Registry.sol";

/// @title MockOptimisticVerifier
/// @notice Implements a mock optimistic verifier contract that returns some status after period of non-atomic delay (via `mockDeliverProof()`)
contract MockOptimisticVerifier is BaseVerifier {
    /*//////////////////////////////////////////////////////////////
                              CONSTRUCTOR
    //////////////////////////////////////////////////////////////*/

    /// @notice Create new OptimisticVerifier
    /// @param registry registry address
    constructor(Registry registry) BaseVerifier(registry) {}

    /*//////////////////////////////////////////////////////////////
                           INHERITED FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /// @notice Implements `IVerifier.requestProofVerification()`
    function requestProofVerification(uint32 subscriptionId, uint32 interval, address node, bytes calldata proof)
        external
    {
        // Do nothing
        return;
    }

    /*//////////////////////////////////////////////////////////////
                           UTILITY FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /// @notice Mocks `COORDINATOR.finalizeProofVerification()`, allowing non-atomic submissions of proof validity
    function mockDeliverProof(uint32 subscriptionId, uint32 interval, address node, bool valid) external {
        COORDINATOR.finalizeProofVerification(subscriptionId, interval, node, valid);
    }
}
