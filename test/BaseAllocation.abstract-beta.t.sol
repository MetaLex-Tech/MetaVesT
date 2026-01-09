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

contract BaseAllocationAbstractBetaTest is Test {
    string saltStr = "BaseAllocationAbstractBetaTest";
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

    function test_DesiredRecipientUpdatedOnConstruct() public {
        bytes32 salt = keccak256(bytes("test_DesiredRecipientUpdatedOnConstruct"));

        vm.startPrank(authority);
        vm.expectEmit(true, true, true, true);
        emit BaseAllocation.MetaVesT_DesiredRecipientUpdated(alice, bob);
        RestrictedTokenAward vault = _createTestVault(bob); // grantee specify bob as the desired recipient
        vm.stopPrank();
    }

    /// @notice Should be able to create a metavest vault without recipient overrides nor grantee preference
    function test_createMetavestDefaultRecipient() public {
        vm.startPrank(authority);
        RestrictedTokenAward vault = _createTestVault(address(0)); // no grantee preference
        vm.stopPrank();

        assertEq(vault.desiredRecipient(), address(0), "should have no grantee preference");
        assertEq(vault.getRecipient(), alice, "should use grantee as the recipient");

        vm.expectEmit(true, true, true, true, address(vault));
        emit BaseAllocation.MetaVesT_Withdrawn(
            alice, // grantee
            alice, // recipient
            address(vestingToken), // tokenAddress
            1000e6 // amount
        );
        vm.prank(alice);
        vault.withdraw(1000e6);
        assertEq(vestingToken.balanceOf(alice), 1000e6, "alice should be able to withdraw cliff to her desired wallet");
    }

    /// @notice Should be able to create a metavest vault without recipient overrides but with grantee preference
    function test_createMetavestGranteePreference() public {
        vm.startPrank(authority);
        RestrictedTokenAward vault = _createTestVault(bob); // grantee specify bob as the desired recipient
        vm.stopPrank();

        assertEq(vault.desiredRecipient(), bob, "grantee preference should be set");
        assertEq(vault.getRecipient(), bob, "should use the grantee preference as the recipient");

        vm.expectEmit(true, true, true, true, address(vault));
        emit BaseAllocation.MetaVesT_Withdrawn(
            alice, // grantee
            bob, // recipient
            address(vestingToken), // tokenAddress
            1000e6 // amount
        );
        vm.prank(alice);
        vault.withdraw(1000e6);
        assertEq(vestingToken.balanceOf(bob), 1000e6, "alice should be able to withdraw cliff to her desired wallet");
    }

    /// @notice Should be able to create a metavest vault with recipient overrides and no grantee preference
    function test_createMetavestRecipientOverridden() public {
        vm.startPrank(authority);
        // Override recipient address
        controller.updateRecipientOverride(chad); // controller overrides recipient address to chad's
        RestrictedTokenAward vault = _createTestVault(bob); // grantee specify bob as the desired recipient, but it would be overridden and have no effects
        vm.stopPrank();

        assertEq(vault.desiredRecipient(), bob, "grantee preference should be set");
        assertEq(vault.getRecipient(), chad, "should use controller override as the recipient");

        vm.expectEmit(true, true, true, true, address(vault));
        emit BaseAllocation.MetaVesT_Withdrawn(
            alice, // grantee
            chad, // recipient
            address(vestingToken), // tokenAddress
            1000e6 // amount
        );
        vm.prank(alice);
        vault.withdraw(1000e6);
        assertEq(vestingToken.balanceOf(chad), 1000e6, "alice should be able to withdraw cliff to controller-overridden wallet");
    }

    function test_updateDesiredRecipient() public {
        vm.startPrank(authority);
        RestrictedTokenAward vault = _createTestVault(address(0)); // no grantee preference
        vm.stopPrank();

        vm.prank(alice);
        vm.expectEmit(true, true, true, true, address(vault));
        emit BaseAllocation.MetaVesT_DesiredRecipientUpdated(alice, bob);
        vault.updateDesiredRecipient(bob);
        assertEq(vault.desiredRecipient(), bob, "unexpected desiredRecipient");
    }

    function test_RevertIf_updateDesiredRecipientNotGrantee() public {
        vm.startPrank(authority);
        RestrictedTokenAward vault = _createTestVault(address(0)); // no grantee preference
        vm.stopPrank();

        vm.expectRevert(BaseAllocation.MetaVesT_OnlyGrantee.selector);
        vault.updateDesiredRecipient(chad);
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
                vestingStartTime: uint48(block.timestamp),
                unlockRate: 100e6,
                unlockStartTime: uint48(block.timestamp)
            }),
            new BaseAllocation.Milestone[](0),
            1e6, // no-op: exercisePrice
            address(paymentToken),
            0, // no-op: _shortStopDuration
            0 // no-op: _longStopDate
        ));
    }
}
