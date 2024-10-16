pragma solidity ^0.8.20;

import "forge-std/Test.sol";

import "../test/controller.t.sol";

contract Audit is MetaVestControllerTest {

    function testFailAuditTerminateFailAfterWithdraw() public {
        // template from testTerminateVestAndRecoverSlowUnlock
        address vestingAllocation = createDummyVestingAllocationSlowUnlock();
        uint256 snapshot = token.balanceOf(authority);
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
        uint256 snapshot = token.balanceOf(authority);
        VestingAllocation(vestingAllocation).confirmMilestone(0);
        vm.warp(block.timestamp + 25 seconds);
        vm.startPrank(grantee);
        VestingAllocation(vestingAllocation).withdraw(VestingAllocation(vestingAllocation).getAmountWithdrawable());
        vm.warp(block.timestamp + 25 seconds);
        VestingAllocation(vestingAllocation).withdraw(VestingAllocation(vestingAllocation).getAmountWithdrawable());
        vm.stopPrank();

        controller.terminateMetavestVesting(vestingAllocation);
        vm.warp(block.timestamp + 365 days);
        vm.startPrank(grantee);
        VestingAllocation(vestingAllocation).withdraw(VestingAllocation(vestingAllocation).getAmountWithdrawable());
        vm.stopPrank();
        //check balance of the vesting contract
        assertEq(token.balanceOf(vestingAllocation), 0);
    }

    function testAuditTerminateFailAfterWithdrawFixCheckOptions() public {
        // template from testTerminateVestAndRecoverSlowUnlock
        address vestingAllocation = createDummyTokenOptionAllocation();
        uint256 snapshot = token.balanceOf(authority);
        VestingAllocation(vestingAllocation).confirmMilestone(0);
        vm.warp(block.timestamp + 5 seconds);
        vm.startPrank(grantee);
        ERC20Stable(paymentToken).approve(vestingAllocation, TokenOptionAllocation(vestingAllocation).getPaymentAmount(TokenOptionAllocation(vestingAllocation).getAmountExercisable()));
        TokenOptionAllocation(vestingAllocation).exerciseTokenOption(TokenOptionAllocation(vestingAllocation).getAmountExercisable());
        TokenOptionAllocation(vestingAllocation).withdraw(VestingAllocation(vestingAllocation).getAmountWithdrawable());
        vm.warp(block.timestamp + 5 seconds);
        ERC20Stable(paymentToken).approve(vestingAllocation, TokenOptionAllocation(vestingAllocation).getPaymentAmount(TokenOptionAllocation(vestingAllocation).getAmountExercisable()));
        TokenOptionAllocation(vestingAllocation).exerciseTokenOption(TokenOptionAllocation(vestingAllocation).getAmountExercisable());
        TokenOptionAllocation(vestingAllocation).withdraw(VestingAllocation(vestingAllocation).getAmountWithdrawable());
        vm.stopPrank();
        vm.warp(block.timestamp + 5 seconds);
        controller.terminateMetavestVesting(vestingAllocation);
      
        vm.startPrank(grantee);
        ERC20Stable(paymentToken).approve(vestingAllocation, TokenOptionAllocation(vestingAllocation).getPaymentAmount(TokenOptionAllocation(vestingAllocation).getAmountExercisable()));
        TokenOptionAllocation(vestingAllocation).exerciseTokenOption(TokenOptionAllocation(vestingAllocation).getAmountExercisable());
        TokenOptionAllocation(vestingAllocation).withdraw(VestingAllocation(vestingAllocation).getAmountWithdrawable());
        vm.stopPrank();
        vm.warp(block.timestamp + 365 days);

        vm.prank(authority);
        TokenOptionAllocation(vestingAllocation).recoverForfeitTokens();
        //check balance of the vesting contract
        assertEq(token.balanceOf(vestingAllocation), 0);
    }

}