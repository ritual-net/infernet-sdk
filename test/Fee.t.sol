// SPDX-License-Identifier: BSD-3-Clause-Clear
pragma solidity ^0.8.4;

import {Test} from "forge-std/Test.sol";
import {Fee} from "../src/payments/Fee.sol";
import {Ownable} from "solady/auth/Ownable.sol";

/// @title FeeTest
/// @notice Tests Fee registry implementation
contract FeeTest is Test {
    /*//////////////////////////////////////////////////////////////
                                 TESTS
    //////////////////////////////////////////////////////////////*/

    /// @notice Fee registry owner can update fee
    function testFuzzOwnerCanUpdateFee(address owner, uint16 fee) public {
        // Initialize fee registry
        Fee f = new Fee(owner, 0);

        // Assert owner/fee recipient
        assertEq(owner, f.owner());
        assertEq(owner, f.FEE_RECIPIENT());

        // Assert fee is initially zero
        assertEq(0, f.FEE());

        // Update fee
        vm.prank(owner);
        f.updateFee(fee);

        // Assert new fee
        assertEq(fee, f.FEE());
    }

    /// @notice Non-fee registry owner cannot update fee
    function testFuzzNonOwnerCannotUpdateFee(address nonOwner) public {
        // Assume nonOwner cannot be actual owner
        address actualOwner = address(123);
        vm.assume(nonOwner != actualOwner);

        // Initialize fee registry with owner as actual owner and 0 fee
        Fee f = new Fee(actualOwner, 0);

        // Attempt to update fee as non-owner
        vm.startPrank(nonOwner);
        vm.expectRevert(Ownable.Unauthorized.selector);
        f.updateFee(123);
        vm.stopPrank();
    }

    /// @notice Ownership transfer works
    function testOwnerCanTransferOwnership() public {
        // Setup transfer
        address initialOwner = address(1);
        address newOwner = address(2);

        // Initialize fee registry
        Fee f = new Fee(initialOwner, 0);

        // Check owner
        assertEq(f.FEE_RECIPIENT(), initialOwner);

        // Process transfer
        vm.prank(initialOwner);
        f.transferOwnership(newOwner);

        // Assert ownership transferred
        assertEq(f.FEE_RECIPIENT(), newOwner);
    }
}
