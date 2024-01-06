// SPDX-License-Identifier: BSD-3-Clause-Clear
pragma solidity ^0.8.4;

/// @title Registry
/// @notice An address registry for contract discovery.
/// @dev Allows discovery of different modules
contract Registry {
    /// @notice Address of the Node Manager
    address public immutable NODE_MANAGER;
    /// @notice Address of the Coordinator
    address public immutable COORDINATOR;

    /// @notice Initialize the Registry with the addresses of all the modules.
    /// Since each module depends on the Registry for its own deployment, the
    /// addresses must be predicted ahead of time.
    /// Refer to https://book.getfoundry.sh/reference/forge-std/compute-create-address for more details.
    /// @param nodeManager predicted address of the NodeManager contract
    /// @param coordinator predicted address of the Coordinator contract
    constructor(address nodeManager, address coordinator) {
        NODE_MANAGER = nodeManager;
        COORDINATOR = coordinator;
    }
}
