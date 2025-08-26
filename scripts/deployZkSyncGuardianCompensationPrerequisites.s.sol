// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.24;

import {ZkSyncGuardianCompensation2024_2025} from "./lib/ZkSyncGuardianCompensation2024_2025.sol";
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

contract DeployZkSyncGuardianCompensationPrerequisitesScript is SafeTxHelper, Script {
    using ZkSyncGuardianCompensation2024_2025 for ZkSyncGuardianCompensation2024_2025.Config;

    /// @dev For running from `forge script`. Provide the deployer private key through env var.
    function run() public virtual {
        deployPrerequisites(
            "MetaLexMetaVestZkSyncGuardianCompensationLaunchV1.0",
            vm.envUint("DEPLOYER_PRIVATE_KEY"),
            ZkSyncGuardianCompensation2024_2025.getDefault()
        );
    }

    /// @dev For running in tests
    function deployPrerequisites(
        string memory saltStr,
        uint256 deployerPrivateKey,
        ZkSyncGuardianCompensation2024_2025.Config memory config
    ) public virtual returns(
        BorgAuth,
        CyberAgreementRegistry,
        VestingAllocationFactory
    ) {
        address deployer = vm.addr(deployerPrivateKey);

        console2.log("");
        console2.log("=== DeployZkSyncGuardianCompensationPrerequisitesScript ===");
        console2.log("Deployer: ", deployer);
        console2.log("Salt string: ", saltStr);
        console2.log("Guardian Safe: ", address(config.guardianSafe));
        console2.log("");

        bytes32 salt = keccak256(bytes(saltStr));

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
            config.compTemplateId,
            config.compTemplateName,
            config.compAgreementUri,
            config.compGlobalFields,
            config.compPartyFields
        );

        // Create MetaLeX <> zkSync Guardian BORG Service Agreement template
        registry.createTemplate(
            config.serviceTemplateId,
            config.serviceTemplateName,
            config.serviceAgreementUri,
            config.serviceGlobalFields,
            config.servicePartyFields
        );

        // Transfer CyberAgreementRegistry ownership to MetaLeX SAFE

        auth.updateRole(address(config.metalexSafe), auth.OWNER_ROLE());
        auth.zeroOwner();

        // Deploy MetaVesT pre-requisites

        VestingAllocationFactory vestingAllocationFactory = new VestingAllocationFactory{salt: salt}();

        vm.stopBroadcast();

        // Output logs

        console2.log("Deployed addresses:");
        console2.log("  BorgAuth: ", address(auth));
        console2.log("  CyberAgreementRegistry: ", address(registry));
        console2.log("  VestingAllocationFactory: ", address(vestingAllocationFactory));
        console2.log("");

        return (auth, registry, vestingAllocationFactory);
    }
}
