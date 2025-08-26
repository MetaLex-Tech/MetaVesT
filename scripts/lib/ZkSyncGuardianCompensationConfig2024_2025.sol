// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.28;

import {ZkSyncGuardianCompensationConfigBase} from "./ZkSyncGuardianCompensationConfigBase.sol";
import {CommonBase} from "forge-std/Base.sol";
import {ZkCappedMinterV2} from "zk-governance/l2-contracts/src/ZkCappedMinterV2.sol";
import {CyberAgreementRegistry} from "cybercorps-contracts/src/CyberAgreementRegistry.sol";
import {IZkCappedMinterV2} from "../../src/interfaces/zk-governance/IZkCappedMinterV2.sol";
import {IGnosisSafe} from "../../test/lib/safe.sol";
import {BaseAllocation} from "../../src/BaseAllocation.sol";
import {VestingAllocationFactory} from "../../src/VestingAllocationFactory.sol";
import {metavestController} from "../../src/MetaVesTController.sol";

contract ZkSyncGuardianCompensationConfig2024_2025 is ZkSyncGuardianCompensationConfigBase {
    // ZK Governance
    // Vote: https://vote.zknation.io/dao/proposal/14920227315823844313255249182525601975564035647349569740836448589354658768084?govId=eip155:324:0xb83FF6501214ddF40C91C9565d095400f3F45746
    IZkCappedMinterV2 zkCappedMinter = IZkCappedMinterV2(0xE555FC98E45637D1B45e60E4fc05cF0F22836156);

    // MetaLeX <> zkSync Guardian BORG Service Agreement template

    string serviceAgreementUri = "ipfs://bafybeiangqvqenqkvybrbxu2npv6mlqreunxxygsh3377mpwwjao64qpse"; // TODO WIP
    string serviceTemplateName = "MetaLeX <> zkSync Guardian BORG Service Agreement"; // TODO WIP
    bytes32 serviceTemplateId = bytes32(uint256(200)); // TODO TBD

    string[] serviceGlobalFields;
    string[] servicePartyFields;

    // zkSync Guardian Compensation Agreement template

    string compAgreementUri = "ipfs://bafybeiangqvqenqkvybrbxu2npv6mlqreunxxygsh3377mpwwjao64qpse"; // TODO WIP
    string compTemplateName = "zkSync Guardian Compensation Agreement"; // TODO WIP
    bytes32 compTemplateId = bytes32(uint256(201)); // TODO TBD

    string[] compGlobalFields;
    string[] compPartyFields;

    // MetaLeX <> zkSync Guardian BORG Service Agreement parameters
    uint256 serviceAgreementExpiry = 1788220800;

    // Vesting parameters
    
    // TODO TBD
    PartyInfo guardianSafeInfo = PartyInfo({
        name: "Guardian BORG",
        evmAddress: address(guardianSafe),
        contactDetails: "inbox@guardian.borg",
        _type: "Foundation"
    });

    address[] guardians;
    uint256 fixedAnnualCompensation = 625e3 ether;
    uint48 metavestVestingAndUnlockStartTime = 1725148800; // 2024/09/01 00:00 UTC (means by the deployment @ 2025/09/01 it would've been fully unlocked)
    BaseAllocation.Milestone[] milestones = new BaseAllocation.Milestone[](0);

    // Deployments

    metavestController controller = metavestController(address(0)); // TODO TBD

    // Support data structures
    
    struct PartyInfo {
        string name;
        address evmAddress;
        string contactDetails;
        string _type;
    }

    constructor() {
        // zkSync Guardian Compensation Agreement template

        compGlobalFields = new string[](11);
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

        compPartyFields = new string[](4);
        compPartyFields[0] = "name";
        compPartyFields[1] = "evmAddress";
        compPartyFields[2] = "contactDetails";
        compPartyFields[3] = "type";

        // MetaLeX <> zkSync Guardian BORG Service Agreement template

        serviceGlobalFields = new string[](1);
        serviceGlobalFields[0] = "expiryDate";

        servicePartyFields = new string[](4);
        servicePartyFields[0] = "name";
        servicePartyFields[1] = "evmAddress";
        servicePartyFields[2] = "contactDetails";
        servicePartyFields[3] = "type";

        // Vesting parameters

        guardians = new address[](6);
        guardians[0] = 0xDeaDbeefdEAdbeefdEadbEEFdeadbeEFdEaDbeeF; // TODO TBD
        guardians[1] = 0xDeaDbeefdEAdbeefdEadbEEFdeadbeEFdEaDbeeF; // TODO TBD
        guardians[2] = 0xDeaDbeefdEAdbeefdEadbEEFdeadbeEFdEaDbeeF; // TODO TBD
        guardians[3] = 0xDeaDbeefdEAdbeefdEadbEEFdeadbeEFdEaDbeeF; // TODO TBD
        guardians[4] = 0xDeaDbeefdEAdbeefdEadbEEFdeadbeEFdEaDbeeF; // TODO TBD
        guardians[5] = 0xDeaDbeefdEAdbeefdEadbEEFdeadbeEFdEaDbeeF; // TODO TBD
    }

    function _parseAllocation(address token, uint48 startTime) internal returns(BaseAllocation.Allocation memory) {
        return BaseAllocation.Allocation({
            tokenContract: token,
        // 100k ZK total, the first half unlocks with a cliff and the second half unlocks over an year
            tokenStreamTotal: fixedAnnualCompensation,
            vestingCliffCredit: 0e3 ether,
            unlockingCliffCredit: 0e3 ether,
            vestingRate: uint160(fixedAnnualCompensation / 365 days),
            vestingStartTime: startTime, // start along with capped minter
            unlockRate: uint160(fixedAnnualCompensation / 365 days),
            unlockStartTime: startTime // start along with capped minter
        });
    }

    function _compFormatGlobalValues(
        address grantor,
        address grantee,
        address token,
        uint48 startTime
    ) internal returns(string[] memory) {
        BaseAllocation.Allocation memory allocation = _parseAllocation(token, startTime);

        string[] memory globalValues = new string[](11);
        globalValues[0] = "0"; // metavestType: Vesting
        globalValues[1] = vm.toString(grantor); // grantor
        globalValues[2] = vm.toString(grantee); // grantee
        globalValues[3] = vm.toString(allocation.tokenContract); // tokenContract
        globalValues[4] = vm.toString(allocation.tokenStreamTotal / 1 ether); //tokenStreamTotal (human-readable)
        globalValues[5] = vm.toString(allocation.vestingCliffCredit / 1 ether); // vestingCliffCredit (human-readable)
        globalValues[6] = vm.toString(allocation.unlockingCliffCredit / 1 ether); // unlockingCliffCredit (human-readable)
        globalValues[7] = vm.toString(fixedAnnualCompensation / 1 ether); // vestingRate (annually) (human-readable)
        globalValues[8] = vm.toString(allocation.vestingStartTime); // vestingStartTime
        globalValues[9] = vm.toString(fixedAnnualCompensation / 1 ether); // unlockRate (annually) (human-readable)
        globalValues[10] = vm.toString(allocation.unlockStartTime); // unlockStartTime
        return globalValues;
    }

    function _compFormatPartyValues(
        PartyInfo memory partyInfo
    ) internal returns(string[] memory) {
        string[] memory partyValues = new string[](4);
        partyValues[0] = partyInfo.name;
        partyValues[1] = vm.toString(partyInfo.evmAddress);
        partyValues[2] = partyInfo.contactDetails;
        partyValues[3] = partyInfo._type;
        return partyValues;
    }

    function _compFormatPartyValues(
        PartyInfo memory guardianSafeInfo,
        PartyInfo memory guardianInfo
    ) internal returns(string[][] memory) {
        string[][] memory partyValues = new string[][](2);
        partyValues[0] = _compFormatPartyValues(guardianSafeInfo);
        partyValues[1] = _compFormatPartyValues(guardianInfo);
        return partyValues;
    }

    function _serviceFormatGlobalValues(uint256 expiry) internal returns(string[] memory) {
        string[] memory globalValues = new string[](1);
        globalValues[0] = vm.toString(expiry);
        return globalValues;
    }

    function _serviceFormatPartyValues(
        address metalex,
        address guardianBorg
    ) internal returns(string[][] memory) {
        string[][] memory partyValues = new string[][](2);
        partyValues[0] = new string[](4);
        partyValues[0][0] = "MetaLeX";
        partyValues[0][1] = vm.toString(metalex);
        partyValues[0][2] = "test@metalex.tech";
        partyValues[0][3] = "Corporation";
        partyValues[1] = new string[](4);
        partyValues[1][0] = "Guardian BORG";
        partyValues[1][1] = vm.toString(guardianBorg);
        partyValues[1][2] = "inbox@guardian.borg";
        partyValues[1][3] = "Foundation";
        return partyValues;
    }
}
