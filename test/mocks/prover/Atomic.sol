// SPDX-License-Identifier: BSD-3-Clause-Clear
pragma solidity ^0.8.4;

import {BaseProver} from "./Base.sol";
import {Registry} from "../../../src/Registry.sol";

/// @title AtomicProver
/// @notice Implements a mock atomic prover contract that immediately returns `status` as proof validity
contract AtomicProver is BaseProver {
    /*//////////////////////////////////////////////////////////////
                                MUTABLE
    //////////////////////////////////////////////////////////////*/

    /// @notice Next proof valid status to return
    /// @dev Modified by `updateNextStatus()`; returned as proof validity in `requestProofValidation()`
    bool private status = false;

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
        // Mock atomic proof validation w/ pre-defined status
        COORDINATOR.finalizeProofValidation(subscriptionId, interval, node, status);
    }

    /*//////////////////////////////////////////////////////////////
                           UTILITY FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /// @notice Sets next proof validity status to false
    function setNextValidityFalse() external {
        status = false;
    }

    /// @notice Sets next proof validity status to true
    function setNextValidityTrue() external {
        status = true;
    }
}
