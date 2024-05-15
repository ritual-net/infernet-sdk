// SPDX-License-Identifier: BSD-3-Clause-Clear
pragma solidity ^0.8.4;

import {Inbox} from "../src/Inbox.sol";
import {Script} from "forge-std/Script.sol";
import {Registry} from "../src/Registry.sol";
import {console} from "forge-std/Console.sol";
import {Reader} from "../src/utility/Reader.sol";
import {LibDeploy} from "../test/lib/LibDeploy.sol";
import {EIP712Coordinator} from "../src/EIP712Coordinator.sol";

/// @title Deploy
/// @notice Deploys Infernet SDK to destination chain defined in environment
contract Deploy is Script {
    function run() public {
        // Setup wallet
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        vm.startBroadcast(deployerPrivateKey);

        // Log address
        address deployerAddress = vm.addr(deployerPrivateKey);
        console.log("Loaded deployer: ", deployerAddress);

        // Get deployer address nonce
        uint256 initialNonce = vm.getNonce(deployerAddress);

        // Deploy contracts via LibDeploy
        (Registry registry, EIP712Coordinator coordinator, Inbox inbox, Reader reader, Fee fee, WalletFactory walletFactory) = LibDeploy.deployContracts(initialNonce, deployerAddress, 500);

        // Log deployed contracts
        console.log("Using protocol fee: 5%");
        console.log("Deployed Registry: ", address(registry));
        console.log("Deployed EIP712Coordinator: ", address(coordinator));
        console.log("Deployed Inbox: ", address(inbox));
        console.log("Deployed Reader: ", address(reader));
        console.log("Deployed Fee: ", address(fee));
        console.log("Deployed WalletFactory: ", address(walletFactory));

        // Execute
        vm.stopBroadcast();
    }
}
