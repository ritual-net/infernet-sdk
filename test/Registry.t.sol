// SPDX-License-Identifier: BSD-3-Clause-Clear
pragma solidity ^0.8.4;

import {Inbox} from "../src/Inbox.sol";
import {Test} from "forge-std/Test.sol";
import {Fee} from "../src/payments/Fee.sol";
import {Registry} from "../src/Registry.sol";
import {LibDeploy} from "./lib/LibDeploy.sol";
import {Reader} from "../src/utility/Reader.sol";
import {EIP712Coordinator} from "../src/EIP712Coordinator.sol";
import {WalletFactory} from "../src/payments/WalletFactory.sol";

/// @title RegistryTest
/// @notice Tests Registry implementation
contract RegistryTest is Test {
    /*//////////////////////////////////////////////////////////////
                                INTERNAL
    //////////////////////////////////////////////////////////////*/

    /// @notice Registry
    Registry private REGISTRY;

    /// @notice Coordinator
    EIP712Coordinator private COORDINATOR;

    /// @notice Inbox
    Inbox private INBOX;

    /// @notice Reader
    Reader private READER;

    /// @notice Fee
    Fee private FEE;

    /// @notice Wallet factory
    WalletFactory private WALLET_FACTORY;

    /*//////////////////////////////////////////////////////////////
                                 SETUP
    //////////////////////////////////////////////////////////////*/

    function setUp() public {
        // Precompute contract addresses
        uint256 initialNonce = vm.getNonce(address(this));
        address coordinatorAddress = vm.computeCreateAddress(address(this), initialNonce + 1);
        address inboxAddress = vm.computeCreateAddress(address(this), initialNonce + 2);
        address readerAddress = vm.computeCreateAddress(address(this), initialNonce + 3);
        address feeAddress = vm.computeCreateAddress(address(this), initialNonce + 4);
        address walletFactoryAddress = vm.computeCreateAddress(address(this), initialNonce + 5);

        // Deploy registry
        REGISTRY = new Registry(coordinatorAddress, inboxAddress, readerAddress, feeAddress, walletFactoryAddress);

        // Deploy coordinator, inbox, reader
        COORDINATOR = new EIP712Coordinator(REGISTRY);
        INBOX = new Inbox(REGISTRY);
        READER = new Reader(REGISTRY);
        FEE = new Fee(address(this), 500); // Initialize with this address as feeRecipient + 5% fee
        WALLET_FACTORY = new WalletFactory(REGISTRY);
    }

    /*//////////////////////////////////////////////////////////////
                                 TESTS
    //////////////////////////////////////////////////////////////*/

    /// @notice Check registry addresses correctly correspond to deployed counterparts
    function testRegistryAddresses() public {
        assertEq(REGISTRY.COORDINATOR(), address(COORDINATOR));
        assertEq(REGISTRY.INBOX(), address(INBOX));
        assertEq(REGISTRY.READER(), address(READER));
        assertEq(REGISTRY.FEE(), address(FEE));
        assertEq(REGISTRY.WALLET_FACTORY(), address(WALLET_FACTORY));
    }

    /// @notice Check registry addresses correctly correspond to deployed counterparts when using LibDeploy
    function testRegistryViaLibDeploy() public {
        // Deploy via LibDeploy
        uint256 initialNonce = vm.getNonce(address(this));
        address registryAddress = vm.computeCreateAddress(address(this), initialNonce);
        (
            Registry registry,
            EIP712Coordinator coordinator,
            Inbox inbox,
            Reader reader,
            Fee fee,
            WalletFactory walletFactory
        ) = LibDeploy.deployContracts(address(this), initialNonce, address(this), 500);

        // Assert checks
        // Note: these are somewhat redundant given LibDeploy also `require`-checks at deploy time, but useful for future safety
        assertEq(address(registry), registryAddress);
        assertEq(registry.COORDINATOR(), address(coordinator));
        assertEq(registry.INBOX(), address(inbox));
        assertEq(registry.READER(), address(reader));
        assertEq(registry.FEE(), address(fee));
        assertEq(registry.WALLET_FACTORY(), address(walletFactory));
    }
}
