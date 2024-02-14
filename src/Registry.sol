// SPDX-License-Identifier: BSD-3-Clause-Clear
pragma solidity ^0.8.4;

/// @title Registry
/// @notice Allows registering Infernet contracts for inter-contract discovery
/// @dev Requires deploy-time decleration of contract addresses
/// @dev Immutable with no upgradeability; used only for discovery
contract Registry {
    /*//////////////////////////////////////////////////////////////
                               IMMUTABLE
    //////////////////////////////////////////////////////////////*/

    /// @notice NodeManager address
    address public immutable NODE_MANAGER;

    /// @notice Coordinator address
    address public immutable COORDINATOR;

    /// @notice Inbox address
    address public immutable INBOX;

    /*//////////////////////////////////////////////////////////////
                              CONSTRUCTOR
    //////////////////////////////////////////////////////////////*/

    /// @notice Initializes new Registry
    /// @dev Requires pre-computing expected deployed addresses
    /// @param nodeManager NodeManager address
    /// @param coordinator Coordinator address
    /// @param inbox Inbox address
    constructor(address nodeManager, address coordinator, address inbox) {
        NODE_MANAGER = nodeManager;
        COORDINATOR = coordinator;
        INBOX = inbox;
    }
}
