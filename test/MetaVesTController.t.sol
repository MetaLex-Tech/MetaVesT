// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.20;

import "../src/MetaVesTController.sol";
import "../src/VestingAllocationFactory.sol";
import "../src/interfaces/zk-governance/IZkCappedMinterV2.sol";
import "../src/interfaces/zk-governance/IZkTokenV1.sol";
import "./lib/MetaVesTUtils.sol";
import "./lib/MetaVesTControllerTestBase.sol";

// Test by forge test --zksync --via-ir
contract MetaVesTControllerTest is MetaVesTControllerTestBase {
    // Parameters
    bytes32 salt = keccak256("MetaVesTControllerTest");
    uint256 cap = 100 ether;
    uint48 cappedMinterStartTime = uint48(block.timestamp + 60); // Minter start 60 seconds later
    uint48 cappedMinterExpirationTime = uint48(cappedMinterStartTime + 120); // Minter expired 120 seconds after start

    function setUp() public {
        vm.startPrank(deployer);

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

    function test_RevertIf_ExceedCap() public {
        // Add a large grant that exceeds the cap
        bytes32 contractIdChad = _signAndCreateContract(
            guardianSafe,
            chad,
            chadPrivateKey,
            "ipfs.io/ipfs/[cid]",
            BaseAllocation.Allocation({
                tokenContract: address(zkToken),
                // 101 ZK total in one cliff
                tokenStreamTotal: 101 ether,
                vestingCliffCredit: 101 ether,
                unlockingCliffCredit: 101 ether,
                vestingRate: 0,
                vestingStartTime: 0,
                unlockRate: 0,
                unlockStartTime: 0
            }),
            new BaseAllocation.Milestone[](0)
        );
        VestingAllocation vestingAllocationChad = VestingAllocation(controller.createMetavest(contractIdChad));

        // Wait until minter starts
        skip(60);

        vm.prank(chad);
        vm.expectRevert(abi.encodeWithSelector(IZkCappedMinterV2.ZkCappedMinterV2__CapExceeded.selector, address(vestingAllocationChad), 101 ether));
        vestingAllocationChad.withdraw(101 ether);
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
                tokenStreamTotal: 100 ether,
                vestingCliffCredit: 10 ether,
                unlockingCliffCredit: 10 ether,
                vestingRate: 1 ether,
                vestingStartTime: zkCappedMinter.START_TIME(), // start along with capped minter
                unlockRate: 1 ether,
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
                tokenStreamTotal: 100 ether,
                vestingCliffCredit: 10 ether,
                unlockingCliffCredit: 10 ether,
                vestingRate: 1 ether,
                vestingStartTime: zkCappedMinter.START_TIME(), // start along with capped minter
                unlockRate: 1 ether,
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
                tokenStreamTotal: 100 ether,
                vestingCliffCredit: 10 ether,
                unlockingCliffCredit: 10 ether,
                vestingRate: 1 ether,
                vestingStartTime: zkCappedMinter.START_TIME(), // start along with capped minter
                unlockRate: 1 ether,
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
                tokenStreamTotal: 100 ether,
                vestingCliffCredit: 10 ether,
                unlockingCliffCredit: 10 ether,
                vestingRate: 1 ether,
                vestingStartTime: zkCappedMinter.START_TIME(), // start along with capped minter
                unlockRate: 1 ether,
                unlockStartTime: zkCappedMinter.START_TIME() // start along with capped minter
            }),
            new BaseAllocation.Milestone[](0),
            abi.encodeWithSelector(metavestController.MetaVesTController_SignatureVerificationFailed.selector) // Expected revert
        );
    }

//    function _guardiansSignAndTppPass() internal returns(bytes32) {
//        // Guardians to sign agreements and register on MetaVesTController
//
//        bytes32 contractIdAlice = _signAndCreateContract(
//            guardianSafe,
//            alice,
//            alicePrivateKey,
//            "ipfs.io/ipfs/[cid]",
//            BaseAllocation.Allocation({
//                tokenContract: address(zkToken),
//                // 100k ZK total, the first half unlocks with a cliff and the second half unlocks over an year
//                tokenStreamTotal: 60 ether,
//                vestingCliffCredit: 30 ether,
//                unlockingCliffCredit: 30 ether,
//                vestingRate: 1 ether,
//                vestingStartTime: zkCappedMinter.START_TIME(), // start along with capped minter
//                unlockRate: 1 ether,
//                unlockStartTime: zkCappedMinter.START_TIME() // start along with capped minter
//            }),
//            new BaseAllocation.Milestone[](0)
//        );
//
//        // TPP to review agreements and on-chain parameters, then approve by granting our ZkCappedMinter permissions
//
//        bytes32 minterRole = zkToken.MINTER_ROLE();
//        vm.prank(zkTokenAdmin);
//        zkToken.grantRole(minterRole, address(zkCappedMinter));
//
//        return contractIdAlice;
//    }
}
