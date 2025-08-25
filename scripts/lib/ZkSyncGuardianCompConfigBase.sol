// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.28;

import {CommonBase} from "forge-std/Base.sol";
import {ZkCappedMinterV2} from "zk-governance/l2-contracts/src/ZkCappedMinterV2.sol";
import {CyberAgreementRegistry} from "cybercorps-contracts/src/CyberAgreementRegistry.sol";
import {IZkTokenV1} from "../../src/interfaces/zk-governance/IZkTokenV1.sol";
import {IZkCappedMinterV2Factory} from "../../src/interfaces/zk-governance/IZkCappedMinterV2Factory.sol";
import {IGnosisSafe} from "../../test/lib/safe.sol";
import {BaseAllocation} from "../../src/BaseAllocation.sol";
import {VestingAllocationFactory} from "../../src/VestingAllocationFactory.sol";

contract ZkSyncGuardianCompConfigBase is CommonBase {
    // Assume zkSync Era mainnet @ 64202885

    // MetaLeX SAFE

    IGnosisSafe metalexSafe = IGnosisSafe(0x99ba28257DbDB399b53bF59Aa5656480f3bdc5bc);

    // zkSync Guardian SAFE

    IGnosisSafe guardianSafe = IGnosisSafe(0x06E19F3CEafBC373329973821ee738021A58F0E3);

    // ZK Governance

    IZkTokenV1 zkToken = IZkTokenV1(0x5A7d6b2F92C77FAD6CCaBd7EE0624E64907Eaf3E);

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

    BaseAllocation.Milestone[] milestones = new BaseAllocation.Milestone[](0);

    // Vesting parameters (should be overridden by child deploy configs)

    address[] guardians;
    uint256 fixedAnnualCompensation;
    uint48 metavestVestingAndUnlockStartTime;

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

    function _formatGlobalValues(
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

    function _formatPartyValues(
        address grantor,
        address grantee,
        string memory granteeName
    ) internal returns(string[][] memory) {
        // TODO WIP
        string[][] memory partyValues = new string[][](2);
        partyValues[0] = new string[](4);
        partyValues[0][0] = "Guardian BORG";
        partyValues[0][1] = vm.toString(grantor);
        partyValues[0][2] = "inbox@guardian.borg";
        partyValues[0][3] = "Foundation";
        partyValues[1] = new string[](4);
        partyValues[1][0] = granteeName;
        partyValues[1][1] = vm.toString(grantee);
        partyValues[1][2] = "email@company.com";
        partyValues[1][3] = "individual";
        return partyValues;
    }
}
