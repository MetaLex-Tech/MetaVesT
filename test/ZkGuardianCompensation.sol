// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.20;

import "../src/MetaVesTController.sol";
import "../src/RestrictedTokenFactory.sol";
import "../src/TokenOptionFactory.sol";
import "../src/VestingAllocationFactory.sol";
import "../src/interfaces/zk-governance/IZkTokenV1.sol";
import "forge-std/Test.sol";

// TODO this does not use the actual ZkCappedMinterV2 yet. Still v1
contract ZkGuardianCompensationTest is Test {
    // zkSync Era Sepolia @ 5576300
    address zkTokenAdmin = 0x0d9DD6964692a0027e1645902536E7A3b34AA1d7;
    IZkTokenV1 zkToken = IZkTokenV1(0x69e5DC39E2bCb1C17053d2A4ee7CAEAAc5D36f96);
    IZkCappedMinterV2Factory zkCappedMinterFactory = IZkCappedMinterV2Factory(0x329CE320a0Ef03F8c0E01195604b5ef7D3Fb150E);
//    // zkSync Era mainnet
//    address zkTokenAdmin = 0xe5d21A9179CA2E1F0F327d598D464CcF60d89c3d;
//    IZkTokenV1 zkToken = IZkTokenV1(0x5A7d6b2F92C77FAD6CCaBd7EE0624E64907Eaf3E);
//    IZkCappedMinterV2Factory zkCappedMinterFactory = IZkCappedMinterV2Factory(0x0400E6bc22B68686Fb197E91f66E199C6b0DDD6a);

    IZkCappedMinterV2 zkCappedMinter;

    address deployer = address(0x2);
    address guardianSafe = address(0x3);
    address alice = address(0x4);
    address bob = address(0x5);

    VestingAllocationFactory vestingAllocationFactory;
    TokenOptionFactory tokenOptionFactory;
    RestrictedTokenFactory restrictedTokenFactory;

    metavestController controller;

    // Parameters
    bytes32 salt = keccak256("MetaLexZkSyncTest");
    uint256 cap = 1e6 ether;
    uint48 cappedMinterStartTime = uint48(block.timestamp + 30 days);
    uint48 cappedMinterExpirationTime = uint48(block.timestamp + 30 days + 365 days * 2);

    function setUp() public {
        vm.startPrank(deployer);

        // Deploy MetaVesT controller

        vestingAllocationFactory = new VestingAllocationFactory();
        tokenOptionFactory = new TokenOptionFactory();
        restrictedTokenFactory = new RestrictedTokenFactory();

        controller = new metavestController{salt: salt}(
            guardianSafe,
            guardianSafe,
            address(vestingAllocationFactory),
            address(tokenOptionFactory),
            address(restrictedTokenFactory)
        );

        // Deploy ZK Capped Minter v2

        zkCappedMinter = IZkCappedMinterV2(zkCappedMinterFactory.createCappedMinter(
            address(zkToken),
            address(controller), // Grant controller admin privilege so it can grant minter privilege to deployed MetaVesT
            cap,
            cappedMinterStartTime,
            cappedMinterExpirationTime,
            uint256(salt)
        ));

        vm.stopPrank();

        vm.prank(guardianSafe);
        controller.setZkCappedMinter(address(zkCappedMinter));
    }

    // Test by forge test --zksync --via-ir
    function test_GuardianCompensationYear1_2() public {
        // Assume ZK Capped Minter and its MetaVesTController counterpart are already deployed

        // Guardians to sign agreements and register on MetaVesTController

        BaseAllocation.Milestone[] memory milestones = new BaseAllocation.Milestone[](0);
        vm.startPrank(guardianSafe);
        controller.registerGrantee(
            metavestController.metavestType.Vesting,
            alice,
            alice,
            BaseAllocation.Allocation({
                tokenContract: address(zkToken),
                tokenStreamTotal: 1000e18,
                vestingCliffCredit: 100e18,
                unlockingCliffCredit: 100e18,
                vestingRate: 10e18,
                vestingStartTime: zkCappedMinter.START_TIME(), // start along with capped minter
                unlockRate: 10e18,
                unlockStartTime: zkCappedMinter.START_TIME() // start along with capped minter
            }),
            milestones,
            "ipfs.io/ipfs/[cid]",
            hex"1234" // TODO WIP: signature of all arguments above
        );
        controller.registerGrantee(
            metavestController.metavestType.Vesting,
            bob,
            bob,
            BaseAllocation.Allocation({
                tokenContract: address(zkToken),
                tokenStreamTotal: 2000e18,
                vestingCliffCredit: 200e18,
                unlockingCliffCredit: 200e18,
                vestingRate: 20e18,
                vestingStartTime: zkCappedMinter.START_TIME(), // start along with capped minter
                unlockRate: 20e18,
                unlockStartTime: zkCappedMinter.START_TIME() // start along with capped minter
            }),
            milestones,
            "ipfs.io/ipfs/[cid]",
            hex"1234" // TODO WIP: signature of all arguments above
        );
        vm.stopPrank();

        // TPP to review agreements and on-chain parameters, then approve by granting our ZkCappedMinter permissions

        bytes32 minterRole = zkToken.MINTER_ROLE();
        vm.prank(zkTokenAdmin);
        zkToken.grantRole(minterRole, address(zkCappedMinter));

        // Anyone can create MetaVesT for Alice and Bob (per agreements) to start vesting

        VestingAllocation vestingAllocationAlice = VestingAllocation(controller.createMetavest(0));
        assertEq(zkToken.balanceOf(address(vestingAllocationAlice)), 0, "Alice's vesting contract should not have any token (it mints on-demand)");

        VestingAllocation vestingAllocationBob = VestingAllocation(controller.createMetavest(1));
        assertEq(zkToken.balanceOf(address(vestingAllocationBob)), 0, "Vesting contract should not have any token (it mints on-demand)");

        // Alice and Bob should be able to start withdrawal after capped minter and MetaVesT start
        skip(30 days);

        granteeWithdrawAndAsserts(vestingAllocationAlice, 100e18, "Alice cliff");
        granteeWithdrawAndAsserts(vestingAllocationBob, 200e18, "Bob cliff");

        // Alice and Bob should be able to withdrawal all remaining tokens after sufficient time passed
        skip(90 seconds);

        granteeWithdrawAndAsserts(vestingAllocationAlice, 900e18, "Alice full");
        granteeWithdrawAndAsserts(vestingAllocationBob, 1800e18, "Bob full");
    }

    function granteeWithdrawAndAsserts(VestingAllocation vestingAllocation, uint256 amount, string memory assertName) public {
        address grantee = vestingAllocation.grantee();
        uint256 balanceBefore = zkToken.balanceOf(grantee);
        assertEq(vestingAllocation.getAmountWithdrawable(), amount, string(abi.encodePacked(assertName, ": unexpected withdrawable amount after cliff")));
        vm.prank(grantee);
        vestingAllocation.withdraw(amount);
        assertEq(zkToken.balanceOf(grantee), balanceBefore + amount, string(abi.encodePacked(assertName, ": unexpected received amount")));
        assertEq(zkToken.balanceOf(address(vestingAllocation)), 0, string(abi.encodePacked(assertName, ": vesting contract should not have any token (it mints on-demand)")));
    }
}
