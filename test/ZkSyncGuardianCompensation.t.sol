// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.20;

import "../src/MetaVesTController.sol";
import "../src/VestingAllocationFactory.sol";
import "../src/interfaces/zk-governance/IZkCappedMinterV2.sol";
import "../src/interfaces/zk-governance/IZkTokenV1.sol";
import "./lib/MetaVesTControllerTestBase.sol";
import {Test} from "forge-std/Test.sol";
import {console2} from "forge-std/console2.sol";
import {CyberAgreementRegistry} from "cybercorps-contracts/src/CyberAgreementRegistry.sol";
import {DeployZkSyncGuardianCompensationPrerequisitesScript} from "../scripts/deployZkSyncGuardianCompensationPrerequisites.s.sol";
import {DeployZkSyncGuardianCompensation2024_2025Script} from "../scripts/deployZkSyncGuardianCompensation2024_2025.s.sol";
import {GnosisTransaction} from "./lib/safe.sol";

// Test by forge test --zksync --via-ir
contract ZkSyncGuardianCompensationTest is
    DeployZkSyncGuardianCompensationPrerequisitesScript,
    DeployZkSyncGuardianCompensation2024_2025Script,
    Test
{
    // zkSync Era mainnet @ 63631890
    address zkTokenAdmin = 0xe5d21A9179CA2E1F0F327d598D464CcF60d89c3d;

    // Randomly generated to avoid contaminated common test address
    uint256 privateKeySalt = 0x4425fdf88097e51c669a66d392c4019ad555544e966908af6ee3cec32f53ab77;

    uint256 deployerPrivateKey = privateKeySalt + 0;
    address deployer = vm.addr(deployerPrivateKey);
    uint256 delegatePrivateKey = privateKeySalt + 1;
    address delegate = vm.addr(delegatePrivateKey);
    uint256 alicePrivateKey = privateKeySalt + 2;
    address alice = vm.addr(alicePrivateKey);
    uint256 bobPrivateKey = privateKeySalt + 3;
    address bob = vm.addr(bobPrivateKey);
    uint256 chadPrivateKey = privateKeySalt + 4;
    address chad = vm.addr(chadPrivateKey);

    IZkCappedMinterV2 masterMinter;

    BorgAuth auth;
    metavestController controller;

    function setUp() public {
        deal(deployer, 1 ether);

        // Run deploy scripts
        GnosisTransaction[] memory safeTxs;
        (auth, registry, vestingAllocationFactory) = DeployZkSyncGuardianCompensationPrerequisitesScript.run(deployerPrivateKey);
        (controller, safeTxs) = DeployZkSyncGuardianCompensation2024_2025Script.run(deployerPrivateKey, registry, vestingAllocationFactory);

        // Simulate Guardian SAFE to execute txs as instructed
        for (uint256 i = 0; i < safeTxs.length; i++) {
            vm.prank(address(guardianSafe));
            (safeTxs[i].to).call{value: safeTxs[i].value}(safeTxs[i].data);
        }

        // Simulate vote pass (https://vote.zknation.io/dao/proposal/14920227315823844313255249182525601975564035647349569740836448589354658768084?govId=eip155:324:0xb83FF6501214ddF40C91C9565d095400f3F45746)

        vm.startPrank(zkTokenAdmin);

        masterMinter = IZkCappedMinterV2(zkCappedMinter.MINTABLE());
        masterMinter.grantRole(masterMinter.MINTER_ROLE(), address(zkCappedMinter));

        IZkCappedMinterV2 grandMasterMinter = IZkCappedMinterV2(masterMinter.MINTABLE());
        grandMasterMinter.grantRole(grandMasterMinter.MINTER_ROLE(), address(masterMinter));

        vm.stopPrank();
    }

    function run() public override(
        DeployZkSyncGuardianCompensationPrerequisitesScript,
        DeployZkSyncGuardianCompensation2024_2025Script
    ) {
        // No-op, we don't use this part of the scripts
    }

    function test_metadata() public {
        // ZK governance pre-requisites

        assertTrue(masterMinter.hasRole(masterMinter.MINTER_ROLE(), address(zkCappedMinter)), "Master Minter should grant this year's ZK Capped Minter access");

        // MetaVesT pre-requisites

        auth.onlyRole(auth.OWNER_ROLE(), address(metalexSafe)); // MetaLeX SAFE should own BorgAuth
        vm.assertEq(auth.userRoles(deployer), 0, "deployer should revoke BorgAuth ownership");
        vm.assertEq(address(registry.AUTH()), address(auth), "Unexpected CyberAgreementRegistry auth");

        _assertTemplate(
            registry,
            compTemplateId,
            compAgreementUri,
            compTemplateName,
            compGlobalFields,
            compPartyFields
        );
        _assertTemplate(
            registry,
            serviceTemplateId,
            serviceAgreementUri,
            serviceTemplateName,
            serviceGlobalFields,
            servicePartyFields
        );

        // MetaVesT deployments

        vm.assertEq(controller.authority(), address(guardianSafe), "MetaVesTController's authority should be Guardian SAFE");
        vm.assertEq(controller.dao(), address(guardianSafe), "MetaVesTController's DAO should be Guardian SAFE");
        vm.assertEq(controller.registry(), address(registry), "Unexpected MetaVesTController registry");
        vm.assertEq(controller.vestingFactory(), address(vestingAllocationFactory), "Unexpected MetaVesTController vesting allocation factory");
        vm.assertEq(controller.zkCappedMinter(), address(zkCappedMinter), "MetaVesTController should have ZK Capped Minter should set");
        vm.assertTrue(zkCappedMinter.hasRole(zkCappedMinter.MINTER_ROLE(), address(controller)), "ZK Capped Minter should grant MetaVesTController MINTER role");
    }

    function test_GuardianCompensation() public {
        (address metavestAddressAlice, address metavestAddressBob) = _guardiansSignAndTppPass();

        VestingAllocation vestingAllocationAlice = VestingAllocation(metavestAddressAlice);
        VestingAllocation vestingAllocationBob = VestingAllocation(metavestAddressBob);

        // Grantee should be able to withdraw all on 2025/09/01 because this compensation is for 2024~2025
        vm.warp(1756684800 + 1); // 2025/09/01 00:00 UTC with some margin for precision error

        console2.log("alice amount withdrawable: %d", vestingAllocationAlice.getAmountWithdrawable());
        _granteeWithdrawAndAsserts(zkToken, zkCappedMinter, vestingAllocationAlice, 625e3 ether, "Alice full");
        _granteeWithdrawAndAsserts(zkToken, zkCappedMinter, vestingAllocationBob, 615e3 ether, "Bob partial");

        // Grantees should be able to withdraw within the grace period (set by ZK Capped Minter expiry)
        skip(60 days);

        _granteeWithdrawAndAsserts(zkToken, zkCappedMinter, vestingAllocationBob, 10e3 ether, "Bob remaining");
    }

    function test_AdminToolingCompensation() public {
        (address metavestAddressAlice, address metavestAddressBob) = _guardiansSignAndTppPass();
        VestingAllocation vestingAllocationAlice = VestingAllocation(metavestAddressAlice);

        // Vesting starts and a month has passed
        vm.warp(1756684800 + 1); // 2025/09/01 00:00 UTC with some margin for precision error

        _granteeWithdrawAndAsserts(zkToken, zkCappedMinter, vestingAllocationAlice, 300e3 ether, "Alice partial");

        // A month has passed
        skip(30 days);

        // Add new grantee for admin/tooling compensation

        // Guardian SAFE to delegate signing to an EOA
        vm.prank(address(guardianSafe));
        registry.setDelegation(delegate, block.timestamp + 60);
        assertTrue(registry.isValidDelegate(address(guardianSafe), delegate), "delegate should be Guardian SAFE's delegate");

        bytes32 contractIdChad = _proposeAndSignDeal(
            registry,
            controller,
            compTemplateId,
            block.timestamp, // salt
            delegatePrivateKey,
            chad,
            BaseAllocation.Allocation({
                tokenContract: address(zkToken),
                // 10k ZK total in one cliff
                tokenStreamTotal: 10e3 ether,
                vestingCliffCredit: 10e3 ether,
                unlockingCliffCredit: 10e3 ether,
                vestingRate: 0,
                vestingStartTime: 0,
                unlockRate: 0,
                unlockStartTime: 0
            }),
            new BaseAllocation.Milestone[](0),
            "Chad",
            block.timestamp + 60
        );
        VestingAllocation vestingAllocationChad = VestingAllocation(_granteeSignDeal(
            registry,
            controller,
            contractIdChad,
            chad, // grantee
            chad, // recipient
            chadPrivateKey,
            "Chad"
        ));
        _granteeWithdrawAndAsserts(zkToken, zkCappedMinter, vestingAllocationChad, 10e3 ether, "Chad cliff");
    }

    function _guardiansSignAndTppPass() internal returns(address, address) {
        // Guardian SAFE to delegate signing to an EOA
        vm.prank(address(guardianSafe));
        registry.setDelegation(delegate, block.timestamp + 60);
        assertTrue(registry.isValidDelegate(address(guardianSafe), delegate), "delegate should be Guardian SAFE's delegate");

        // Guardian SAFE to propose deals on MetaVesTController

        // TODO revise it to fit actual numbers
        bytes32 contractIdAlice = _proposeAndSignDeal(
            registry,
            controller,
            compTemplateId,
            block.timestamp, // salt
            delegatePrivateKey,
            alice,
            BaseAllocation.Allocation({
                tokenContract: address(zkToken),
            // 100k ZK total, the first half unlocks with a cliff and the second half unlocks over an year
                tokenStreamTotal: 625e3 ether,
                vestingCliffCredit: 0e3 ether,
                unlockingCliffCredit: 0e3 ether,
                vestingRate: uint160(625e3 ether) / 365 days,
                vestingStartTime: metavestVestingAndUnlockStartTime,
                unlockRate: uint160(625e3 ether) / 365 days,
                unlockStartTime: metavestVestingAndUnlockStartTime
            }),
            new BaseAllocation.Milestone[](0),
            "Alice",
            block.timestamp + 7 days
        );

        bytes32 contractIdBob = _proposeAndSignDeal(
            registry,
            controller,
            compTemplateId,
            block.timestamp, // salt
            delegatePrivateKey,
            bob,
            BaseAllocation.Allocation({
                tokenContract: address(zkToken),
            // 80k ZK total, the first half unlocks with a cliff and the second half unlocks over an year
                tokenStreamTotal: 625e3 ether,
                vestingCliffCredit: 0e3 ether,
                unlockingCliffCredit: 0e3 ether,
                vestingRate: uint160(625e3 ether) / 365 days,
                vestingStartTime: metavestVestingAndUnlockStartTime,
                unlockRate: uint160(625e3 ether) / 365 days,
                unlockStartTime: metavestVestingAndUnlockStartTime
            }),
            new BaseAllocation.Milestone[](0),
            "Bob",
            block.timestamp + 7 days
        );

        // Guardians to sign agreements

        address metavestAlice = _granteeSignDeal(
            registry,
            controller,
            contractIdAlice,
            alice, // grantee
            alice, // recipient
            alicePrivateKey,
            "Alice"
        );

        address metavestBob = _granteeSignDeal(
            registry,
            controller,
            contractIdBob,
            bob, // grantee
            bob, // recipient
            bobPrivateKey,
            "Bob"
        );

        return (metavestAlice, metavestBob);
    }

    function _assertTemplate(
        CyberAgreementRegistry registry,
        bytes32 templateId,
        string memory _legalContractUri,
        string memory _title,
        string[] memory _globalFields,
        string[] memory _partyFields
    ) internal {
        (
            string memory legalContractUri,
            string memory title,
            string[] memory globalFields,
            string[] memory partyFields
        ) = registry.getTemplateDetails(templateId);
        vm.assertEq(legalContractUri, _legalContractUri, "Unexpected legalContractUri");
        vm.assertEq(title, _title, "Unexpected template title");
        vm.assertEq(globalFields, _globalFields, "Unexpected template global fields");
        vm.assertEq(partyFields, _partyFields, "Unexpected template party fields");
    }

    function _granteeWithdrawAndAsserts(IZkTokenV1 zkToken, IZkCappedMinterV2 zkCappedMinter, VestingAllocation vestingAllocation, uint256 amount, string memory assertName) internal {
        address grantee = vestingAllocation.grantee();
        uint256 balanceBefore = zkToken.balanceOf(grantee);

        vm.prank(grantee);
        vm.expectEmit(true, true, true, true);
        emit metavestController.MetaVesTController_Minted(address(vestingAllocation), grantee, address(zkCappedMinter), amount);
        vestingAllocation.withdraw(amount);

        assertEq(zkToken.balanceOf(grantee), balanceBefore + amount, string(abi.encodePacked(assertName, ": unexpected received amount")));
        assertEq(zkToken.balanceOf(address(vestingAllocation)), 0, string(abi.encodePacked(assertName, ": vesting contract should not have any token (it mints on-demand)")));
    }

    function _proposeAndSignDeal(
        CyberAgreementRegistry registry,
        metavestController controller,
        bytes32 templateId,
        uint256 agreementSalt,
        uint256 grantorOrDelegatePrivateKey,
        address grantee,
        BaseAllocation.Allocation memory allocation,
        BaseAllocation.Milestone[] memory milestones,
        string memory partyName,
        uint256 expiry
    ) internal returns(bytes32) {
        return _proposeAndSignDeal(
            registry, controller, templateId, agreementSalt, grantorOrDelegatePrivateKey, grantee, allocation, milestones, partyName, expiry,
            "" // Not expecting revert
        );
    }

    function _proposeAndSignDeal(
        CyberAgreementRegistry registry,
        metavestController controller,
        bytes32 templateId,
        uint256 agreementSalt,
        uint256 grantorOrDelegatePrivateKey,
        address grantee,
        BaseAllocation.Allocation memory allocation,
        BaseAllocation.Milestone[] memory milestones,
        string memory partyName,
        uint256 expiry,
        bytes memory expectRevertData
    ) internal returns(bytes32) {
        string[] memory globalValues = new string[](11);
        globalValues[0] = "0"; // metavestType: Vesting
        globalValues[1] = vm.toString(address(guardianSafe)); // grantor
        globalValues[2] = vm.toString(grantee); // grantee
        globalValues[3] = vm.toString(allocation.tokenContract); // tokenContract
        globalValues[4] = vm.toString(allocation.tokenStreamTotal / 1 ether); //tokenStreamTotal (human-readable)
        globalValues[5] = vm.toString(allocation.vestingCliffCredit / 1 ether); // vestingCliffCredit (human-readable)
        globalValues[6] = vm.toString(allocation.unlockingCliffCredit / 1 ether); // unlockingCliffCredit (human-readable)
        globalValues[7] = vm.toString(allocation.vestingRate * 365 days / 1 ether); // vestingRate (annually) (human-readable)
        globalValues[8] = vm.toString(allocation.vestingStartTime); // vestingStartTime
        globalValues[9] = vm.toString(allocation.unlockRate * 365 days / 1 ether); // unlockRate (annually) (human-readable)
        globalValues[10] = vm.toString(allocation.unlockStartTime); // unlockStartTime

        // TODO what to do with milestones, which could be of dynamic lengths

        string[][] memory partyValues = new string[][](2);
        partyValues[0] = new string[](4);
        partyValues[0][0] = "Guardian BORG";
        partyValues[0][1] = vm.toString(address(guardianSafe));
        partyValues[0][2] = "guardian-safe@company.com";
        partyValues[0][3] = "Foundation";
        partyValues[1] = new string[](4);
        partyValues[1][0] = partyName;
        partyValues[1][1] = vm.toString(grantee); // evmAddress
        partyValues[1][2] = "email@company.com";
        partyValues[1][3] = "individual";

        address[] memory parties = new address[](2);
        parties[0] = address(guardianSafe);
        parties[1] = grantee;
        bytes32 expectedContractId = keccak256(
            abi.encode(
                templateId,
                agreementSalt,
                globalValues,
                parties
            )
        );

        bytes memory signature = CyberAgreementUtils.signAgreementTypedData(
            vm,
            registry.DOMAIN_SEPARATOR(),
            registry.SIGNATUREDATA_TYPEHASH(),
            expectedContractId,
            compAgreementUri,
            compGlobalFields,
            compPartyFields,
            globalValues,
            partyValues[0],
            grantorOrDelegatePrivateKey
        );

        if (expectRevertData.length > 0) {
            vm.expectRevert(expectRevertData);
        }
        bytes32 contractId = controller.proposeAndSignDeal(
            templateId,
            agreementSalt,
            metavestController.metavestType.Vesting,
            grantee,
            allocation,
            milestones,
            globalValues,
            parties,
            partyValues,
            signature,
            bytes32(0), // no secrets
            expiry
        );

        if (expectRevertData.length == 0) {
            assertEq(contractId, expectedContractId, "Unexpected contract ID");
            return contractId;
        } else {
            return 0;
        }
    }

    function _granteeSignDeal(
        CyberAgreementRegistry registry,
        metavestController controller,
        bytes32 contractId,
        address grantee,
        address recipient,
        uint256 granteePrivateKey,
        string memory partyName
    ) internal returns(address) {
        return _granteeSignDeal(
            registry, controller, contractId, grantee, recipient, granteePrivateKey, partyName,
            "" // Not expecting revert
        );
    }

    function _granteeSignDeal(
        CyberAgreementRegistry registry,
        metavestController controller,
        bytes32 contractId,
        address grantee,
        address recipient,
        uint256 granteePrivateKey,
        string memory partyName,
        bytes memory expectRevertData
    ) internal returns(address) {
        metavestController.DealData memory deal = controller.getDeal(contractId);

        string[] memory globalValues = new string[](11);
        globalValues[0] = "0"; // metavestType: Vesting
        globalValues[1] = vm.toString(address(guardianSafe)); // grantor
        globalValues[2] = vm.toString(grantee); // grantee
        globalValues[3] = vm.toString(deal.allocation.tokenContract); // tokenContract
        globalValues[4] = vm.toString(deal.allocation.tokenStreamTotal / 1 ether); //tokenStreamTotal (human-readable)
        globalValues[5] = vm.toString(deal.allocation.vestingCliffCredit / 1 ether); // vestingCliffCredit (human-readable)
        globalValues[6] = vm.toString(deal.allocation.unlockingCliffCredit / 1 ether); // unlockingCliffCredit (human-readable)
        globalValues[7] = vm.toString(deal.allocation.vestingRate * 365 days / 1 ether); // vestingRate (annually) (human-readable)
        globalValues[8] = vm.toString(deal.allocation.vestingStartTime); // vestingStartTime
        globalValues[9] = vm.toString(deal.allocation.unlockRate * 365 days / 1 ether); // unlockRate (annually) (human-readable)
        globalValues[10] = vm.toString(deal.allocation.unlockStartTime); // unlockStartTime

        string[] memory partyValues = new string[](4);
        partyValues[0] = partyName;
        partyValues[1] = vm.toString(grantee); // evmAddress
        partyValues[2] = "email@company.com"; // Make sure it matches the proposed deal
        partyValues[3] = "individual"; // Make sure it matches the proposed deal

        bytes memory signature = CyberAgreementUtils.signAgreementTypedData(
            vm,
            registry.DOMAIN_SEPARATOR(),
            registry.SIGNATUREDATA_TYPEHASH(),
            contractId,
            compAgreementUri,
            compGlobalFields,
            compPartyFields,
            globalValues,
            partyValues,
            granteePrivateKey
        );

        if (expectRevertData.length > 0) {
            vm.expectRevert(expectRevertData);
        }
        address metavest = controller.signDealAndCreateMetavest(
            grantee,
            recipient,
            contractId,
            partyValues,
            signature,
            "" // no secrets
        );

        if (expectRevertData.length == 0) {
            return metavest;
        } else {
            return address(0);
        }
    }
}
