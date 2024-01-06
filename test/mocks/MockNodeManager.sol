// SPDX-License-Identifier: BSD-3-Clause-Clear
pragma solidity ^0.8.4;

import {NodeManager} from "../../src/NodeManager.sol";

/// @title MockNodeManager
/// @notice Mocks the NodeManager contract
/// @dev Useful to test manager functions
contract MockNodeManager is NodeManager {
    /*//////////////////////////////////////////////////////////////
                           UTILITY FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /// @notice Returns true if caller has status `NodeStatus.Active` or reverts
    /// @dev Essentially testing that exposed `onlyActiveNode` modifier works
    function isActiveNode() external view returns (bool) {
        if (nodeInfo[msg.sender].status != NodeStatus.Active) {
            revert NodeNotActive();
        }
        return true;
    }
}
