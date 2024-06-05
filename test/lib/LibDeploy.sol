// SPDX-License-Identifier: BSD-3-Clause-Clear
pragma solidity ^0.8.4;

import {Vm} from "forge-std/Vm.sol";
import {Inbox} from "../../src/Inbox.sol";
import {Fee} from "../../src/payments/Fee.sol";
import {Registry} from "../../src/Registry.sol";
import {Reader} from "../../src/utility/Reader.sol";
import {Coordinator} from "../../src/Coordinator.sol";
import {StdAssertions} from "forge-std/StdAssertions.sol";
import {EIP712Coordinator} from "../../src/EIP712Coordinator.sol";
import {WalletFactory} from "../../src/payments/WalletFactory.sol";

/// @title LibDeploy
/// @dev Useful helpers to deploy contracts + register with Registry contract
library LibDeploy {
    /*//////////////////////////////////////////////////////////////
                               CONSTANTS
    //////////////////////////////////////////////////////////////*/

    /// @notice Setup Vm cheatcode
    /// @dev Can't inherit abstract contracts in libraries, forces us to redeclare
    Vm internal constant vm = Vm(address(uint160(uint256(keccak256("hevm cheat code")))));

    /*//////////////////////////////////////////////////////////////
                           UTILITY FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /// @notice Deploys suite of contracts (Registry, EIP712Coordinator, Inbox, Reader), returning typed references
    /// @dev Precomputes deployed addresses to use in registry deployment by incrementing provided `initialNonce`
    /// @param initialNonce starting deployer nonce
    /// @param initialFeeRecipient initial fee recipient for Fee registry
    /// @param initialFee initial protocol fee for Fee registry
    /// @return {Registry, EIP712Coordinator, Inbox, Reader, Fee, WalletFactory}-typed references
    function deployContracts(
        address deployerAddress,
        uint256 initialNonce,
        address initialFeeRecipient,
        uint16 initialFee
    ) internal returns (Registry, EIP712Coordinator, Inbox, Reader, Fee, WalletFactory) {
        // Precompute addresses for {Coordinator, Inbox, Reader}
        address coordinatorAddress = vm.computeCreateAddress(deployerAddress, initialNonce + 1);
        address inboxAddress = vm.computeCreateAddress(deployerAddress, initialNonce + 2);
        address readerAddress = vm.computeCreateAddress(deployerAddress, initialNonce + 3);
        address feeAddress = vm.computeCreateAddress(deployerAddress, initialNonce + 4);
        address walletFactoryAddress = vm.computeCreateAddress(deployerAddress, initialNonce + 5);

        // Initialize new registry
        Registry registry =
            new Registry(coordinatorAddress, inboxAddress, readerAddress, feeAddress, walletFactoryAddress);

        // Initialize new EIP712Coordinator
        EIP712Coordinator coordinator = new EIP712Coordinator(registry);

        // Initialize new Inbox
        Inbox inbox = new Inbox(registry);

        // Initialize new Reader
        Reader reader = new Reader(registry);

        // Initialize new Fee
        Fee fee = new Fee(initialFeeRecipient, initialFee);

        // Initialize new WalletFactory
        WalletFactory walletFactory = new WalletFactory(registry);

        // Verify addresses match
        require(registry.COORDINATOR() == address(coordinator), "Coordinator address mismatch");
        require(registry.INBOX() == address(inbox), "Inbox address mismatch");
        require(registry.READER() == address(reader), "Reader address mismatch");
        require(registry.FEE() == address(fee), "Fee address mismatch");
        require(registry.WALLET_FACTORY() == address(walletFactory), "WalletFactory address mismatch");

        return (registry, coordinator, inbox, reader, fee, walletFactory);
    }
}
