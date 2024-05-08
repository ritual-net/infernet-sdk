// SPDX-License-Identifier: BSD-3-Clause-Clear
pragma solidity ^0.8.4;

import {Registry} from "../Registry.sol";
import {ERC20} from "solady/tokens/ERC20.sol";
import {Ownable} from "solady/auth/Ownable.sol";
import {Coordinated} from "../utility/Coordinated.sol";

/// @title Wallet
/// @notice Payments wallet that allows: (1) managing ETH & ERC20 token balances, (2) allowing consumers to spend balance, (3) allowing coordinator to manage balance
/// @dev Implements `Ownable` to setup an update-able `Wallet` `owner`
/// @dev Implements `Coordinated` to restrict payment-handling functions to being called from coordinator
contract Wallet is Ownable, Coordinated {
    /*//////////////////////////////////////////////////////////////
                                MUTABLE
    //////////////////////////////////////////////////////////////*/

    /// @notice token address => locked balance in escrow
    /// @dev address(0) represents ETH
    mapping(address => uint256) private lockedBalance;

    /// @notice consumer => token address => spend limit
    /// @dev Exposes public getter to enable checking allowance
    mapping(address => mapping(address => uint256)) public allowance;

    /*//////////////////////////////////////////////////////////////
                                 ERRORS
    //////////////////////////////////////////////////////////////*/

    /// @notice Thrown by `_transferToken` if token transfer fails
    /// @dev 4-byte signature: `0x90b8ec18`
    error TransferFailed();

    /// @notice Thrown if attempting to transfer or lock tokens in quantity greater than possible
    /// @dev Thrown by `withdraw()` if attempting to withdraw `amount > unlockedBalance`
    /// @dev Thrown by `cLock()` if attempting to escrow `amount > unlockedBalance`
    /// @dev 4-byte signature: `0x356680b7`
    error InsufficientFunds();

    /*//////////////////////////////////////////////////////////////
                              CONSTRUCTOR
    //////////////////////////////////////////////////////////////*/

    /// @notice Initializes new Wallet
    /// @param registry registry contract
    /// @param initialOwner intial wallet owner
    constructor(Registry registry, address initialOwner) Coordinated(registry) {
        // Initialize owner
        _initializeOwner(initialOwner);
    }

    /*//////////////////////////////////////////////////////////////
                           INTERNAL FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /// @notice Returns balance of `token` that is not currently locked in escrow
    /// @param token token address (ERC20 contract address or `address(0)` for ETH)
    /// @return unlocked token balance
    function _getUnlockedBalance(address token) internal view returns (uint256) {
        // Get locked token balance
        uint256 locked = lockedBalance[token];

        // Get total token balance
        uint256 balance;
        if (token == address(0)) {
            // If token is ETH, collect contract balance
            balance = address(this).balance;
        } else {
            // Else, collect token balance from ERC20 contract
            balance = ERC20(token).balanceOf(address(this));
        }

        // Return total token balance - locked token balance
        return balance - locked;
    }

    /// @notice Transfers `amount` `token` from `address(this)` to `to`
    /// @param token token to transfer (ERC20 contract address or `address(0)` for ETH)
    /// @param to address to transfer to
    /// @param amount amount of token to transfer
    function _transferToken(address token, address to, uint256 amount) internal {
        // Track successful completion
        bool success;

        if (token == address(0)) {
            // Transfer ETH
            (success,) = payable(to).call{value: amount}("");
        } else {
            // Tranfer tokens
            success = ERC20(token).transfer(to, amount);
        }

        // If transfer unsuccessful, revert with transfer failure error
        if (!success) {
            revert TransferFailed();
        }
    }

    /*//////////////////////////////////////////////////////////////
                               FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /// @notice Allows `owner` to withdraw `amount` `token`(s)
    /// @dev Can only withdraw tokens not locked in escrow
    /// @param token token address
    /// @param amount amount of tokens to withdraw from `Wallet`
    function withdraw(address token, uint256 amount) external onlyOwner {
        // Get unlocked token balance
        uint256 unlockedBalance = _getUnlockedBalance(token);

        // Throw if requested withdraw amount > unlocked token balance
        if (amount > unlockedBalance) {
            revert InsufficientFunds();
        }

        // Withdraw `amount` `token`(s) to `msg.sender` (`owner`)
        _transferToken(token, msg.sender, amount);
    }

    /// @notice Allows `owner` to approve `spender` as a consumer that can spend `amount` `token`(s) from `Wallet`
    /// @dev We purposefully ignore the `approve` frontrunning vulnerability as it is rarely applied in practice
    /// @param spender consumer address to approve
    /// @param token token address to approve spend for
    /// @param amount approval amount
    function approve(address spender, address token, uint256 amount) external onlyOwner {
        allowance[spender][token] = amount;
    }

    /// @notice Allows coordinator to transfer `amount` `tokens` to `to`
    /// @param token token to transfer (ERC20 contract address or `address(0)` for ETH)
    /// @param to address to transfer to
    /// @param amount amount of token to transfer
    function cTransfer(address token, address to, uint256 amount) external onlyCoordinator {
        _transferToken(token, to, amount);
    }

    /// @notice Allows coordinator to decrease a `spender`(s) `token` spend allowance by `amount`
    /// @dev Notice, this does not allow increasing a `spender`(s) allowance; just decreasing by some consumed amount
    /// @param spender consumer address
    /// @param token spent token
    /// @param amount amount spent
    function cDecreaseAllowance(address spender, address token, uint256 amount) external onlyCoordinator {
        allowance[spender][token] -= amount;
    }

    /// @notice Allows coordinator to lock `amount` `token`(s) indefinitely in escrow
    /// @param token token to lock
    /// @param amount amount to lock
    function cLock(address token, uint256 amount) external onlyCoordinator {
        // Get unlocked token balance
        uint256 unlockedBalance = _getUnlockedBalance(token);

        // Throw if requested escrow amount is greater than available unlocked token amount
        if (amount > unlockedBalance) {
            revert InsufficientFunds();
        }

        lockedBalance[token] += amount;
    }

    /// @notice Allows coordinator to unlock `amount` `token`(s) from escrow
    /// @param token token to unlock
    /// @param amount amount to unlock
    function cUnlock(address token, uint256 amount) external onlyCoordinator {
        lockedBalance[token] -= amount;
    }

    /*//////////////////////////////////////////////////////////////
                                FALLBACK
    //////////////////////////////////////////////////////////////*/

    /// @notice Allow ETH deposits to `Wallet`
    receive() external payable {}
}
