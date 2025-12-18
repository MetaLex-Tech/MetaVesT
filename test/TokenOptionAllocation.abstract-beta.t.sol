// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.20;

import {BaseAllocation} from "../src/BaseAllocation.sol";
import {TokenOptionAllocation} from "../src/TokenOptionAllocation.sol";
import {RestrictedTokenFactory} from "../src/RestrictedTokenFactory.sol";
import {Test, console2} from "forge-std/Test.sol";
import {TokenOptionFactory} from "../src/TokenOptionFactory.sol";
import {VestingAllocationFactory} from "../src/VestingAllocationFactory.sol";
import {metavestController} from "../src/MetaVesTController.sol";
import {MockERC20} from "./mocks/MockERC20.sol";

contract TokenOptionAllocationAbstractBetaTest is Test {
    string saltStr = "TokenOptionAllocationAbstractBetaTest";
    bytes32 salt = keccak256(bytes(saltStr));

    address deployer = makeAddr("deployer");
    address authority = makeAddr("authority");
    address alice = makeAddr("alice");
    address bob = makeAddr("bob");
    address chad = makeAddr("chad");

    MockERC20 vestingToken = new MockERC20("Vesting Token", "VEST", 6);
    MockERC20 paymentToken = new MockERC20("Payment Token", "PAY", 6);

    metavestController controller;
    TokenOptionAllocation vault;

    function setUp() public {
        vm.startPrank(deployer);

        controller = new metavestController{salt: salt}(
            authority,
            authority,
            address(0), // _recipientOverride
            address(new VestingAllocationFactory{salt: salt}()),
            address(new TokenOptionFactory{salt: salt}()),
            address(new RestrictedTokenFactory{salt: salt}())
        );

        // Prepare funds

        vestingToken = new MockERC20("Vesting Token", "VEST", 6);
        paymentToken = new MockERC20("Payment Token", "PAY", 6);

        vestingToken.mint(authority, 10000e6);
        paymentToken.mint(alice, 100000e6);

        vm.stopPrank();

        vm.startPrank(authority);
        vestingToken.approve(address(controller), 10000e6);
        vm.stopPrank();
    }

    function test_SanityCheck() public {
        vm.prank(authority);
        TokenOptionAllocation vault = _createTestVault(
            address(0),
            uint48(block.timestamp), // vestingStartTime
            uint48(block.timestamp) // unlockStartTime
        );
        assertEq(vault.desiredRecipient(), address(0), "test vault should have no recipient preference set");
    }

    /// @notice Vesting token should go to the default recipient (grantee)
    function test_exerciseTokenOptionDefaultRecipient() public {
        uint48 now = uint48(block.timestamp);

        uint256 alicePaymentTokenBalanceBefore = paymentToken.balanceOf(alice);
        uint256 aliceVestingTokenBalanceBefore = vestingToken.balanceOf(alice);

        vm.prank(authority);
        TokenOptionAllocation vault = _createTestVault(
            address(0), // no grantee preference
            uint48(block.timestamp), // vestingStartTime
            uint48(block.timestamp) // unlockStartTime
        );

        vm.warp(now + 2); // 2 secs. into vesting & unlocking
        vm.startPrank(alice);
        paymentToken.approve(address(vault), 12000e6);
        // (1000 + 100 * 2) * 10 = 12000
        vm.expectEmit(true, true, true, true, address(vault));
        emit TokenOptionAllocation.MetaVesT_TokenOptionExercised(alice, 1200e6, 12000e6);
        vault.exerciseTokenOption(1200e6);
        vault.withdraw(1200e6);
        vm.stopPrank();

        // Payment is always coming from grantee
        assertEq(alicePaymentTokenBalanceBefore - paymentToken.balanceOf(alice), 12000e6, "unexpected payment");
        assertEq(vestingToken.balanceOf(alice) - aliceVestingTokenBalanceBefore, 1200e6, "unexpected received token amount");
    }

    /// @notice Vesting token should go to the recipient address set by grantee
    function test_exerciseTokenOptionGranteePreference() public {
        uint48 now = uint48(block.timestamp);

        uint256 alicePaymentTokenBalanceBefore = paymentToken.balanceOf(alice);
        uint256 bobVestingTokenBalanceBefore = vestingToken.balanceOf(bob);

        vm.prank(authority);
        TokenOptionAllocation vault = _createTestVault(
            bob, // set bob as the desired recipient
            uint48(block.timestamp), // vestingStartTime
            uint48(block.timestamp) // unlockStartTime
        );

        vm.warp(now + 2); // 2 secs. into vesting & unlocking
        vm.startPrank(alice);
        paymentToken.approve(address(vault), 12000e6);
        // (1000 + 100 * 2) * 10 = 12000
        vm.expectEmit(true, true, true, true, address(vault));
        emit TokenOptionAllocation.MetaVesT_TokenOptionExercised(alice, 1200e6, 12000e6);
        vault.exerciseTokenOption(1200e6);
        vault.withdraw(1200e6);
        vm.stopPrank();

        // Payment is always coming from grantee
        assertEq(alicePaymentTokenBalanceBefore - paymentToken.balanceOf(alice), 12000e6, "unexpected payment");
        assertEq(vestingToken.balanceOf(bob) - bobVestingTokenBalanceBefore, 1200e6, "unexpected received token amount");
    }

    /// @notice Vesting token should go to the recipient address set by the controller
    function test_exerciseTokenOptionControllerOverride() public {
        uint48 now = uint48(block.timestamp);

        uint256 alicePaymentTokenBalanceBefore = paymentToken.balanceOf(alice);
        uint256 chadVestingTokenBalanceBefore = vestingToken.balanceOf(chad);

        vm.prank(authority);
        TokenOptionAllocation vault = _createTestVault(
            bob, // set bob as the desired recipient, but it would be overridden and have no effects
            uint48(block.timestamp), // vestingStartTime
            uint48(block.timestamp) // unlockStartTime
        );

        // Override recipient address
        vm.prank(authority);
        controller.updateRecipientOverride(chad);

        vm.warp(now + 2); // 2 secs. into vesting & unlocking
        vm.startPrank(alice);
        paymentToken.approve(address(vault), 12000e6);
        // (1000 + 100 * 2) * 10 = 12000
        vm.expectEmit(true, true, true, true, address(vault));
        emit TokenOptionAllocation.MetaVesT_TokenOptionExercised(alice, 1200e6, 12000e6);
        vault.exerciseTokenOption(1200e6);
        vault.withdraw(1200e6);
        vm.stopPrank();

        // Payment is always coming from grantee
        assertEq(alicePaymentTokenBalanceBefore - paymentToken.balanceOf(alice), 12000e6, "unexpected payment");
        assertEq(vestingToken.balanceOf(chad) - chadVestingTokenBalanceBefore, 1200e6, "unexpected received token amount");
    }

    function test_RevertIf_exerciseTokenOptionShortStopDatePassed() public {
        uint48 now = uint48(block.timestamp);

        vm.prank(authority);
        TokenOptionAllocation vault = _createTestVault(
            address(0), // no grantee preference
            uint48(block.timestamp), // vestingStartTime
            uint48(block.timestamp) // unlockStartTime
        );

        // contract terminated and shortStop date has passed
        vm.prank(authority);
        controller.terminateMetavestVesting(address(vault));
        vm.warp(now + 11);

        vm.startPrank(alice);
        paymentToken.approve(address(vault), 100000e6);
        vm.expectRevert(BaseAllocation.MetaVest_ShortStopDatePassed.selector);
        vault.exerciseTokenOption(1e6);
        vm.stopPrank();
    }

    function test_RevertIf_exerciseTokenOptionMoreThanAvailable() public {
        uint48 now = uint48(block.timestamp);

        vm.startPrank(authority);
        TokenOptionAllocation vault = _createTestVault(
            address(0), // no grantee preference
            uint48(block.timestamp), // vestingStartTime
            uint48(block.timestamp) // unlockStartTime
        );

        vm.warp(now + 2); // 2 secs. into vesting & unlocking
        vm.startPrank(alice);
        paymentToken.approve(address(vault), 100000e6);
        // (1000 + 100 * 2) * 10 = 12000
        vm.expectRevert(BaseAllocation.MetaVesT_MoreThanAvailable.selector);
        vault.exerciseTokenOption(1201e6);
        vm.stopPrank();
    }

    function test_updateVestingStartTime() public {
        uint48 now = uint48(block.timestamp);

        vm.startPrank(authority);
        TokenOptionAllocation vault = _createTestVault(
            address(0), // no grantee preference
            uint48(now + 10), // vestingStartTime
            uint48(now + 20) // unlockStartTime
        );
        vm.stopPrank();

        {
            (,,,, uint48 vestingStartTime,,,) = vault.allocation();
            assertEq(vestingStartTime, now + 10, "unexpected vestingStartTime before update");
            assertEq(vault.getAmountExercisable(), 0, "unexpected getAmountExercisable() before update");
        }

        _consentStartTime(
            address(vault),
            metavestController.updateMetavestVestingStartTime.selector,
            abi.encodeWithSelector(metavestController.updateMetavestVestingStartTime.selector, address(vault), now + 30)
        );

        // Perform amendment
        vm.prank(authority);
        controller.updateMetavestVestingStartTime(address(vault), uint48(now + 30));

        {
            (,,,, uint48 vestingStartTime,,,) = vault.allocation();
            assertEq(vestingStartTime, now + 30, "unexpected vestingStartTime after update");

            vm.warp(now + 29);
            assertEq(vault.getAmountExercisable(), 0, "unexpected getAmountExercisable() after update & before new start time");
        }

        vm.warp(now + 30 + 2);
        // 1000 + 100 * 2 = 1200
        assertEq(vault.getAmountExercisable(), 1200e6, "unexpected getAmountExercisable() after update & after new start time");
    }

    function test_RevertIf_updateVestingStartTimeOldTimeAlreadyStarted() public {
        uint48 now = uint48(block.timestamp);

        vm.startPrank(authority);
        TokenOptionAllocation vault = _createTestVault(
            address(0), // no grantee preference
            uint48(now + 10), // vestingStartTime
            uint48(now + 20) // unlockStartTime
        );
        vm.stopPrank();

        _consentStartTime(
            address(vault),
            metavestController.updateMetavestVestingStartTime.selector,
            abi.encodeWithSelector(metavestController.updateMetavestVestingStartTime.selector, address(vault), now + 30)
        );

        // Old vestingStartTime has passed
        vm.warp(now + 10);

        // Perform amendment
        vm.expectRevert(BaseAllocation.MetaVesT_AlreadyStarted.selector);
        vm.prank(authority);
        controller.updateMetavestVestingStartTime(address(vault), now + 30);
    }

    function test_RevertIf_updateVestingStartTimeNewTimeAlreadyStarted() public {
        uint48 now = uint48(block.timestamp);

        vm.startPrank(authority);
        TokenOptionAllocation vault = _createTestVault(
            address(0), // no grantee preference
            uint48(now + 10), // vestingStartTime
            uint48(now + 20) // unlockStartTime
        );
        vm.stopPrank();

        _consentStartTime(
            address(vault),
            metavestController.updateMetavestVestingStartTime.selector,
            abi.encodeWithSelector(metavestController.updateMetavestVestingStartTime.selector, address(vault), now + 5)
        );

        // Old vestingStartTime has not passed, but new vestingStartTime has
        vm.warp(now + 5);

        // Perform amendment
        vm.expectRevert(BaseAllocation.MetaVesT_AlreadyStarted.selector);
        vm.prank(authority);
        controller.updateMetavestVestingStartTime(address(vault), now + 5);
    }

    function test_updateUnlockStartTime() public {
        uint48 now = uint48(block.timestamp);

        vm.startPrank(authority);
        TokenOptionAllocation vault = _createTestVault(
            address(0), // no grantee preference
            uint48(now + 10), // vestingStartTime
            uint48(now + 20) // unlockStartTime
        );
        vm.stopPrank();

        {
            (,,,,,, uint48 unlockStartTime,) = vault.allocation();
            assertEq(unlockStartTime, now + 20, "unexpected unlockStartTime before update");
            assertEq(vault.getUnlockedTokenAmount(), 0, "unexpected getUnlockedTokenAmount() before update");
        }

        _consentStartTime(
            address(vault),
            metavestController.updateMetavestUnlockStartTime.selector,
            abi.encodeWithSelector(metavestController.updateMetavestUnlockStartTime.selector, address(vault), now + 40)
        );

        // Perform amendment
        vm.prank(authority);
        controller.updateMetavestUnlockStartTime(address(vault), uint48(now + 40));

        {
            (,,,,,, uint48 unlockStartTime,) = vault.allocation();
            assertEq(unlockStartTime, now + 40, "unexpected unlockStartTime after update");

            vm.warp(now + 39);
            assertEq(vault.getUnlockedTokenAmount(), 0, "unexpected getUnlockedTokenAmount() after update & before new start time");
        }

        vm.warp(now + 40 + 2);
        // 1000 + 100 * 2 = 1200
        assertEq(vault.getUnlockedTokenAmount(), 1200e6, "unexpected getUnlockedTokenAmount() after update & after new start time");
    }

    function test_RevertIf_updateUnlockStartTimeOldTimeAlreadyStarted() public {
        uint48 now = uint48(block.timestamp);

        vm.startPrank(authority);
        TokenOptionAllocation vault = _createTestVault(
            address(0), // no grantee preference
            uint48(now + 10), // vestingStartTime
            uint48(now + 20) // unlockStartTime
        );
        vm.stopPrank();

        _consentStartTime(
            address(vault),
            metavestController.updateMetavestUnlockStartTime.selector,
            abi.encodeWithSelector(metavestController.updateMetavestUnlockStartTime.selector, address(vault), now + 40)
        );

        // Old unlockStartTime has passed
        vm.warp(now + 20);

        // Perform amendment
        vm.expectRevert(BaseAllocation.MetaVesT_AlreadyStarted.selector);
        vm.prank(authority);
        controller.updateMetavestUnlockStartTime(address(vault), now + 40);
    }

    function test_RevertIf_updateUnlockStartTimeNewTimeAlreadyStarted() public {
        uint48 now = uint48(block.timestamp);

        vm.startPrank(authority);
        TokenOptionAllocation vault = _createTestVault(
            address(0), // no grantee preference
            uint48(now + 10), // vestingStartTime
            uint48(now + 20) // unlockStartTime
        );
        vm.stopPrank();

        _consentStartTime(
            address(vault),
            metavestController.updateMetavestUnlockStartTime.selector,
            abi.encodeWithSelector(metavestController.updateMetavestUnlockStartTime.selector, address(vault), now + 15)
        );

        // Old unlockStartTime has not passed, but new unlockStartTime has
        vm.warp(now + 15);

        // Perform amendment
        vm.expectRevert(BaseAllocation.MetaVesT_AlreadyStarted.selector);
        vm.prank(authority);
        controller.updateMetavestUnlockStartTime(address(vault), now + 15);
    }

    function _createTestVault(
        address desiredRecipient,
        uint48 vestingStartTime,
        uint48 unlockStartTime
    ) internal returns (TokenOptionAllocation) {
        return TokenOptionAllocation(controller.createMetavest(
            metavestController.metavestType.TokenOption,
            alice,
            desiredRecipient,
            BaseAllocation.Allocation({
                tokenContract: address(vestingToken),
                tokenStreamTotal: 10000e6,
                vestingCliffCredit: 1000e6,
                unlockingCliffCredit: 1000e6,
                vestingRate: 100e6,
                vestingStartTime: vestingStartTime,
                unlockRate: 100e6,
                unlockStartTime: unlockStartTime
            }),
            new BaseAllocation.Milestone[](0),
            10e6,
            address(paymentToken),
            10, // shortStopDuration
            0 // no-op: _longStopDate
        ));
    }

    function _consentStartTime(address vaultAddr, bytes4 msgSig, bytes memory data) internal {
        // Propose amendment
        vm.prank(authority);
        controller.proposeMetavestAmendment(
            vaultAddr,
            msgSig,
            data
        );

        vm.stopPrank();

        // Approve amendment
        vm.prank(alice);
        controller.consentToMetavestAmendment(vaultAddr, msgSig, true);
    }
}
