// SPDX-License-Identifier: BSD-3-Clause-Clear
pragma solidity ^0.8.4;

import {Wallet} from "./Wallet.sol";
import {Registry} from "../Registry.sol";

/// @title WalletFactory
/// @notice Responsible for creating and tracking `Wallet`(s)
contract WalletFactory {
    /*//////////////////////////////////////////////////////////////
                               IMMUTABLE
    //////////////////////////////////////////////////////////////*/

    /// @notice Registry contract
    /// @dev Consumed as parameter during `Wallet`-creation
    Registry private immutable REGISTRY;

    /*//////////////////////////////////////////////////////////////
                                MUTABLE
    //////////////////////////////////////////////////////////////*/

    /// @notice address => is wallet created by factory?
    /// @dev View functionality exposed via `isValidWallet()`
    mapping(address => bool) private wallets;

    /*//////////////////////////////////////////////////////////////
                                 EVENTS
    //////////////////////////////////////////////////////////////*/

    /// @notice Emitted when a new `Wallet` is created
    /// @param caller `createWallet` call initiator
    /// @param owner owner of `Wallet`
    /// @param wallet `Wallet` address
    event WalletCreated(address indexed caller, address indexed owner, address wallet);

    /*//////////////////////////////////////////////////////////////
                              CONSTRUCTOR
    //////////////////////////////////////////////////////////////*/

    /// @notice Initializes new WalletFactory
    /// @param registry registry contract
    constructor(Registry registry) {
        // Store registry contract
        REGISTRY = registry;
    }

    /*//////////////////////////////////////////////////////////////
                               FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /// @notice Creates new `Wallet` initially owned by `owner`
    /// @param initialOwner initial owner
    /// @return newly-created `Wallet` address
    function createWallet(address initialOwner) external returns (address) {
        // Create new wallet
        Wallet wallet = new Wallet(REGISTRY, initialOwner);

        // Track created wallet
        wallets[address(wallet)] = true;

        // Emit wallet creation
        emit WalletCreated(msg.sender, initialOwner, address(wallet));

        // Return created wallet address
        return address(wallet);
    }

    /// @notice Checks if an address is a valid `Wallet` created by this `WalletFactory`
    /// @param wallet address to check
    /// @return `true` if `wallet` is a valid `Wallet`, else `false`
    function isValidWallet(address wallet) external view returns (bool) {
        return wallets[wallet];
    }
}
