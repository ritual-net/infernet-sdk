// SPDX-License-Identifier: BSD-3-Clause-Clear
pragma solidity ^0.8.4;

import {BaseVerifier} from "./Base.sol";
import {Registry} from "../../../src/Registry.sol";

/// @title MockAtomicVerifier
/// @notice Implements a mock atomic verifier contract that immediately returns `status` as proof validity
contract MockAtomicVerifier is BaseVerifier {
    /*//////////////////////////////////////////////////////////////
                                MUTABLE
    //////////////////////////////////////////////////////////////*/

    /// @notice Next proof valid status to return
    /// @dev Modified by `updateNextStatus()`; returned as proof validity in `requestProofVerification()`
    bool private status = false;

    /*//////////////////////////////////////////////////////////////
                              CONSTRUCTOR
    //////////////////////////////////////////////////////////////*/

    /// @notice Create new AtomicVerifier
    /// @param registry registry address
    constructor(Registry registry) BaseVerifier(registry) {}

    /*//////////////////////////////////////////////////////////////
                           INHERITED FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /// @notice Implements `IVerifier.requestProofVerification()`
    function requestProofVerification(uint32 subscriptionId, uint32 interval, address node, bytes calldata proof)
        external
    {
        // Mock atomic proof verification w/ pre-defined status
        COORDINATOR.finalizeProofVerification(subscriptionId, interval, node, status);
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
