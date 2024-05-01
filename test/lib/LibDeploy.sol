// SPDX-License-Identifier: BSD-3-Clause-Clear
pragma solidity ^0.8.4;

import {Vm} from "forge-std/Vm.sol";
import {Inbox} from "../../src/Inbox.sol";
import {Registry} from "../../src/Registry.sol";
import {Reader} from "../../src/utility/Reader.sol";
import {Coordinator} from "../../src/Coordinator.sol";
import {StdAssertions} from "forge-std/StdAssertions.sol";
import {EIP712Coordinator} from "../../src/EIP712Coordinator.sol";

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
    /// @return {Registry, EIP712Coordinator, Inbox, Reader}-typed references
    function deployContracts(uint256 initialNonce) internal returns (Registry, EIP712Coordinator, Inbox, Reader) {
        // Precompute addresses for {Coordinator, Inbox, Reader}
        address coordinatorAddress = vm.computeCreateAddress(address(this), initialNonce + 1);
        address inboxAddress = vm.computeCreateAddress(address(this), initialNonce + 2);
        address readerAddress = vm.computeCreateAddress(address(this), initialNonce + 3);

        // Initialize new registry
        Registry registry = new Registry(coordinatorAddress, inboxAddress, readerAddress);

        // Initialize new EIP712Coordinator
        EIP712Coordinator coordinator = new EIP712Coordinator(registry);

        // Initialize new Inbox
        Inbox inbox = new Inbox(registry);

        // Initialize new Reader
        Reader reader = new Reader(registry);

        // Verify addresses match
        require(registry.COORDINATOR() == coordinatorAddress, "Coordinator address mismatch");
        require(registry.INBOX() == inboxAddress, "Inbox address mismatch");
        require(registry.READER() == readerAddress, "Reader address mismatch");

        return (registry, coordinator, inbox, reader);
    }
}
