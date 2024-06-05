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

    /// @notice Fee amount, range: [0, 10000] with 2 decimal precision [0.00, 100.00]
    /// @dev Updating fee past 100.00 is not disallowed and it is up to the updating caller to ensure bounds
    /// @dev Exposes public getter to allow checking fee
    uint16 public FEE;

    /*//////////////////////////////////////////////////////////////
                              CONSTRUCTOR
    //////////////////////////////////////////////////////////////*/

    /// @notice Initializes new Fee
    /// @param feeRecipient initial protocol fee recipient
    /// @param fee initial protocol fee
    constructor(address feeRecipient, uint16 fee) {
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
    function updateFee(uint16 newFee) external onlyOwner {
        FEE = newFee;
    }

    /// @notice Returns fee recipient (`owner`) address
    /// @dev Acts simply as a proxy to the existing `owner()` fn to be more verbose
    /// @return fee recipient address
    function FEE_RECIPIENT() external view returns (address) {
        return owner();
    }
}
