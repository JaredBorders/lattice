// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.29;

import {Script, console} from "@forge-std/Script.sol";

contract DeployScript is Script {

    function setUp() public {}

    function run() public {
        vm.startBroadcast();

        /// @custom:todo

        vm.stopBroadcast();
    }

}
