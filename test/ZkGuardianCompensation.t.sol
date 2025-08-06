// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.20;

import "../src/MetaVesTController.sol";
import "../src/VestingAllocationFactory.sol";
import "../src/interfaces/zk-governance/IZkCappedMinterV2.sol";
import "../src/interfaces/zk-governance/IZkTokenV1.sol";
import "./lib/MetaVesTUtils.sol";
import "./lib/MetaVesTControllerTestBase.sol";
import {CyberAgreementRegistry} from "cybercorps-contracts/CyberAgreementRegistry.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

// Test by forge test --zksync --via-ir
contract ZkGuardianCompensationTest is MetaVesTControllerTestBase {
    // Parameters
    bytes32 salt = keccak256("MetaLexZkSyncTest");
    uint256 cap = 1e6 ether; // 1M ZK
    uint48 cappedMinterStartTime = 1756684800; // 2025/9/1 UTC
    uint48 cappedMinterExpirationTime = cappedMinterStartTime + 365 days * 2; // Expect to vest over an year with a margin of an extra year for withdrawal

    function setUp() public {
        // Assume deployment 7 days before the vesting starts
        vm.warp(cappedMinterStartTime - 7 days);

        vm.startPrank(deployer);

        // Deploy CyberAgreementRegistry
        // TODO who should be the owner of auth?
        auth = new BorgAuth{salt: salt}(deployer);
        registry = CyberAgreementRegistry(address(new ERC1967Proxy{salt: salt}(
            address(new CyberAgreementRegistry{salt: salt}()),
            abi.encodeWithSelector(
                CyberAgreementRegistry.initialize.selector,
                address(auth)
            )
        )));

        // Deploy MetaVesT controller

        vestingAllocationFactory = new VestingAllocationFactory();

        controller = new metavestController{salt: salt}(
            guardianSafe,
            guardianSafe,
            address(vestingAllocationFactory)
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

    function test_GuardianCompensationYear1_2() public {
        // Assume ZK Capped Minter and its MetaVesTController counterpart are already deployed

        (bytes32 contractIdAlice, bytes32 contractIdBob) = _guardiansSignAndTppPass();

        // Anyone can create MetaVesT for Alice and Bob (per agreements) to start vesting

        VestingAllocation vestingAllocationAlice = VestingAllocation(controller.createMetavest(contractIdAlice));
        assertEq(zkToken.balanceOf(address(vestingAllocationAlice)), 0, "Alice's vesting contract should not have any token (it mints on-demand)");

        VestingAllocation vestingAllocationBob = VestingAllocation(controller.createMetavest(contractIdBob));
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
        (bytes32 contractIdAlice, bytes32 contractIdBob) = _guardiansSignAndTppPass();

        // Vesting starts and a month has passed
        vm.warp(cappedMinterStartTime + 30 days);

        // Alice creates vesting contract and start withdrawal
        VestingAllocation vestingAllocationAlice = VestingAllocation(controller.createMetavest(contractIdAlice));
        _granteeWithdrawAndAsserts(vestingAllocationAlice, uint256(50e3 ether) + uint160(50e3 ether) / 365 days * 30 days, "Alice cliff + first month");

        // Second month
        skip(30 days);

        // Add new grantee for admin/tooling compensation
        bytes32 contractIdChad = _signAndCreateContract(
            guardianSafe,
            chad,
            chadPrivateKey,
            "ipfs.io/ipfs/[cid]",
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
            new BaseAllocation.Milestone[](0)
        );
        VestingAllocation vestingAllocationChad = VestingAllocation(controller.createMetavest(contractIdChad));
        _granteeWithdrawAndAsserts(vestingAllocationChad, 10e3 ether, "Chad cliff");
    }

    function test_RevertIf_NotAuthority() public {
        // Non Guardian SAFE should not be able to accept agreement and create contract
        _signAndCreateContract(
            deployer, // Not authority
            alice,
            alicePrivateKey,
            "ipfs.io/ipfs/[cid]",
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
            new BaseAllocation.Milestone[](0),
            abi.encodeWithSelector(metavestController.MetaVesTController_OnlyAuthority.selector) // Expected revert
        );
    }

    function test_RevertIf_IncorrectAgreementSignature() public {
        // Register Alice with someone else's signature should fail
        _signAndCreateContract(
            guardianSafe,
            alice,
            bobPrivateKey, // Use someone else to sign
            "ipfs.io/ipfs/[cid]",
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
            new BaseAllocation.Milestone[](0),
            abi.encodeWithSelector(metavestController.MetaVesTController_SignatureVerificationFailed.selector) // Expected revert
        );
    }

    function test_DelegateSignature() public {
        // Alice to delegate to Bob
        vm.prank(alice);
        controller.setDelegation(bob, block.timestamp + 60);
        assertTrue(controller.isValidDelegate(alice, bob), "Bob should be Alice's delegate");

        // Bob should be able to sign for Alice now
        bytes32 contractId = _signAndCreateContract(
            guardianSafe,
            alice,
            bobPrivateKey, // Use Bob to sign
            "ipfs.io/ipfs/[cid]",
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
            new BaseAllocation.Milestone[](0)
        );
        metavestController.AgreementData memory agreement = controller.getAgreement(contractId);
        assertEq(agreement.signedData.grantee, alice, "Alice should be the grantee");

        // Wait until expiry
        skip(61);

        // Bob should no longer be able to sign for Alice
        assertFalse(controller.isValidDelegate(alice, bob), "Bob should no longer be Alice's delegate");
        _signAndCreateContract(
            guardianSafe,
            alice,
            bobPrivateKey, // Use Bob to sign
            "ipfs.io/ipfs/[cid]",
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
            new BaseAllocation.Milestone[](0),
            abi.encodeWithSelector(metavestController.MetaVesTController_SignatureVerificationFailed.selector) // Expected revert
        );
    }

    function _guardiansSignAndTppPass() internal returns(bytes32, bytes32) {
        // Guardians to sign agreements and register on MetaVesTController

        bytes32 contractIdAlice = _signAndCreateContract(
            guardianSafe,
            alice,
            alicePrivateKey,
            "ipfs.io/ipfs/[cid]",
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
            new BaseAllocation.Milestone[](0)
        );

        bytes32 contractIdBob = _signAndCreateContract(
            guardianSafe,
            bob,
            bobPrivateKey,
            "ipfs.io/ipfs/[cid]",
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
            new BaseAllocation.Milestone[](0)
        );

        // TPP to review agreements and on-chain parameters, then approve by granting our ZkCappedMinter permissions

        bytes32 minterRole = zkToken.MINTER_ROLE();
        vm.prank(zkTokenAdmin);
        zkToken.grantRole(minterRole, address(zkCappedMinter));

        return (contractIdAlice, contractIdBob);
    }
}
