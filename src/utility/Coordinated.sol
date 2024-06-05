// SPDX-License-Identifier: BSD-3-Clause-Clear
pragma solidity ^0.8.4;

import {Registry} from "../Registry.sol";

/// @title Coordinated
/// @notice Exposes utility modifier `onlyCoordinator` for coordinator-permissioned functions
/// @dev Best used when implementing contract needs just a msg.sender check (and not call access to coordinator itself)
abstract contract Coordinated {
    /*//////////////////////////////////////////////////////////////
                               IMMUTABLE
    //////////////////////////////////////////////////////////////*/

    /// @notice Coordinator contract address
    /// @dev Private to prevent conflicting with similar public variables in namespace
    /// @dev Immutable to prevent address changes given registry deployment is immutable
    address private immutable COORDINATOR;

    /*//////////////////////////////////////////////////////////////
                                 ERRORS
    //////////////////////////////////////////////////////////////*/

    /// @notice Thrown if coordinator-permissioned function is called from non-coordinator address
    /// @dev 4-byte signature: `0x9ec853e6`
    error NotCoordinator();

    /*//////////////////////////////////////////////////////////////
                               MODIFIERS
    //////////////////////////////////////////////////////////////*/

    /// @notice Allows calls from only the coordinator
    modifier onlyCoordinator() {
        if (msg.sender != COORDINATOR) {
            revert NotCoordinator();
        }
        _;
    }

    /*//////////////////////////////////////////////////////////////
                              CONSTRUCTOR
    //////////////////////////////////////////////////////////////*/

    /// @notice Initializes new Coordinated
    /// @param registry registry contract
    constructor(Registry registry) {
        // Collect coordinator address from registry
        COORDINATOR = registry.COORDINATOR();
    }
}
