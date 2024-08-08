// SPDX-License-Identifier: BSD-3-Clause-Clear
pragma solidity ^0.8.4;

import {Test} from "forge-std/Test.sol";
import {Registry} from "../src/Registry.sol";
import {LibDeploy} from "./lib/LibDeploy.sol";
import {Wallet} from "../src/payments/Wallet.sol";
import {WalletFactory} from "../src/payments/WalletFactory.sol";

/// @title IWalletFactoryEvents
/// @notice Events emitted by WalletFactory
interface IWalletFactoryEvents {
    event WalletCreated(address indexed owner, address wallet);
}

/// @title WalletFactoryTest
/// @notice Tests WalletFactory implementation
contract WalletFactoryTest is Test, IWalletFactoryEvents {
    /*//////////////////////////////////////////////////////////////
                                INTERNAL
    //////////////////////////////////////////////////////////////*/

    /// @notice Registry
    Registry internal REGISTRY;

    /// @notice Wallet factory
    WalletFactory internal WALLET_FACTORY;

    /*//////////////////////////////////////////////////////////////
                                 SETUP
    //////////////////////////////////////////////////////////////*/

    function setUp() public {
        // Initialize contracts
        uint256 initialNonce = vm.getNonce(address(this));
        (Registry registry,,,,, WalletFactory walletFactory) =
            LibDeploy.deployContracts(address(this), initialNonce, address(0), 0);

        // Assign contracts
        REGISTRY = registry;
        WALLET_FACTORY = walletFactory;
    }

    /*//////////////////////////////////////////////////////////////
                                 TESTS
    //////////////////////////////////////////////////////////////*/

    /// @notice Wallets created via `WalletFactory.createWallet()` are appropriately setup
    function testFuzzWalletsAreCreatedCorrectly(address initialOwner) public {
        // Predict expected wallet address
        uint256 nonce = vm.getNonce(address(WALLET_FACTORY));
        address expected = vm.computeCreateAddress(address(WALLET_FACTORY), nonce);

        // Create new wallet
        vm.expectEmit(address(WALLET_FACTORY));
        emit WalletCreated(initialOwner, expected);
        address walletAddress = WALLET_FACTORY.createWallet(initialOwner);

        // Verify wallet is deployed to correct address
        assertEq(expected, walletAddress);

        // Verify wallet is valid
        assertTrue(WALLET_FACTORY.isValidWallet(walletAddress));

        // Setup created wallet
        Wallet wallet = Wallet(payable(walletAddress));

        // Verify wallet owner is correctly set
        assertEq(wallet.owner(), initialOwner);

        // Verify coordinator-only functions fail at first error that is not Auth error
        vm.startPrank(REGISTRY.COORDINATOR());
        vm.expectRevert(Wallet.InsufficientFunds.selector);
        wallet.cLock(address(0), address(0), 1);
        vm.stopPrank();
    }

    /// @notice Wallets not created via `WalletFactory` do not return as valid
    function testFuzzWalletsCreatedDirectlyAreNotValid(address deployer) public {
        // Deploy from a different address to increase entropy
        vm.startPrank(deployer);

        // Create wallet directly
        Wallet wallet = new Wallet(REGISTRY, deployer);

        // Verify wallet is not valid
        assertFalse(WALLET_FACTORY.isValidWallet(address(wallet)));

        vm.stopPrank();
    }
}
