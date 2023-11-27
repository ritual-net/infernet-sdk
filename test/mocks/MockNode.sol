// SPDX-License-Identifier: BSD-3-Clause-Clear
pragma solidity ^0.8.4;

import {Manager} from "../../src/Manager.sol";
import {MockManager} from "./MockManager.sol";
import {StdAssertions} from "forge-std/StdAssertions.sol";
import {EIP712Coordinator} from "../../src/EIP712Coordinator.sol";

/// @title MockNode
/// @notice Mocks the functionality of an off-chain Infernet node
/// @dev Inherited functions contain state checks but not event or error checks and do not interrupt parent reverts (with reverting pre-checks)
contract MockNode is StdAssertions {
    /*//////////////////////////////////////////////////////////////
                                INTERNAL
    //////////////////////////////////////////////////////////////*/

    /// @notice Coordinator
    EIP712Coordinator internal COORDINATOR;

    /*//////////////////////////////////////////////////////////////
                              CONSTRUCTOR
    //////////////////////////////////////////////////////////////*/

    /// Creates new MockNode
    /// @param _coordinator Coordinator
    constructor(EIP712Coordinator _coordinator) {
        COORDINATOR = _coordinator;
    }

    /*//////////////////////////////////////////////////////////////
                           UTILITY FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /// @notice Returns node cooldown start timestamp
    function cooldownStart() public view returns (uint32) {
        (, uint32 startTimestamp) = COORDINATOR.nodeInfo(address(this));
        return startTimestamp;
    }

    /// @notice Asserts node status against status to check
    /// @param status status to check
    function assertNodeStatus(Manager.NodeStatus status) public {
        (Manager.NodeStatus actual,) = COORDINATOR.nodeInfo(address(this));
        assertEq(uint8(actual), uint8(status));
    }

    /// @notice Checks if node has `NodeStatus.Active` or reverts
    /// @dev MockManager-only function, thus forced interface
    function isActiveNode() public view returns (bool) {
        return MockManager(address(COORDINATOR)).isActiveNode();
    }

    /*//////////////////////////////////////////////////////////////
                           INHERITED FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /// @dev Augmented with checks
    /// @dev Checks status change to `NodeStatus.Registered`
    /// @dev Checks that cooldown start timestamp for node has been updated to current timestamp
    function registerNode(address node) external {
        // Initialize registration
        uint256 currentTimestamp = block.timestamp;
        COORDINATOR.registerNode(node);

        // Check status
        (Manager.NodeStatus status, uint32 cds) = COORDINATOR.nodeInfo(address(this));
        assertEq(uint8(status), uint8(Manager.NodeStatus.Registered));

        // Ensure cooldown start timestamp conforms to current timestamp
        assertEq(currentTimestamp, cds);
    }

    /// @dev Augmented with checks
    /// @dev Checks status change to `NodeStatus.Active`
    /// @dev Checks node cooldown start timestamp is zeroed out
    function activateNode() external {
        COORDINATOR.activateNode();

        // Check status
        assertNodeStatus(Manager.NodeStatus.Active);
        // Ensure cooldown start timestamp is nullified
        assertEq(cooldownStart(), 0);
    }

    /// @dev Augmented with checks
    /// @dev Checks status change to `NodeStatus.Inactive`
    /// @dev Checks node cooldown start timestamp is zeroed out
    function deactivateNode() external {
        COORDINATOR.deactivateNode();

        // Check status
        assertNodeStatus(Manager.NodeStatus.Inactive);
        // Ensure cooldown start timestamp is nullified
        assertEq(cooldownStart(), 0);
    }

    /// @dev Wrapper function (calling Coordinator with msg.sender == node)
    function deliverCompute(
        uint32 subscriptionId,
        uint32 deliveryInterval,
        bytes calldata input,
        bytes calldata output,
        bytes calldata proof
    ) external {
        COORDINATOR.deliverCompute(subscriptionId, deliveryInterval, input, output, proof);
    }

    /// @dev Wrapper function (calling Coordinator with msg.sender == node)
    function deliverComputeDelegatee(
        uint32 nonce,
        uint32 expiry,
        EIP712Coordinator.Subscription calldata sub,
        uint8 v,
        bytes32 r,
        bytes32 s,
        uint32 deliveryInterval,
        bytes calldata input,
        bytes calldata output,
        bytes calldata proof
    ) external {
        COORDINATOR.deliverComputeDelegatee(nonce, expiry, sub, v, r, s, deliveryInterval, input, output, proof);
    }
}
