pragma solidity ^0.8.20;

import "forge-std/Test.sol";

import "../test/controller.t.sol";

// TODO WIP: non-VestingAllocation tests are disabled until adopted ZkCappedMinter
contract Audit is MetaVestControllerTest {

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

        controller.terminateMetavestVesting(vestingAllocation);
        vm.warp(block.timestamp + 365 days);
         assertEq(VestingAllocation(vestingAllocation).getAmountWithdrawable(), (10e18 - 5e18) * 50, "Unexpected amount after termination");
        vm.startPrank(grantee);
        VestingAllocation(vestingAllocation).withdraw(VestingAllocation(vestingAllocation).getAmountWithdrawable());
        vm.stopPrank();
    }

//    function testAuditTerminateFailAfterWithdrawFixCheckOptions() public {
//        // template from testTerminateVestAndRecoverSlowUnlock
//        address vestingAllocation = createDummyTokenOptionAllocation();
//        uint256 snapshot = token.balanceOf(authority);
//        VestingAllocation(vestingAllocation).confirmMilestone(0);
//        vm.warp(block.timestamp + 5 seconds);
//        vm.startPrank(grantee);
//        ERC20Stable(paymentToken).approve(vestingAllocation, TokenOptionAllocation(vestingAllocation).getPaymentAmount(TokenOptionAllocation(vestingAllocation).getAmountExercisable()));
//        TokenOptionAllocation(vestingAllocation).exerciseTokenOption(TokenOptionAllocation(vestingAllocation).getAmountExercisable());
//        TokenOptionAllocation(vestingAllocation).withdraw(VestingAllocation(vestingAllocation).getAmountWithdrawable());
//        vm.warp(block.timestamp + 5 seconds);
//        ERC20Stable(paymentToken).approve(vestingAllocation, TokenOptionAllocation(vestingAllocation).getPaymentAmount(TokenOptionAllocation(vestingAllocation).getAmountExercisable()));
//        TokenOptionAllocation(vestingAllocation).exerciseTokenOption(TokenOptionAllocation(vestingAllocation).getAmountExercisable());
//        TokenOptionAllocation(vestingAllocation).withdraw(VestingAllocation(vestingAllocation).getAmountWithdrawable());
//        vm.stopPrank();
//        vm.warp(block.timestamp + 5 seconds);
//        controller.terminateMetavestVesting(vestingAllocation);
//
//        vm.startPrank(grantee);
//        ERC20Stable(paymentToken).approve(vestingAllocation, TokenOptionAllocation(vestingAllocation).getPaymentAmount(TokenOptionAllocation(vestingAllocation).getAmountExercisable()));
//        TokenOptionAllocation(vestingAllocation).exerciseTokenOption(TokenOptionAllocation(vestingAllocation).getAmountExercisable());
//        TokenOptionAllocation(vestingAllocation).withdraw(VestingAllocation(vestingAllocation).getAmountWithdrawable());
//        vm.stopPrank();
//        vm.warp(block.timestamp + 365 days);
//
//        vm.prank(authority);
//        TokenOptionAllocation(vestingAllocation).recoverForfeitTokens();
//        //check balance of the vesting contract
//        assertEq(token.balanceOf(vestingAllocation), 0);
//    }
}