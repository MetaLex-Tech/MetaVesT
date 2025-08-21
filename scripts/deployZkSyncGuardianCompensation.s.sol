// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.24;

import {ZkSyncGuardianCompConfig} from "./lib/ZkSyncGuardianCompConfig.sol";
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
import {console} from "forge-std/console.sol";
import {metavestController} from "../src/MetaVesTController.sol";

contract DeployZkSyncGuardianCompensationScript is ZkSyncGuardianCompConfig, SafeTxHelper, Script {
    // Assume zkSync Era mainnet @ 64166260

    function run() public {
        uint256 deployerPrivateKey = vm.envUint("DEPLOYER_PRIVATE_KEY");
        address deployer = vm.addr(deployerPrivateKey);

        console.log(deployer.balance);

        bytes32 salt = keccak256("MetaLexMetaVestZkSyncGuardianCompensationLaunchV1.0");

        vm.startBroadcast(deployerPrivateKey);

        // Deploy CyberAgreementRegistry and create templates
        // MetaLeX does not have a CyberAgreementRegistry on zkSync Era yet, so we will deploy it here

        // TODO who should own BorgAuth?
        BorgAuth auth = new BorgAuth{salt: salt}(deployer);
        CyberAgreementRegistry registry = CyberAgreementRegistry(address(new ERC1967Proxy{salt: salt}(
            address(new CyberAgreementRegistry{salt: salt}()),
            abi.encodeWithSelector(
                CyberAgreementRegistry.initialize.selector,
                address(auth)
            )
        )));

        // Create zkSync Guardian Compensation Agreement template
        registry.createTemplate(
            compTemplateId,
            compTemplateName,
            compAgreementUri,
            compGlobalFields,
            compPartyFields
        );

        // Create MetaLeX <> zkSync Guardian BORG Service Agreement template
        registry.createTemplate(
            serviceTemplateId,
            serviceTemplateName,
            serviceAgreementUri,
            serviceGlobalFields,
            servicePartyFields
        );

        // Deploy MetaVesT Controller

        VestingAllocationFactory vestingAllocationFactory = new VestingAllocationFactory{salt: salt}();

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

        // Deploy ZK Capped Minter v2

        ZkCappedMinterV2 zkCappedMinter = ZkCappedMinterV2(zkCappedMinterFactory.createCappedMinter(
            address(zkToken),
            address(controller), // Grant controller admin privilege so it can grant minter privilege to deployed MetaVesT
            cap,
            zkCappedMinterStartTime,
            zkCappedMinterExpirationTime,
            uint256(salt)
        ));

        // Guardian SAFE to set MetaVesT Controller's ZK Capped Minter
        GnosisTransaction[] memory safeTxs = new GnosisTransaction[](1);
        safeTxs[0] = GnosisTransaction({
            to: address(controller),
            value: 0,
            data: abi.encodeWithSelector(
                controller.setZkCappedMinter.selector,
                address(zkCappedMinter)
            )
        });

        vm.stopBroadcast();

        console.log("Deployer: ", deployer);
        console.log("Guardian Safe: ", address(guardianSafe));
        console.log("ZK token: ", address(zkToken));
        console.log("ZkCappedMinterFactoryV2: ", address(zkCappedMinterFactory));
        console.log("");

        console.log("Deployed addresses:");
        console.log("  BorgAuth: ", address(auth));
        console.log("  CyberAgreementRegistry: ", address(registry));
        console.log("  VestingAllocationFactory: ", address(vestingAllocationFactory));
        console.log("  MetavesTController: ", address(controller));
        console.log("  ZkCappedMinterV2: ", address(zkCappedMinter));
        console.log("");

        console.log("Safe TXs:");
        for (uint256 i = 0 ; i < safeTxs.length ; i++) {
            console.log("  #", i);
            console.log("    to:", safeTxs[i].to);
            console.log("    value:", safeTxs[i].value);
            console.log("    data:");
            console.logBytes(safeTxs[i].data);
            console.log("");
        }
    }
}
