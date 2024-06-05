// SPDX-License-Identifier: BSD-3-Clause-Clear
pragma solidity ^0.8.4;

import {Registry} from "../Registry.sol";
import {Coordinator, Subscription} from "../Coordinator.sol";

/// @title Reader
/// @notice Utility contract: implements multicall like batch reading functionality
/// @dev Multicall src: https://github.com/mds1/multicall
/// @dev Functions forgo validation assuming correct off-chain inputs are used
contract Reader {
    /*//////////////////////////////////////////////////////////////
                               IMMUTABLE
    //////////////////////////////////////////////////////////////*/

    /// @notice Coordinator
    /// @dev `Coordinator` used over `EIP712Coordinator` since no EIP-712 functionality consumed
    Coordinator private immutable COORDINATOR;

    /*//////////////////////////////////////////////////////////////
                              CONSTRUCTOR
    //////////////////////////////////////////////////////////////*/

    /// @notice Initializes new Reader
    /// @param registry registry contract
    constructor(Registry registry) {
        // Collect coordinator from registry
        COORDINATOR = Coordinator(registry.COORDINATOR());
    }

    /*//////////////////////////////////////////////////////////////
                               FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /// @notice Reads `Subscription`(s) from `Coordinator` in batch
    /// @dev Does not validate that subscriptions between `startId` and `endId` exist
    /// @dev Does not validate that `startId` is at least `0`
    /// @dev Does not validate that `endId` is greater than `startId`
    /// @param startId start subscription ID (inclusive)
    /// @param endId end subscription ID (exclusive)
    /// @return `Subscription`(s)
    function readSubscriptionBatch(uint32 startId, uint32 endId) external view returns (Subscription[] memory) {
        // Setup array to populate
        uint32 length = endId - startId;
        Subscription[] memory subscriptions = new Subscription[](length);

        // Iterate and collect subscriptions
        for (uint32 id = startId; id < endId; id++) {
            // Collect 0-index array id
            uint32 idx = id - startId;
            // Collect and store subscription
            subscriptions[idx] = COORDINATOR.getSubscription(id);
        }

        return subscriptions;
    }

    /// @notice Given `Subscription` ids and intervals, collects redundancy count of (subscription, interval)-pair
    /// @dev By default, if a (subscription ID, interval)-pair does not exist, function will return `redundancyCount == 0`
    /// @dev Does not validate `ids.length == intervals.length`
    /// @param ids array of subscription IDs
    /// @param intervals array of intervals to check where each ids[idx] corresponds to intervals[idx]
    /// @return array of redundancy counts for (subscription ID, interval)-pairs
    function readRedundancyCountBatch(uint32[] calldata ids, uint32[] calldata intervals)
        external
        view
        returns (uint16[] memory)
    {
        // Setup array to populate
        uint16[] memory redundancyCounts = new uint16[](ids.length);

        // For each (subscription ID, interval)-pair
        for (uint32 i = 0; i < ids.length; i++) {
            // Compute `redundancyCount`-mapping key
            bytes32 key = keccak256(abi.encode(ids[i], intervals[i]));
            // Collect redundancy for (id, interval)
            redundancyCounts[i] = COORDINATOR.redundancyCount(key);
        }

        return redundancyCounts;
    }
}
