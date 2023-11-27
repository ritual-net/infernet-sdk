// SPDX-License-Identifier: BSD-3-Clause-Clear
pragma solidity ^0.8.4;

import {MockCallbackConsumer} from "./Callback.sol";
import {Delegator} from "../../../src/pattern/Delegator.sol";

/// @title MockDelegatorCallbackConsumer
/// @notice Mocks CallbackConsumer w/ delegator set to an address
contract MockDelegatorCallbackConsumer is Delegator, MockCallbackConsumer {
    /*//////////////////////////////////////////////////////////////
                              CONSTRUCTOR
    //////////////////////////////////////////////////////////////*/

    /// Create new MockDelegatorCallbackConsumer
    /// @param _coordinator coordinator address
    /// @param _signer delegated signer address
    constructor(address _coordinator, address _signer) MockCallbackConsumer(_coordinator) Delegator(_signer) {}

    /*//////////////////////////////////////////////////////////////
                           INHERITED FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /// @notice Update new signer
    /// @param newSigner to update
    /// @dev Checks signer is updated after calling
    function updateMockSigner(address newSigner) external {
        _updateSigner(newSigner);

        assertEq(signer, newSigner);
    }
}
