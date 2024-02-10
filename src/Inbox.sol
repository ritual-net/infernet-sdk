// SPDX-License-Identifier: BSD-3-Clause-Clear
pragma solidity ^0.8.4;

import {Registry} from "./Registry.sol";
import {NodeManager} from "./NodeManager.sol";

/// @title Inbox
/// @notice Optionally stores container compute responses
/// @dev Allows `Coordinator` to store compute responses for lazy consumption
/// @dev Allows nodes with `NodeManager.NodeStatus.Active` to store compute responses without associated `Subscription`(s)
contract Inbox {
    /*//////////////////////////////////////////////////////////////
                                STRUCTS
    //////////////////////////////////////////////////////////////*/

    /// @notice An inbox item contains data about a compute response
    /// @dev An inbox item must have an associated immutable `timestamp` of when it was first recorded
    /// @dev An inbox item must have a `subscriptionId` and an `interval` if it is storing the response to a `Subscription`
    /// @dev An inbox item may optionally have an `input`, `output`, and `proof` (compute response parameters)
    /// @dev Tightly-packed struct:
    ///     - [timestamp, subscriptionId, interval]: [32, 32, 32] = 96
    //      - [input, output, proof] = dynamic
    struct InboxItem {
        uint32 timestamp;
        uint32 subscriptionId;
        uint32 interval;
        bytes input;
        bytes output;
        bytes proof;
    }

    /*//////////////////////////////////////////////////////////////
                               IMMUTABLE
    //////////////////////////////////////////////////////////////*/

    /// @notice Node manager contract (handles node lifecycle)
    NodeManager internal immutable NODE_MANAGER;

    /// @notice Coordinator contract address
    address internal immutable COORDINATOR_ADDRESS;

    /*//////////////////////////////////////////////////////////////
                                MUTABLE
    //////////////////////////////////////////////////////////////*/

    /// @notice containerId => delivering node address => array of delivered compute responses
    /// @dev Notice that validation of an `InboxItem` corresponding to a `containerId` is left to a downstream consumer
    mapping(bytes32 => mapping(address => InboxItem[])) public store;

    /*//////////////////////////////////////////////////////////////
                                 EVENTS
    //////////////////////////////////////////////////////////////*/

    /// @notice Emitted when a new InboxItem is added
    /// @param containerId compute container ID
    /// @param node delivering node address
    /// @param index index of newly-added inbox item
    event NewInboxItem(bytes32 indexed containerId, address indexed node, uint256 index);

    /*//////////////////////////////////////////////////////////////
                                 ERRORS
    //////////////////////////////////////////////////////////////*/

    /// @notice Thrown by `write()` if delivering tx from inactive node (status != `NodeManager.NodeStatus.Active`)
    /// @dev 4-byte signature: `0x8741cbb8`
    error NodeNotActive();

    /// @notice Thrown by `writeAuthenticated()` if called from non-Coordinator address
    /// @dev 4-byte signature: `0x9ec853e6`
    error NotCoordinator();

    /*//////////////////////////////////////////////////////////////
                               MODIFIERS
    //////////////////////////////////////////////////////////////*/

    /// @notice Allows only callers that are active nodes
    modifier onlyActiveNode() {
        if (!NODE_MANAGER.isActiveNode(msg.sender)) {
            revert NodeNotActive();
        }
        _;
    }

    /// @notice Allows calls from only the coordinator
    /// @dev Allows authenticating functions that store `Subscription` responses
    modifier onlyCoordinator() {
        if (msg.sender != COORDINATOR_ADDRESS) {
            revert NotCoordinator();
        }
        _;
    }

    /*//////////////////////////////////////////////////////////////
                              CONSTRUCTOR
    //////////////////////////////////////////////////////////////*/

    /// @notice Initializes new Inbox
    /// @param registry registry contract
    constructor(Registry registry) {
        // Collect node manager contract from registry
        NODE_MANAGER = NodeManager(registry.NODE_MANAGER());
        // Collect coordinator address from registry
        COORDINATOR_ADDRESS = registry.COORDINATOR();
    }

    /*//////////////////////////////////////////////////////////////
                           INTERNAL FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /// @notice Allows pushing `InboxItem`(s) to `store`
    /// @param containerId compute container ID
    /// @param node delivering node address
    /// @param subscriptionId optional associated subscription ID (`0` if none)
    /// @param interval optional associated subscription interval (`0` if none)
    /// @param input optional compute container input
    /// @param output optional compute container output
    /// @param proof optional compute container proof
    /// @return index of newly-added inbox item
    function _write(
        bytes32 containerId,
        address node,
        uint32 subscriptionId,
        uint32 interval,
        bytes calldata input,
        bytes calldata output,
        bytes calldata proof
    ) internal returns (uint256) {
        // Push new inbox item to store
        store[containerId][node].push(
            InboxItem({
                timestamp: uint32(block.timestamp),
                subscriptionId: subscriptionId,
                interval: interval,
                input: input,
                output: output,
                proof: proof
            })
        );

        // Collect index of newly-added inbox item
        uint256 index = store[containerId][node].length - 1;

        // Emit newly-added inbox item
        emit NewInboxItem(containerId, node, index);

        // Explicitly return index
        return index;
    }

    /*//////////////////////////////////////////////////////////////
                               FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /// @notice Allows nodes with `NodeManager.NodeStatus.Active` to optimistically deliver compute responses
    /// @dev Zeroes out `subscriptionId` and `interval` since compute response is not associated to a subscription request
    /// @param containerId compute container ID
    /// @param input optional compute container input
    /// @param output optional compute container output
    /// @param proof optional compute container proof
    /// @return index of newly-added inbox item
    function write(bytes32 containerId, bytes calldata input, bytes calldata output, bytes calldata proof)
        external
        onlyActiveNode
        returns (uint256)
    {
        return _write(containerId, msg.sender, 0, 0, input, output, proof);
    }

    /// @notice Allows `Coordinator` to store container compute response during `deliverCompute()` execution
    /// @dev `node` address is explicitly passed because `tx.origin` may not be accurate
    /// @dev `msg.sender` must be `address(COORDINATOR)` for authenticated write (storing subscriptionId, interval)
    /// @param containerId compute container ID
    /// @param node delivering node address
    /// @param subscriptionId optional associated subscription ID (`0` if none)
    /// @param interval optional associated subscription interval (`0` if none)
    /// @param input optional compute container input
    /// @param output optional compute container output
    /// @param proof optional compute container proof
    /// @return index of newly-added inbox item
    function writeViaCoordinator(
        bytes32 containerId,
        address node,
        uint32 subscriptionId,
        uint32 interval,
        bytes calldata input,
        bytes calldata output,
        bytes calldata proof
    ) external onlyCoordinator returns (uint256) {
        return _write(containerId, node, subscriptionId, interval, input, output, proof);
    }
}
