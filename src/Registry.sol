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

    /// @notice Coordinator address
    address public immutable COORDINATOR;

    /// @notice Inbox address
    address public immutable INBOX;

    /// @notice Reader address
    address public immutable READER;

    /// @notice Fee registry address
    address public immutable FEE;

    /// @notice Wallet factory address
    address public immutable WALLET_FACTORY;

    /*//////////////////////////////////////////////////////////////
                              CONSTRUCTOR
    //////////////////////////////////////////////////////////////*/

    /// @notice Initializes new Registry
    /// @dev Requires pre-computing expected deployed addresses
    /// @param coordinator Coordinator address
    /// @param inbox Inbox address
    /// @param reader Reader address
    /// @param fee Fee registry address
    /// @param walletFactory Wallet factory address
    constructor(address coordinator, address inbox, address reader, address fee, address walletFactory) {
        COORDINATOR = coordinator;
        INBOX = inbox;
        READER = reader;
        FEE = fee;
        WALLET_FACTORY = walletFactory;
    }
}
