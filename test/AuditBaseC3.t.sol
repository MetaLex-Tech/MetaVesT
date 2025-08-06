pragma solidity ^0.8.20;

import "forge-std/Test.sol";

import "../test/controller.t.sol";

// TODO WIP: non-VestingAllocation tests are disabled until adopted ZkCappedMinter
contract Audit is MetaVestControllerTest {

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

//    function test_RevertIf_AuditRounding() public {
//        // template from testConfirmingMilestoneTokenOption
//        address vestingAllocation = createDummyTokenOptionAllocation();
//        uint256 snapshot = token.balanceOf(authority);
//        TokenOptionAllocation(vestingAllocation).confirmMilestone(0);
//        vm.warp(block.timestamp + 50 seconds);
//        vm.startPrank(grantee);
//        //exercise max available
//        ERC20Stable(paymentToken).approve(vestingAllocation, TokenOptionAllocation(vestingAllocation).getPaymentAmount(TokenOptionAllocation(vestingAllocation).getAmountExercisable()));
//
//        console.log('before amount of payment token:', ERC20Stable(paymentToken).balanceOf(grantee));
//        console.log('before tokensExercised: ', TokenOptionAllocation(vestingAllocation).tokensExercised());
//        console.log('small amount payment: ', TokenOptionAllocation(vestingAllocation).getPaymentAmount(1e6));
//        console.log('small amount payment: ', TokenOptionAllocation(vestingAllocation).getPaymentAmount(1e11));
//        console.log('small amount payment: ', TokenOptionAllocation(vestingAllocation).getPaymentAmount(9.99e11));
//        console.log('small amount payment: ', TokenOptionAllocation(vestingAllocation).getPaymentAmount(1e12));
//        console.log('small amount payment: ', TokenOptionAllocation(vestingAllocation).getPaymentAmount(1.1e12));
//        console.log('small amount payment: ', TokenOptionAllocation(vestingAllocation).getPaymentAmount(1e13));
//        TokenOptionAllocation(vestingAllocation).exerciseTokenOption(1.1e12);
//        TokenOptionAllocation(vestingAllocation).exerciseTokenOption(1e6);
//        TokenOptionAllocation(vestingAllocation).exerciseTokenOption(1e6);
//        TokenOptionAllocation(vestingAllocation).exerciseTokenOption(1e6);
//        TokenOptionAllocation(vestingAllocation).exerciseTokenOption(1e6);
//        TokenOptionAllocation(vestingAllocation).exerciseTokenOption(1e6);
//
//        console.log('after amount of payment token: ', ERC20Stable(paymentToken).balanceOf(grantee));
//        console.log('after tokensExercised: ', TokenOptionAllocation(vestingAllocation).tokensExercised());
//        // TokenOptionAllocation(vestingAllocation).withdraw(VestingAllocation(vestingAllocation).getAmountWithdrawable());
//        vm.stopPrank();
//    }
//
//    function testAuditExcercisePrice() public {
//        // template from testConfirmingMilestoneTokenOption
//        address vestingAllocation = createDummyTokenOptionAllocation();
//        uint256 snapshot = token.balanceOf(authority);
//        TokenOptionAllocation(vestingAllocation).confirmMilestone(0);
//        vm.warp(block.timestamp + 50 seconds);
//        vm.startPrank(grantee);
//        //exercise max available
//        ERC20Stable(paymentToken).approve(vestingAllocation, TokenOptionAllocation(vestingAllocation).getPaymentAmount(TokenOptionAllocation(vestingAllocation).getAmountExercisable()));
//
//        console.log('before amount of payment token:', ERC20Stable(paymentToken).balanceOf(grantee));
//        console.log('before tokensExercised: ', TokenOptionAllocation(vestingAllocation).tokensExercised());
//
//        TokenOptionAllocation(vestingAllocation).exerciseTokenOption(1e18);
//
//        console.log('after amount of payment token: ', ERC20Stable(paymentToken).balanceOf(grantee));
//        console.log('after tokensExercised: ', TokenOptionAllocation(vestingAllocation).tokensExercised());
//        // TokenOptionAllocation(vestingAllocation).withdraw(VestingAllocation(vestingAllocation).getAmountWithdrawable());
//        vm.stopPrank();
//    }
}
