// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.20;

import "../src/MetaVesTController.sol";
import "../src/RestrictedTokenFactory.sol";
import "../src/TokenOptionFactory.sol";
import "../src/VestingAllocationFactory.sol";
import "../src/interfaces/zk-governance/IZkTokenV1.sol";
import "./lib/MetaVesTUtils.sol";
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

    uint256 alicePrivateKey = 1;
    address alice = vm.addr(alicePrivateKey);
    uint256 bobPrivateKey = 2;
    address bob = vm.addr(bobPrivateKey);

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

        bytes32 contractIdAlice = _signAndCreateContract(
            guardianSafe,
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
            new BaseAllocation.Milestone[](0)
        );

        bytes32 contractIdBob = _signAndCreateContract(
            guardianSafe,
            bob,
            bobPrivateKey,
            "ipfs.io/ipfs/[cid]",
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
            new BaseAllocation.Milestone[](0)
        );

        // TPP to review agreements and on-chain parameters, then approve by granting our ZkCappedMinter permissions

        bytes32 minterRole = zkToken.MINTER_ROLE();
        vm.prank(zkTokenAdmin);
        zkToken.grantRole(minterRole, address(zkCappedMinter));

        // Anyone can create MetaVesT for Alice and Bob (per agreements) to start vesting

        VestingAllocation vestingAllocationAlice = VestingAllocation(controller.createMetavest(contractIdAlice));
        assertEq(zkToken.balanceOf(address(vestingAllocationAlice)), 0, "Alice's vesting contract should not have any token (it mints on-demand)");

        VestingAllocation vestingAllocationBob = VestingAllocation(controller.createMetavest(contractIdBob));
        assertEq(zkToken.balanceOf(address(vestingAllocationBob)), 0, "Vesting contract should not have any token (it mints on-demand)");

        // Alice and Bob should be able to start withdrawal after capped minter and MetaVesT start
        skip(30 days);

        _granteeWithdrawAndAsserts(vestingAllocationAlice, 100e18, "Alice cliff");
        _granteeWithdrawAndAsserts(vestingAllocationBob, 200e18, "Bob cliff");

        // Alice and Bob should be able to withdrawal all remaining tokens after sufficient time passed
        skip(90 seconds);

        _granteeWithdrawAndAsserts(vestingAllocationAlice, 900e18, "Alice full");
        _granteeWithdrawAndAsserts(vestingAllocationBob, 1800e18, "Bob full");
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

    function _granteeWithdrawAndAsserts(VestingAllocation vestingAllocation, uint256 amount, string memory assertName) internal {
        address grantee = vestingAllocation.grantee();
        uint256 balanceBefore = zkToken.balanceOf(grantee);
        assertEq(vestingAllocation.getAmountWithdrawable(), amount, string(abi.encodePacked(assertName, ": unexpected withdrawable amount after cliff")));
        vm.prank(grantee);
        vestingAllocation.withdraw(amount);
        assertEq(zkToken.balanceOf(grantee), balanceBefore + amount, string(abi.encodePacked(assertName, ": unexpected received amount")));
        assertEq(zkToken.balanceOf(address(vestingAllocation)), 0, string(abi.encodePacked(assertName, ": vesting contract should not have any token (it mints on-demand)")));
    }

    function _signAndCreateContract(
        address authority,
        address grantee,
        uint256 granteePrivateKey,
        string memory agreementUri,
        BaseAllocation.Allocation memory allocation,
        BaseAllocation.Milestone[] memory milestones
    ) internal returns(bytes32) {
        return _signAndCreateContract(
            authority, grantee, granteePrivateKey, agreementUri, allocation, milestones,
            "" // Not expecting revert
        );
    }

    function _signAndCreateContract(
        address authority,
        address grantee,
        uint256 granteePrivateKey,
        string memory agreementUri,
        BaseAllocation.Allocation memory allocation,
        BaseAllocation.Milestone[] memory milestones,
        bytes memory expectRevertData
    ) internal returns(bytes32) {
        uint256 contractSalt = block.timestamp;
        bytes32 expectedContractId = controller.computeContractId(contractSalt, agreementUri, grantee, grantee, allocation, milestones);
        bytes memory signature = MetaVesTUtils.signAgreementTypedData(
            vm,
            controller,
            metavestController.SignedAgreementData({
                id: expectedContractId,
                agreementUri: agreementUri,
                _metavestType: metavestController.metavestType.Vesting,
                grantee: grantee,
                recipient: grantee,
                allocation: allocation,
                milestones: milestones
            }),
            granteePrivateKey
        );

        if (expectRevertData.length > 0) {
            vm.expectRevert(expectRevertData);
        }
        vm.prank(authority);
        bytes32 contractId = controller.createSignedContract(
            contractSalt,
            metavestController.metavestType.Vesting,
            grantee,
            grantee,
            allocation,
            milestones,
            agreementUri,
            signature
        );

        if (expectRevertData.length == 0) {
            assertEq(contractId, expectedContractId, "Unexpected contract ID");
            return contractId;
        } else {
            return 0;
        }
    }
}
