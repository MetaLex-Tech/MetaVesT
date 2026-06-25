pragma solidity ^0.8.20;

import "forge-std/Test.sol";

import "../test/controller.t.sol";

contract Audit is MetaVestControllerTest {

    // Regression test for the audit finding "terminate fails after withdraw": terminating
    // after the grantee has withdrawn now succeeds instead of reverting on the token transfer.
    function testAuditTerminateSucceedsAfterWithdraw() public {
        // template from testTerminateVestAndRecoverSlowUnlock
        address vestingAllocation = createDummyVestingAllocationSlowUnlock();
        VestingAllocation(vestingAllocation).confirmMilestone(0);
        vm.warp(block.timestamp + 25 seconds);
        vm.startPrank(grantee);
        VestingAllocation(vestingAllocation).withdraw(VestingAllocation(vestingAllocation).getAmountWithdrawable());
        vm.warp(block.timestamp + 25 seconds);
        VestingAllocation(vestingAllocation).withdraw(VestingAllocation(vestingAllocation).getAmountWithdrawable());
        vm.stopPrank();

        controller.terminateMetavestVesting(vestingAllocation);
        assertTrue(VestingAllocation(vestingAllocation).terminated());
    }

    function testAuditTerminateVestAndRecovers() public {
        // template from testTerminateVestAndRecovers
        address vestingAllocation = createDummyVestingAllocation();
        uint256 snapshot = token.balanceOf(authority);

        BaseAllocation.Milestone[] memory milestones = new BaseAllocation.Milestone[](1);
        milestones[0] = BaseAllocation.Milestone({
            milestoneAward: 1000e18,
            unlockOnCompletion: false,
            complete: false,
            conditionContracts: new address[](0)
        }); 
        token.approve(address(controller), 2100e18);
        
        
        controller.addMetavestMilestone(vestingAllocation, milestones[0]);
        VestingAllocation(vestingAllocation).confirmMilestone(1);

        vm.warp(block.timestamp + 50 seconds);
        controller.terminateMetavestVesting(vestingAllocation);
        vm.startPrank(grantee);
        VestingAllocation(vestingAllocation).getVestedTokenAmount();
        VestingAllocation(vestingAllocation).getUnlockedTokenAmount();

        VestingAllocation(vestingAllocation).withdraw(VestingAllocation(vestingAllocation).getAmountWithdrawable());
        vm.stopPrank();
        // assertEq(token.balanceOf(vestingAllocation), 0);
    }

    function test_RevertWhen_AuditRounding() public {
        // template from testConfirmingMilestoneTokenOption
        address vestingAllocation = createDummyTokenOptionAllocation();
        TokenOptionAllocation(vestingAllocation).confirmMilestone(0);
        vm.warp(block.timestamp + 50 seconds);
        vm.startPrank(grantee);
        //exercise max available
        ERC20Stable(paymentToken).approve(vestingAllocation, TokenOptionAllocation(vestingAllocation).getPaymentAmount(TokenOptionAllocation(vestingAllocation).getAmountExercisable()));

        // exercising a fractional amount rounds the payment down below the minimum
        vm.expectRevert(BaseAllocation.MetaVesT_TooSmallAmount.selector);
        TokenOptionAllocation(vestingAllocation).exerciseTokenOption(1.1e12);
        vm.stopPrank();
    }

    function testAuditExcercisePrice() public {
        // template from testConfirmingMilestoneTokenOption
        address vestingAllocation = createDummyTokenOptionAllocation();
        uint256 snapshot = token.balanceOf(authority);
        TokenOptionAllocation(vestingAllocation).confirmMilestone(0);
        vm.warp(block.timestamp + 50 seconds);
        vm.startPrank(grantee);
        //exercise max available
        ERC20Stable(paymentToken).approve(vestingAllocation, TokenOptionAllocation(vestingAllocation).getPaymentAmount(TokenOptionAllocation(vestingAllocation).getAmountExercisable()));
        
        console.log('before amount of payment token:', ERC20Stable(paymentToken).balanceOf(grantee));
        console.log('before tokensExercised: ', TokenOptionAllocation(vestingAllocation).tokensExercised());

        TokenOptionAllocation(vestingAllocation).exerciseTokenOption(1e18);

        console.log('after amount of payment token: ', ERC20Stable(paymentToken).balanceOf(grantee));
        console.log('after tokensExercised: ', TokenOptionAllocation(vestingAllocation).tokensExercised());
        // TokenOptionAllocation(vestingAllocation).withdraw(VestingAllocation(vestingAllocation).getAmountWithdrawable());
        vm.stopPrank();
    }
}