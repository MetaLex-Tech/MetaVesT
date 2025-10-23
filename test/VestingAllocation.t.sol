// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import {MockERC20} from "./mocks/MockERC20.sol";
import {BaseAllocation} from "../src/BaseAllocation.sol";
import {VestingAllocation} from "../src/VestingAllocation.sol";
import {metavestController} from "../src/MetaVesTController.sol";

contract MockMetaVesTController {
    address public authority;

    constructor(
        address _authority
    ) {
        authority = _authority;
    }

    function updateMetavestVestingRate(
        address _grant,
        uint160 _vestingRate
    ) external {
        BaseAllocation(_grant).updateVestingRate(_vestingRate);
    }
}

contract VestingAllocationTest is Test {

    address grantee = address(0xa);
    address recipient = address(0xb);
    address newRecipient = address(0xc);

    MockERC20 paymentToken;

    MockMetaVesTController mockController;
    VestingAllocation vestingAllocation;

    function setUp() public {
        // Provision payment token
        paymentToken = new MockERC20("Payment Token", "PAY", 18);

        // Create mock controller
        mockController = new MockMetaVesTController(address(this));

        BaseAllocation.Milestone[] memory milestones = new BaseAllocation.Milestone[](1);
        milestones[0] = BaseAllocation.Milestone({
            milestoneAward: 2000 ether,
            unlockOnCompletion: false,
            complete: false,
            conditionContracts: new address[](0)
        });

        // Provision the vesting contract
        vestingAllocation = new VestingAllocation(
            grantee,
            recipient,
            address(mockController),
            BaseAllocation.Allocation({
                tokenContract: address(paymentToken),
                tokenStreamTotal: 1000 ether,
                vestingCliffCredit: 100 ether,
                unlockingCliffCredit: 100 ether,
                vestingRate: 10 ether,
                vestingStartTime: uint48(block.timestamp),
                unlockRate: 10 ether,
                unlockStartTime: uint48(block.timestamp)
            }),
            milestones
        );
        paymentToken.mint(
            address(vestingAllocation),
            1000 ether + 2000 ether // allocation.tokenStreamTotal + milestones[].milestoneAward
        );
    }

    function test_Metadata() public {
        assertEq(vestingAllocation.grantee(), grantee, "Unexpected grantee");
        assertEq(vestingAllocation.recipient(), recipient, "Unexpected recipient");
    }

    /// @notice Since MetaVesT uses ERC20 token's native precision, one must beware of precision loss
    /// when calculating the vesting/unlocking rates
    function test_RevertIf_LowPrecisionLowAmount() public {
        MockERC20 lowPrecisionPaymentToken = new MockERC20("Low Precision Payment Token", "LPAY", 6);

        // Provision the vesting contract

        // Seemingly innocent rate of 10 tokens over a year = 10 / (365 * 24 * 3600) = 0.0000003170979198 token / sec.
        // However, it would be truncated to 0 if represented in 6 decimals
        uint160 rate = uint160(10e6) / 365 days;

        vm.expectRevert(BaseAllocation.MetaVesT_RateTooLow.selector);
        vestingAllocation = new VestingAllocation(
            grantee,
            recipient,
            address(mockController),
            BaseAllocation.Allocation({
                tokenContract: address(lowPrecisionPaymentToken),
                tokenStreamTotal: 10e6,
                vestingCliffCredit: 0e6,
                unlockingCliffCredit: 0e6,
                vestingRate: rate,
                vestingStartTime: uint48(block.timestamp),
                unlockRate: rate,
                unlockStartTime: uint48(block.timestamp)
            }),
            new BaseAllocation.Milestone[](0)
        );
    }

    function test_Withdraw() public {
        // Should withdraw to recipient by default
        uint256 balanceBefore = paymentToken.balanceOf(recipient);

        vm.expectEmit(true, true, true, true);
        emit BaseAllocation.MetaVesT_Withdrawn(grantee, recipient, address(paymentToken), 100 ether);
        vm.prank(grantee);
        VestingAllocation(vestingAllocation).withdraw(100 ether);

        assertEq(paymentToken.balanceOf(recipient), balanceBefore + 100 ether);
    }

    function test_RevertIf_WithdrawTooMuch() public {
        vm.prank(grantee);
        vm.expectRevert(abi.encodeWithSelector(BaseAllocation.MetaVesT_MoreThanAvailable.selector));
        VestingAllocation(vestingAllocation).withdraw(101 ether);
    }

    function test_UpdateRecipient() public {
        // Grantee should be able to update recipient
        vm.prank(grantee);
        vm.expectEmit(true, true, true, true);
        emit BaseAllocation.MetaVesT_UpdatedRecipient(grantee, newRecipient);
        VestingAllocation(vestingAllocation).updateRecipient(newRecipient);

        // Should withdraw to new recipient now
        uint256 balanceBefore = paymentToken.balanceOf(newRecipient);
        vm.prank(grantee);
        VestingAllocation(vestingAllocation).withdraw(100 ether);
        assertEq(paymentToken.balanceOf(newRecipient), balanceBefore + 100 ether);
    }

    function test_RevertIf_UpdateRecipientNonGrantee() public {
        vm.expectRevert(abi.encodeWithSelector(BaseAllocation.MetaVesT_OnlyGrantee.selector));
        VestingAllocation(vestingAllocation).updateRecipient(newRecipient);
    }

    function test_Terminate() public {
        // Controller should be able to terminate it
        assertFalse(vestingAllocation.terminated(), "vesting contract should not be terminated yet");
        vm.prank(address(mockController));
        vm.expectEmit(true, true, true, true);
        emit BaseAllocation.MetaVesT_Terminated(
            grantee,
            2900 ether // 1000 + 2000 - 100 (vested cliff)
        );
        vestingAllocation.terminate();
        assertTrue(vestingAllocation.terminated(), "vesting contract should be terminated");
    }

    function test_RevertIf_TerminateNonController() public {
        vm.expectRevert(abi.encodeWithSelector(BaseAllocation.MetaVesT_OnlyController.selector));
        vestingAllocation.terminate();
    }

    function test_GetGoverningPowerAfterVestingRateReduction() public {
        // Withdraw cliff amount first
        vm.prank(grantee);
        VestingAllocation(vestingAllocation).withdraw(100 ether);

        skip(2 seconds);
        assertEq(vestingAllocation.getAmountWithdrawable(), 10 ether * 2);
        assertEq(vestingAllocation.getGoverningPower(), 10 ether * 2);

        vm.prank(grantee);
        VestingAllocation(vestingAllocation).withdraw(10 ether);

        assertEq(vestingAllocation.getAmountWithdrawable(), 10 ether * 2 - 10 ether);
        assertEq(vestingAllocation.getGoverningPower(), 10 ether * 2 - 10 ether);

        mockController.updateMetavestVestingRate(address(vestingAllocation), 4 ether);

        // 4 ether/sec * 2 sec - 10 ether = -2 ether < 0
        assertEq(vestingAllocation.getAmountWithdrawable(), 0 ether);
        assertEq(vestingAllocation.getGoverningPower(), 0 ether);
    }
}
