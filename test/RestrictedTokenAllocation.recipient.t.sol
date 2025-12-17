// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.20;

import {BaseAllocation} from "../src/BaseAllocation.sol";
import {MetaVesTFactory} from "../src/MetaVesTFactory.sol";
import {RestrictedTokenAward} from "../src/RestrictedTokenAllocation.sol";
import {RestrictedTokenFactory} from "../src/RestrictedTokenFactory.sol";
import {Test, console2} from "forge-std/Test.sol";
import {TokenOptionFactory} from "../src/TokenOptionFactory.sol";
import {VestingAllocationFactory} from "../src/VestingAllocationFactory.sol";
import {metavestController} from "../src/MetaVesTController.sol";
import {MockERC20} from "./mocks/MockERC20.sol";

contract RestrictedTokenAwardRecipientTest is Test {
    string saltStr = "RestrictedTokenAwardTest";
    bytes32 salt = keccak256(bytes(saltStr));

    address deployer = makeAddr("deployer");
    address authority = makeAddr("authority");
    address alice = makeAddr("alice");
    address bob = makeAddr("bob");
    address chad = makeAddr("chad");

    MockERC20 vestingToken = new MockERC20("Vesting Token", "VEST", 6);
    MockERC20 paymentToken = new MockERC20("Payment Token", "PAY", 6);

    MetaVesTFactory controllerFactory;
    metavestController controller;
    RestrictedTokenAward vault;

    function setUp() public {
        vm.startPrank(deployer);

        controllerFactory = new MetaVesTFactory{salt: salt}();

        controller = metavestController(controllerFactory.deployMetavestAndController(
            authority,
            authority,
            address(0), // _recipientOverride
            address(new VestingAllocationFactory{salt: salt}()),
            address(new TokenOptionFactory{salt: salt}()),
            address(new RestrictedTokenFactory{salt: salt}())
        ));

        // Prepare funds

        vestingToken = new MockERC20("Vesting Token", "VEST", 6);
        paymentToken = new MockERC20("Payment Token", "PAY", 6);

        vestingToken.mint(authority, 10000e6);
        paymentToken.mint(authority, 100000e6);

        vm.stopPrank();

        vm.startPrank(authority);
        vestingToken.approve(address(controller), 10000e6);
        vm.stopPrank();
    }

    function test_SanityCheck() public {
        vm.prank(authority);
        RestrictedTokenAward vault = _createTestVault(address(0));
        assertEq(vault.desiredRecipient(), address(0), "test vault should have no recipient preference set");
    }

    /// @notice Payment should go to the default recipient (grantee)
    function test_claimRepurchasedTokensDefaultRecipient() public {
        uint256 alicePaymentTokenBalanceBefore = paymentToken.balanceOf(alice);

        RestrictedTokenAward vault = _createAndTerminateTestVault(address(0)); // no grantee preference
        vm.prank(alice);
        vault.claimRepurchasedTokens();

        assertEq(paymentToken.balanceOf(alice) - alicePaymentTokenBalanceBefore, 88000e6, "unexpected received payment");
    }

    function test_claimRepurchasedTokensGranteePreference() public {
        uint256 bobPaymentTokenBalanceBefore = paymentToken.balanceOf(bob);

        RestrictedTokenAward vault = _createAndTerminateTestVault(bob); // set bob as the desired recipient
        vm.prank(alice);
        vault.claimRepurchasedTokens();

        assertEq(paymentToken.balanceOf(bob) - bobPaymentTokenBalanceBefore, 88000e6, "unexpected received payment");
    }

    function test_claimRepurchasedTokensControllerOverride() public {
        RestrictedTokenAward vault = _createAndTerminateTestVault(bob); // set bob as the desired recipient, but it would be overridden and have no effects

        // Override recipient address
        vm.prank(authority);
        controller.updateRecipientOverride(chad);

        uint256 chadPaymentTokenBalanceBefore = paymentToken.balanceOf(chad);

        vm.prank(alice);
        vault.claimRepurchasedTokens();

        assertEq(paymentToken.balanceOf(chad) - chadPaymentTokenBalanceBefore, 88000e6, "unexpected received payment");
    }

    function test_RevertIf_repurchaseTokensShortStopTimeNotReached() public {
        vm.startPrank(authority);
        RestrictedTokenAward vault = _createTestVault(address(0)); // no grantee preference

        // 2% vested & unlocked
        vm.warp(block.timestamp + 2);

        controller.terminateMetavestVesting(address(vault));

        // Not enough wait for shortStopDuration
        vm.warp(block.timestamp + 9);

        paymentToken.approve(address(vault), 100000e6);
        vm.expectRevert(BaseAllocation.MetaVesT_ShortStopTimeNotReached.selector);
        vault.repurchaseTokens(8800e6); // 10000 - (1000 + 100 * 2) at the time of creation

        vm.stopPrank();
    }

    function test_RevertIf_repurchaseTokensMoreThanAvailable() public {
        vm.startPrank(authority);
        RestrictedTokenAward vault = _createTestVault(address(0)); // no grantee preference

        // 2% vested & unlocked
        vm.warp(block.timestamp + 2);

        controller.terminateMetavestVesting(address(vault));

        // Wait for shortStopDuration
        vm.warp(block.timestamp + 10);

        paymentToken.approve(address(vault), 100000e6);
        vm.expectRevert(BaseAllocation.MetaVesT_MoreThanAvailable.selector);
        vault.repurchaseTokens(8801e6); // 10000 - (1000 + 100 * 2) at the time of creation, plus one

        vm.stopPrank();
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
            10e6,
            address(paymentToken),
            10, // shortStopDuration
            0 // no-op: _longStopDate
        ));
    }

    function _createAndTerminateTestVault(address desiredRecipient) internal returns (RestrictedTokenAward) {
        vm.startPrank(authority);

        RestrictedTokenAward vault = _createTestVault(desiredRecipient);

        // 2% vested & unlocked
        vm.warp(block.timestamp + 2);

        controller.terminateMetavestVesting(address(vault));

        // Wait for shortStopDuration
        vm.warp(block.timestamp + 10);

        uint256 authorityPaymentTokenBalanceBefore = paymentToken.balanceOf(authority);
        uint256 authorityVestingTokenBalanceBefore = vestingToken.balanceOf(authority);

        paymentToken.approve(address(vault), 100000e6);
        vault.repurchaseTokens(8800e6); // 10000 - (1000 + 100 * 2) at the time of creation

        assertEq(authorityPaymentTokenBalanceBefore - paymentToken.balanceOf(authority), 88000e6, "unexpected paid payment");
        assertEq(vestingToken.balanceOf(authority) - authorityVestingTokenBalanceBefore, 8800e6, "unexpected repurchased token amount");

        vm.stopPrank();

        return vault;
    }
}
