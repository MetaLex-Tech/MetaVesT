// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
//import {ERC20} from "openzeppelin-contracts/contracts/token/ERC20/ERC20.sol";
import {ZkCappedMinterV2, IMintable} from "zk-governance/l2-contracts/src/ZkCappedMinterV2.sol";
import {ZkTokenV1} from "zk-governance/l2-contracts/src/ZkTokenV1.sol";
import {BaseAllocation} from "../src/BaseAllocation.sol";
import {VestingAllocation} from "../src/VestingAllocation.sol";

//contract TestToken is ERC20 {
//    uint8 _decimals;
//
//    constructor(uint256 initialSupply, uint8 __decimals) ERC20("Test Token", "TestUSDC") {
//        _decimals = __decimals;
//        _mint(msg.sender, initialSupply);
//    }
//
//    function decimals() public view override returns (uint8) {
//        return _decimals;
//    }
//}

contract VestingAllocationTest is Test {

    address grantee = address(0xa);
    address recipient = address(0xb);
    address newRecipient = address(0xc);

    ZkTokenV1 zkToken;

    VestingAllocation vestingAllocation;

    function setUp() public {
        zkToken = new ZkTokenV1();
        zkToken.initialize(address(this), address(this), 0 ether);

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
            address(this),
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

        // Deploy ZK Capped Minter v2
        ZkCappedMinterV2 zkCappedMinter = new ZkCappedMinterV2(
            IMintable(address(zkToken)),
            address(this),
            10000 ether,
            uint48(block.timestamp),
            uint48(block.timestamp + 365 days * 10)
        );

        // Grant ZkCappedMinter permissions
        bytes32 minterRole = zkToken.MINTER_ROLE();
        zkToken.grantRole(minterRole, address(zkCappedMinter));

        // Grant MetaVesT minter privilege
        zkCappedMinter.grantRole(
            zkCappedMinter.MINTER_ROLE(),
            address(vestingAllocation)
        );
        vestingAllocation.setZkCappedMinterAddress(address(zkCappedMinter));
    }

    function test_metadata() public {
        assertEq(vestingAllocation.grantee(), grantee, "Unexpected grantee");
        assertEq(vestingAllocation.recipient(), recipient, "Unexpected recipient");
    }

    function test_withdraw() public {
        // Should withdraw to recipient by default
        uint256 balanceBefore = zkToken.balanceOf(recipient);

        vm.expectEmit(true, true, true, true);
        emit BaseAllocation.MetaVesT_Withdrawn(grantee, recipient, address(zkToken), 100 ether);
        vm.prank(grantee);
        VestingAllocation(vestingAllocation).withdraw(100 ether);

        assertEq(zkToken.balanceOf(recipient), balanceBefore + 100 ether);
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

    function test_RevertIf_NonGranteeUpdateRecipient() public {
        vm.expectRevert(abi.encodeWithSelector(BaseAllocation.MetaVesT_OnlyGrantee.selector));
        VestingAllocation(vestingAllocation).updateRecipient(newRecipient);
    }
}
