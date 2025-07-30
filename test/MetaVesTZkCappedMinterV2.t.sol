// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.20;

import "../src/MetaVesTController.sol";
import "../src/RestrictedTokenFactory.sol";
import "../src/TokenOptionFactory.sol";
import "../src/VestingAllocationFactory.sol";
import "../src/interfaces/zk-governance/IZkTokenV1.sol";
import "forge-std/Test.sol";

// TODO this does not use the actual ZkCappedMinterV2 yet. Still v1
contract MetaVesTZkCappedMinterV2Test is Test {
    address zkTokenAdmin;
    IZkTokenV1 zkToken;
    IZkCappedMinterFactory zkCappedMinterFactory;

    address authority = address(0x2);
    address dao = address(0x3);
    address grantee = address(0x4);

    VestingAllocationFactory vestingAllocationFactory;
    TokenOptionFactory tokenOptionFactory;
    RestrictedTokenFactory restrictedTokenFactory;

    metavestController controller;

    function setUp() public {
        // zkSync Era Sepolia does not work, but the addresses aren't verified anyways
        zkTokenAdmin = 0x0d9DD6964692a0027e1645902536E7A3b34AA1d7;
        zkToken = IZkTokenV1(0x69e5DC39E2bCb1C17053d2A4ee7CAEAAc5D36f96);
        zkCappedMinterFactory = IZkCappedMinterFactory(0x4dBBd2dE17F811B5281a79275a66f4a8aFbc7bc7);
        // TODO try zkSync Era mainnet
//        zkToken = ZkTokenV2(0x5A7d6b2F92C77FAD6CCaBd7EE0624E64907Eaf3E);
//        zkCappedMinterFactory = ZkCappedMinterFactory(0x4dBBd2dE17F811B5281a79275a66f4a8aFbc7bc7);
//        zkToken = new ZkTokenV2();
//        zkCappedMinterFactory = new ZkCappedMinterFactory(0x073749a0f8ed0d49b1acfd4e0efdc59328c83d0c2eed9ee099a3979f0c332ff8);

        vestingAllocationFactory = new VestingAllocationFactory();
        tokenOptionFactory = new TokenOptionFactory();
        restrictedTokenFactory = new RestrictedTokenFactory();

        controller = new metavestController(
            authority,
            dao,
            address(vestingAllocationFactory),
            address(tokenOptionFactory),
            address(restrictedTokenFactory),
            address(zkCappedMinterFactory),
            address(zkToken)
        );
    }

    // Test by forge test --zksync --fork-url https://zksync-sepolia.g.alchemy.com/v2/<api-key> --mc MetaVesTZkCappedMinterV2Test
    function test_GuardianCompensationYear1_2() public {
        // TODO guardians to sign agreements

        // Create MetaVesT for grantee

        BaseAllocation.Allocation memory allocation = BaseAllocation.Allocation({
            tokenContract: address(zkToken),
            tokenStreamTotal: 1000e18,
            vestingCliffCredit: 100e18,
            unlockingCliffCredit: 100e18,
            vestingRate: 10e18,
            vestingStartTime: uint48(block.timestamp),
            unlockRate: 10e18,
            unlockStartTime: uint48(block.timestamp)
        });

        BaseAllocation.Milestone[] memory milestones = new BaseAllocation.Milestone[](1);
        milestones[0] = BaseAllocation.Milestone({
            milestoneAward: 100e18,
            unlockOnCompletion: true,
            complete: false,
            conditionContracts: new address[](0)
        });

        VestingAllocation vestingAllocation = VestingAllocation(controller.createMetavest(
            metavestController.metavestType.Vesting,
            grantee,
            allocation,
            milestones,
            0,
            address(0),
            0,
            0
        ));
        assertEq(zkToken.balanceOf(address(vestingAllocation)), 0, "Vesting contract should not have any token (it is minted on-the-fly)");

        // Simulate TPP approval and ZK Token admin to grant our ZkCappedMinter access

        bytes32 minterRole = zkToken.MINTER_ROLE();
        // TODO this is a hack. Ideally we should not create one ZkCappedMinter for every MetaVesT created. We should share it so only one ZkCappedMinter needs TPP approval
        address zkCappedMinter = BaseAllocation(vestingAllocation).ZkCappedMinterAddress();
        vm.prank(zkTokenAdmin);
        zkToken.grantRole(minterRole, zkCappedMinter);

        // Simulate grantee withdrawal
        // Since there is a cliff and vesting/unlock starts immediately, the grantee should be able to withdraw the cliff amount

        uint256 balanceBefore = zkToken.balanceOf(grantee);
        vm.prank(grantee);
        vestingAllocation.withdraw(100e18);
        assertEq(zkToken.balanceOf(grantee), balanceBefore + 100e18, "Grantee should be able to withdraw cliff amount");
        assertEq(zkToken.balanceOf(address(vestingAllocation)), 0, "Vesting contract should not have any token (it is minted on-the-fly)");
    }
}
