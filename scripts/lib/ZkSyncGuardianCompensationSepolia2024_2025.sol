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

library ZkSyncGuardianCompensationSepolia2024_2025 {

    function getDefault() internal returns(ZkSyncGuardianCompensation2024_2025.Config memory) {
        ZkSyncGuardianCompensation2024_2025.Config memory defaultConfig = ZkSyncGuardianCompensation2024_2025.getDefault();

        IGnosisSafe guardianSafe = IGnosisSafe(0x3C785F96864002eB47bDe32d597476a3D97fCd15);
        IGnosisSafe metalexSafe = IGnosisSafe(0x8E9603BcB5D974Ed9C870510F3665F67CE5c5bDe); // This is faked by EOA

        ZkSyncGuardianCompensation2024_2025.PartyInfo[] memory guardians = new ZkSyncGuardianCompensation2024_2025.PartyInfo[](2);
        guardians[0] = ZkSyncGuardianCompensation2024_2025.PartyInfo({
            name: "Alice",
            evmAddress: 0x48d206948C366396a86A449DdD085FDbfC280B4b
        });
        guardians[1] = ZkSyncGuardianCompensation2024_2025.PartyInfo({
            name: "Bob",
            evmAddress: 0x8E9603BcB5D974Ed9C870510F3665F67CE5c5bDe
        });

        return ZkSyncGuardianCompensation2024_2025.Config({

            // ZK Governance
    
            zkToken: IZkTokenV1(0x384278020767ed975618b94DA36EC54Da362812A),
            zkCappedMinter: IZkCappedMinterV2(0x6F26e588f28bf67C016EEA19CA90c4E41B70d499),

            // zkSync Guardians

            guardianSafe: guardianSafe,
            guardianSafeInfo: ZkSyncGuardianCompensation2024_2025.PartyInfo({
                name: defaultConfig.guardianSafeInfo.name,
                evmAddress: address(guardianSafe)
            }),

            // MetaLeX

            metalexSafe: metalexSafe,
            registry: CyberAgreementRegistry(0x7BD5EBE57e64AA6D9904caE90A192E76d818b49e),
            vestingAllocationFactory: VestingAllocationFactory(0x3fFd990dB0E398235456A720501E6007003a6cdf),
            controller: metavestController(0x856A8Aea8a37A338e2490384Bb790cD87b5CaaE4),

            // zkSync Guardian BORG Resolution

            borgResolutionUri: defaultConfig.borgResolutionUri,
            borgResolutionTemplateName: defaultConfig.borgResolutionTemplateName,
            borgResolutionTemplateId: bytes32(uint256(206)),
            borgResolutionGlobalFields: defaultConfig.borgResolutionGlobalFields,
            borgResolutionPartyFields: defaultConfig.borgResolutionPartyFields,

            // zkSync Guardian Compensation Agreement

            compAgreementUri: defaultConfig.compAgreementUri,
            compTemplateName: defaultConfig.compTemplateName,
            compTemplateId: bytes32(uint256(207)),
            compGlobalFields: defaultConfig.compGlobalFields,
            compPartyFields: defaultConfig.compPartyFields,

            guardians: guardians,
            fixedAnnualCompensation: defaultConfig.fixedAnnualCompensation,
            metavestVestingAndUnlockStartTime: defaultConfig.metavestVestingAndUnlockStartTime,
            milestones: defaultConfig.milestones
        });
    }
}
