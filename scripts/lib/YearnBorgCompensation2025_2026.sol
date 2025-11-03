// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.28;

import {Vm} from "forge-std/Vm.sol";
import {CommonBase} from "forge-std/Base.sol";
import {CyberAgreementRegistry} from "cybercorps-contracts/src/CyberAgreementRegistry.sol";
import {IGnosisSafe} from "../../test/lib/safe.sol";
import {BaseAllocation} from "../../src/BaseAllocation.sol";
import {metavestController} from "../../src/MetaVesTController.sol";
import {MetaVesTControllerFactory} from "../../src/MetaVesTControllerFactory.sol";

library YearnBorgCompensation2025_2026 {

    struct Config {

        // External dependencies

        address paymentToken; // USDC

        // Yearn BORG

        IGnosisSafe borgSafe;
        PartyInfo borgSafeInfo;
        address borgAgreementDelegate; // Delegate EOA for signing agreement on BORG's behalf

        // MetaLeX

        IGnosisSafe metalexSafe;
        CyberAgreementRegistry registry;
        MetaVesTControllerFactory metavestControllerFactory;
        metavestController controller;

        // Yearn BORG Director Compensation Agreement (one template per director for now)

        CompInfo[] compRecipients;
        uint256 paymentTokenApprovalCap; // Maximum `paymentToken` allowance borgSafe should approve metavestController to spend
        uint256 fixedAnnualCompensation; // Expected annual compensation (in `paymentToken`) per recipient
        uint48 metavestVestingAndUnlockStartTime;
        BaseAllocation.Milestone[] milestones;
    }

    struct TemplateInfo {
        bytes32 id;
        string agreementUri;
        string name;
        string[] globalFields;
        string[] partyFields;
    }

    struct PartyInfo {
        string name;
        address evmAddress;
    }

    struct CompInfo {
        PartyInfo partyInfo;
        TemplateInfo compTemplate;
        bytes signature;
    }
    
    function getDefault(Vm vm) internal view returns(Config memory) {
        IGnosisSafe borgSafe = IGnosisSafe(0xFEB4acf3df3cDEA7399794D0869ef76A6EfAff52);
        IGnosisSafe metalexSafe = IGnosisSafe(0x68Ab3F79622cBe74C9683aA54D7E1BBdCAE8003C);

        return Config({

            // External dependencies

            paymentToken: 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48,
            
            // Yearn BORG

            borgSafe: borgSafe,
            borgSafeInfo: PartyInfo({
                name: "Yearn BORG",
                evmAddress: address(borgSafe)
            }),
            borgAgreementDelegate: 0xDeaDbeefdEAdbeefdEadbEEFdeadbeEFdEaDbeeF, // TODO TBD

            // MetaLeX

            metalexSafe: metalexSafe,
            registry: CyberAgreementRegistry(0xa9E808B8eCBB60Bb19abF026B5b863215BC4c134),
            metavestControllerFactory: MetaVesTControllerFactory(0xDeaDbeefdEAdbeefdEadbEEFdeadbeEFdEaDbeeF), // TODO TBD
            controller: metavestController(0xDeaDbeefdEAdbeefdEadbEEFdeadbeEFdEaDbeeF), // TODO TBD

            // Yearn BORG Compensation Agreement

            compRecipients: loadGuardianAndComps(vm),
            paymentTokenApprovalCap: 5000e6, // 5000 USDC * 1 recipient
            fixedAnnualCompensation: 5000e6, // 5000 USDC
            metavestVestingAndUnlockStartTime: 1756684800, // TODO TBD: for now it is 2025/09/01 00:00 UTC
            milestones: new BaseAllocation.Milestone[](0)
        });
    }

    function loadGuardianAndComps(Vm vm) internal view returns(CompInfo[] memory) {
        uint256 numRecipients = vm.envOr("NUM_RECIPIENTS", uint256(0));

        CompInfo[] memory compRecipients = new CompInfo[](numRecipients);
        for (uint i = 0; i < compRecipients.length ; i++) {
            compRecipients[i] = CompInfo({
                partyInfo: PartyInfo({
                    name: vm.envString(string(abi.encodePacked("RECIPIENT_NAME_", vm.toString(i)))),
                    evmAddress: address(uint160(vm.envUint(string(abi.encodePacked("RECIPIENT_ADDR_", vm.toString(i))))))
                }),
                compTemplate: TemplateInfo({
                    id: bytes32(vm.envUint(string(abi.encodePacked("RECIPIENT_TEMPLATE_ID_", vm.toString(i))))),
                    agreementUri: vm.envString(string(abi.encodePacked("RECIPIENT_AGREEMENT_URI_", vm.toString(i)))),
                    name: vm.envString(string(abi.encodePacked("RECIPIENT_TEMPLATE_NAME_", vm.toString(i)))),
                    globalFields: getCompGlobalFields(),
                    partyFields: getCompPartyFields()
                }),
                signature: vm.envBytes(string(abi.encodePacked("RECIPIENT_SAFE_DELEGATE_SIGNATURE_", vm.toString(i))))
            });
        }
        return compRecipients;
    }

    function parseAllocation(Config memory config) internal view returns(BaseAllocation.Allocation memory) {
        return BaseAllocation.Allocation({
            tokenContract: address(config.paymentToken),
            tokenStreamTotal: config.fixedAnnualCompensation,
            vestingCliffCredit: 0, // assume no cliff
            unlockingCliffCredit: 0, // assume no cliff
            vestingRate: uint160(config.fixedAnnualCompensation / 365 days),
            vestingStartTime: config.metavestVestingAndUnlockStartTime,
            unlockRate: uint160(config.fixedAnnualCompensation / 365 days),
            unlockStartTime: config.metavestVestingAndUnlockStartTime
        });
    }

    function getCompGlobalFields() internal pure returns(string[] memory) {
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
        return compGlobalFields;
    }

    function getCompPartyFields() internal pure returns(string[] memory) {
        string[] memory compPartyFields = new string[](2);
        compPartyFields[0] = "name";
        compPartyFields[1] = "evmAddress";
        return compPartyFields;
    }

    function formatCompGlobalValues(
        Config memory config,
        Vm vm,
        address grantee
    ) internal view returns(string[] memory) {
        BaseAllocation.Allocation memory allocation = parseAllocation(config);

        string[] memory globalValues = new string[](11);
        globalValues[0] = "0"; // metavestType: Vesting
        globalValues[1] = vm.toString(config.borgSafeInfo.evmAddress); // grantor
        globalValues[2] = vm.toString(grantee); // grantee
        globalValues[3] = vm.toString(allocation.tokenContract); // tokenContract
        globalValues[4] = vm.toString(allocation.tokenStreamTotal / 1e6); //tokenStreamTotal (human-readable) (USDC)
        globalValues[5] = vm.toString(allocation.vestingCliffCredit / 1e6); // vestingCliffCredit (human-readable) (USDC)
        globalValues[6] = vm.toString(allocation.unlockingCliffCredit / 1e6); // unlockingCliffCredit (human-readable) (USDC)
        globalValues[7] = vm.toString(config.fixedAnnualCompensation / 1e6); // vestingRate (annually) (human-readable) (USDC)
        globalValues[8] = vm.toString(allocation.vestingStartTime); // vestingStartTime
        globalValues[9] = vm.toString(config.fixedAnnualCompensation / 1e6); // unlockRate (annually) (human-readable) (USDC)
        globalValues[10] = vm.toString(allocation.unlockStartTime); // unlockStartTime
        return globalValues;
    }

    function formatBorgResolutionGlobalValues(Vm vm) internal view returns(string[] memory) {
        return new string[](0);
    }

    function formatPartyValues(
        Vm vm,
        PartyInfo memory partyInfo
    ) internal view returns(string[] memory) {
        string[] memory partyValues = new string[](2);
        partyValues[0] = partyInfo.name;
        partyValues[1] = vm.toString(partyInfo.evmAddress);
        return partyValues;
    }

    function formatPartyValues(
        Vm vm,
        PartyInfo memory borgSafeInfo,
        PartyInfo memory guardianInfo
    ) internal view returns(string[][] memory) {
        string[][] memory partyValues = new string[][](2);
        partyValues[0] = formatPartyValues(vm, borgSafeInfo);
        partyValues[1] = formatPartyValues(vm, guardianInfo);
        return partyValues;
    }
}
