// SPDX-License-Identifier: BSD-3-Clause-Clear
pragma solidity ^0.8.4;

import {Manager} from "../../src/Manager.sol";

/// @title MockManager
/// @notice Mocks Manager contract
/// @dev Useful to test manager functions independent to coordinator
contract MockManager is Manager {
    /*//////////////////////////////////////////////////////////////
                           UTILITY FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /// @notice Returns true if caller has status `NodeStatus.Active` or reverts
    /// @dev Essentially testing that exposed `onlyActiveNode` modifier works
    function isActiveNode() external view onlyActiveNode returns (bool) {
        return true;
    }
}
