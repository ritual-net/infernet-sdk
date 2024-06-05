// SPDX-License-Identifier: BSD-3-Clause-Clear
pragma solidity ^0.8.4;

import {Test} from "forge-std/Test.sol";
import {Registry} from "../src/Registry.sol";
import {LibDeploy} from "./lib/LibDeploy.sol";
import {Ownable} from "solady/auth/Ownable.sol";
import {MockToken} from "./mocks/MockToken.sol";
import {Wallet} from "../src/payments/Wallet.sol";
import {EIP712Coordinator} from "../src/EIP712Coordinator.sol";

/// @title WalletTest
/// @notice Tests Wallet implementation
contract WalletTest is Test {
    /*//////////////////////////////////////////////////////////////
                                INTERNAL
    //////////////////////////////////////////////////////////////*/

    /// @notice Mock ERC20 token
    MockToken internal TOKEN;

    /// @notice Registry
    Registry internal REGISTRY;

    /*//////////////////////////////////////////////////////////////
                                 SETUP
    //////////////////////////////////////////////////////////////*/

    function setUp() public {
        // Initialize contracts
        uint256 initialNonce = vm.getNonce(address(this));
        (Registry registry,,,,,) = LibDeploy.deployContracts(address(this), initialNonce, address(0), 0);

        // Assign contracts
        REGISTRY = registry;

        // Setup mock ERC20 token
        TOKEN = new MockToken();
    }

    /*//////////////////////////////////////////////////////////////
                                 TESTS
    //////////////////////////////////////////////////////////////*/

    /// @notice Can create wallet with correct owner
    function testFuzzCanCreateWalletWithCorrectOwner(address initialOwner) public {
        // Create Wallet
        Wallet wallet = new Wallet(REGISTRY, initialOwner);

        // Assert owner
        assertEq(wallet.owner(), initialOwner);
    }

    /// @notice Can transfer wallet ownership
    function testFuzzCanTransferWalletOwnership(address newOwner) public {
        // Assert new owner is not zero address
        vm.assume(newOwner != address(0));

        // Assume newOwner cannot be initialOwner
        address initialOwner = address(123);
        vm.assume(initialOwner != newOwner);

        // Create wallet w/ initialOwner
        Wallet wallet = new Wallet(REGISTRY, initialOwner);
        assertEq(wallet.owner(), initialOwner);

        // Transfer wallet ownership
        vm.prank(initialOwner);
        wallet.transferOwnership(newOwner);

        // Assert new ownership
        assertEq(wallet.owner(), newOwner);
    }

    /// @notice Can transfer Ether to wallet
    function testFuzzCanTransferEtherToWallet(uint256 amount) public {
        // Deal this contract initial balance
        vm.deal(address(this), amount);

        // Create new wallet
        Wallet wallet = new Wallet(REGISTRY, address(123));

        // Assert initial balance
        assertEq(address(wallet).balance, 0);

        // Send Ether to wallet
        (bool success,) = payable(wallet).call{value: amount}("");
        assertTrue(success);

        // Assert new balance
        assertEq(address(wallet).balance, amount);

        // Ensure balance is withdrawable
        vm.prank(address(123));
        wallet.withdraw(address(0), amount);

        // Assert withdrawn balance
        assertEq(address(123).balance, amount);
    }

    /// @notice Can transfer ERC20 token to wallet
    function testFuzzCanTransferERC20ToWallet(uint256 amount) public {
        // Create new wallet
        Wallet wallet = new Wallet(REGISTRY, address(123));

        // Mint some tokens to wallet
        TOKEN.mint(address(wallet), amount);

        // Ensure token balance is reflected
        assertEq(TOKEN.balanceOf(address(wallet)), amount);

        // Ensure balance is withdrawable
        vm.startPrank(address(123));
        wallet.withdraw(address(TOKEN), amount);

        // Assert withdrawn balance
        assertEq(TOKEN.balanceOf(address(123)), amount);
    }

    /// @notice Can approve a spender to spend some Ether with approval updating on spend
    function testFuzzCanApproveSpenderToSpendEther(address spender, uint256 balance, uint256 amount) public {
        // Create new wallet
        Wallet wallet = new Wallet(REGISTRY, address(123));

        // Assume balance >= amount to approve spend and amount is non-0
        vm.assume(amount > 0 && amount < UINT256_MAX); // we add + 1 during tests
        vm.assume(balance >= amount);

        // Transfer some Ether balance to contract
        vm.deal(address(this), balance);
        (bool success,) = payable(address(wallet)).call{value: balance}("");
        assertTrue(success);

        // Assert initial spender allowance is 0
        assertEq(wallet.allowance(spender, address(0)), 0);

        // Increase spender allowance as non-owner and expect error
        vm.startPrank(address(1234));
        vm.expectRevert(Ownable.Unauthorized.selector);
        wallet.approve(spender, address(0), amount);
        vm.stopPrank();

        // Increase spender allowance as owner
        vm.startPrank(address(123));
        wallet.approve(spender, address(0), amount);
        vm.stopPrank();

        // Verify increased allowance
        assertEq(wallet.allowance(spender, address(0)), amount);

        // Use coordinator to consume allowance (first failing to transfer amount + 1)
        vm.startPrank(address(REGISTRY.COORDINATOR()));
        vm.expectRevert(Wallet.InsufficientAllowance.selector);
        wallet.cTransfer(spender, address(0), address(200), amount + 1);

        // Then, working transferring correct amount
        wallet.cTransfer(spender, address(0), address(200), amount);
        vm.stopPrank();

        // Assert allowance is now 0
        assertEq(wallet.allowance(spender, address(0)), 0);

        // Assert new balance of address(200) is amount
        assertEq(address(200).balance, amount);

        // Assert reduced balance of wallet contract
        assertEq(address(wallet).balance, balance - amount);

        // Assert reduced withdraw capacity (failure if withdrawing full amount)
        vm.startPrank(address(123));
        vm.expectRevert(Wallet.InsufficientFunds.selector);
        wallet.withdraw(address(0), balance);

        // Assert accurate withdraw capacity if removing already transferred amount
        wallet.withdraw(address(0), balance - amount);
        assertEq(address(wallet).balance, 0);
        assertEq(address(123).balance, balance - amount);
        vm.stopPrank();
    }

    /// @notice Can approve a spender to spend some token with approval updating on spend
    function testFuzzCanApproveSpenderToSpendToken(address spender, uint256 balance, uint256 amount) public {
        // Create new wallet
        Wallet wallet = new Wallet(REGISTRY, address(123));

        // Assume balance >= amount to approve spend and amount is non-0
        vm.assume(amount > 0);
        vm.assume(balance >= amount);

        // Transfer some token balance to contract
        TOKEN.mint(address(wallet), balance);

        // Assert initial spender allowance is 0
        assertEq(wallet.allowance(spender, address(TOKEN)), 0);

        // Increase spender allowance as non-owner and expect error
        vm.startPrank(address(1234));
        vm.expectRevert(Ownable.Unauthorized.selector);
        wallet.approve(spender, address(TOKEN), amount);
        vm.stopPrank();

        // Increase spender allowance as owner
        vm.startPrank(address(123));
        wallet.approve(spender, address(TOKEN), amount);
        vm.stopPrank();

        // Verify increased allowance
        assertEq(wallet.allowance(spender, address(TOKEN)), amount);

        // Use coordinator to consume allowance
        vm.startPrank(address(REGISTRY.COORDINATOR()));
        wallet.cTransfer(spender, address(TOKEN), address(200), amount);
        vm.stopPrank();

        // Assert allowance is now 0
        assertEq(wallet.allowance(spender, address(TOKEN)), 0);

        // Assert new balance of address(200) is amount
        assertEq(TOKEN.balanceOf(address(200)), amount);

        // Assert reduced balance of wallet contract
        assertEq(TOKEN.balanceOf(address(wallet)), balance - amount);

        // Assert reduced withdraw capacity (failure if withdrawing full amount)
        vm.startPrank(address(123));
        vm.expectRevert(Wallet.InsufficientFunds.selector);
        wallet.withdraw(address(TOKEN), balance);

        // Assert accurate withdraw capacity if removing already transferred amount
        wallet.withdraw(address(TOKEN), balance - amount);
        assertEq(TOKEN.balanceOf(address(wallet)), 0);
        assertEq(TOKEN.balanceOf(address(123)), balance - amount);
        vm.stopPrank();
    }

    /// @notice Can have multiple spenders utilizing wallet funds in-flight
    function testMultipleSpendersUtilizingFunds() public {
        // Setup addresses
        address walletOwner = address(122);
        address spenderOne = address(123);
        address spenderTwo = address(124);
        address spenderThree = address(125);

        // Create new wallet
        Wallet wallet = new Wallet(REGISTRY, walletOwner);

        // Mint wallet with initial balance of 100 ETH
        vm.deal(address(this), 100 ether);
        (bool success,) = payable(address(wallet)).call{value: 100 ether}("");
        assertTrue(success);
        assertEq(address(wallet).balance, 100 ether);

        // And 100 TOKENs
        TOKEN.mint(address(wallet), 100e6);
        assertEq(TOKEN.balanceOf(address(wallet)), 100e6);

        // Approve spenders for various amounts of spend across tokens
        vm.startPrank(walletOwner);
        wallet.approve(spenderOne, address(0), 50 ether);
        wallet.approve(spenderTwo, address(0), 10 ether);
        wallet.approve(spenderTwo, address(TOKEN), 90e6);
        wallet.approve(spenderTwo, address(TOKEN), 80e6);
        wallet.approve(spenderThree, address(TOKEN), 30e6);
        vm.stopPrank();

        // Verify allowances are correctly reflected
        assertEq(wallet.allowance(spenderOne, address(0)), 50 ether);
        assertEq(wallet.allowance(spenderOne, address(TOKEN)), 0);
        assertEq(wallet.allowance(spenderTwo, address(0)), 10 ether);
        assertEq(wallet.allowance(spenderTwo, address(TOKEN)), 80e6);
        assertEq(wallet.allowance(spenderThree, address(0)), 0 ether);
        assertEq(wallet.allowance(spenderThree, address(TOKEN)), 30e6);

        // Lock TOKENs from spenderThree
        vm.startPrank(REGISTRY.COORDINATOR());
        wallet.cLock(spenderThree, address(TOKEN), 30e6); // 100 balance, 30 locked
        vm.stopPrank();

        // Ensure allowance updated
        assertEq(wallet.allowance(spenderThree, address(TOKEN)), 0);

        // Ensure withdrawing up to remaining unlocked balance works
        assertEq(TOKEN.balanceOf(walletOwner), 0);
        vm.startPrank(walletOwner);
        wallet.withdraw(address(TOKEN), 70e6); // 30 balance, 30 locked
        assertEq(TOKEN.balanceOf(walletOwner), 70e6);
        TOKEN.transfer(address(wallet), 70e6); // 100 balance, 30 locked
        vm.stopPrank();

        // Attempt to lock full allowance of spenderTwo (unsuccessfully)
        vm.startPrank(REGISTRY.COORDINATOR());
        vm.expectRevert(Wallet.InsufficientFunds.selector);
        wallet.cLock(spenderTwo, address(TOKEN), 80e6);

        // Attempt to lock partial allowance of spenderTwo (successfully)
        wallet.cLock(spenderTwo, address(TOKEN), 40e6); // 100 balance, 70 locked (40e6 left on spenderTwo, 0e6 on spenderThree)
        vm.stopPrank();

        // Fail to withdraw greater than 30e6 tokens from owner
        vm.startPrank(walletOwner);
        vm.expectRevert(Wallet.InsufficientFunds.selector);
        wallet.withdraw(address(TOKEN), 30e6 + 1);
        wallet.withdraw(address(TOKEN), 30e6); // 70 balance, 70 locked
        vm.stopPrank();
        assertEq(TOKEN.balanceOf(walletOwner), 30e6);
        assertEq(TOKEN.balanceOf(address(wallet)), 70e6);

        // Partial unlock tokens and assert allowance is incremented
        assertEq(wallet.allowance(spenderTwo, address(TOKEN)), 40e6);
        vm.startPrank(REGISTRY.COORDINATOR());
        wallet.cUnlock(spenderTwo, address(TOKEN), 20e6); // 70 balance, 50 locked (60e6 left on spenderTwo, 0e6 on spenderThree)
        assertEq(wallet.allowance(spenderTwo, address(TOKEN)), 60e6);

        // Expect failure locking greater than allowance but less than total balance
        wallet.cUnlock(spenderThree, address(TOKEN), 25e6); // 70 balance, 25 locked (60e6 left on spenderTwo, 25e6 on spenderThree)
        vm.expectRevert(Wallet.InsufficientAllowance.selector);
        wallet.cLock(spenderThree, address(TOKEN), 30e6);

        // Expect allowance decrease upon transferring tokens
        wallet.cTransfer(spenderTwo, address(TOKEN), spenderThree, 25e6); // 45 balance, 25 locked (35e6 left on spenderTwo, 25e6 on spenderThree)
        vm.stopPrank();
        assertEq(wallet.allowance(spenderTwo, address(TOKEN)), 35e6);
        assertEq(TOKEN.balanceOf(address(wallet)), 45e6);
        assertEq(TOKEN.balanceOf(spenderThree), 25e6);

        // Expect can only withdraw up to new unlocked balance of 20e6
        vm.startPrank(walletOwner);
        vm.expectRevert(Wallet.InsufficientFunds.selector);
        wallet.withdraw(address(TOKEN), 20e6 + 1);
        wallet.withdraw(address(TOKEN), 20e6);
        vm.stopPrank();
        assertEq(TOKEN.balanceOf(walletOwner), 50e6);
        assertEq(TOKEN.balanceOf(address(wallet)), 25e6);
    }

    /*//////////////////////////////////////////////////////////////
                                FALLBACK
    //////////////////////////////////////////////////////////////*/

    /// @notice Allow ETH deposits
    receive() external payable {}
}
