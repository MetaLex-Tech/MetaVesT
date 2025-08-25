// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.24;

import {ZkSyncGuardianCompConfigBase} from "./lib/ZkSyncGuardianCompConfigBase.sol";
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

contract DeployZkSyncGuardianCompensationPrerequisitesScript is ZkSyncGuardianCompConfigBase, SafeTxHelper, Script {
    // Assume zkSync Era mainnet @ 64166260

    /// @dev For running from `forge script`. Provide the deployer private key through env var.
    function run() public virtual {
        run(vm.envUint("DEPLOYER_PRIVATE_KEY"));
    }

    /// @dev For running in tests
    function run(uint256 deployerPrivateKey) public virtual returns(
        BorgAuth,
        CyberAgreementRegistry,
        VestingAllocationFactory
    ) {
        address deployer = vm.addr(deployerPrivateKey);

        bytes32 salt = keccak256("MetaLexMetaVestZkSyncGuardianCompensationLaunchV1.0");

        vm.startBroadcast(deployerPrivateKey);

        // Deploy CyberAgreementRegistry and create templates
        // MetaLeX does not have a CyberAgreementRegistry on zkSync Era yet, so we will deploy it here

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

        // Deploy MetaVesT pre-requisites

        VestingAllocationFactory vestingAllocationFactory = new VestingAllocationFactory{salt: salt}();

        vm.stopBroadcast();

        // Output logs

        console2.log("Deployer: ", deployer);
        console2.log("Guardian Safe: ", address(guardianSafe));
        console2.log("");

        console2.log("Deployed addresses:");
        console2.log("  BorgAuth: ", address(auth));
        console2.log("  CyberAgreementRegistry: ", address(registry));
        console2.log("  VestingAllocationFactory: ", address(vestingAllocationFactory));

        return (auth, registry, vestingAllocationFactory);
    }
}
