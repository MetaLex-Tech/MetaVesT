pragma solidity ^0.8.20;

import "forge-std/Test.sol";

import "../test/controller.t.sol";

contract Audit is MetaVestControllerTest {

    function testAuditTerminateFailAfterWithdraw() public {
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

}