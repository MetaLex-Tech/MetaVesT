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
        string[] memory serviceGlobalFields = new string[](1);
        serviceGlobalFields[0] = "expiryDate";

        string[] memory servicePartyFields = new string[](4);
        servicePartyFields[0] = "name";
        servicePartyFields[1] = "evmAddress";
        servicePartyFields[2] = "contactDetails";
        servicePartyFields[3] = "type";

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

        string[] memory compPartyFields = new string[](4);
        compPartyFields[0] = "name";
        compPartyFields[1] = "evmAddress";
        compPartyFields[2] = "contactDetails";
        compPartyFields[3] = "type";

        IGnosisSafe guardianSafe = IGnosisSafe(0x06E19F3CEafBC373329973821ee738021A58F0E3);

        address[] memory guardians = new address[](0); // TODO TBD

        return ZkSyncGuardianCompensation2024_2025.Config({
            zkToken: IZkTokenV1(0x5A7d6b2F92C77FAD6CCaBd7EE0624E64907Eaf3E),
            // Vote: https://vote.zknation.io/dao/proposal/14920227315823844313255249182525601975564035647349569740836448589354658768084?govId=eip155:324:0xb83FF6501214ddF40C91C9565d095400f3F45746
            zkCappedMinter: IZkCappedMinterV2(0x1358F460bD147C4a6BfDaB75aD2B78C837a11D4A),
        
            guardianSafe: guardianSafe,
        
            metalexSafe: IGnosisSafe(0x99ba28257DbDB399b53bF59Aa5656480f3bdc5bc),
            registry: CyberAgreementRegistry(address(0)), // TODO TBD
            vestingAllocationFactory: VestingAllocationFactory(address(0)), // TODO TBD
            controller: metavestController(address(0)), // TODO TBD

            serviceAgreementUri: "ipfs://bafybeiangqvqenqkvybrbxu2npv6mlqreunxxygsh3377mpwwjao64qpse", // TODO TBD
            serviceTemplateName: "MetaLeX <> zkSync Guardian BORG Service Agreement", // TODO TBD
            serviceTemplateId: bytes32(uint256(200)),
            serviceGlobalFields: serviceGlobalFields,
            servicePartyFields: servicePartyFields,

            serviceAgreementExpiry: 1788220800,

            compAgreementUri: "ipfs://bafybeiangqvqenqkvybrbxu2npv6mlqreunxxygsh3377mpwwjao64qpse", // TODO TBD
            compTemplateName: "zkSync Guardian Compensation Agreement", // TODO TBD
            compTemplateId: bytes32(uint256(201)),
            compGlobalFields: compGlobalFields,
            compPartyFields: compPartyFields,

            guardianSafeInfo: ZkSyncGuardianCompensation2024_2025.PartyInfo({ // TODO TBD
                name: "Guardian BORG",
                evmAddress: address(guardianSafe),
                contactDetails: "inbox@guardian.borg",
                _type: "Foundation"
            }),
            guardians: guardians,
            fixedAnnualCompensation: 625e3 ether,
            metavestVestingAndUnlockStartTime: 1756684800, // 2025/09/01 00:00 UTC
            milestones: new BaseAllocation.Milestone[](0)
        });
    }
}
