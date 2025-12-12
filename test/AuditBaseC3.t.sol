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

    function testAuditTerminateVestAndRecovers() public {
        // template from testTerminateVestAndRecovers
        address vestingAllocation = createDummyVestingAllocation();

        BaseAllocation.Milestone[] memory milestones = new BaseAllocation.Milestone[](1);
        milestones[0] = BaseAllocation.Milestone({
            milestoneAward: 1000e18,
            unlockOnCompletion: false,
            complete: false,
            conditionContracts: new address[](0)
        });
        vm.prank(authority);
        controller.addMetavestMilestone(vestingAllocation, milestones[0]);
        VestingAllocation(vestingAllocation).confirmMilestone(1);

        skip(50 seconds);
        vm.prank(authority);
        controller.terminateMetavestVesting(vestingAllocation);
        vm.startPrank(grantee);
        assertEq(VestingAllocation(vestingAllocation).getVestedTokenAmount(), 100e18 + 1000e18 + 10e18 * 50, "Unexpected vested amount after termination");
        assertEq(VestingAllocation(vestingAllocation).getUnlockedTokenAmount(), 100e18 + 5e18 * 50 + 5e18 * 50, "Unexpected unlocked amount after termination");

        VestingAllocation(vestingAllocation).withdraw(VestingAllocation(vestingAllocation).getAmountWithdrawable());
        vm.stopPrank();
        // assertEq(token.balanceOf(vestingAllocation), 0);
    }

    function test_AuditRounding() public {
        // template from testConfirmingMilestoneTokenOption
        address metavest = createDummyTokenOptionAllocation();
        TokenOptionAllocation(metavest).confirmMilestone(0);

        vm.warp(block.timestamp + 50 seconds);

        paymentToken.mint(grantee, 550_002_500_000);

        vm.startPrank(grantee);
        //exercise max available
        paymentToken.approve(metavest, TokenOptionAllocation(metavest).getPaymentAmount(TokenOptionAllocation(metavest).getAmountExercisable()));

        console2.log('before amount of payment token:', paymentToken.balanceOf(grantee));
        assertEq(TokenOptionAllocation(metavest).tokensExercised(), 0, "no token exercised yet");
        assertEq(TokenOptionAllocation(metavest).getPaymentAmount(1e6), 5e5);
        assertEq(TokenOptionAllocation(metavest).getPaymentAmount(1e11), 5e10);
        assertEq(TokenOptionAllocation(metavest).getPaymentAmount(9.99e11), 4.995e11);
        assertEq(TokenOptionAllocation(metavest).getPaymentAmount(1e12), 5e11);
        assertEq(TokenOptionAllocation(metavest).getPaymentAmount(1.1e12), 5.5e11);
        assertEq(TokenOptionAllocation(metavest).getPaymentAmount(1e13), 5e12);
        TokenOptionAllocation(metavest).exerciseTokenOption(1.1e12);
        assertEq(TokenOptionAllocation(metavest).tokensExercised(), 1.1e12);
        TokenOptionAllocation(metavest).exerciseTokenOption(1e6);
        assertEq(TokenOptionAllocation(metavest).tokensExercised(), 1100001e6);
        TokenOptionAllocation(metavest).exerciseTokenOption(1e6);
        assertEq(TokenOptionAllocation(metavest).tokensExercised(), 1100002e6);
        TokenOptionAllocation(metavest).exerciseTokenOption(1e6);
        assertEq(TokenOptionAllocation(metavest).tokensExercised(), 1100003e6);
        TokenOptionAllocation(metavest).exerciseTokenOption(1e6);
        assertEq(TokenOptionAllocation(metavest).tokensExercised(), 1100004e6);
        TokenOptionAllocation(metavest).exerciseTokenOption(1e6);
        assertEq(TokenOptionAllocation(metavest).tokensExercised(), 1100005e6);

        console2.log('after amount of payment token: ', paymentToken.balanceOf(grantee));
        assertEq(TokenOptionAllocation(metavest).getAmountWithdrawable(), 1100005e6, "should be able to withdraw all exercised");
        TokenOptionAllocation(metavest).withdraw(TokenOptionAllocation(metavest).getAmountWithdrawable());
        vm.stopPrank();
    }

    function testAuditExercisePrice() public {
        // template from testConfirmingMilestoneTokenOption
        address metavest = createDummyTokenOptionAllocation();
        TokenOptionAllocation(metavest).confirmMilestone(0);

        vm.warp(block.timestamp + 50 seconds);

        paymentToken.mint(grantee, 0.5e18);

        vm.startPrank(grantee);
        //exercise max available
        paymentToken.approve(metavest, TokenOptionAllocation(metavest).getPaymentAmount(TokenOptionAllocation(metavest).getAmountExercisable()));

        console2.log('before amount of payment token:', paymentToken.balanceOf(grantee));
        assertEq(TokenOptionAllocation(metavest).tokensExercised(), 0, "no token exercised yet");

        TokenOptionAllocation(metavest).exerciseTokenOption(1e18);

        console2.log('after amount of payment token: ', paymentToken.balanceOf(grantee));
        assertEq(TokenOptionAllocation(metavest).tokensExercised(), 1e18, "should have exercised");
        TokenOptionAllocation(metavest).withdraw(TokenOptionAllocation(metavest).getAmountWithdrawable());
        vm.stopPrank();
    }
}
