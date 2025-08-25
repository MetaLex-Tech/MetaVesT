// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.24;

import {ZkSyncGuardianCompensationConfig2024_2025} from "./lib/ZkSyncGuardianCompensationConfig2024_2025.sol";
import {ISafeProxyFactory, IGnosisSafe, GnosisTransaction} from "../test/lib/safe.sol";
import {BorgAuth} from "cybercorps-contracts/src/libs/auth.sol";
import {CyberAgreementRegistry} from "cybercorps-contracts/src/CyberAgreementRegistry.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {IZkCappedMinterV2Factory} from "../src/interfaces/zk-governance/IZkCappedMinterV2Factory.sol";
import {SafeTxHelper} from "./lib/SafeTxHelper.sol";
import {Script} from "forge-std/Script.sol";
import {VestingAllocationFactory} from "../src/VestingAllocationFactory.sol";
import {ZkCappedMinterV2} from "zk-governance/l2-contracts/src/ZkCappedMinterV2.sol";
import {ZkTokenV2} from "zk-governance/l2-contracts/src/ZkTokenV2.sol";
import {console2} from "forge-std/console2.sol";
import {metavestController} from "../src/MetaVesTController.sol";

contract DeployZkSyncGuardianCompensation2025_2026Script is ZkSyncGuardianCompConfig2025_2026, SafeTxHelper, Script {
    // Assume zkSync Era mainnet @ 64166260

    function run() public {
        uint256 deployerPrivateKey = vm.envUint("DEPLOYER_PRIVATE_KEY");
        address deployer = vm.addr(deployerPrivateKey);

        string memory saltStr = "MetaLexMetaVestZkSyncGuardianCompensationLaunchV1.0.2025-2026";
        bytes32 salt = keccak256(saltStr);

        vm.startBroadcast(deployerPrivateKey);

        // Deploy MetaVesT Controller

        metavestController controller = metavestController(address(new ERC1967Proxy{salt: salt}(
            address(new metavestController{salt: salt}()),
            abi.encodeWithSelector(
                metavestController.initialize.selector,
                address(guardianSafe),
                address(guardianSafe),
                address(registry),
                address(vestingAllocationFactory)
            )
        )));

        vm.stopBroadcast();

        // Prepare Guardian SAFE txs to set MetaVesT Controller's ZK Capped Minter
        GnosisTransaction[] memory safeTxs = new GnosisTransaction[](1);
        safeTxs[0] = GnosisTransaction({
            to: address(controller),
            value: 0,
            data: abi.encodeWithSelector(
                controller.setZkCappedMinter.selector,
                address(zkCappedMinter)
            )
        });

        // Post-deployment verifications

        vm.assertEq(controller.authority(), address(guardianSafe), "MetaVesTController's authority should be Guardian SAFE");
        vm.assertEq(controller.dao(), address(guardianSafe), "MetaVesTController's DAO should be Guardian SAFE");
        vm.assertEq(controller.registry(), address(registry), "Unexpected MetaVesTController registry");
        vm.assertEq(controller.vestingFactory(), address(vestingAllocationFactory), "Unexpected MetaVesTController vesting allocation factory");

        // Output logs

        console2.log("Deployer: ", deployer);
        console2.log("salt: ", saltStr);
        console2.log("Guardian Safe: ", address(guardianSafe));
        console2.log("CyberAgreementRegistry: ", address(registry));
        console2.log("VestingAllocationFactory: ", address(vestingAllocationFactory));
        console2.log("");

        console2.log("Deployed addresses:");
        console2.log("  MetavesTController: ", address(controller));
        console2.log("  ZkCappedMinterV2: ", address(zkCappedMinter));
        console2.log("");

        console2.log("Safe TXs:");
        for (uint256 i = 0 ; i < safeTxs.length ; i++) {
            console2.log("  #", i);
            console2.log("    to:", safeTxs[i].to);
            console2.log("    value:", safeTxs[i].value);
            console2.log("    data:");
            console2.logBytes(safeTxs[i].data);
            console2.log("");
        }
    }
}
