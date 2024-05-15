// SPDX-License-Identifier: BSD-3-Clause-Clear
pragma solidity ^0.8.4;

import {ERC20} from "solady/tokens/ERC20.sol";
import {Registry} from "../../../src/Registry.sol";
import {Coordinator} from "../../../src/Coordinator.sol";
import {IProver} from "../../../src/payments/IProver.sol";

/// @title BaseProver
/// @notice Implements all necessary `IProver` functions + some utility functions, except for `requestProofValidation()`
/// @dev Useful utility to be inherited by mock provers downstream
abstract contract BaseProver is IProver {
    /*//////////////////////////////////////////////////////////////
                               IMMUTABLE
    //////////////////////////////////////////////////////////////*/

    /// @notice Coordinator
    /// @dev Restricted to `internal` visibility to allow consumption in downstream mock implementations
    Coordinator internal immutable COORDINATOR;

    /*//////////////////////////////////////////////////////////////
                                MUTABLE
    //////////////////////////////////////////////////////////////*/

    /// @notice token address => prover fee
    mapping(address => uint256) private tokenFees;

    /// @notice token address => is supported payment token
    mapping(address => bool) private supportedTokens;

    /*//////////////////////////////////////////////////////////////
                              CONSTRUCTOR
    //////////////////////////////////////////////////////////////*/

    /// @notice Create new BaseProver
    /// @param registry registry address
    constructor(Registry registry) {
        // Collect coordinator from registry
        COORDINATOR = Coordinator(registry.COORDINATOR());
    }

    /*//////////////////////////////////////////////////////////////
                           INHERITED FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /// @notice Implements `IProver.getWallet()`
    /// @dev Simply returns current address as recipient
    function getWallet() external view returns (address) {
        return address(this);
    }

    /// @notice Implements `IProver.isSupportedToken()`
    function isSupportedToken(address token) external view returns (bool) {
        return supportedTokens[token];
    }

    /// @notice Impelments `IProver.fee()`
    function fee(address token) external view returns (uint256) {
        return tokenFees[token];
    }

    /*//////////////////////////////////////////////////////////////
                           UTILITY FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /// @notice Allows updating fee for a token
    /// @param token to update fee for
    /// @param newFee new fee to update
    function updateFee(address token, uint256 newFee) external {
        tokenFees[token] = newFee;
    }

    /// @notice Allows updating token support
    /// @param token to update support for
    /// @param status new support status
    function updateSupportedToken(address token, bool status) external {
        supportedTokens[token] = status;
    }

    /// @notice Returns Ether balance of contract
    /// @return Ether balance of this address
    function getEtherBalance() external view returns (uint256) {
        return address(this).balance;
    }

    /// @notice Returns `token` balance of contract
    /// @param token address of ERC20 token contract
    /// @return `token` balance of this address
    function getTokenBalance(address token) external view returns (uint256) {
        return ERC20(token).balanceOf(address(this));
    }

    /// @notice Allow receiving ETH
    receive() external payable {}
}
