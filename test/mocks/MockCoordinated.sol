// SPDX-License-Identifier: BSD-3-Clause-Clear
pragma solidity ^0.8.4;

import {Registry} from "../../src/Registry.sol";
import {Coordinated} from "../../src/utility/Coordinated.sol";

/// @title MockCoordinated
/// @notice Mocks the functionality of a contract implementing Coordinated (coordinator-permissioned functions)
contract MockCoordinated is Coordinated {
    /*//////////////////////////////////////////////////////////////
                              CONSTRUCTOR
    //////////////////////////////////////////////////////////////*/

    /// @notice Initializes new MockCoordinated
    /// @param registry registry contract
    constructor(Registry registry) Coordinated(registry) {}

    /*//////////////////////////////////////////////////////////////
                           UTILITY FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /// @notice Mock coordinator-permissioned function via `onlyCoordinator` modifier
    /// @dev Throws `NotCoordinator()` if called by non-coordinator address
    function mockCoordinatorPermissionedFn() external view onlyCoordinator {
        return;
    }
}
