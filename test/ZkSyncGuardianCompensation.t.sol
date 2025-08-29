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
import {DeployZkSyncGuardianCompensationScript} from "../scripts/deployZkSyncGuardianCompensation.s.sol";
import {ProposeBorgResolutionScript} from "../scripts/proposeBorgResolution.s.sol";
import {ProposeMetaVestDealScript} from "../scripts/proposeMetavestDeal.s.sol";
import {SignDealAndCreateMetavestScript} from "../scripts/signDealAndCreateMetavest.s.sol";
import {ZkSyncGuardianCompensation2024_2025} from "../scripts/lib/ZkSyncGuardianCompensation2024_2025.sol";
import {ZkSyncGuardianCompensation2025_2026} from "../scripts/lib/ZkSyncGuardianCompensation2025_2026.sol";
import {GnosisTransaction} from "./lib/safe.sol";

// Test by forge test --zksync --via-ir
contract ZkSyncGuardianCompensationTest is
    DeployZkSyncGuardianCompensationPrerequisitesScript,
    DeployZkSyncGuardianCompensationScript,
    ProposeBorgResolutionScript,
    ProposeMetaVestDealScript,
    SignDealAndCreateMetavestScript,
    Test
{
    // zkSync Era mainnet @ 63631890
    address zkTokenAdmin = 0xe5d21A9179CA2E1F0F327d598D464CcF60d89c3d;

    string saltStr = "ZkSyncGuardianCompensationTest";

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

    ZkSyncGuardianCompensation2024_2025.Config config2024_2025;
    ZkSyncGuardianCompensation2024_2025.Config config2025_2026;

    BorgAuth auth;
    metavestController controller2024_2025;
    metavestController controller2025_2026;

    function setUp() public {
        // Prepare funds for accounts used by the actual deployment scripts
        deal(deployer, 1 ether);
        deal(metalexDelegate, 1 ether);
        deal(guardianDelegate, 1 ether);
        deal(alice, 1 ether);
        deal(bob, 1 ether);
        deal(chad, 1 ether);

        CyberAgreementRegistry registry;
        VestingAllocationFactory vestingAllocationFactory;
        metavestController controller;
        GnosisTransaction[] memory safeTxs2024_2025;
        GnosisTransaction[] memory safeTxs2025_2026;

        config2024_2025 = ZkSyncGuardianCompensation2024_2025.getDefault();
        config2025_2026 = ZkSyncGuardianCompensation2025_2026.getDefault();

        (auth, registry, vestingAllocationFactory) = DeployZkSyncGuardianCompensationPrerequisitesScript.deployPrerequisites(
            deployerPrivateKey,
            saltStr,
            config2024_2025
        );

        // Update configs with deployed contracts
        config2024_2025.registry = registry;
        config2024_2025.vestingAllocationFactory = vestingAllocationFactory;
        config2025_2026.registry = registry;
        config2025_2026.vestingAllocationFactory = vestingAllocationFactory;

        // Deploy 2024-2025 compensation contracts
        (controller, safeTxs2024_2025) = DeployZkSyncGuardianCompensationScript.deployCompensation(
            deployerPrivateKey,
            string(abi.encodePacked(saltStr, ".2024-2025")),
            config2024_2025
        );
        config2024_2025.controller = controller; // Update configs with deployed contracts

        // Deploy 2025-2026 compensation contracts
        (controller, safeTxs2025_2026) = DeployZkSyncGuardianCompensationScript.deployCompensation(
            deployerPrivateKey,
            string(abi.encodePacked(saltStr, ".2025-2026")),
            config2025_2026
        );
        config2025_2026.controller = controller; // Update configs with deployed contracts

        // Simulate Guardian SAFE to execute txs as instructed

        for (uint256 i = 0; i < safeTxs2024_2025.length; i++) {
            vm.prank(address(config2024_2025.guardianSafe));
            (safeTxs2024_2025[i].to).call{value: safeTxs2024_2025[i].value}(safeTxs2024_2025[i].data);
        }
        for (uint256 i = 0; i < safeTxs2025_2026.length; i++) {
            vm.prank(address(config2025_2026.guardianSafe));
            (safeTxs2025_2026[i].to).call{value: safeTxs2025_2026[i].value}(safeTxs2025_2026[i].data);
        }

        // Simulate MetaLeX SAFE create templates for Guardian Compensation and Service Agreement

        vm.startPrank(address(config2024_2025.metalexSafe));

        registry.createTemplate(
            config2024_2025.borgResolutionTemplateId,
            config2024_2025.borgResolutionTemplateName,
            config2024_2025.borgResolutionUri,
            config2024_2025.borgResolutionGlobalFields,
            config2024_2025.borgResolutionPartyFields
        );

        registry.createTemplate(
            config2024_2025.compTemplateId,
            config2024_2025.compTemplateName,
            config2024_2025.compAgreementUri,
            config2024_2025.compGlobalFields,
            config2024_2025.compPartyFields
        );

        vm.stopPrank();

        // Simulate vote pass (https://vote.zknation.io/dao/proposal/14920227315823844313255249182525601975564035647349569740836448589354658768084?govId=eip155:324:0xb83FF6501214ddF40C91C9565d095400f3F45746)

        vm.startPrank(zkTokenAdmin);

        masterMinter = IZkCappedMinterV2(config2024_2025.zkCappedMinter.MINTABLE());
        masterMinter.grantRole(masterMinter.MINTER_ROLE(), address(config2024_2025.zkCappedMinter));
        masterMinter.grantRole(masterMinter.MINTER_ROLE(), address(config2025_2026.zkCappedMinter));

        IZkCappedMinterV2 grandMasterMinter = IZkCappedMinterV2(masterMinter.MINTABLE());
        grandMasterMinter.grantRole(grandMasterMinter.MINTER_ROLE(), address(masterMinter));

        vm.stopPrank();
    }

    function run() public override(
        DeployZkSyncGuardianCompensationPrerequisitesScript,
        DeployZkSyncGuardianCompensationScript,
        ProposeBorgResolutionScript,
        ProposeMetaVestDealScript,
        SignDealAndCreateMetavestScript
    ) {
        // No-op, we don't use this part of the scripts
    }

    function test_metadata() public {
        // ZK governance pre-requisites

        assertTrue(masterMinter.hasRole(masterMinter.MINTER_ROLE(), address(config2024_2025.zkCappedMinter)), "Master Minter should grant this year's ZK Capped Minter access");

        // MetaVesT pre-requisites

        auth.onlyRole(auth.OWNER_ROLE(), address(config2024_2025.metalexSafe)); // MetaLeX SAFE should own BorgAuth
        vm.assertEq(auth.userRoles(deployer), 0, "deployer should revoke BorgAuth ownership");
        vm.assertEq(address(config2024_2025.registry.AUTH()), address(auth), "Unexpected CyberAgreementRegistry auth");

        _assertTemplate(
            config2024_2025.registry,
            config2024_2025.compTemplateId,
            config2024_2025.compAgreementUri,
            config2024_2025.compTemplateName,
            config2024_2025.compGlobalFields,
            config2024_2025.compPartyFields
        );
        _assertTemplate(
            config2024_2025.registry,
            config2024_2025.borgResolutionTemplateId,
            config2024_2025.borgResolutionUri,
            config2024_2025.borgResolutionTemplateName,
            config2024_2025.borgResolutionGlobalFields,
            config2024_2025.borgResolutionPartyFields
        );

        // MetaVesT deployments

        vm.assertEq(config2024_2025.controller.authority(), address(config2024_2025.guardianSafe), "2024-2025 MetaVesTController's authority should be Guardian SAFE");
        vm.assertEq(config2024_2025.controller.dao(), address(config2024_2025.guardianSafe), "2024-2025 MetaVesTController's DAO should be Guardian SAFE");
        vm.assertEq(config2024_2025.controller.registry(), address(config2024_2025.registry), "2024-2025 Unexpected MetaVesTController registry");
        vm.assertEq(config2024_2025.controller.vestingFactory(), address(config2024_2025.vestingAllocationFactory), "2024-2025 Unexpected MetaVesTController vesting allocation factory");
        vm.assertEq(config2024_2025.controller.zkCappedMinter(), address(config2024_2025.zkCappedMinter), "2024-2025 MetaVesTController should have ZK Capped Minter should set");
        vm.assertTrue(config2024_2025.zkCappedMinter.hasRole(config2024_2025.zkCappedMinter.MINTER_ROLE(), address(config2024_2025.controller)), "2024-2025 ZK Capped Minter should grant MetaVesTController MINTER role");

        vm.assertEq(config2025_2026.controller.authority(), address(config2025_2026.guardianSafe), "2025-2026 MetaVesTController's authority should be Guardian SAFE");
        vm.assertEq(config2025_2026.controller.dao(), address(config2025_2026.guardianSafe), "2025-2026 MetaVesTController's DAO should be Guardian SAFE");
        vm.assertEq(config2025_2026.controller.registry(), address(config2025_2026.registry), "2025-2026 Unexpected MetaVesTController registry");
        vm.assertEq(config2025_2026.controller.vestingFactory(), address(config2025_2026.vestingAllocationFactory), "2025-2026 Unexpected MetaVesTController vesting allocation factory");
        vm.assertEq(config2025_2026.controller.zkCappedMinter(), address(config2025_2026.zkCappedMinter), "2025-2026 MetaVesTController should have ZK Capped Minter should set");
        vm.assertTrue(config2025_2026.zkCappedMinter.hasRole(config2025_2026.zkCappedMinter.MINTER_ROLE(), address(config2025_2026.controller)), "2025-2026 ZK Capped Minter should grant MetaVesTController MINTER role");
    }

    function test_AgreementDeadline() public {
        // Guardian SAFE to delegate signing to an EOA
        vm.prank(address(config2024_2025.guardianSafe));
        config2024_2025.registry.setDelegation(guardianDelegate, block.timestamp + 60);
        assertTrue(config2024_2025.registry.isValidDelegate(address(config2024_2025.guardianSafe), guardianDelegate), "delegate should be Guardian SAFE's delegate");

        // Run scripts to propose deals
        bytes32 agreementId = ProposeMetaVestDealScript.run(
            guardianDelegatePrivateKey,
            ZkSyncGuardianCompensation2024_2025.PartyInfo({
                name: "Alice",
                evmAddress: alice
            }),
            config2024_2025
        );

        (, , , , , , uint256 agreementExpiry) = config2024_2025.registry.agreements(agreementId);
        assertGt(agreementExpiry, config2024_2025.zkCappedMinter.EXPIRATION_TIME(), "Agreement expiry should be later than the minter's");
    }

    function test_ProposeBorgResolution() public {
        // Simulate Guardian SAFE delegation
        vm.prank(address(config2024_2025.guardianSafe));
        config2024_2025.registry.setDelegation(guardianDelegate, block.timestamp + 60);
        assertTrue(config2024_2025.registry.isValidDelegate(address(config2024_2025.guardianSafe), guardianDelegate), "should be MetaLeX SAFE's delegate");

        // Simulate MetaLeX delegate proposing and signing agreement
        bytes32 agreementId = ProposeBorgResolutionScript.run(
            guardianDelegatePrivateKey,
            config2024_2025
        );

        // Verify agreement

        (bytes32 templateId, , , , , , uint256 expiry) = config2024_2025.registry.agreements(agreementId);
        assertEq(templateId, config2024_2025.borgResolutionTemplateId, "Unexpected borg Resolution template ID");

        (, , , , , address[] memory parties, , , , ) = config2024_2025.registry.getContractDetails(agreementId);
        vm.assertEq(parties.length, 1, "Should be single-party");
        vm.assertEq(parties[0], address(config2024_2025.guardianSafe), "First party should be Guardian SAFE");
    }

    function test_GuardianCompensation() public {
        (address metavestAddressAlice2024_2025, address metavestAddressAlice2025_2026) = _proposeAndFinalizeAllGuardianDeals();

        VestingAllocation vestingAllocationAlice2024_2025 = VestingAllocation(metavestAddressAlice2024_2025);
        VestingAllocation vestingAllocationAlice2025_2026 = VestingAllocation(metavestAddressAlice2025_2026);

        // Alice should be able to withdraw all on 2025/09/01 because this compensation is for 2024~2025
        vm.warp(1756684800); // 2025/09/01 00:00 UTC
        _granteeWithdrawAndAsserts(config2024_2025.zkToken, config2024_2025.zkCappedMinter, vestingAllocationAlice2024_2025, 615e3 ether, "Alice 2024-2025 partial");

        // Alice should be able to withdraw within the 2024-2025 grace period (set by ZK Capped Minter expiry)
        vm.warp(1767225599); // 2025/12/31 23:59:59 UTC
        _granteeWithdrawAndAsserts(config2024_2025.zkToken, config2024_2025.zkCappedMinter, vestingAllocationAlice2024_2025, 10e3 ether, "Alice 2024-2025 remaining");

        // Alice should be able to withdraw half of her 2025-2026 compensation half way through the period
        vm.warp(1772496000); // 2026/03/03 00:00 UTC
        _granteeWithdrawAndAsserts(config2025_2026.zkToken, config2025_2026.zkCappedMinter, vestingAllocationAlice2025_2026, 312.5e3 ether, "Alice 2025-2026 half");

        // Alice should be able to withdraw within the 2025-2026 grace period (set by ZK Capped Minter expiry)
        vm.warp(1793491199); // 2026/10/31 23:59:59 UTC
        _granteeWithdrawAndAsserts(config2025_2026.zkToken, config2025_2026.zkCappedMinter, vestingAllocationAlice2025_2026, 312.5e3 ether, "Alice 2025-2026 remaining");
    }

    function test_AdminToolingCompensation() public {
        (address metavestAddressAlice2024_2025, ) = _proposeAndFinalizeAllGuardianDeals();
        VestingAllocation vestingAllocationAlice = VestingAllocation(metavestAddressAlice2024_2025);

        // 2024-2025 Vesting starts
        vm.warp(1756684800); // 2025/09/01 00:00 UTC

        _granteeWithdrawAndAsserts(config2024_2025.zkToken, config2024_2025.zkCappedMinter, vestingAllocationAlice, 300e3 ether, "Alice partial");

        // A month has passed
        skip(30 days);

        // Add new grantee for admin/tooling compensation

        // Guardian SAFE to delegate signing to an EOA
        vm.prank(address(config2024_2025.guardianSafe));
        config2024_2025.registry.setDelegation(guardianDelegate, block.timestamp + 60);
        assertTrue(config2024_2025.registry.isValidDelegate(address(config2024_2025.guardianSafe), guardianDelegate), "should be Guardian SAFE's delegate");

        ZkSyncGuardianCompensation2024_2025.PartyInfo memory chadInfo = ZkSyncGuardianCompensation2024_2025.PartyInfo({
            name: "Chad",
            evmAddress: chad
        });
        bytes32 contractIdChad = ProposeMetaVestDealScript.run(
            guardianDelegatePrivateKey,
            chadInfo,
            BaseAllocation.Allocation({
                tokenContract: address(config2024_2025.zkToken),
                // 10k ZK total in one cliff
                tokenStreamTotal: 10e3 ether,
                vestingCliffCredit: 10e3 ether,
                unlockingCliffCredit: 10e3 ether,
                vestingRate: 0,
                vestingStartTime: 0,
                unlockRate: 0,
                unlockStartTime: 0
            }),
            config2024_2025
        );
        VestingAllocation vestingAllocationChad = VestingAllocation(SignDealAndCreateMetavestScript.run(
            chadPrivateKey,
            contractIdChad,
            chadInfo,
            config2024_2025
        ));
        _granteeWithdrawAndAsserts(config2024_2025.zkToken, config2024_2025.zkCappedMinter, vestingAllocationChad, 10e3 ether, "Chad cliff");
    }

    function _proposeAndFinalizeAllGuardianDeals() internal returns(address, address) {
        // Guardian SAFE to delegate signing to an EOA
        vm.prank(address(config2024_2025.guardianSafe));
        config2024_2025.registry.setDelegation(guardianDelegate, block.timestamp + 60);
        assertTrue(config2024_2025.registry.isValidDelegate(address(config2024_2025.guardianSafe), guardianDelegate), "delegate should be Guardian SAFE's delegate");

        // Run scripts to propose deals

        ZkSyncGuardianCompensation2024_2025.PartyInfo memory aliceInfo = ZkSyncGuardianCompensation2024_2025.PartyInfo({
            name: "Alice",
            evmAddress: alice
        });

        bytes32 contractIdAlice2024_2025 = ProposeMetaVestDealScript.run(
            guardianDelegatePrivateKey,
            aliceInfo,
            config2024_2025
        );
        bytes32 contractIdAlice2025_2026 = ProposeMetaVestDealScript.run(
            guardianDelegatePrivateKey,
            aliceInfo,
            config2025_2026
        );

        // Simulate guardian counter-sign and finalize the deal

        address metavestAlice2024_2025 = SignDealAndCreateMetavestScript.run(
            alicePrivateKey,
            contractIdAlice2024_2025,
            aliceInfo,
            config2024_2025
        );
        address metavestAlice2025_2026 = SignDealAndCreateMetavestScript.run(
            alicePrivateKey,
            contractIdAlice2025_2026,
            aliceInfo,
            config2025_2026
        );

        return (metavestAlice2024_2025, metavestAlice2025_2026);
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
