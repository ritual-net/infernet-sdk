// SPDX-License-Identifier: BSD-3-Clause-Clear
pragma solidity ^0.8.4;

import {Ownable} from "solady/auth/Ownable.sol";

/// @title Fee
/// @notice Protocol fee registry
/// @dev Implements `Ownable` to represent `feeRecipient` as registry owner
contract Fee is Ownable {
    /*//////////////////////////////////////////////////////////////
                                MUTABLE
    //////////////////////////////////////////////////////////////*/

    /// @notice Fee amount, range: [0, 100]
    /// @dev Updating fee past 100 is not disallowed and it is up to the `feeRecipient` to ensure bounds
    /// @dev Exposes public getter to allow checking fee
    uint8 public FEE;

    /*//////////////////////////////////////////////////////////////
                              CONSTRUCTOR
    //////////////////////////////////////////////////////////////*/

    /// @notice Initializes new Fee
    /// @param feeRecipient initial protocol fee recipient
    /// @param fee initial protocol fee
    constructor(address feeRecipient, uint8 fee) {
        // Set owner as fee recipient
        _initializeOwner(feeRecipient);
        // Set fee
        FEE = fee;
    }

    /*//////////////////////////////////////////////////////////////
                               FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /// @notice Allows `owner` (fee recipient) to update protocol `fee`
    /// @param newFee protocol fee to update to
    function updateFee(uint8 newFee) external onlyOwner {
        FEE = newFee;
    }

    /// @notice Returns fee recipient (`owner`) address
    /// @dev Acts simply as a proxy to the existing `owner()` fn to be more verbose
    /// @return fee recipient address
    function FEE_RECIPIENT() public view returns (address) {
        return owner();
    }
}
