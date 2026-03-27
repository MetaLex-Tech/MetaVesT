// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.20;

import {BaseAllocation} from "../src/BaseAllocation.sol";
import {RestrictedTokenAward} from "../src/RestrictedTokenAllocation.sol";
import {RestrictedTokenFactory} from "../src/RestrictedTokenFactory.sol";
import {Test} from "forge-std/Test.sol";
import {TokenOptionFactory} from "../src/TokenOptionFactory.sol";
import {VestingAllocationFactory} from "../src/VestingAllocationFactory.sol";
import {metavestController} from "../src/MetaVesTController.sol";
import {MockERC20} from "./mocks/MockERC20.sol";
import {FalseCondition} from "./mocks/MockCondition.sol";

contract MetaVestControllerAbstractBetaTest is Test {
    string saltStr = "MetaVestControllerAbstractBetaTest";
    bytes32 salt = keccak256(bytes(saltStr));

    address deployer = makeAddr("deployer");
    address authority = makeAddr("authority");
    address alice = makeAddr("alice");
    address bob = makeAddr("bob");
    address chad = makeAddr("chad");

    MockERC20 vestingToken = new MockERC20("Vesting Token", "VEST", 6);
    MockERC20 paymentToken = new MockERC20("Payment Token", "PAY", 6);

    metavestController controller;

    function setUp() public {
        vm.startPrank(deployer);

        controller = new metavestController{salt: salt}(
            authority,
            authority,
            address(0),
            address(new VestingAllocationFactory{salt: salt}()),
            address(new TokenOptionFactory{salt: salt}()),
            address(new RestrictedTokenFactory{salt: salt}())
        );

        // Prepare funds
        vestingToken = new MockERC20("Vesting Token", "VEST", 6);
        paymentToken = new MockERC20("Payment Token", "PAY", 6);

        vestingToken.mint(authority, 10000e6);

        vm.stopPrank();

        vm.startPrank(authority);
        vestingToken.approve(address(controller), 10000e6);
        vm.stopPrank();
    }

    function test_RecipientOverrideUpdatedOnConstruct() public {
        bytes32 salt = keccak256(bytes("test_RecipientOverrideUpdatedOnConstruct"));

        vm.expectEmit(true, true, true, true);
        emit metavestController.MetaVesTController_RecipientOverrideUpdated(chad);
        metavestController testController = new metavestController{salt: salt}(
            authority,
            authority,
            chad,
            address(new VestingAllocationFactory{salt: salt}()),
            address(new TokenOptionFactory{salt: salt}()),
            address(new RestrictedTokenFactory{salt: salt}())
        );
        assertEq(testController.recipientOverride(), chad, "unexpected recipientOverride");
    }

    function test_updateRecipientOverride() public {
        vm.prank(authority);
        vm.expectEmit(true, true, true, true, address(controller));
        emit metavestController.MetaVesTController_RecipientOverrideUpdated(chad);
        controller.updateRecipientOverride(chad);
        assertEq(controller.recipientOverride(), chad, "unexpected recipientOverride");
    }

    function test_RevertIf_updateRecipientOverrideNotAuthority() public {
        vm.expectRevert(metavestController.MetaVesTController_OnlyAuthority.selector);
        controller.updateRecipientOverride(chad);
    }

    function test_updateMetavestVestingStartTime() public {
        // Create vault
        vm.prank(authority);
        RestrictedTokenAward vault = _createTestVault(address(0));

        {
            (,,,, uint48 vestingStartTime,,,) = vault.allocation();
            assertEq(vestingStartTime, block.timestamp + 10, "unexpected vestingStartTime before update");
        }

        // Propose amendment
        vm.prank(authority);
        controller.proposeMetavestAmendment(
            address(vault),
            metavestController.updateMetavestVestingStartTime.selector,
            abi.encodeWithSelector(metavestController.updateMetavestVestingStartTime.selector, address(vault), uint48(block.timestamp + 30))
        );

        vm.stopPrank();

        // Approve amendment
        vm.prank(alice);
        controller.consentToMetavestAmendment(address(vault), metavestController.updateMetavestVestingStartTime.selector, true);

        // Perform amendment
        vm.prank(authority);
        controller.updateMetavestVestingStartTime(address(vault), uint48(block.timestamp + 30));

        {
            (,,,, uint48 vestingStartTime,,,) = vault.allocation();
            assertEq(vestingStartTime, block.timestamp + 30, "unexpected vestingStartTime after update");
        }
    }

    function test_RevertIf_updateMetavestVestingStartTimeNotAuthority() public {
        // Create vault
        vm.prank(authority);
        RestrictedTokenAward vault = _createTestVault(address(0));

        vm.expectRevert(metavestController.MetaVesTController_OnlyAuthority.selector);
        controller.updateMetavestVestingStartTime(address(vault), uint48(block.timestamp + 30));
    }

    function test_RevertIf_updateMetavestVestingStartTimeConditionNotMet() public {
        // Create vault
        vm.prank(authority);
        RestrictedTokenAward vault = _createTestVault(address(0));

        // Add mock condition
        address falseCondition = address(new FalseCondition());
        vm.prank(authority);
        controller.updateFunctionCondition(
            falseCondition,
            metavestController.updateMetavestVestingStartTime.selector
        );

        vm.expectRevert(abi.encodeWithSelector(metavestController.MetaVesTController_ConditionNotSatisfied.selector, falseCondition));
        vm.prank(authority);
        controller.updateMetavestVestingStartTime(address(vault), uint48(block.timestamp + 30));
    }

    function test_RevertIf_updateMetavestVestingStartTimeNoConsent() public {
        // Create vault
        vm.prank(authority);
        RestrictedTokenAward vault = _createTestVault(address(0));

        vm.expectRevert(metavestController.MetaVesTController_AmendmentNeitherMutualNorMajorityConsented.selector);
        vm.prank(authority);
        controller.updateMetavestVestingStartTime(address(vault), uint48(block.timestamp + 30));
    }

    function test_updateMetavestUnlockStartTime() public {
        // Create vault
        vm.prank(authority);
        RestrictedTokenAward vault = _createTestVault(address(0));

        {
            (,,,,,, uint48 unlockStartTime,) = vault.allocation();
            assertEq(unlockStartTime, block.timestamp + 20, "unexpected unlockStartTime before update");
        }

        // Propose amendment
        vm.prank(authority);
        controller.proposeMetavestAmendment(
            address(vault),
            metavestController.updateMetavestUnlockStartTime.selector,
            abi.encodeWithSelector(metavestController.updateMetavestUnlockStartTime.selector, address(vault), uint48(block.timestamp + 40))
        );

        vm.stopPrank();

        // Approve amendment
        vm.prank(alice);
        controller.consentToMetavestAmendment(address(vault), metavestController.updateMetavestUnlockStartTime.selector, true);

        // Perform amendment
        vm.prank(authority);
        controller.updateMetavestUnlockStartTime(address(vault), uint48(block.timestamp + 40));

        {
            (,,,,,, uint48 unlockStartTime,) = vault.allocation();
            assertEq(unlockStartTime, block.timestamp + 40, "unexpected unlockStartTime after update");
        }
    }

    function test_RevertIf_updateMetavestUnlockStartTimeNotAuthority() public {
        // Create vault
        vm.prank(authority);
        RestrictedTokenAward vault = _createTestVault(address(0));

        vm.expectRevert(metavestController.MetaVesTController_OnlyAuthority.selector);
        controller.updateMetavestUnlockStartTime(address(vault), uint48(block.timestamp + 40));
    }

    function test_RevertIf_updateMetavestUnlockStartTimeConditionNotMet() public {
        // Create vault
        vm.prank(authority);
        RestrictedTokenAward vault = _createTestVault(address(0));

        // Add mock condition
        address falseCondition = address(new FalseCondition());
        vm.prank(authority);
        controller.updateFunctionCondition(
            falseCondition,
            metavestController.updateMetavestUnlockStartTime.selector
        );

        vm.expectRevert(abi.encodeWithSelector(metavestController.MetaVesTController_ConditionNotSatisfied.selector, falseCondition));
        vm.prank(authority);
        controller.updateMetavestUnlockStartTime(address(vault), uint48(block.timestamp + 30));
    }



    function test_RevertIf_updateMetavestUnlockStartTimeNoConsent() public {
        // Create vault
        vm.prank(authority);
        RestrictedTokenAward vault = _createTestVault(address(0));

        vm.expectRevert(metavestController.MetaVesTController_AmendmentNeitherMutualNorMajorityConsented.selector);
        vm.prank(authority);
        controller.updateMetavestUnlockStartTime(address(vault), uint48(block.timestamp + 40));
    }

    function _createTestVault(address desiredRecipient) internal returns (RestrictedTokenAward) {
        return RestrictedTokenAward(controller.createMetavest(
            metavestController.metavestType.RestrictedTokenAward,
            alice,
            desiredRecipient,
            BaseAllocation.Allocation({
                tokenContract: address(vestingToken),
                tokenStreamTotal: 10000e6,
                vestingCliffCredit: 1000e6,
                unlockingCliffCredit: 1000e6,
                vestingRate: 100e6,
                vestingStartTime: uint48(block.timestamp + 10),
                unlockRate: 100e6,
                unlockStartTime: uint48(block.timestamp + 20)
            }),
            new BaseAllocation.Milestone[](0),
            1e6, // no-op: exercisePrice
            address(paymentToken),
            block.timestamp, // no-op: _shortStopDuration
            0 // no-op: _longStopDate
        ));
    }
}
