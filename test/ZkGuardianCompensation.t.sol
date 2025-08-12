// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.20;

import "../src/MetaVesTController.sol";
import "../src/VestingAllocationFactory.sol";
import "../src/interfaces/zk-governance/IZkCappedMinterV2.sol";
import "../src/interfaces/zk-governance/IZkTokenV1.sol";
import "./lib/MetaVesTControllerTestBase.sol";
import {CyberAgreementRegistry} from "cybercorps-contracts/src/CyberAgreementRegistry.sol";

// Test by forge test --zksync --via-ir
contract ZkGuardianCompensationTest is MetaVesTControllerTestBase {
    // Parameters
    uint256 cap = 1e6 ether; // 1M ZK
    uint48 cappedMinterStartTime = 1756684800; // 2025/9/1 UTC
    uint48 cappedMinterExpirationTime = cappedMinterStartTime + 365 days * 2; // Expect to vest over an year with a margin of an extra year for withdrawal

    function setUp() public override {
        // Assume deployment 7 days before the vesting starts
        vm.warp(cappedMinterStartTime - 7 days);

        MetaVesTControllerTestBase.setUp();

        vm.startPrank(deployer);

        // Deploy MetaVesT controller

        vestingAllocationFactory = new VestingAllocationFactory();

        controller = metavestController(address(new ERC1967Proxy{salt: salt}(
            address(new metavestController{salt: salt}()),
            abi.encodeWithSelector(
                metavestController.initialize.selector,
                guardianSafe,
                guardianSafe,
                address(registry),
                address(vestingAllocationFactory)
            )
        )));

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

    function test_GuardianCompensationYear1_2() public {
        // Assume ZK Capped Minter and its MetaVesTController counterpart are already deployed

        (address metavestAddressAlice, address metavestAddressBob) = _guardiansSignAndTppPass();

        VestingAllocation vestingAllocationAlice = VestingAllocation(metavestAddressAlice);
        assertEq(zkToken.balanceOf(address(vestingAllocationAlice)), 0, "Alice's vesting contract should not have any token (it mints on-demand)");

        VestingAllocation vestingAllocationBob = VestingAllocation(metavestAddressBob);
        assertEq(zkToken.balanceOf(address(vestingAllocationBob)), 0, "Vesting contract should not have any token (it mints on-demand)");

        // Grantees should not be able to withdraw yet
        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(BaseAllocation.MetaVesT_MoreThanAvailable.selector));
        vestingAllocationAlice.withdraw(1 ether);
        vm.prank(bob);
        vm.expectRevert(abi.encodeWithSelector(BaseAllocation.MetaVesT_MoreThanAvailable.selector));
        vestingAllocationBob.withdraw(1 ether);

        // Grantees should be able to start withdrawal after capped minter and MetaVesT start
        vm.warp(cappedMinterStartTime);

        _granteeWithdrawAndAsserts(vestingAllocationAlice, 50e3 ether, "Alice cliff");
        _granteeWithdrawAndAsserts(vestingAllocationBob, 40e3 ether, "Bob cliff");

        // Grantees should be able to withdraw all remaining tokens after sufficient time passed
        skip(365 days + 1);

        _granteeWithdrawAndAsserts(vestingAllocationAlice, 50e3 ether, "Alice full");
        _granteeWithdrawAndAsserts(vestingAllocationBob, 30e3 ether, "Bob partial");

        // Grantees should be able to withdraw within an year after vesting ends
        skip(364 days);

        _granteeWithdrawAndAsserts(vestingAllocationBob, 10e3 ether, "Bob full");
    }
    
    function test_AdminToolingCompensation() public {
        (address metavestAddressAlice, address metavestAddressBob) = _guardiansSignAndTppPass();
        VestingAllocation vestingAllocationAlice = VestingAllocation(metavestAddressAlice);

        // Vesting starts and a month has passed
        vm.warp(cappedMinterStartTime + 30 days);

        _granteeWithdrawAndAsserts(vestingAllocationAlice, uint256(50e3 ether) + uint160(50e3 ether) / 365 days * 30 days, "Alice cliff + first month");

        // Second month
        skip(30 days);

        // Add new grantee for admin/tooling compensation

        // Guardian SAFE to delegate signing to an EOA
        vm.prank(guardianSafe);
        registry.setDelegation(delegate, block.timestamp + 60);
        assertTrue(registry.isValidDelegate(guardianSafe, delegate), "delegate should be Guardian SAFE's delegate");

        bytes32 contractIdChad = _proposeAndSignDeal(
            templateId,
            block.timestamp, // salt
            delegatePrivateKey,
            chad,
            BaseAllocation.Allocation({
                tokenContract: address(zkToken),
                // 10k ZK total in one cliff
                tokenStreamTotal: 10e3 ether,
                vestingCliffCredit: 10e3 ether,
                unlockingCliffCredit: 10e3 ether,
                vestingRate: 0,
                vestingStartTime: 0,
                unlockRate: 0,
                unlockStartTime: 0
            }),
            new BaseAllocation.Milestone[](0),
            "Chad",
            cappedMinterExpirationTime // Same expiry as the minter so grantee can defer vesting contract creation as much as possible
        );
        VestingAllocation vestingAllocationChad = VestingAllocation(_granteeSignDeal(
            contractIdChad,
            chad, // grantee
            chad, // recipient
            chadPrivateKey,
            "Chad"
        ));
        _granteeWithdrawAndAsserts(vestingAllocationChad, 10e3 ether, "Chad cliff");
    }

    function _guardiansSignAndTppPass() internal returns(address, address) {
        // Guardian SAFE to delegate signing to an EOA
        vm.prank(guardianSafe);
        registry.setDelegation(delegate, block.timestamp + 60);
        assertTrue(registry.isValidDelegate(guardianSafe, delegate), "delegate should be Guardian SAFE's delegate");

        // Guardian SAFE to propose deals on MetaVesTController

        bytes32 contractIdAlice = _proposeAndSignDeal(
            templateId,
            block.timestamp, // salt
            delegatePrivateKey,
            alice,
            BaseAllocation.Allocation({
                tokenContract: address(zkToken),
            // 100k ZK total, the first half unlocks with a cliff and the second half unlocks over an year
                tokenStreamTotal: 100e3 ether,
                vestingCliffCredit: 50e3 ether,
                unlockingCliffCredit: 50e3 ether,
                vestingRate: uint160(50e3 ether) / 365 days,
                vestingStartTime: zkCappedMinter.START_TIME(), // start along with capped minter
                unlockRate: uint160(50e3 ether) / 365 days,
                unlockStartTime: zkCappedMinter.START_TIME() // start along with capped minter
            }),
            new BaseAllocation.Milestone[](0),
            "Alice",
            block.timestamp + 7 days
        );

        bytes32 contractIdBob = _proposeAndSignDeal(
            templateId,
            block.timestamp, // salt
            delegatePrivateKey,
            bob,
            BaseAllocation.Allocation({
                tokenContract: address(zkToken),
            // 80k ZK total, the first half unlocks with a cliff and the second half unlocks over an year
                tokenStreamTotal: 80e3 ether,
                vestingCliffCredit: 40e3 ether,
                unlockingCliffCredit: 40e3 ether,
                vestingRate: uint160(40e3 ether) / 365 days,
                vestingStartTime: zkCappedMinter.START_TIME(), // start along with capped minter
                unlockRate: uint160(40e3 ether) / 365 days,
                unlockStartTime: zkCappedMinter.START_TIME() // start along with capped minter
            }),
            new BaseAllocation.Milestone[](0),
            "Bob",
            block.timestamp + 7 days
        );

        // Guardians to sign agreements

        address metavestAlice = _granteeSignDeal(
            contractIdAlice,
            alice, // grantee
            alice, // recipient
            alicePrivateKey,
            "Alice"
        );

        address metavestBob = _granteeSignDeal(
            contractIdBob,
            bob, // grantee
            bob, // recipient
            bobPrivateKey,
            "Bob"
        );

        // TPP to review agreements and on-chain parameters, then approve by granting our ZkCappedMinter permissions

        bytes32 minterRole = zkToken.MINTER_ROLE();
        vm.prank(zkTokenAdmin);
        zkToken.grantRole(minterRole, address(zkCappedMinter));

        return (metavestAlice, metavestBob);
    }
}
