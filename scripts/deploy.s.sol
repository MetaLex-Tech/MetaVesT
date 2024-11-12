// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.24;

import {Script} from "forge-std/Script.sol";
import {console} from "forge-std/console.sol";
import "../src/VestingAllocationFactory.sol";
import "../src/TokenOptionFactory.sol";
import "../src/RestrictedTokenFactory.sol";
import "../src/MetaVesTController.sol";
import "../src/MetaVesTFactory.sol";
import "../lib/zk-governance/l2-contracts/src/ZkTokenV2.sol";
import "../lib/zk-governance/l2-contracts/src/ZkCappedMinterFactory.sol";

contract BaseScript is Script {
    address deployerAddress;
    address metaVesTController;



     function run() public {
            deployerAddress = vm.addr(vm.envUint("PRIVATE_KEY_DEPLOY"));
            uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY_DEPLOY");
            
            vm.startBroadcast(deployerPrivateKey);
            VestingAllocationFactory vestingFactory = new VestingAllocationFactory();
            TokenOptionFactory tokenOptionFactory = new TokenOptionFactory();
            RestrictedTokenFactory restrictedTokenFactory = new RestrictedTokenFactory();
            MetaVesTFactory factory = new MetaVesTFactory();

            ZkTokenV2 zkToken = new ZkTokenV2();
            ZkCappedMinterFactory zkMinterFactory = new ZkCappedMinterFactory(0x073749a0f8ed0d49b1acfd4e0efdc59328c83d0c2eed9ee099a3979f0c332ff8);
        

            metaVesTController = factory.deployMetavestAndController(deployerAddress, deployerAddress, address(vestingFactory), address(tokenOptionFactory), address(restrictedTokenFactory), address(zkMinterFactory), address(zkToken));
            //metaVesTController = new metavestController(deployerAddress, deployerAddress, address(vestingFactory), address(tokenOptionFactory), address(restrictedTokenFactory));
            vm.stopBroadcast();
            console.log("Deployed");
            console.log("Addresses:");
            console.log("VestingAllocationFactory: ", address(vestingFactory));
            console.log("TokenOptionFactory: ", address(tokenOptionFactory));
            console.log("RestrictedTokenFactory: ", address(restrictedTokenFactory));
            console.log("MetaVesTController: ", metaVesTController);
            console.log("MetaVesTFactory: ", address(factory));
            console.log("ZkToken: ", address(zkToken));
            console.log("ZkCappedMinterFactory: ", address(zkMinterFactory));
        }
}