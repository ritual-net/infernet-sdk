// SPDX-License-Identifier: BSD-3-Clause-Clear
pragma solidity ^0.8.4;

import {Coordinator} from "../../src/Coordinator.sol";
import {Registry} from "../../src/Registry.sol";
import {NodeManager} from "../../src/NodeManager.sol";
import {CommonBase} from "forge-std/Base.sol";
import {EIP712Coordinator} from "../../src/EIP712Coordinator.sol";

/// @title DeploymentFixture
/// @dev This contract is a helper fixture used to deploy the contracts
abstract contract DeploymentFixture is CommonBase {
    /*//////////////////////////////////////////////////////////////
                           UTILITY FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /// @notice deploys the Infernet contracts and returns their addresses
    /// @dev predict the addresses of the contracts and deploy them
    function deployInfernet() internal returns (address, address, address, address) {
        /// @dev Since all contracts use the registry for discovery, we need to deploy
        /// it first. To do that, we predict the addresses of the rest of the contracts first.
        address managerAddr = vm.computeCreateAddress(address(this), 2);
        address coordinatorAddr = vm.computeCreateAddress(address(this), 3);
        address eip712CoordinatorAddr = vm.computeCreateAddress(address(this), 4);
        Registry registry = new Registry(managerAddr, coordinatorAddr);
        NodeManager manager = new NodeManager();
        Coordinator coordinator = new Coordinator(address(registry));
        EIP712Coordinator eipCoordinator = new EIP712Coordinator(address(registry));
        /// @dev we don't need to check matching of the rest of the addresses, if the first one doesn't
        /// match the rest won't either
        require(
            address(manager) == managerAddr,
            "Deployment address not matching the predicted ones in the registry, ensure you're "
            "calling this function at the start of your script"
        );

        return (address(registry), managerAddr, coordinatorAddr, eip712CoordinatorAddr);
    }
}
