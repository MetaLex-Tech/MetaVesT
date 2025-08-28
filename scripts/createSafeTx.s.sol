// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.24;

import {ZkSyncGuardianCompensation2024_2025} from "./lib/ZkSyncGuardianCompensation2024_2025.sol";
import {ZkSyncGuardianCompensation2025_2026} from "./lib/ZkSyncGuardianCompensation2025_2026.sol";
import {ZkSyncGuardianCompensationSepolia2024_2025} from "./lib/ZkSyncGuardianCompensationSepolia2024_2025.sol";
import {ISafeProxyFactory, IGnosisSafe, GnosisTransaction} from "../test/lib/safe.sol";
import {BorgAuth} from "cybercorps-contracts/src/libs/auth.sol";
import {CyberAgreementRegistry} from "cybercorps-contracts/src/CyberAgreementRegistry.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {IZkCappedMinterV2} from "../src/interfaces/zk-governance/IZkCappedMinterV2.sol";
import {SafeTxHelper} from "./lib/SafeTxHelper.sol";
import {Script} from "forge-std/Script.sol";
import {VestingAllocationFactory} from "../src/VestingAllocationFactory.sol";
import {console2} from "forge-std/console2.sol";
import {metavestController} from "../src/MetaVesTController.sol";

contract CreateSafeTxScript is SafeTxHelper, Script {
    /// @dev For running from `forge script`. Provide the deployer private key through env var.
    function run() public virtual {
        IGnosisSafe safe;
        ZkSyncGuardianCompensation2024_2025.Config memory config;
        GnosisTransaction[] memory safeTxs = new GnosisTransaction[](2);

        // zkSync Sepolia
        config = ZkSyncGuardianCompensationSepolia2024_2025.getDefault();
        safe = config.guardianSafe;
        safeTxs[0] = GnosisTransaction({
            to: address(config.registry),
            value: 0 ether,
            data: abi.encodeWithSelector(
                CyberAgreementRegistry.createTemplate.selector,
                config.compTemplateId,
                config.compTemplateName,
                config.compAgreementUri,
                config.compGlobalFields,
                config.compPartyFields
            )
        });
        safeTxs[1] = GnosisTransaction({
            to: address(config.registry),
            value: 0 ether,
            data: abi.encodeWithSelector(
                CyberAgreementRegistry.createTemplate.selector,
                config.serviceTemplateId,
                config.serviceTemplateName,
                config.serviceAgreementUri,
                config.serviceGlobalFields,
                config.servicePartyFields
            )
        });

        // Output logs

        console2.log("");
        console2.log("=== CreateSafeTxScript ===");
        console2.log("Safe: ", address(safe));
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
