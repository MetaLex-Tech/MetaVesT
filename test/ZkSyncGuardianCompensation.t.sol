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
import {ProposeServiceAgreementScript} from "../scripts/proposeServiceAgreement.s.sol";
import {ProposeMetaVestDealScript} from "../scripts/proposeMetavestDeal.s.sol";
import {SignDealAndCreateMetavestScript} from "../scripts/signDealAndCreateMetavest.s.sol";
import {ZkSyncGuardianCompensationConfig2024_2025} from "../scripts/lib/ZkSyncGuardianCompensationConfig2024_2025.sol";
import {GnosisTransaction} from "./lib/safe.sol";

// Test by forge test --zksync --via-ir
contract ZkSyncGuardianCompensationTest is
    DeployZkSyncGuardianCompensationPrerequisitesScript,
    DeployZkSyncGuardianCompensation2024_2025Script,
    ProposeServiceAgreementScript,
    ProposeMetaVestDealScript,
    SignDealAndCreateMetavestScript,
    Test
{
    // zkSync Era mainnet @ 63631890
    address zkTokenAdmin = 0xe5d21A9179CA2E1F0F327d598D464CcF60d89c3d;

    // Randomly generated to avoid contaminated common test address
    uint256 privateKeySalt = 0x4425fdf88097e51c669a66d392c4019ad555544e966908af6ee3cec32f53ab77;

    uint256 deployerPrivateKey = privateKeySalt + 0;
    address deployer = vm.addr(deployerPrivateKey);
    uint256 metalexDelegatePrivateKey = privateKeySalt + 1;
    address metalexDelegate = vm.addr(metalexDelegatePrivateKey);
    uint256 guardianDelegatePrivateKey = privateKeySalt + 2;
    address guardianDelegate = vm.addr(guardianDelegatePrivateKey);
    uint256 alicePrivateKey = privateKeySalt + 3;
    address alice = vm.addr(alicePrivateKey);
    uint256 bobPrivateKey = privateKeySalt + 4;
    address bob = vm.addr(bobPrivateKey);
    uint256 chadPrivateKey = privateKeySalt + 5;
    address chad = vm.addr(chadPrivateKey);

    IZkCappedMinterV2 masterMinter;

    BorgAuth auth;

    function setUp() public {
        // Prepare funds for accounts used by the actual deployment scripts
        deal(deployer, 1 ether);
        deal(metalexDelegate, 1 ether);
        deal(guardianDelegate, 1 ether);
        deal(alice, 1 ether);
        deal(bob, 1 ether);
        deal(chad, 1 ether);

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
        DeployZkSyncGuardianCompensation2024_2025Script,
        ProposeServiceAgreementScript,
        ProposeMetaVestDealScript,
        SignDealAndCreateMetavestScript
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

    function test_ProposeServiceAgreement() public {
        // Simulate MetaLeX SAFE delegation
        vm.prank(address(metalexSafe));
        registry.setDelegation(metalexDelegate, block.timestamp + 60);
        assertTrue(registry.isValidDelegate(address(metalexSafe), metalexDelegate), "should be MetaLeX SAFE's delegate");

        // Simulate MetaLeX delegate proposing and signing agreement
        bytes32 agreementId = ProposeServiceAgreementScript.run(metalexDelegatePrivateKey, registry);

        // Verify agreement

        (bytes32 templateId, , , , , , uint256 expiry) = registry.agreements(agreementId);
        assertEq(templateId, serviceTemplateId, "Unexpected service agreement template ID");
        assertEq(expiry, serviceAgreementExpiry, "Unexpected service agreement expiry");

        (, , , , , address[] memory parties, , , , ) = registry.getContractDetails(agreementId);
        vm.assertEq(parties[0], address(metalexSafe), "First party should be MetaLeX SAFE");
        vm.assertEq(parties[1], address(guardianSafe), "Second party should be Guardian SAFE");

        vm.assertTrue(registry.hasSigned(agreementId, metalexDelegate), "Should signed by MetaLeX delegate");
    }

    function test_GuardianCompensation() public {
        (address metavestAddressAlice, address metavestAddressBob) = _proposeAndFinalizeAllGuardianDeals();

        VestingAllocation vestingAllocationAlice = VestingAllocation(metavestAddressAlice);
        VestingAllocation vestingAllocationBob = VestingAllocation(metavestAddressBob);

        // Grantee should be able to withdraw all on 2025/09/01 because this compensation is for 2024~2025
        vm.warp(1756684800 + 1); // 2025/09/01 00:00 UTC with some margin for precision error

        _granteeWithdrawAndAsserts(zkToken, zkCappedMinter, vestingAllocationAlice, 625e3 ether, "Alice full");
        _granteeWithdrawAndAsserts(zkToken, zkCappedMinter, vestingAllocationBob, 615e3 ether, "Bob partial");

        // Grantees should be able to withdraw within the grace period (set by ZK Capped Minter expiry)
        skip(60 days);

        _granteeWithdrawAndAsserts(zkToken, zkCappedMinter, vestingAllocationBob, 10e3 ether, "Bob remaining");
    }

    function test_AdminToolingCompensation() public {
        (address metavestAddressAlice, address metavestAddressBob) = _proposeAndFinalizeAllGuardianDeals();
        VestingAllocation vestingAllocationAlice = VestingAllocation(metavestAddressAlice);

        // Vesting starts and a month has passed
        vm.warp(1756684800 + 1); // 2025/09/01 00:00 UTC with some margin for precision error

        _granteeWithdrawAndAsserts(zkToken, zkCappedMinter, vestingAllocationAlice, 300e3 ether, "Alice partial");

        // A month has passed
        skip(30 days);

        // Add new grantee for admin/tooling compensation

        // Guardian SAFE to delegate signing to an EOA
        vm.prank(address(guardianSafe));
        registry.setDelegation(guardianDelegate, block.timestamp + 60);
        assertTrue(registry.isValidDelegate(address(guardianSafe), guardianDelegate), "should be Guardian SAFE's delegate");

        ZkSyncGuardianCompensationConfig2024_2025.PartyInfo memory chadInfo = ZkSyncGuardianCompensationConfig2024_2025.PartyInfo({
            name: "Chad",
            evmAddress: chad,
            contactDetails: "chad@email.com",
            _type: "individual"
        });
        bytes32 contractIdChad = ProposeMetaVestDealScript.run(
            guardianDelegatePrivateKey,
            registry,
            controller,
            guardianSafeInfo,
            chadInfo,
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
            })
        );
        VestingAllocation vestingAllocationChad = VestingAllocation(SignDealAndCreateMetavestScript.run(
            chadPrivateKey,
            registry,
            controller,
            contractIdChad,
            chadInfo
        ));
        _granteeWithdrawAndAsserts(zkToken, zkCappedMinter, vestingAllocationChad, 10e3 ether, "Chad cliff");
    }

    function _proposeAndFinalizeAllGuardianDeals() internal returns(address, address) {
        // Guardian SAFE to delegate signing to an EOA
        vm.prank(address(guardianSafe));
        registry.setDelegation(guardianDelegate, block.timestamp + 60);
        assertTrue(registry.isValidDelegate(address(guardianSafe), guardianDelegate), "delegate should be Guardian SAFE's delegate");

        // Run scripts to propose deals

        ZkSyncGuardianCompensationConfig2024_2025.PartyInfo memory aliceInfo = ZkSyncGuardianCompensationConfig2024_2025.PartyInfo({
            name: "Alice",
            evmAddress: alice,
            contactDetails: "alice@email.com",
            _type: "individual"
        });
        ZkSyncGuardianCompensationConfig2024_2025.PartyInfo memory bobInfo = ZkSyncGuardianCompensationConfig2024_2025.PartyInfo({
            name: "Bob",
            evmAddress: bob,
            contactDetails: "bob@email.com",
            _type: "individual"
        });

        bytes32 contractIdAlice = ProposeMetaVestDealScript.run(
            guardianDelegatePrivateKey,
            registry,
            controller,
            guardianSafeInfo,
            aliceInfo
        );
        bytes32 contractIdBob = ProposeMetaVestDealScript.run(
            guardianDelegatePrivateKey,
            registry,
            controller,
            guardianSafeInfo,
            bobInfo
        );

        // Simulate guardian counter-sign and finalize the deal

        address metavestAlice = SignDealAndCreateMetavestScript.run(
            alicePrivateKey,
            registry,
            controller,
            contractIdAlice,
            aliceInfo
        );
        address metavestBob = SignDealAndCreateMetavestScript.run(
            bobPrivateKey,
            registry,
            controller,
            contractIdBob,
            bobInfo
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
}
