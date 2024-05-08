// SPDX-License-Identifier: BSD-3-Clause-Clear
pragma solidity ^0.8.4;

import {ERC20} from "solady/tokens/ERC20.sol";
import {Fee} from "../../src/payments/Fee.sol";
import {Registry} from "../../src/Registry.sol";

/// @title MockProtocol
/// @notice Mocks functionality of a protocol `feeRecipient`
contract MockProtocol {
    /*//////////////////////////////////////////////////////////////
                               IMMUTABLE
    //////////////////////////////////////////////////////////////*/

    /// @notice Fee
    Fee private immutable FEE;

    /*//////////////////////////////////////////////////////////////
                              CONSTRUCTOR
    //////////////////////////////////////////////////////////////*/

    /// Creates new MockProtocol
    /// @param registry registry contract
    constructor(Registry registry) {
        // Collect Fee from registry
        FEE = Fee(registry.FEE());
    }

    /*//////////////////////////////////////////////////////////////
                           INHERITED FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /// @dev Wrapper function (calling Ownable.transferOwnership)
    function transferOwnership(address newOwner) external {
        FEE.transferOwnership(newOwner);
    }

    /// @dev Wrapper function (calling Ownable.renounceOwnership)
    function renounceOwnership() external {
        FEE.renounceOwnership();
    }

    /// @dev Wrapper function (calling Ownable.requestOwnershipHandover)
    function requestOwnershipHandover() external {
        FEE.requestOwnershipHandover();
    }

    /// @dev Wrapper function (calling Ownable.cancelOwnershipHandover)
    function cancelOwnershipHandover() external {
        FEE.cancelOwnershipHandover();
    }

    /// @dev Wrapper function (calling Ownable.completeOwnershipHandover)
    function completeOwnershipHandover(address pendingOwner) external {
        FEE.completeOwnershipHandover(pendingOwner);
    }

    /// @dev Wrapper function (calling Ownable.updateFee)
    function updateFee(uint16 newFee) external {
        FEE.updateFee(newFee);
    }

    /*//////////////////////////////////////////////////////////////
                           UTILITY FUNCTIONS
    //////////////////////////////////////////////////////////////*/

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

    /*//////////////////////////////////////////////////////////////
                                FALLBACK
    //////////////////////////////////////////////////////////////*/

    /// @notice Allow receiving ETH
    receive() external payable {}
}
