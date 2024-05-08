// SPDX-License-Identifier: BSD-3-Clause-Clear
pragma solidity ^0.8.4;

import {BaseProver} from "./Base.sol";
import {Registry} from "../../../src/Registry.sol";

/// @title OptimisticProver
/// @notice Implements a mock optimistic prover contract that returns some status after period of non-atomic delay (via `mockDeliverProof()`)
contract OptimisticProver is BaseProver {
    /*//////////////////////////////////////////////////////////////
                              CONSTRUCTOR
    //////////////////////////////////////////////////////////////*/

    /// @notice Create new AtomicProver
    /// @param registry registry address
    constructor(Registry registry) BaseProver(registry) {}

    /*//////////////////////////////////////////////////////////////
                           INHERITED FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /// @notice Implements `IProver.requestProofValidation()`
    function requestProofValidation(uint32 subscriptionId, uint32 interval, address node, bytes calldata proof)
        external
    {
        // Do nothing
        return;
    }

    /*//////////////////////////////////////////////////////////////
                           UTILITY FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /// @notice Mocks `COORDINATOR.finalizeProofValidation()`, allowing non-atomic submissions of proof validity
    function mockDeliverProof(uint32 subscriptionId, uint32 interval, address node, bool valid) external {
        COORDINATOR.finalizeProofValidation(subscriptionId, interval, node, valid);
    }
}
