// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.20;

import {Script} from "forge-std/Script.sol";
import {console} from "forge-std/console.sol";
import "../src/VestingAllocationFactory.sol";
import "../src/TokenOptionFactory.sol";
import "../src/RestrictedTokenFactory.sol";
import "../src/MetaVesTController.sol";
import "../src/MetaVesTFactory.sol";
import "../src/conditions/multiTimeCondition.sol";


contract BaseScript is Script {
    address deployerAddress;
    address metaVesTController;


    address MULTISIG = 0x709b1B5D0FDC75caCe1Eb7f6aa00873F2f2cBC27;


     function run() public {
            deployerAddress = vm.addr(vm.envUint("PRIVATE_KEY_DEPLOY"));
            uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY_DEPLOY");
     
            /*== Logs ==
  Deployed
  Addresses:
  VestingAllocationFactory:  0x92e6226182b13E3826d332616C16EeD94b7b6247
  TokenOptionFactory:  0x61D66fd4d572dD18c2844300BaBDcf35D6414785
  RestrictedTokenFactory:  0x0Cc4A631ce5b24f089E8bc2140D28b52a06D9cAd
  MetaVesTController:  0x8E4Ee5aD8025528FB1EB9e8a4230BcB1Eaccf811
  MultiTimeCondition:  0xB060178dD96c389C51c242E3FDFF435F418181F3*/
           
            vm.startBroadcast(deployerPrivateKey);
           // token =I ERC20(0xFE67A4450907459c3e1FFf623aA927dD4e28c67a);
     
        
          //  VestingAllocationFactory vestingFactory =  VestingAllocationFactory(0x92e6226182b13E3826d332616C16EeD94b7b6247);
          //  TokenOptionFactory tokenOptionFactory =  TokenOptionFactory(0x61D66fd4d572dD18c2844300BaBDcf35D6414785);
          //  RestrictedTokenFactory restrictedTokenFactory =  RestrictedTokenFactory(0x0Cc4A631ce5b24f089E8bc2140D28b52a06D9cAd);
         //   MetaVesTFactory factory =  MetaVesTFactory(0xC3CBCd058BACc34b7C4f09F3116c61bA0B9930dd);
         //   metaVesTController = factory.deployMetavestAndController(MULTISIG, MULTISIG, address(vestingFactory), address(tokenOptionFactory), address(restrictedTokenFactory));
            
            uint256[] memory unlockTimes = new uint256[](15);
        
            unlockTimes[0] = 1743944400;
            unlockTimes[1] = 1746536400;
            unlockTimes[2] = 1749214800;
            unlockTimes[3] = 1751806800;
            unlockTimes[4] = 1754485200;
            unlockTimes[5] = 1757163600;
            unlockTimes[6] = 1759755600;
            unlockTimes[7] = 1762434000;
            unlockTimes[8] = 1765026000;
            unlockTimes[9] = 1767704400;
            unlockTimes[10] = 1770382800;
            unlockTimes[11] = 1772802000;
            unlockTimes[12] = 1775480400;
            unlockTimes[13] = 1778072400;
            unlockTimes[14] = 1780750800;

            MultiTimeCondition mt = new MultiTimeCondition(MULTISIG, unlockTimes);

            vm.stopBroadcast();
            
            //metaVesTController = new metavestController(deployerAddress, deployerAddress, address(vestingFactory), address(tokenOptionFactory), address(restrictedTokenFactory));

            console.log("Deployed");
            console.log("Addresses:");
            //console.log("VestingAllocationFactory: ", address(vestingFactory));
           // console.log("TokenOptionFactory: ", address(tokenOptionFactory));
            //console.log("RestrictedTokenFactory: ", address(restrictedTokenFactory));
            //console.log("MetaVesTController: ", metaVesTController);
            console.log("MultiTimeCondition: ", address(mt));
        }
}