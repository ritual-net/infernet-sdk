// SPDX-License-Identifier: BSD-3-Clause-Clear
pragma solidity ^0.8.4;

/// @title Allowlist
/// @notice Exposes an `onlyAllowedNode` modifier that restricts unallowed nodes from calling permissioned contract functions
/// @dev To be used with `BaseConsumer._receiveCompute` to restrict responding nodes
/// @dev In the future, this list can be abstracted out to a contract that enables dynamic list declarations (registry)
abstract contract Allowlist {
    /*//////////////////////////////////////////////////////////////
                                MUTABLE
    //////////////////////////////////////////////////////////////*/

    /// @notice node address => is allowed
    /// @dev Only applies if `onlyAllowedNode` modifier is used
    /// @dev Forced `private` visibility to disallow modifications outside of via `_updateAllowlist`
    /// @dev Read getter exposed via `isAllowedNode()`
    mapping(address => bool) private allowedNodes;

    /*//////////////////////////////////////////////////////////////
                                 ERRORS
    //////////////////////////////////////////////////////////////*/

    /// @notice Thrown by `onlyAllowedNode()` if node address is not in `allowedNodes` set
    /// @dev 4-byte signature: `0x42764946`
    error NodeNotAllowed();

    /*//////////////////////////////////////////////////////////////
                               MODIFIERS
    //////////////////////////////////////////////////////////////*/

    /// @notice Allow only nodes in the `allowedNodes` set
    modifier onlyAllowedNode(address node) {
        if (!allowedNodes[node]) {
            revert NodeNotAllowed();
        }
        _;
    }

    /*//////////////////////////////////////////////////////////////
                              CONSTRUCTOR
    //////////////////////////////////////////////////////////////*/

    /// @notice Initializes new Allowlist
    /// @param initialAllowed array of initially-allowed node addresses
    constructor(address[] memory initialAllowed) {
        // For each address in list of initially allowed nodes
        for (uint256 i = 0; i < initialAllowed.length; i++) {
            // Set allowedNodes[address] to be true (allowed)
            allowedNodes[initialAllowed[i]] = true;
        }
    }

    /*//////////////////////////////////////////////////////////////
                           INTERNAL FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /// @notice Update `allowedNodes`
    /// @param nodes array of node addresses to update
    /// @param status array of status(es) to update where index corresponds to node address
    /// @dev Does not validate `nodes.length == status.length`
    function _updateAllowlist(address[] memory nodes, bool[] memory status) internal {
        // For each (address, status)-pair
        for (uint256 i = 0; i < nodes.length; i++) {
            // Set new status
            allowedNodes[nodes[i]] = status[i];
        }
    }

    /*//////////////////////////////////////////////////////////////
                               FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /// @notice Check whether a `node` is in `allowedNodes` set
    /// @param node address to check for set inclusion
    /// @return true if node is in allowlist, else false
    function isAllowedNode(address node) external view returns (bool) {
        return allowedNodes[node];
    }
}
