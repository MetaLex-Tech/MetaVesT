// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.20;

import "../src/MetaVesTController.sol";
import "./lib/MetaVesTControllerTestBase.sol";
import {Test} from "forge-std/Test.sol";
import {console2} from "forge-std/console2.sol";
import {CyberAgreementRegistry} from "cybercorps-contracts/src/CyberAgreementRegistry.sol";
import {ERC20} from "openzeppelin-contracts/token/ERC20/ERC20.sol";
import {DeployYearnBorgCompensationPrerequisitesScript} from "../scripts/deployYearnBorgCompensationPrerequisites.s.sol";
import {DeployYearnBorgCompensationScript} from "../scripts/deployYearnBorgCompensation.s.sol";
import {CreateAllTemplatesScript} from "../scripts/createAllTemplates.s.sol";
import {ProposeAllGuardiansMetaVestDealScript} from "../scripts/proposeAllGuardiansMetavestDeals.s.sol";
import {SignDealAndCreateMetavestScript} from "../scripts/signDealAndCreateMetavest.s.sol";
import {YearnBorgCompensation2025_2026} from "../scripts/lib/YearnBorgCompensation2025_2026.sol";
import {GnosisTransaction} from "./lib/safe.sol";
import {MetaVesTControllerFactory} from "../../src/MetaVesTControllerFactory.sol";

// Test with fresh deployment (except third-party dependencies)
// - Use third-party dependencies on Ethereum mainnet
// - Does not need to be run with environment variables
contract YearnBorgCompensationTest is
    DeployYearnBorgCompensationPrerequisitesScript,
    DeployYearnBorgCompensationScript,
    CreateAllTemplatesScript,
    ProposeAllGuardiansMetaVestDealScript,
    SignDealAndCreateMetavestScript,
    Test
{
    string saltStr = "YearnBorgCompensationTest";
    uint256 agreementSalt = block.timestamp;

    // Randomly generated to avoid contaminated common test address
    uint256 privateKeySalt = 0x4425fdf88097e51c669a66d392c4019ad555544e966908af6ee3cec32f53ab77;

    uint256 deployerPrivateKey = privateKeySalt + 0;
    address deployer = vm.addr(deployerPrivateKey);
    uint256 metalexDelegatePrivateKey = privateKeySalt + 1;
    address metalexDelegate = vm.addr(metalexDelegatePrivateKey);
    uint256 borgDelegatePrivateKey = privateKeySalt + 2;
    address borgDelegate = vm.addr(borgDelegatePrivateKey);
    uint256 chadPrivateKey = privateKeySalt + 3;
    address chad = vm.addr(chadPrivateKey);
    uint256[] borgRecipientPrivateKeys;

    YearnBorgCompensation2025_2026.Config config2025_2026;

    BorgAuth auth;

    function setUp() virtual public {
        // Prepare funds for accounts used by the actual deployment scripts
        deal(deployer, 1 ether);
        deal(metalexDelegate, 1 ether);
        deal(borgDelegate, 1 ether);
        deal(chad, 1 ether);

        MetaVesTControllerFactory metavestControllerFactory;
        metavestController controller;
        GnosisTransaction[] memory safeTxsCreateAllTemplates;
        GnosisTransaction[] memory safeTxs2025_2026;

        config2025_2026 = YearnBorgCompensation2025_2026.getDefault(vm);

        // Override recipient info for tests

        borgRecipientPrivateKeys = new uint256[](1);
        borgRecipientPrivateKeys[0] = privateKeySalt + 100;
        config2025_2026.compRecipients = new YearnBorgCompensation2025_2026.CompInfo[](1);
        config2025_2026.compRecipients[0] = YearnBorgCompensation2025_2026.CompInfo({
            partyInfo: YearnBorgCompensation2025_2026.PartyInfo({
                name: "Alice",
                evmAddress: vm.addr(borgRecipientPrivateKeys[0])
            }),
            compTemplate: YearnBorgCompensation2025_2026.TemplateInfo({
                id: bytes32(uint256(999001)),
                agreementUri: "ipfs://bafkreidefnk2tf6req4tn3bya7pkfkt45i6cppmannb5fz7ncv6mfg6vj4",
                name: "Alice template",
                globalFields: YearnBorgCompensation2025_2026.getCompGlobalFields(),
                partyFields: YearnBorgCompensation2025_2026.getCompPartyFields()
            }),
            signature: ""
        });
        deal(config2025_2026.compRecipients[0].partyInfo.evmAddress, 1 ether); // Prepare gas for compRecipients

        // Update known info
        auth = config2025_2026.registry.AUTH();

        // Deploy prerequisites
        metavestControllerFactory = DeployYearnBorgCompensationPrerequisitesScript.deployPrerequisites(
            deployerPrivateKey,
            saltStr,
            config2025_2026
        );

        // Update configs with deployed contracts
        config2025_2026.metavestControllerFactory = metavestControllerFactory;

        // Update configs with test BORG delegate
        config2025_2026.borgAgreementDelegate = borgDelegate;

        // Deploy 2025-2026 compensation contracts
        (controller, safeTxs2025_2026) = DeployYearnBorgCompensationScript.deployCompensation(
            deployerPrivateKey,
            string(abi.encodePacked(saltStr, ".2025-2026")),
            config2025_2026
        );
        config2025_2026.controller = controller; // Update configs with deployed contracts

        // Create all templates
        safeTxsCreateAllTemplates = CreateAllTemplatesScript.run(config2025_2026);

        // Simulate MetaLeX SAFE to execute txs as instructed
        for (uint256 i = 0; i < safeTxsCreateAllTemplates.length; i++) {
            vm.prank(address(config2025_2026.metalexSafe));
            (safeTxsCreateAllTemplates[i].to).call{value: safeTxsCreateAllTemplates[i].value}(safeTxsCreateAllTemplates[i].data);
        }

        // Simulate BORG SAFE to execute txs as instructed
        for (uint256 i = 0; i < safeTxs2025_2026.length; i++) {
            vm.prank(address(config2025_2026.borgSafe));
            (safeTxs2025_2026[i].to).call{value: safeTxs2025_2026[i].value}(safeTxs2025_2026[i].data);
        }

        // Simulate BORG SAFE to prepare USDC
        deal(config2025_2026.paymentToken, address(config2025_2026.borgSafe), 5000e6);
    }

    function run() public override(
        DeployYearnBorgCompensationPrerequisitesScript,
        DeployYearnBorgCompensationScript,
        CreateAllTemplatesScript,
        ProposeAllGuardiansMetaVestDealScript,
        SignDealAndCreateMetavestScript
    ) {
        // No-op, we don't use this part of the scripts
    }

    function test_metadata() public {
        // MetaVesT pre-requisites

        auth.onlyRole(auth.OWNER_ROLE(), address(config2025_2026.metalexSafe)); // MetaLeX SAFE should own core auth
        vm.assertEq(auth.userRoles(deployer), 0, "deployer should revoke core auth ownership");
        vm.assertEq(address(config2025_2026.registry.AUTH()), address(auth), "Unexpected CyberAgreementRegistry auth");

        for (uint256 i = 0; i < config2025_2026.compRecipients.length; i ++) {
            YearnBorgCompensation2025_2026.CompInfo memory guardian = config2025_2026.compRecipients[i];
            _assertTemplate(
                config2025_2026.registry,
                guardian.compTemplate.id,
                guardian.compTemplate.agreementUri,
                guardian.compTemplate.name,
                guardian.compTemplate.globalFields,
                guardian.compTemplate.partyFields
            );
        }

        // MetaVesT deployments

        vm.assertEq(config2025_2026.controller.authority(), address(config2025_2026.borgSafe), "2025-2026 MetaVesTController's authority should be BORG SAFE");
        vm.assertEq(config2025_2026.controller.dao(), address(config2025_2026.borgSafe), "2025-2026 MetaVesTController's DAO should be BORG SAFE");
        vm.assertEq(config2025_2026.controller.registry(), address(config2025_2026.registry), "2025-2026 Unexpected MetaVesTController registry");
        vm.assertEq(config2025_2026.controller.upgradeFactory(), address(config2025_2026.metavestControllerFactory), "2025-2026 Unexpected MetaVesTControllerFactory");

        // BORG provisioning
        assertTrue(config2025_2026.registry.isValidDelegate(address(config2025_2026.borgSafe), borgDelegate), "delegate should be BORG SAFE's delegate");
        assertEq(
            ERC20(config2025_2026.paymentToken).allowance(address(config2025_2026.borgSafe), address(config2025_2026.controller)),
            config2025_2026.paymentTokenApprovalCap,
            "BORG should approve metavestController to transfer USDC"
        );
    }

    function test_AgreementDeadline() public {
        // Run scripts to propose deals
        bytes32 agreementId = ProposeAllGuardiansMetaVestDealScript.runSingle(
            deployerPrivateKey,
            borgDelegatePrivateKey,
            config2025_2026.compRecipients[0], // alice
            agreementSalt,
            config2025_2026
        );

        (, , , , , , uint256 agreementExpiry) = config2025_2026.registry.agreements(agreementId);
        assertGt(agreementExpiry, config2025_2026.metavestVestingAndUnlockStartTime + 365 days, "Agreement expiry should be at least one year after vesting start");
    }

    function test_GuardianCompensation() public {
        address[] memory metavestAddresses2025_2026 = _proposeAndFinalizeAllGuardianDeals();

        VestingAllocation vestingAllocationAlice2025_2026 = VestingAllocation(metavestAddresses2025_2026[0]);

        // Alice should be able to withdraw half of her 2025-2026 compensation half way through the period
        vm.warp(1772496000 + 1 days); // 2026/03/03 00:00 UTC + margin for precision errors
        _granteeWithdrawAndAsserts(config2025_2026.paymentToken, vestingAllocationAlice2025_2026, 2500e6, "Alice 2025-2026 half");

        // Alice should be able to withdraw within the 2025-2026 grace period (set by ZK Capped Minter expiry)
        vm.warp(1793491199 + 1 days); // 2026/10/31 23:59:59 UTC + margin for precision errors
        _granteeWithdrawAndAsserts(config2025_2026.paymentToken, vestingAllocationAlice2025_2026, 2500e6, "Alice 2025-2026 remaining");
    }

    function _proposeAndFinalizeAllGuardianDeals() internal returns(address[] memory) {
        // Run scripts to propose deals for all compRecipients

        bytes32[] memory agreementIds2025_2026 = ProposeAllGuardiansMetaVestDealScript.runAll(
            deployerPrivateKey,
            borgDelegatePrivateKey,
            agreementSalt,
            config2025_2026
        );

        // Simulate guardian counter-sign and finalize the deal

        address[] memory metavests2025_2026 = new address[](borgRecipientPrivateKeys.length);

        for (uint256 i = 0; i < metavests2025_2026.length; i++) {
            metavests2025_2026[i] = SignDealAndCreateMetavestScript.run(
                borgRecipientPrivateKeys[i],
                agreementIds2025_2026[i],
                config2025_2026.compRecipients[i],
                config2025_2026
            );
        }

        return metavests2025_2026;
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

    function _granteeWithdrawAndAsserts(address paymentToken, VestingAllocation vestingAllocation, uint256 amount, string memory assertName) internal {
        address grantee = vestingAllocation.grantee();
        uint256 balanceBefore = ERC20(paymentToken).balanceOf(grantee);

        vm.prank(grantee);
        vestingAllocation.withdraw(amount);

        assertEq(ERC20(paymentToken).balanceOf(grantee), balanceBefore + amount, string(abi.encodePacked(assertName, ": unexpected received amount")));
    }
}
