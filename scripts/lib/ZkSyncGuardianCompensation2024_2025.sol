// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.28;

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

library ZkSyncGuardianCompensation2024_2025 {

    struct Config {

        // ZK Governance

        IZkTokenV1 zkToken;
        IZkCappedMinterV2 zkCappedMinter;

        // zkSync Guardians

        IGnosisSafe guardianSafe;
        MetavestPartyInfo guardianSafeInfoForMetavest;

        // MetaLeX

        IGnosisSafe metalexSafe;
        CyberAgreementRegistry registry;
        VestingAllocationFactory vestingAllocationFactory;
        metavestController controller;

        // zkSync Guardian Compensation Agreement

        string compAgreementUri;
        string compTemplateName;
        bytes32 compTemplateId;
        string[] compGlobalFields;
        string[] compPartyFields;

        MetavestPartyInfo[] guardians;
        uint256 fixedAnnualCompensation;
        uint48 metavestVestingAndUnlockStartTime;
        BaseAllocation.Milestone[] milestones;
    }

    struct MetavestPartyInfo {
        string name;
        address evmAddress;
    }
    
    function getDefault() internal view returns(Config memory) {
        string[] memory compGlobalFields = new string[](11);
        compGlobalFields[0] = "metavestType";
        compGlobalFields[1] = "grantor";
        compGlobalFields[2] = "grantee";
        compGlobalFields[3] = "tokenContract";
        compGlobalFields[4] = "tokenStreamTotal";
        compGlobalFields[5] = "vestingCliffCredit";
        compGlobalFields[6] = "unlockingCliffCredit";
        compGlobalFields[7] = "vestingRate";
        compGlobalFields[8] = "vestingStartTime";
        compGlobalFields[9] = "unlockRate";
        compGlobalFields[10] = "unlockStartTime";

        string[] memory compPartyFields = new string[](2);
        compPartyFields[0] = "name";
        compPartyFields[1] = "evmAddress";

        IGnosisSafe guardianSafe = IGnosisSafe(0x06E19F3CEafBC373329973821ee738021A58F0E3);
        IGnosisSafe metalexSafe = IGnosisSafe(0x99ba28257DbDB399b53bF59Aa5656480f3bdc5bc);

        MetavestPartyInfo[] memory guardians = new MetavestPartyInfo[](0); // TODO TBD

        return Config({

            // ZK Governance

            zkToken: IZkTokenV1(0x5A7d6b2F92C77FAD6CCaBd7EE0624E64907Eaf3E),
            // Vote: https://vote.zknation.io/dao/proposal/14920227315823844313255249182525601975564035647349569740836448589354658768084?govId=eip155:324:0xb83FF6501214ddF40C91C9565d095400f3F45746
            zkCappedMinter: IZkCappedMinterV2(0xE555FC98E45637D1B45e60E4fc05cF0F22836156),

            // zkSync Guardians

            guardianSafe: guardianSafe,
            guardianSafeInfoForMetavest: MetavestPartyInfo({
                name: "Guardian BORG",
                evmAddress: address(guardianSafe)
            }),

            // MetaLeX
        
            metalexSafe: metalexSafe,
            registry: CyberAgreementRegistry(address(0)), // TODO TBD
            vestingAllocationFactory: VestingAllocationFactory(address(0)), // TODO TBD
            controller: metavestController(address(0)), // TODO TBD

            // zkSync Guardian Compensation Agreement

            compAgreementUri: "ipfs://bafybeiangqvqenqkvybrbxu2npv6mlqreunxxygsh3377mpwwjao64qpse", // TODO TBD
            compTemplateName: "zkSync Guardian Compensation Agreement", // TODO TBD
            compTemplateId: bytes32(uint256(200)),
            compGlobalFields: compGlobalFields,
            compPartyFields: compPartyFields,

            guardians: guardians,
            fixedAnnualCompensation: 625e3 ether,
            metavestVestingAndUnlockStartTime: 1725148800, // 2024/09/01 00:00 UTC (means by the deployment @ 2025/09/01 it would've been fully unlocked)
            milestones: new BaseAllocation.Milestone[](0)
        });
    }

    function parseAllocation(Config memory config) internal view returns(BaseAllocation.Allocation memory) {
        return BaseAllocation.Allocation({
            tokenContract: address(config.zkToken),
        // 100k ZK total, the first half unlocks with a cliff and the second half unlocks over an year
            tokenStreamTotal: config.fixedAnnualCompensation,
            vestingCliffCredit: 0e3 ether,
            unlockingCliffCredit: 0e3 ether,
            vestingRate: uint160(config.fixedAnnualCompensation / 365 days),
            vestingStartTime: config.metavestVestingAndUnlockStartTime,
            unlockRate: uint160(config.fixedAnnualCompensation / 365 days),
            unlockStartTime: config.metavestVestingAndUnlockStartTime
        });
    }

    function formatCompGlobalValues(
        Config memory config,
        Vm vm,
        address grantee
    ) internal view returns(string[] memory) {
        BaseAllocation.Allocation memory allocation = parseAllocation(config);

        string[] memory globalValues = new string[](11);
        globalValues[0] = "0"; // metavestType: Vesting
        globalValues[1] = vm.toString(config.guardianSafeInfoForMetavest.evmAddress); // grantor
        globalValues[2] = vm.toString(grantee); // grantee
        globalValues[3] = vm.toString(allocation.tokenContract); // tokenContract
        globalValues[4] = vm.toString(allocation.tokenStreamTotal / 1 ether); //tokenStreamTotal (human-readable)
        globalValues[5] = vm.toString(allocation.vestingCliffCredit / 1 ether); // vestingCliffCredit (human-readable)
        globalValues[6] = vm.toString(allocation.unlockingCliffCredit / 1 ether); // unlockingCliffCredit (human-readable)
        globalValues[7] = vm.toString(config.fixedAnnualCompensation / 1 ether); // vestingRate (annually) (human-readable)
        globalValues[8] = vm.toString(allocation.vestingStartTime); // vestingStartTime
        globalValues[9] = vm.toString(config.fixedAnnualCompensation / 1 ether); // unlockRate (annually) (human-readable)
        globalValues[10] = vm.toString(allocation.unlockStartTime); // unlockStartTime
        return globalValues;
    }

    function formatServiceGlobalValues(Vm vm, uint256 expiry) internal view returns(string[] memory) {
        string[] memory globalValues = new string[](1);
        globalValues[0] = vm.toString(expiry);
        return globalValues;
    }

    function formatMetaVestPartyValues(
        Vm vm,
        MetavestPartyInfo memory partyInfo
    ) internal view returns(string[] memory) {
        string[] memory partyValues = new string[](2);
        partyValues[0] = partyInfo.name;
        partyValues[1] = vm.toString(partyInfo.evmAddress);
        return partyValues;
    }

    function formatMetaVestPartyValues(
        Vm vm,
        MetavestPartyInfo memory guardianSafeInfo,
        MetavestPartyInfo memory guardianInfo
    ) internal view returns(string[][] memory) {
        string[][] memory partyValues = new string[][](2);
        partyValues[0] = formatMetaVestPartyValues(vm, guardianSafeInfo);
        partyValues[1] = formatMetaVestPartyValues(vm, guardianInfo);
        return partyValues;
    }
}
