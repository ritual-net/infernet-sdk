// SPDX-License-Identifier: BSD-3-Clause-Clear
pragma solidity ^0.8.4;

import {ERC20} from "solady/tokens/ERC20.sol";

/// @title MockToken
/// @notice Mocks ERC20 token with exposed mint functionality
contract MockToken is ERC20 {
    /*//////////////////////////////////////////////////////////////
                           INHERITED FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /// @notice Overrides ERC20.name (necessary for implementation)
    function name() public pure override returns (string memory) {
        return "TOKEN";
    }

    /// @notice Overrides ERC20.symbol (necessary for implementation)
    function symbol() public pure override returns (string memory) {
        return "TKN";
    }

    /*//////////////////////////////////////////////////////////////
                           UTILITY FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /// @notice Mints `amount` tokens to `to` address
    /// @param to address to mint tokens to
    /// @param amount quantity of tokens to mint
    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }
}
