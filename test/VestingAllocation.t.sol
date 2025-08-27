// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import {ZkCappedMinterV2, IMintable} from "zk-governance/l2-contracts/src/ZkCappedMinterV2.sol";
import {ZkTokenV1} from "zk-governance/l2-contracts/src/ZkTokenV1.sol";
import {BaseAllocation} from "../src/BaseAllocation.sol";
import {VestingAllocation} from "../src/VestingAllocation.sol";
import {metavestController} from "../src/MetaVesTController.sol";

contract MockMetaVesTController {
    address public authority;
    address public zkCappedMinter;

    constructor(
        address _authority,
        address _zkCappedMinter
    ) {
        authority = _authority;
        zkCappedMinter = _zkCappedMinter;
    }

    function mint(address recipient, uint256 amount) external {
        ZkCappedMinterV2(zkCappedMinter).mint(recipient, amount);
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

    ZkTokenV1 zkToken;

    MockMetaVesTController mockController;
    VestingAllocation vestingAllocation;

    function setUp() public {
        zkToken = new ZkTokenV1();
        zkToken.initialize(address(this), address(this), 0 ether);

        // Deploy ZK Capped Minter v2
        ZkCappedMinterV2 zkCappedMinter = new ZkCappedMinterV2(
            IMintable(address(zkToken)),
            address(this),
            10000 ether,
            uint48(block.timestamp),
            uint48(block.timestamp + 365 days * 10)
        );

        // Grant ZkCappedMinter permissions
        zkToken.grantRole(zkToken.MINTER_ROLE(), address(zkCappedMinter));

        // Create mock controller
        mockController = new MockMetaVesTController(address(this), address(zkCappedMinter));

        // Grant controller minter privilege
        zkCappedMinter.grantRole(
            zkCappedMinter.MINTER_ROLE(),
            address(mockController)
        );

        BaseAllocation.Milestone[] memory milestones = new BaseAllocation.Milestone[](1);
        milestones[0] = BaseAllocation.Milestone({
            milestoneAward: 2000 ether,
            unlockOnCompletion: false,
            complete: false,
            conditionContracts: new address[](0)
        });

        vestingAllocation = new VestingAllocation(
            grantee,
            recipient,
            address(mockController),
            BaseAllocation.Allocation({
                tokenContract: address(zkToken),
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
    }

    function test_Metadata() public {
        assertEq(vestingAllocation.grantee(), grantee, "Unexpected grantee");
        assertEq(vestingAllocation.recipient(), recipient, "Unexpected recipient");
    }

    function test_Withdraw() public {
        // Should withdraw to recipient by default
        uint256 balanceBefore = zkToken.balanceOf(recipient);

        vm.expectEmit(true, true, true, true);
        emit BaseAllocation.MetaVesT_Withdrawn(grantee, recipient, address(zkToken), 100 ether);
        vm.prank(grantee);
        VestingAllocation(vestingAllocation).withdraw(100 ether);

        assertEq(zkToken.balanceOf(recipient), balanceBefore + 100 ether);
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
        uint256 balanceBefore = zkToken.balanceOf(newRecipient);
        vm.prank(grantee);
        VestingAllocation(vestingAllocation).withdraw(100 ether);
        assertEq(zkToken.balanceOf(newRecipient), balanceBefore + 100 ether);
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
        emit BaseAllocation.MetaVesT_Terminated(grantee, 0); // No token recovered because it is mint-on-demand
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

        console2.log("getAmountWithdrawable: %d", vestingAllocation.getAmountWithdrawable()); // 10 ether
        console2.log("getGoverningPower: %d", vestingAllocation.getGoverningPower()); // 10 ether

        mockController.updateMetavestVestingRate(address(vestingAllocation), 4 ether);

        // TODO this will fail because 4 ether/sec * 2 sec - 10 ether = -2 ether
        console2.log("getAmountWithdrawable: %d", vestingAllocation.getAmountWithdrawable());
        console2.log("getGoverningPower: %d", vestingAllocation.getGoverningPower());
    }
}
