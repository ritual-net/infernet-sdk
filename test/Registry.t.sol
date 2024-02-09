// SPDX-License-Identifier: BSD-3-Clause-Clear
pragma solidity ^0.8.4;

import {Test} from "forge-std/Test.sol";
import {Registry} from "../src/Registry.sol";
import {LibDeploy} from "./lib/LibDeploy.sol";
import {NodeManager} from "../src/NodeManager.sol";
import {EIP712Coordinator} from "../src/EIP712Coordinator.sol";

/// @title RegistryTest
/// @notice Tests Registry implementation
contract RegistryTest is Test {
    /*//////////////////////////////////////////////////////////////
                                INTERNAL
    //////////////////////////////////////////////////////////////*/

    /// @notice Registry
    Registry internal REGISTRY;

    /// @notice NodeManager
    NodeManager internal NODE_MANAGER;

    /// @notice Coordinator
    EIP712Coordinator internal COORDINATOR;

    /*//////////////////////////////////////////////////////////////
                                 SETUP
    //////////////////////////////////////////////////////////////*/

    function setUp() public {
        // Precompute contract addresses
        uint256 initialNonce = vm.getNonce(address(this));
        address nodeManagerAddress = vm.computeCreateAddress(address(this), initialNonce + 1);
        address coordinatorAddress = vm.computeCreateAddress(address(this), initialNonce + 2);

        // Deploy registry
        REGISTRY = new Registry(nodeManagerAddress, coordinatorAddress);

        // Deploy node manager + coordinator
        NODE_MANAGER = new NodeManager();
        COORDINATOR = new EIP712Coordinator(REGISTRY);
    }

    /*//////////////////////////////////////////////////////////////
                                 TESTS
    //////////////////////////////////////////////////////////////*/

    /// @notice Check registry addresses correctly correspond to deployed counterparts
    function testRegistryAddresses() public {
        assertEq(REGISTRY.NODE_MANAGER(), address(NODE_MANAGER));
        assertEq(REGISTRY.COORDINATOR(), address(COORDINATOR));
    }

    /// @notice Check registry addresses correctly correspond to deployed counterparts when using LibDeploy
    function testRegistryViaLibDeploy() public {
        // Deploy via LibDeploy
        uint256 initialNonce = vm.getNonce(address(this));
        (Registry registry, NodeManager nodeManager, EIP712Coordinator coordinator) =
            LibDeploy.deployContracts(initialNonce);

        // Assert checks
        // Note: these are somewhat redundant given LibDeploy also `require`-checks at deploy time, but useful for future safety
        assertEq(registry.NODE_MANAGER(), address(nodeManager));
        assertEq(registry.COORDINATOR(), address(coordinator));
    }
}
