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
import {console2} from "forge-std/console2.sol";
import {metavestController} from "../src/MetaVesTController.sol";

contract DeployZkSyncGuardianCompensationScript is ZkSyncGuardianCompConfig, SafeTxHelper, Script {
    // Assume zkSync Era mainnet @ 64166260

    function run() public {
        uint256 deployerPrivateKey = vm.envUint("DEPLOYER_PRIVATE_KEY");
        address deployer = vm.addr(deployerPrivateKey);

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

        // Transfer CyberAgreementRegistry ownership to MetaLeX SAFE

        auth.updateRole(address(metalexSafe), auth.OWNER_ROLE());
        auth.zeroOwner();

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

        // Post-deployment verifications

        auth.onlyRole(auth.OWNER_ROLE(), address(metalexSafe)); // MetaLeX SAFE should own BorgAuth
        vm.assertEq(auth.userRoles(deployer), 0, "deployer should revoke BorgAuth ownership");
        vm.assertEq(address(registry.AUTH()), address(auth), "Unexpected CyberAgreementRegistry auth");

        _assertTemplate(
            registry,
            compTemplateId,
            compAgreementUri,
            compTemplateName,
            compGlobalFields,
            compPartyFields
        );
        _assertTemplate(
            registry,
            serviceTemplateId,
            serviceAgreementUri,
            serviceTemplateName,
            serviceGlobalFields,
            servicePartyFields
        );

        vm.assertEq(controller.authority(), address(guardianSafe), "MetaVesTController's authority should be Guardian SAFE");
        vm.assertEq(controller.dao(), address(guardianSafe), "MetaVesTController's DAO should be Guardian SAFE");
        vm.assertEq(controller.registry(), address(registry), "Unexpected MetaVesTController registry");
        vm.assertEq(controller.vestingFactory(), address(vestingAllocationFactory), "Unexpected MetaVesTController vesting allocation factory");

        vm.assertEq(address(zkCappedMinter.MINTABLE()), address(zkToken), "ZkCappedMinter should mint ZK");
        vm.assertTrue(zkCappedMinter.hasRole(zkCappedMinter.DEFAULT_ADMIN_ROLE(), address(controller)), "MetaVesTController should be the admin of ZkCappedMinter");
        vm.assertEq(zkCappedMinter.CAP(), 1e6 ether, "Unexpected ZkCappedMinter cap");
        vm.assertEq(zkCappedMinter.START_TIME(), 1756684800, "Unexpected ZkCappedMinter start time"); // 2025/09/01 00:00 UTC
        vm.assertEq(zkCappedMinter.EXPIRATION_TIME(), 1756684800 + 365 days * 2, "Unexpected ZkCappedMinter expiry");

        // Output logs

        console2.log("Deployer: ", deployer);
        console2.log("Guardian Safe: ", address(guardianSafe));
        console2.log("ZK token: ", address(zkToken));
        console2.log("ZkCappedMinterFactoryV2: ", address(zkCappedMinterFactory));
        console2.log("");

        console2.log("Deployed addresses:");
        console2.log("  BorgAuth: ", address(auth));
        console2.log("  CyberAgreementRegistry: ", address(registry));
        console2.log("  VestingAllocationFactory: ", address(vestingAllocationFactory));
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

    function _assertTemplate(
        CyberAgreementRegistry registry,
        bytes32 templateId,
        string memory _legalContractUri,
        string memory _title,
        string[] memory _globalFields,
        string[] memory _partyFields
    ) internal {
        (
            string memory legalContractUri,
            string memory title,
            string[] memory globalFields,
            string[] memory partyFields
        ) = registry.getTemplateDetails(templateId);
        vm.assertEq(legalContractUri, _legalContractUri, "Unexpected legalContractUri");
        vm.assertEq(title, _title, "Unexpected template title");
        vm.assertEq(globalFields, _globalFields, "Unexpected template global fields");
        vm.assertEq(partyFields, _partyFields, "Unexpected template party fields");
    }
}
