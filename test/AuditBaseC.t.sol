pragma solidity ^0.8.20;

import "forge-std/Test.sol";

import "./lib/MetaVesTControllerTestBaseExtended.sol";

contract Audit is MetaVesTControllerTestBaseExtended {

    function test_RevertIf_AuditTerminateFailAfterWithdraw() public {
        // template from testTerminateVestAndRecoverSlowUnlock
        address vestingAllocation = createDummyVestingAllocationSlowUnlock();
        uint256 snapshot = vestingToken.balanceOf(authority);
        VestingAllocation(vestingAllocation).confirmMilestone(0);
        vm.warp(block.timestamp + 25 seconds);
        vm.startPrank(grantee);
        VestingAllocation(vestingAllocation).withdraw(VestingAllocation(vestingAllocation).getAmountWithdrawable());
        vm.warp(block.timestamp + 25 seconds);
        VestingAllocation(vestingAllocation).withdraw(VestingAllocation(vestingAllocation).getAmountWithdrawable());
        vm.stopPrank();

        // InsufficientBalance
        vm.expectRevert();
        controller.terminateMetavestVesting(vestingAllocation);
    }

     function testAuditTerminateFailAfterWithdrawFixCheck() public {
        // template from testTerminateVestAndRecoverSlowUnlock
        address vestingAllocation = createDummyVestingAllocationSlowUnlock();
        VestingAllocation(vestingAllocation).confirmMilestone(0);
        vm.startPrank(grantee);
         skip(25 seconds);
         assertEq(VestingAllocation(vestingAllocation).getAmountWithdrawable(), 1000e18 + 100e18 + 25 * 5e18, "Unexpected amount after cliff and milestone");
        VestingAllocation(vestingAllocation).withdraw(VestingAllocation(vestingAllocation).getAmountWithdrawable());
         skip(25 seconds);
         assertEq(VestingAllocation(vestingAllocation).getAmountWithdrawable(), 25 * 5e18, "Unexpected amount after the second vesting period");
        VestingAllocation(vestingAllocation).withdraw(VestingAllocation(vestingAllocation).getAmountWithdrawable());
        vm.stopPrank();
         vm.prank(authority);
        controller.terminateMetavestVesting(vestingAllocation);
        skip(1200 seconds);
         assertEq(VestingAllocation(vestingAllocation).getAmountWithdrawable(), (10e18 - 5e18) * 50, "Unexpected amount after termination");
        vm.startPrank(grantee);
        VestingAllocation(vestingAllocation).withdraw(VestingAllocation(vestingAllocation).getAmountWithdrawable());
        vm.stopPrank();
    }

    function testAuditTerminateFailAfterWithdrawFixCheckOptions() public {
        // template from testTerminateVestAndRecoverSlowUnlock
        address metavest = createDummyTokenOptionAllocation();
        TokenOptionAllocation(metavest).confirmMilestone(0);

        paymentToken.mint(grantee, 2000e18);

        vm.warp(block.timestamp + 5 seconds);

        vm.startPrank(grantee);
        paymentToken.approve(metavest, TokenOptionAllocation(metavest).getPaymentAmount(TokenOptionAllocation(metavest).getAmountExercisable()));
        TokenOptionAllocation(metavest).exerciseTokenOption(TokenOptionAllocation(metavest).getAmountExercisable());
        TokenOptionAllocation(metavest).withdraw(TokenOptionAllocation(metavest).getAmountWithdrawable());

        vm.warp(block.timestamp + 5 seconds);

        paymentToken.approve(metavest, TokenOptionAllocation(metavest).getPaymentAmount(TokenOptionAllocation(metavest).getAmountExercisable()));
        TokenOptionAllocation(metavest).exerciseTokenOption(TokenOptionAllocation(metavest).getAmountExercisable());
        TokenOptionAllocation(metavest).withdraw(TokenOptionAllocation(metavest).getAmountWithdrawable());
        vm.stopPrank();

        vm.warp(block.timestamp + 5 seconds);
        vm.prank(authority);
        controller.terminateMetavestVesting(metavest);

        vm.startPrank(grantee);
        paymentToken.approve(metavest, TokenOptionAllocation(metavest).getPaymentAmount(TokenOptionAllocation(metavest).getAmountExercisable()));
        TokenOptionAllocation(metavest).exerciseTokenOption(TokenOptionAllocation(metavest).getAmountExercisable());
        TokenOptionAllocation(metavest).withdraw(TokenOptionAllocation(metavest).getAmountWithdrawable());
        vm.stopPrank();

        vm.warp(block.timestamp + 365 days);

        vm.prank(authority);
        TokenOptionAllocation(metavest).recoverForfeitTokens();

        //check balance of the vesting contract
        assertEq(paymentToken.balanceOf(metavest), 0);
    }
}