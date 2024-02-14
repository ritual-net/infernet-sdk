// SPDX-License-Identifier: BSD-3-Clause-Clear
pragma solidity ^0.8.4;

import {Inbox} from "../Inbox.sol";
import {Registry} from "../Registry.sol";

/// @title InboxReader
/// @notice Exposes simple read interface to `InboxItem`(s) in `Inbox`
abstract contract InboxReader {
    /*//////////////////////////////////////////////////////////////
                               IMMUTABLE
    //////////////////////////////////////////////////////////////*/

    /// @notice Inbox contract
    /// @dev Private visibility because inbox is only interfaced with via internal view functions
    Inbox private immutable INBOX;

    /*//////////////////////////////////////////////////////////////
                              CONSTRUCTOR
    //////////////////////////////////////////////////////////////*/

    /// @notice Initialize new InboxReader
    /// @param registry registry address
    constructor(address registry) {
        // Setup inbox (via address from registry)
        INBOX = Inbox(Registry(registry).INBOX());
    }

    /*//////////////////////////////////////////////////////////////
                           INTERNAL FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /// @notice Read interface to `Inbox` `InboxItem`
    /// @param containerId compute container ID
    /// @param node delivering node address
    /// @param index item index
    /// @return `InboxItem` immutable creation timestamp
    /// @return Associated subscription ID (`0` if none)
    /// @return Associated subscription interval (`0` if none)
    /// @return Optional compute container input parameters
    /// @return Optional compute container output parameters
    /// @return Optional compute container proof parameters
    function _readInbox(bytes32 containerId, address node, uint256 index)
        internal
        view
        returns (uint32, uint32, uint32, bytes memory, bytes memory, bytes memory)
    {
        return INBOX.items(containerId, node, index);
    }
}
