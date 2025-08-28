// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.28;

import {ZkSyncGuardianCompensation2024_2025} from "./ZkSyncGuardianCompensation2024_2025.sol";
import {Vm} from "forge-std/Vm.sol";
import {CommonBase} from "forge-std/Base.sol";
import {ZkCappedMinterV2} from "zk-governance/l2-contracts/src/ZkCappedMinterV2.sol";
import {CyberAgreementRegistry} from "cybercorps-contracts/src/CyberAgreementRegistry.sol";
import {IZkTokenV1} from "../../src/interfaces/zk-governance/IZkTokenV1.sol";
import {IZkCappedMinterV2} from "../../src/interfaces/zk-governance/IZkCappedMinterV2.sol";
import {IGnosisSafe} from "../../test/lib/safe.sol";
import {BaseAllocation} from "../../src/BaseAllocation.sol";
import {VestingAllocationFactory} from "../../src/VestingAllocationFactory.sol";
import {metavestController} from "../../src/MetaVesTController.sol";

library ZkSyncGuardianCompensation2025_2026 {

    function getDefault() internal returns(ZkSyncGuardianCompensation2024_2025.Config memory) {
        ZkSyncGuardianCompensation2024_2025.Config memory defaultConfig = ZkSyncGuardianCompensation2024_2025.getDefault();

        return ZkSyncGuardianCompensation2024_2025.Config({

            // ZK Governance

            zkToken: defaultConfig.zkToken,
            // Vote: https://vote.zknation.io/dao/proposal/14920227315823844313255249182525601975564035647349569740836448589354658768084?govId=eip155:324:0xb83FF6501214ddF40C91C9565d095400f3F45746
            zkCappedMinter: IZkCappedMinterV2(0x1358F460bD147C4a6BfDaB75aD2B78C837a11D4A),

            // zkSync Guardians

            guardianSafe: defaultConfig.guardianSafe,
            guardianSafeInfoForMetavest: defaultConfig.guardianSafeInfoForMetavest,

            // MetaLeX

            metalexSafe: defaultConfig.metalexSafe,
            registry: defaultConfig.registry,
            vestingAllocationFactory: defaultConfig.vestingAllocationFactory,
            controller: defaultConfig.controller,

            // zkSync Guardian Compensation Agreement

            compAgreementUri: defaultConfig.compAgreementUri,
            compTemplateName: defaultConfig.compTemplateName,
            compTemplateId: defaultConfig.compTemplateId,
            compGlobalFields: defaultConfig.compGlobalFields,
            compPartyFields: defaultConfig.compPartyFields,

            guardians: defaultConfig.guardians,
            fixedAnnualCompensation: 625e3 ether,
            metavestVestingAndUnlockStartTime: 1756684800, // 2025/09/01 00:00 UTC
            milestones: defaultConfig.milestones
        });
    }
}
