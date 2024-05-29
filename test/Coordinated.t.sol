// SPDX-License-Identifier: BSD-3-Clause-Clear
pragma solidity ^0.8.4;

import {Test} from "forge-std/Test.sol";
import {Registry} from "../src/Registry.sol";
import {LibDeploy} from "./lib/LibDeploy.sol";
import {Coordinated} from "../src/utility/Coordinated.sol";
import {MockCoordinated} from "./mocks/MockCoordinated.sol";

/// @title CoordinatedTest
/// @notice Tests Coordinated implementation
contract CoordinatedTest is Test {
    /*//////////////////////////////////////////////////////////////
                                 TESTS
    //////////////////////////////////////////////////////////////*/

    /// @notice Coordinator can call permissioned function
    function testFuzzCoordinatorCanCallPermissionedFunction(address coordinator) public {
        // Deploy new registry w/ specified coordinator address
        // Inbox, reader, fee, wallet factory addresses irrelevant so zeroed out
        Registry registry = new Registry(coordinator, address(0), address(0), address(0), address(0));

        // Verify that coordinator address is correctly set in registry
        assertEq(coordinator, registry.COORDINATOR());

        // Create new MockCoordinated contract w/ registry
        MockCoordinated coordinated = new MockCoordinated(registry);

        // Assert that coordinator address can call permissioned function
        vm.prank(coordinator);
        coordinated.mockCoordinatorPermissionedFn();
    }

    /// @notice Non-coordinator cannot call permissioned function
    function testFuzzNonCoordinatorCannotCallPermissionedFunction(address nonCoordinator) public {
        // Initialize contracts via LibDeploy
        uint256 initialNonce = vm.getNonce(address(this));
        (Registry registry,,,,,) = LibDeploy.deployContracts(address(this), initialNonce, address(0), 0);

        // Enforce that nonCoordinator address != deployed coordinator address
        vm.assume(nonCoordinator != registry.COORDINATOR());

        // Create new MockCoordinator contract w/ registry
        MockCoordinated coordinated = new MockCoordinated(registry);

        // Assert that coordinator address can call permissioned function
        vm.prank(registry.COORDINATOR());
        coordinated.mockCoordinatorPermissionedFn();

        // Assert that non-coordinator addresses cannot call permissioned function
        vm.prank(nonCoordinator);
        vm.expectRevert(Coordinated.NotCoordinator.selector);
        coordinated.mockCoordinatorPermissionedFn();
    }
}
