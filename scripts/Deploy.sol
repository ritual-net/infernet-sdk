// SPDX-License-Identifier: BSD-3-Clause-Clear
pragma solidity ^0.8.4;

import {Script} from "forge-std/Script.sol";
import {console} from "forge-std/console.sol";
import {EIP712Coordinator} from "../src/EIP712Coordinator.sol";

/// @title Deploy
/// @notice Deploys EIP712Coordinator to destination chain defined in environment
contract Deploy is Script {
    function run() public {
        // Setup wallet
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        vm.startBroadcast(deployerPrivateKey);

        // Log address
        address deployerAddress = vm.addr(deployerPrivateKey);
        console.log("Loaded deployer: ", deployerAddress);

        // Create Coordinator
        EIP712Coordinator coordinator = new EIP712Coordinator();
        console.log("Deployed EIP712Coordinator: ", address(coordinator));

        // Execute
        vm.stopBroadcast();
    }
}
