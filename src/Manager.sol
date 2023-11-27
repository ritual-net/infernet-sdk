// SPDX-License-Identifier: BSD-3-Clause-Clear
pragma solidity ^0.8.4;

/// @title Manager
/// @notice Manages node lifecycle (registration, activation, deactivation)
/// @dev Allows anyone to register to become an active node
/// @dev Allows registered nodes to become active after a `cooldown` seconds waiting period
/// @dev Allows any node to deactivate itself and return to an inactive state
/// @dev Exposes an `onlyActiveNode()` modifier used to restrict functions to being called by only active nodes
/// @dev Restricts addresses to 1 of 3 states: `Inactive`, `Registered`, `Active`
abstract contract Manager {
    /*//////////////////////////////////////////////////////////////
                                STRUCTS
    //////////////////////////////////////////////////////////////*/

    /// @notice Packed information about a node (status, cooldown start)
    /// @dev Cheaper to use a struct to store `status` + `cooldownStart` rather than SSTORE 2 independent mappings
    /// @dev Technically, could bitshift pack uint40 of data into single uint256 but readability penalty not worth it
    /// @dev Tightly-packed (well under 32-byte slot): [uint8, uint32] = 40 bits = 5 bytes
    struct NodeInfo {
        /// @notice Node status
        NodeStatus status;
        /// @notice Cooldown start timestamp in seconds
        /// @dev Default initializes to `0`; no cooldown active to start
        /// @dev Equal to `0` if `status != NodeStatus.Registered`, else equal to cooldown start time
        /// @dev Is modified by `registerNode()` to initiate `cooldown` holding period
        /// @dev uint32 allows for a timestamp up to year ~2106, likely far beyond lifecycle of this contract
        uint32 cooldownStart;
    }

    /*//////////////////////////////////////////////////////////////
                                 ENUMS
    //////////////////////////////////////////////////////////////*/

    /// @notice Possible node statuses
    /// @dev Enums in Solidity are unsigned integers capped at 256 members, so Inactive is the 0-initialized default
    /// @dev Inactive (0): Default status is inactive; no status
    /// @dev Registered (1): Node has registered to become active, initiating a period of `cooldown`
    /// @dev Active (2): Node is active, able to fulfill subscriptions, and is part of `modifier(onlyActiveNode)`
    enum NodeStatus {
        Inactive,
        Registered,
        Active
    }

    /*//////////////////////////////////////////////////////////////
                               CONSTANTS
    //////////////////////////////////////////////////////////////*/

    /// @notice Cooldown period, in seconds, before a node with `NodeStatus.Registered` can call `activateNode()`
    /// @dev type(uint32) is sufficient but we are not packing variables so control plane costs are higher because we
    ///      need to cast the 32-bit type into the 256-bit type anyways. Thus, we use type(uint256).
    uint256 public constant cooldown = 1 hours;

    /*//////////////////////////////////////////////////////////////
                                MUTABLE
    //////////////////////////////////////////////////////////////*/

    /// @dev Node address => node information
    mapping(address => NodeInfo) public nodeInfo;

    /*//////////////////////////////////////////////////////////////
                                 EVENTS
    //////////////////////////////////////////////////////////////*/

    /// @notice Emitted when a node moves from `NodeStatus.Inactive` to `NodeStatus.Registered`
    /// @dev It's actually slightly more expensive (~6 gas) to emit the uint32 given the explicit conversion needed
    ///      but this is necessary to have better readability and uniformity across the type (not casting in event)
    /// @param node newly-registered node address
    /// @param registerer optional proxy address registering on behalf of node (is equal to node when self-registering)
    /// @param cooldownStart start timestamp of registration cooldown
    event NodeRegistered(address indexed node, address indexed registerer, uint32 cooldownStart);

    /// @notice Emitted when a node moves from `NodeStatus.Registered` to `NodeStatus.Active`
    /// @param node newly-activated node address
    event NodeActivated(address indexed node);

    /// @notice Emitted when a node moves from any status to `NodeStatus.Inactive`
    /// @param node newly-deactivated node address
    event NodeDeactivated(address indexed node);

    /*//////////////////////////////////////////////////////////////
                                 ERRORS
    //////////////////////////////////////////////////////////////*/

    /// @notice Thrown if attempting to call function that requires a node to have status `NodeStatus.Active`
    /// @dev Only used by `modifier(onlyActiveNode)`
    /// @dev 4-byte signature: `0x8741cbb8`
    error NodeNotActive();

    /// @notice Thrown by `registerNode()` if attempting to register node with status that is not `NodeStatus.Inactive`
    /// @dev 4-byte signature: `0x5acfd518`
    /// @param node address of node attempting to register
    /// @param status current status of node failing registration
    error NodeNotRegisterable(address node, NodeStatus status);

    /// @notice Thrown by `activateNode()` if `cooldown` has not elapsed since node was registered
    /// @dev Like `NodeRegistered`, slightly more expensive to use uint32 over uint256 (~6 gas) but better readability
    /// @dev 4-byte signature: `0xc84b5bdd`
    /// @param cooldownStart start timestamp of node cooldown
    error CooldownActive(uint32 cooldownStart);

    /// @notice Thrown by `activateNode()` if attempting to active node with status that is not `NodeStatus.Registered`
    /// @dev 4-byte signature: `0x33daa7f9`
    /// @param status current status of node failing activation
    error NodeNotActivateable(NodeStatus status);

    /*//////////////////////////////////////////////////////////////
                               MODIFIERS
    //////////////////////////////////////////////////////////////*/

    /// @notice Allow only callers that are active nodes
    modifier onlyActiveNode() {
        if (nodeInfo[msg.sender].status != NodeStatus.Active) {
            revert NodeNotActive();
        }
        _;
    }

    /*//////////////////////////////////////////////////////////////
                               FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /// @notice Allows registering a node for activation
    /// @dev First-step of two-step process (followed by `activateNode()`)
    /// @dev Can call on behalf of other nodes as a proxy registerer
    /// @dev Node must have `NodeStatus.Inactive` to begin registration
    /// @param node node address to register
    function registerNode(address node) external {
        // SLOAD node info
        NodeInfo storage info = nodeInfo[node];

        // Ensure node is registerable
        // Current status must be `NodeStatus.Inactive`
        if (info.status != NodeStatus.Inactive) {
            revert NodeNotRegisterable(node, info.status);
        }

        // Update node status to Registered
        info.status = NodeStatus.Registered;
        // Update cooldown start timestamp to now
        info.cooldownStart = uint32(block.timestamp);

        // Emit new registration event
        emit NodeRegistered(node, msg.sender, uint32(block.timestamp));
    }

    /// @notice Allows activating a registered node after `cooldown` has elapsed
    /// @dev Second-step of two-step process (preceeded by `registerNode()`)
    /// @dev Must be called by node accepting a pending registration (`msg.sender == node`)
    /// @dev Must be called at least `cooldown` seconds after `registerNode()`
    function activateNode() external {
        // SLOAD node info
        NodeInfo storage info = nodeInfo[msg.sender];

        // Ensure node is already registered
        // Technically this check is not needed since the next check would fail anyways, but it provides a useful error
        if (info.status != NodeStatus.Registered) {
            revert NodeNotActivateable(info.status);
        }

        // Ensure node has elapsed required cooldown
        // Adding a uint32 to a uint32-bounded uint256 and upcasting to a uint256, so can't overflow
        uint256 cooldownEnd;
        unchecked {
            cooldownEnd = info.cooldownStart + cooldown;
        }
        if (block.timestamp < cooldownEnd) {
            revert CooldownActive(info.cooldownStart);
        }

        // Toggle node status to Active
        info.status = NodeStatus.Active;
        // Reset cooldown start timestamp
        info.cooldownStart = 0;

        // Emit activation event
        emit NodeActivated(msg.sender);
    }

    /// @notice Allows deactivating a node
    /// @dev Can be called to set the status of any node back to `NodeStatus.Inactive` with no cooldown
    /// @dev Must be called by the node deactivating itself (`msg.sender == node`)
    function deactivateNode() external {
        delete nodeInfo[msg.sender];

        // Emit deactivation event
        emit NodeDeactivated(msg.sender);
    }
}
