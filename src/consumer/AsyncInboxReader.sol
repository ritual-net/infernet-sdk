// SPDX-License-Identifier: BSD-3-Clause-Clear
pragma solidity ^0.8.4;

import {Registry} from "../Registry.sol";
import {AsyncInbox} from "../AsyncInbox.sol";

/// @title AsyncInboxReader
/// @notice Allows reading `InboxItem`(s) from an `AsyncInbox`
abstract contract AsyncInboxReader {
    /*//////////////////////////////////////////////////////////////
                               IMMUTABLE
    //////////////////////////////////////////////////////////////*/

    /// @notice Async inbox
    /// @dev Private visibility since ASYNC_INBOX is interfaced with via internal utility functions
    AsyncInbox private immutable ASYNC_INBOX;

    /*//////////////////////////////////////////////////////////////
                              CONSTRUCTOR
    //////////////////////////////////////////////////////////////*/

    /// @notice Initialize new AsyncInboxReader
    /// @param registry registry address
    constructor(address registry) {
        // Setup async inbox (via address from canonical registry)
        ASYNC_INBOX = AsyncInbox(Registry(registry).ASYNC_INBOX());
    }

    /*//////////////////////////////////////////////////////////////
                           INTERNAL FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /// @notice Allows reading AsyncInbox `InboxItem`(s)
    /// @param containerId item compute container ID
    /// @param node item delivering node address
    /// @param index associated item index
    /// @return AsyncInbox `InboxItem` de-structured
    function _readAsyncInbox(bytes32 containerId, address node, uint256 index)
        internal
        view
        returns (
            uint32,
            uint32,
            uint32,
            bytes memory,
            bytes memory,
            bytes memory
        )
    {
        return ASYNC_INBOX.inbox(containerId, node, index);
    }
}
