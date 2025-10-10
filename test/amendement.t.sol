// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "../src/BaseAllocation.sol";
//import "../src/RestrictedTokenAllocation.sol";
import "../src/interfaces/IAllocationFactory.sol";
import "../src/VestingAllocationFactory.sol";
//import "../src/TokenOptionFactory.sol";
//import "../src/RestrictedTokenFactory.sol";
import "./lib/MetaVesTControllerTestBase.sol";

// TODO WIP: non-VestingAllocation tests are disabled until reviewed with new design with CyberAgreementRegistry
contract MetaVestControllerTest is MetaVesTControllerTestBase {
    address public authority = guardianSafe;
    address public dao = guardianSafe;
    address public grantee = alice;

    uint256 cap = 2000 ether;
    uint48 cappedMinterStartTime = uint48(block.timestamp); // Minter start now
    uint48 cappedMinterExpirationTime = uint48(cappedMinterStartTime + 1600); // Minter expired 1600 seconds after start

    address public vestingAllocation;

    uint256 agreementSaltCounter = 0;

    function setUp() public override {
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

        vm.stopPrank();

        vm.startPrank(guardianSafe);

        controller.createSet("testSet");

        // Guardian SAFE to delegate signing to an EOA
        registry.setDelegation(delegate, block.timestamp + 365 days * 3); // This is a hack. One should not delegate signing for this long
        assertTrue(registry.isValidDelegate(guardianSafe, delegate), "delegate should be Guardian SAFE's delegate");

        vm.stopPrank();

        vestingAllocation = createDummyVestingAllocation();

        // TODO WIP: review needed
        paymentToken.mint(authority, 1000000e58);

        paymentToken.transfer(address(grantee), 1000e25);

        vm.prank(authority);
        controller.createSet("testSet");
    }

    function testProposeMetavestAmendment() public {
        bytes4 msgSig = bytes4(keccak256("updateMetavestTransferability(address,bool)"));
        bytes memory callData = abi.encodeWithSelector(msgSig, address(vestingAllocation), true);

        vm.prank(authority);
        controller.proposeMetavestAmendment(address(vestingAllocation), msgSig, callData);

        (bool isPending, bytes32 dataHash, bool inFavor) = controller.functionToGranteeToAmendmentPending(msgSig, address(vestingAllocation));

        assertTrue(isPending);
        assertEq(dataHash, keccak256(callData));
        assertFalse(inFavor);
    }

     function test_RevertIf_ProposeMajorityMetavestAmendment() public {
        address mockAllocation2 = createDummyVestingAllocation();
        address mockAllocation3 = createDummyVestingAllocation();
        address mockAllocation4 = createDummyVestingAllocation();
        bytes4 msgSig = bytes4(keccak256("updateMetavestTransferability(address,bool)"));
        bytes memory callData = abi.encodeWithSelector(msgSig, mockAllocation2, true);

        vm.prank(authority);
        controller.addMetaVestToSet("testSet", mockAllocation2);
         vm.prank(authority);
        controller.addMetaVestToSet("testSet", mockAllocation3);
         vm.prank(authority);
        controller.addMetaVestToSet("testSet", mockAllocation4);
        vm.warp(block.timestamp + 1 days);
        vm.prank(authority);
        controller.proposeMajorityMetavestAmendment("testSet", msgSig, callData);

        //log the current withdrawable
        console.log(VestingAllocation(mockAllocation2).getAmountWithdrawable());
         vm.prank(grantee);
        controller.voteOnMetavestAmendment(mockAllocation2, "testSet", msgSig, true);

        vm.prank(authority);
         vm.expectRevert(abi.encodeWithSelector(metavestController.MetaVesTController_AmendmentNeitherMutualNorMajorityConsented.selector));
        controller.updateMetavestTransferability(mockAllocation2, true);
    }

    function testQuickProposeMajorityMetavestAmendment() public {
        address mockAllocation2 = createDummyVestingAllocation();
        address mockAllocation3 = createDummyVestingAllocation();
        address mockAllocation4 = createDummyVestingAllocation();
        bytes4 msgSig = bytes4(keccak256("updateMetavestTransferability(address,bool)"));
        bytes memory callData = abi.encodeWithSelector(msgSig, mockAllocation2, true);

        vm.prank(authority);
        controller.addMetaVestToSet("testSet", mockAllocation2);
        vm.prank(authority);
        controller.addMetaVestToSet("testSet", mockAllocation3);
        vm.prank(authority);
        controller.addMetaVestToSet("testSet", mockAllocation4);
        vm.warp(block.timestamp + 15 seconds);
        vm.prank(authority);
        controller.proposeMajorityMetavestAmendment("testSet", msgSig, callData);

        vm.startPrank(grantee);
        //log the current withdrawable
        console.log(VestingAllocation(mockAllocation2).getAmountWithdrawable());

        controller.voteOnMetavestAmendment(mockAllocation2, "testSet", msgSig, true);

        controller.voteOnMetavestAmendment(mockAllocation3, "testSet", msgSig, true);
        vm.stopPrank();
        vm.prank(authority);
        controller.updateMetavestTransferability(mockAllocation2, true);
    }


//    function testMajorityPowerMetavestAmendment() public {
//        address mockAllocation2 = createDummyTokenOptionAllocation();
//        address mockAllocation3 = createDummyTokenOptionAllocation();
//        address mockAllocation4 = createDummyTokenOptionAllocation();
//        bytes4 msgSig = bytes4(keccak256("updateMetavestTransferability(address,bool)"));
//        bytes memory callData = abi.encodeWithSelector(msgSig, mockAllocation2, true);
//
//        vm.prank(authority);
//        controller.addMetaVestToSet("testSet", mockAllocation2);
//        controller.addMetaVestToSet("testSet", mockAllocation3);
//        controller.addMetaVestToSet("testSet", mockAllocation4);
//        vm.warp(block.timestamp + 1 days);
//        vm.startPrank(grantee);
//         ERC20(paymentToken).approve(address(mockAllocation2), 2000e18);
//         TokenOptionAllocation(mockAllocation2).exerciseTokenOption(TokenOptionAllocation(mockAllocation2).getAmountExercisable());
//        vm.stopPrank();
//        vm.prank(authority);
//        controller.proposeMajorityMetavestAmendment("testSet", msgSig, callData);
//
//        vm.prank(grantee);
//        controller.voteOnMetavestAmendment(mockAllocation3, "testSet", msgSig, true);
//        vm.prank(grantee);
//        controller.voteOnMetavestAmendment(mockAllocation4, "testSet", msgSig, true);
//
//        vm.prank(authority);
//        controller.updateMetavestTransferability(mockAllocation2, true);
//    }

//    function test_RevertIf_MajorityPowerMetavestAmendment() public {
//        address mockAllocation2 = createDummyTokenOptionAllocation();
//        address mockAllocation3 = createDummyTokenOptionAllocation();
//        address mockAllocation4 = createDummyTokenOptionAllocation();
//        bytes4 msgSig = bytes4(keccak256("updateMetavestTransferability(address,bool)"));
//        bytes memory callData = abi.encodeWithSelector(msgSig, mockAllocation2, true);
//
//        vm.prank(authority);
//        controller.addMetaVestToSet("testSet", mockAllocation2);
//        controller.addMetaVestToSet("testSet", mockAllocation3);
//        controller.addMetaVestToSet("testSet", mockAllocation4);
//        vm.warp(block.timestamp + 1 days);
//        vm.startPrank(grantee);
//         ERC20(paymentToken).approve(address(mockAllocation2), 2000e18);
//         TokenOptionAllocation(mockAllocation2).exerciseTokenOption(TokenOptionAllocation(mockAllocation2).getAmountExercisable());
//        vm.stopPrank();
//        vm.prank(authority);
//        controller.proposeMajorityMetavestAmendment("testSet", msgSig, callData);
//
//        vm.prank(grantee);
//        controller.voteOnMetavestAmendment(mockAllocation3, "testSet", msgSig, true);
//        vm.prank(grantee);
//        controller.voteOnMetavestAmendment(mockAllocation4, "testSet", msgSig, true);
//
//        vm.prank(authority);
//        controller.updateMetavestTransferability(mockAllocation2, true);
//        vm.prank(authority);
//        controller.updateMetavestTransferability(mockAllocation2, true);
//    }

    function testProposeMajorityMetavestAmendment() public {
        address mockAllocation2 = createDummyVestingAllocation();
        address mockAllocation3 = createDummyVestingAllocation();
        bytes4 msgSig = bytes4(keccak256("updateMetavestTransferability(address,bool)"));
        bytes memory callData = abi.encodeWithSelector(msgSig, mockAllocation2, true);

        vm.prank(authority);
        controller.addMetaVestToSet("testSet", mockAllocation2);
        vm.prank(authority);
        controller.addMetaVestToSet("testSet", mockAllocation3);
        vm.warp(block.timestamp + 1 days);
        vm.prank(authority);
        controller.proposeMajorityMetavestAmendment("testSet", msgSig, callData);

        vm.prank(grantee);
        controller.voteOnMetavestAmendment(mockAllocation2, "testSet", msgSig, true);

        vm.prank(authority);
        controller.updateMetavestTransferability(mockAllocation2, true);

        vm.prank(authority);
        controller.updateMetavestTransferability(mockAllocation3, true);
    }

    function testProposeMajorityMetavestAmendmentReAdd() public {
        address mockAllocation2 = createDummyVestingAllocation();
        address mockAllocation3 = createDummyVestingAllocation();
        bytes4 msgSig = bytes4(keccak256("updateMetavestTransferability(address,bool)"));
        bytes memory callData = abi.encodeWithSelector(msgSig, mockAllocation2, true);

        vm.prank(authority);
        controller.addMetaVestToSet("testSet", mockAllocation2);
        vm.prank(authority);
        controller.addMetaVestToSet("testSet", mockAllocation3);
        vm.warp(block.timestamp + 1 days);
        vm.prank(authority);
        controller.proposeMajorityMetavestAmendment("testSet", msgSig, callData);

        vm.prank(grantee);
        controller.voteOnMetavestAmendment(mockAllocation2, "testSet", msgSig, true);

        vm.prank(authority);
        controller.updateMetavestTransferability(mockAllocation3, true);

        vm.prank(authority);
        controller.removeMetaVestFromSet("testSet", mockAllocation3);
      //  vm.prank(authority);
      //  controller.updateMetavestTransferability(mockAllocation3, true);
        vm.warp(block.timestamp + 90 days);
        vm.prank(authority);
        controller.proposeMajorityMetavestAmendment("testSet", msgSig, callData);

        vm.prank(grantee);
        controller.voteOnMetavestAmendment(mockAllocation2, "testSet", msgSig, true);

        vm.prank(authority);
        controller.updateMetavestTransferability(mockAllocation2, true);

        vm.prank(authority);
        controller.addMetaVestToSet("testSet", mockAllocation3);

        vm.prank(authority);
        controller.updateMetavestTransferability(mockAllocation3, true);
    }

        function test_RevertIf_NoPassProposeMajorityMetavestAmendment() public {
        address mockAllocation2 = createDummyVestingAllocation();
        address mockAllocation3 = createDummyVestingAllocation();
        bytes4 msgSig = bytes4(keccak256("updateMetavestTransferability(address,bool)"));
        bytes memory callData = abi.encodeWithSelector(msgSig, mockAllocation2, true);

        vm.prank(authority);
        controller.addMetaVestToSet("testSet", mockAllocation2);
        vm.prank(authority);
        controller.addMetaVestToSet("testSet", mockAllocation3);
        vm.warp(block.timestamp + 1 days);
        vm.prank(authority);
        controller.proposeMajorityMetavestAmendment("testSet", msgSig, callData);

        vm.prank(authority);
        vm.expectRevert(abi.encodeWithSelector(metavestController.MetaVesTController_AmendmentNeitherMutualNorMajorityConsented.selector));
        controller.updateMetavestTransferability(mockAllocation2, true);

        vm.prank(authority);
        vm.expectRevert(abi.encodeWithSelector(metavestController.MetaVesTController_AmendmentNeitherMutualNorMajorityConsented.selector));
        controller.updateMetavestTransferability(mockAllocation3, true);
    }

    function testVoteOnMetavestAmendment() public {
        bytes4 msgSig = bytes4(keccak256("updateMetavestTransferability(address,bool)"));
        bytes memory callData = abi.encodeWithSelector(msgSig, address(vestingAllocation), true);

        vm.prank(authority);
        controller.addMetaVestToSet("testSet", address(vestingAllocation));

        vm.prank(authority);
        controller.proposeMajorityMetavestAmendment("testSet", msgSig, callData);

        vm.prank(grantee);
        controller.voteOnMetavestAmendment(address(vestingAllocation), "testSet", msgSig, true);

        (uint256 totalVotingPower, uint256 currentVotingPower, , ,  ) = controller.functionToSetMajorityProposal(msgSig, "testSet");

    }

    function test_RevertIf_VoteOnMetavestAmendmentTwice() public {
        bytes4 msgSig = bytes4(keccak256("updateMetavestTransferability(address,bool)"));
        bytes memory callData = abi.encodeWithSelector(msgSig, address(vestingAllocation), true);

        vm.prank(authority);
        controller.addMetaVestToSet("testSet", address(vestingAllocation));

        vm.prank(authority);
        controller.proposeMajorityMetavestAmendment("testSet", msgSig, callData);

        vm.startPrank(grantee);
        controller.voteOnMetavestAmendment(address(vestingAllocation), "testSet", msgSig, true);
        vm.expectRevert(abi.encodeWithSelector(metavestController.MetaVesTController_AlreadyVoted.selector));
        controller.voteOnMetavestAmendment(address(vestingAllocation), "testSet", msgSig, true);
        vm.stopPrank();
    }

    function testSetManagement() public {
        vm.startPrank(authority);

        // Test creating a new set
        controller.createSet("newSet");

        // Test adding a MetaVest to a set
        controller.addMetaVestToSet("newSet", address(vestingAllocation));


        // Test removing a MetaVest from a set
        controller.removeMetaVestFromSet("newSet", address(vestingAllocation));


        // Test removing a set
        controller.removeSet("newSet");


        vm.stopPrank();
    }

    function test_RevertIf_CreateDuplicateSet() public {
        vm.startPrank(authority);
        controller.createSet("duplicateSet");
        vm.expectRevert(abi.encodeWithSelector(metavestController.MetaVesTController_SetAlreadyExists.selector));
        controller.createSet("duplicateSet");
        vm.stopPrank();
    }

    function test_RevertIf_NonAuthorityCreateSet() public {
        vm.prank(grantee);
        vm.expectRevert(abi.encodeWithSelector(metavestController.MetaVesTController_OnlyAuthority.selector));
        controller.createSet("unauthorizedSet");
    }

    // Helper functions to create dummy allocations for testing
    function createDummyVestingAllocation() internal returns (address) {
        return createDummyVestingAllocation(""); // Expect no reverts
    }

    // Helper functions to create dummy allocations for testing
    function createDummyVestingAllocation(bytes memory expectRevertData) internal returns (address) {
        BaseAllocation.Milestone[] memory milestones = new BaseAllocation.Milestone[](1);
        milestones[0] = BaseAllocation.Milestone({
            milestoneAward: 100 ether,
            unlockOnCompletion: true,
            complete: false,
            conditionContracts: new address[](0)
        });

        // Guardians to sign agreements and register on MetaVesTController
        bytes32 contractIdAlice = _proposeAndSignDeal(
            templateId,
            agreementSaltCounter++,
            delegatePrivateKey,
            alice, // = grantee
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
            milestones,
            "Alice",
            cappedMinterExpirationTime // Same expiry as the minter so grantee can defer vesting contract creation as much as possible
        );

        return _granteeSignDeal(
            contractIdAlice,
            alice, // grantee
            alice, // recipient
            alicePrivateKey,
            "Alice",
            expectRevertData
        );
    }

//    function createDummyTokenOptionAllocation() internal returns (address) {
//        BaseAllocation.Allocation memory allocation = BaseAllocation.Allocation({
//            tokenContract: address(token),
//            tokenStreamTotal: 1000e18,
//            vestingCliffCredit: 100e18,
//            unlockingCliffCredit: 100e18,
//            vestingRate: 10e18,
//            vestingStartTime: uint48(block.timestamp),
//            unlockRate: 10e18,
//            unlockStartTime: uint48(block.timestamp)
//        });
//
//        BaseAllocation.Milestone[] memory milestones = new BaseAllocation.Milestone[](1);
//        milestones[0] = BaseAllocation.Milestone({
//            milestoneAward: 100e18,
//            unlockOnCompletion: true,
//            complete: false,
//            conditionContracts: new address[](0)
//        });
//
//        token.approve(address(controller), 1100e18);
//
//        return controller.createMetavest(
//            metavestController.metavestType.TokenOption,
//            grantee,
//            allocation,
//            milestones,
//            1e18,
//            address(paymentToken),
//            365 days,
//            0
//        );
//    }
//
//   function createDummyRestrictedTokenAward() internal returns (address) {
//        BaseAllocation.Allocation memory allocation = BaseAllocation.Allocation({
//            tokenContract: address(token),
//            tokenStreamTotal: 1000e18,
//            vestingCliffCredit: 100e18,
//            unlockingCliffCredit: 100e18,
//            vestingRate: 10e18,
//            vestingStartTime: uint48(block.timestamp),
//            unlockRate: 10e18,
//            unlockStartTime: uint48(block.timestamp)
//        });
//
//        BaseAllocation.Milestone[] memory milestones = new BaseAllocation.Milestone[](1);
//        milestones[0] = BaseAllocation.Milestone({
//            milestoneAward: 100e18,
//            unlockOnCompletion: true,
//            complete: false,
//            conditionContracts: new address[](0)
//        });
//
//        token.approve(address(controller), 1100e18);
//
//        return controller.createMetavest(
//            metavestController.metavestType.RestrictedTokenAward,
//            grantee,
//            allocation,
//            milestones,
//            1e18,
//            address(paymentToken),
//            365 days,
//            0
//
//        );
//    }

    //write a test for every consentcheck function in metavest controller
    function testConsentCheck() public {
        address allocation = createDummyVestingAllocation();
        bytes4 msgSig = bytes4(keccak256("updateMetavestTransferability(address,bool)"));
        bytes memory callData = abi.encodeWithSelector(msgSig, allocation, true);

        vm.prank(authority);
        controller.proposeMetavestAmendment(allocation, msgSig, callData);

        vm.prank(grantee);
        controller.consentToMetavestAmendment(allocation, msgSig, true);

        vm.prank(authority);
        controller.updateMetavestTransferability(allocation, true);
    }

    function test_RevertIf_ConsentCheck() public {
        address allocation = createDummyVestingAllocation();
        bytes4 msgSig = bytes4(keccak256("updateMetavestTransferability(address,bool)"));
        bytes memory callData = abi.encodeWithSelector(msgSig, allocation, true);

        vm.prank(authority);
        controller.proposeMetavestAmendment(allocation, msgSig, callData);

        vm.prank(grantee);
        vm.expectRevert(abi.encodeWithSelector(metavestController.MetaVesTController_SetDoesNotExist.selector));
        controller.voteOnMetavestAmendment(allocation, "testSet", msgSig, false);

        vm.prank(authority);
        vm.expectRevert(abi.encodeWithSelector(metavestController.MetaVesTController_AmendmentNeitherMutualNorMajorityConsented.selector));
        controller.updateMetavestTransferability(allocation, true);
    }

    function test_RevertIf_ConsentCheckNoProposal() public {
        address allocation = createDummyVestingAllocation();
        bytes4 msgSig = bytes4(keccak256("updateMetavestTransferability(address,bool)"));

        vm.prank(grantee);
        vm.expectRevert(abi.encodeWithSelector(metavestController.MetaVesTController_SetDoesNotExist.selector));
        controller.voteOnMetavestAmendment(allocation, "testSet", msgSig, true);
    }

    function test_RevertIf_ConsentCheckNoVote() public {
        address allocation = createDummyVestingAllocation();
        bytes4 msgSig = bytes4(keccak256("updateMetavestTransferability(address,bool)"));
        bytes memory callData = abi.encodeWithSelector(msgSig, allocation, true);

        vm.prank(authority);
        controller.proposeMetavestAmendment(allocation, msgSig, callData);

        vm.prank(authority);
        vm.expectRevert(abi.encodeWithSelector(metavestController.MetaVesTController_AmendmentNeitherMutualNorMajorityConsented.selector));
        controller.updateMetavestTransferability(allocation, true);
    }

    function test_RevertIf_ConsentCheckNoUpdate() public {
        address allocation = createDummyVestingAllocation();
        bytes4 msgSig = bytes4(keccak256("updateMetavestTransferability(address,bool)"));
        bytes memory callData = abi.encodeWithSelector(msgSig, allocation, true);

        vm.prank(authority);
        controller.proposeMetavestAmendment(allocation, msgSig, callData);

        vm.prank(grantee);
        vm.expectRevert(abi.encodeWithSelector(metavestController.MetaVesTController_SetDoesNotExist.selector));
        controller.voteOnMetavestAmendment(allocation, "testSet", msgSig, true);
    }

    function test_RevertIf_ConsentCheckNoVoteUpdate() public {
        address allocation = createDummyVestingAllocation();
        bytes4 msgSig = bytes4(keccak256("updateMetavestTransferability(address,bool)"));
        bytes memory callData = abi.encodeWithSelector(msgSig, allocation, true);

        vm.prank(authority);
        controller.proposeMetavestAmendment(allocation, msgSig, callData);

        vm.prank(grantee);
        vm.expectRevert(abi.encodeWithSelector(metavestController.MetaVesTController_SetDoesNotExist.selector));
        controller.voteOnMetavestAmendment(allocation, "testSet", msgSig, true);
    }

//    function testCreateSetWithThreeTokenOptionsAndChangeExercisePrice() public {
//        address allocation1 = createDummyTokenOptionAllocation();
//        address allocation2 = createDummyTokenOptionAllocation();
//        address allocation3 = createDummyTokenOptionAllocation();
//
//        vm.prank(authority);
//        controller.addMetaVestToSet("testSet", allocation1);
//        controller.addMetaVestToSet("testSet", allocation2);
//        controller.addMetaVestToSet("testSet", allocation3);
//         assertTrue(TokenOptionAllocation(allocation1).exercisePrice() == 1e18);
//         vm.warp(block.timestamp + 25 seconds);
//
//
//        vm.startPrank(grantee);
//        ERC20(paymentToken).approve(address(allocation1), 2000e18);
//        ERC20(paymentToken).approve(address(allocation2), 2000e18);
//
//         TokenOptionAllocation(allocation1).exerciseTokenOption(TokenOptionAllocation(allocation1).getAmountExercisable());
//
//         TokenOptionAllocation(allocation2).exerciseTokenOption(TokenOptionAllocation(allocation2).getAmountExercisable());
//         vm.stopPrank();
//        bytes4 msgSig = bytes4(keccak256("updateExerciseOrRepurchasePrice(address,uint256)"));
//        bytes memory callData = abi.encodeWithSelector(msgSig, allocation1, 2e18);
//
//        vm.prank(authority);
//        controller.proposeMajorityMetavestAmendment("testSet", msgSig, callData);
//
//        vm.prank(grantee);
//        controller.voteOnMetavestAmendment(allocation1, "testSet", msgSig, true);
//
//        vm.prank(grantee);
//        controller.voteOnMetavestAmendment(allocation2, "testSet", msgSig, true);
//
//        vm.prank(authority);
//        controller.updateExerciseOrRepurchasePrice(allocation1, 2e18);
//
//        vm.prank(authority);
//        controller.updateExerciseOrRepurchasePrice(allocation2, 2e18);
//
//        vm.prank(authority);
//        controller.updateExerciseOrRepurchasePrice(allocation3, 2e18);
//
//        // Check that the exercise price was updated
//        assertTrue(TokenOptionAllocation(allocation1).exercisePrice() == 2e18);
//    }

//    function test_RevertIf_CreateSetWithThreeTokenOptionsAndChangeExercisePrice() public {
//        address allocation1 = createDummyTokenOptionAllocation();
//        address allocation2 = createDummyTokenOptionAllocation();
//        address allocation3 = createDummyTokenOptionAllocation();
//
//        vm.prank(authority);
//        controller.addMetaVestToSet("testSet", allocation1);
//        controller.addMetaVestToSet("testSet", allocation2);
//        controller.addMetaVestToSet("testSet", allocation3);
//         assertTrue(TokenOptionAllocation(allocation1).exercisePrice() == 1e18);
//         vm.warp(block.timestamp + 25 seconds);
//
//
//        vm.startPrank(grantee);
//        ERC20(paymentToken).approve(address(allocation1), 2000e18);
//        ERC20(paymentToken).approve(address(allocation2), 2000e18);
//
//         TokenOptionAllocation(allocation1).exerciseTokenOption(TokenOptionAllocation(allocation1).getAmountExercisable());
//
//         TokenOptionAllocation(allocation2).exerciseTokenOption(TokenOptionAllocation(allocation2).getAmountExercisable());
//         vm.stopPrank();
//        bytes4 msgSig = bytes4(keccak256("updateExerciseOrRepurchasePrice(address,uint256)"));
//        bytes memory callData = abi.encodeWithSelector(msgSig, allocation1, 2e18);
//
//        vm.prank(authority);
//        controller.proposeMajorityMetavestAmendment("testSet", msgSig, callData);
//
//        //vm.prank(grantee);
//       // controller.voteOnMetavestAmendment(allocation1, "testSet", msgSig, true);
//
//       // vm.prank(grantee);
//       // controller.voteOnMetavestAmendment(allocation2, "testSet", msgSig, true);
//
//        vm.prank(authority);
//        controller.updateExerciseOrRepurchasePrice(allocation1, 2e18);
//
//        vm.prank(authority);
//        controller.updateExerciseOrRepurchasePrice(allocation2, 2e18);
//
//        vm.prank(authority);
//        controller.updateExerciseOrRepurchasePrice(allocation3, 2e18);
//
//        // Check that the exercise price was updated
//        assertTrue(TokenOptionAllocation(allocation1).exercisePrice() == 2e18);
//    }

    function test_RevertIf_consentToNoPendingAmendment() public {
        address allocation = createDummyVestingAllocation();
        bytes4 msgSig = bytes4(keccak256("updateMetavestTransferability(address,bool)"));
        bytes memory callData = abi.encodeWithSelector(msgSig, allocation, true);

        vm.prank(grantee);
        vm.expectRevert(abi.encodeWithSelector(metavestController.MetaVesTController_NoPendingAmendment.selector, msgSig, allocation));
        controller.consentToMetavestAmendment(allocation, msgSig, true);
    }

//    function testEveryUpdateAmendmentFunction() public {
//        address allocation = createDummyTokenOptionAllocation();
//        bytes4 msgSig = bytes4(keccak256("updateMetavestTransferability(address,bool)"));
//        bytes memory callData = abi.encodeWithSelector(msgSig, allocation, true);
//
//        vm.prank(authority);
//        controller.proposeMetavestAmendment(allocation, msgSig, callData);
//
//        vm.prank(grantee);
//        controller.consentToMetavestAmendment(allocation, msgSig, true);
//
//        vm.prank(authority);
//        controller.updateMetavestTransferability(allocation, true);
//
//        msgSig = bytes4(keccak256("updateExerciseOrRepurchasePrice(address,uint256)"));
//        callData = abi.encodeWithSelector(msgSig, allocation, 2e18);
//
//        vm.prank(authority);
//        controller.proposeMetavestAmendment(allocation, msgSig, callData);
//
//        vm.prank(grantee);
//        controller.consentToMetavestAmendment(allocation, msgSig, true);
//
//        vm.prank(authority);
//        controller.updateExerciseOrRepurchasePrice(allocation, 2e18);
//
//        msgSig = bytes4(keccak256("removeMetavestMilestone(address,uint256)"));
//        callData = abi.encodeWithSelector(msgSig, allocation, 0);
//
//        vm.prank(authority);
//        controller.proposeMetavestAmendment(allocation, msgSig, callData);
//
//        vm.prank(grantee);
//        controller.consentToMetavestAmendment(allocation, msgSig, true);
//
//        vm.prank(authority);
//        controller.removeMetavestMilestone(allocation, 0);
//
//        msgSig = bytes4(keccak256("updateMetavestUnlockRate(address,uint160)"));
//        callData = abi.encodeWithSelector(msgSig, allocation, 20e18);
//
//        vm.prank(authority);
//        controller.proposeMetavestAmendment(allocation, msgSig, callData);
//
//        vm.prank(grantee);
//        controller.consentToMetavestAmendment(allocation, msgSig, true);
//
//        vm.prank(authority);
//        controller.updateMetavestUnlockRate(allocation, 20e18);
//
//        msgSig = bytes4(keccak256("updateMetavestVestingRate(address,uint160)"));
//        callData = abi.encodeWithSelector(msgSig, allocation, 20e18);
//
//        vm.prank(authority);
//        controller.proposeMetavestAmendment(allocation, msgSig, callData);
//
//        vm.prank(grantee);
//        controller.consentToMetavestAmendment(allocation, msgSig, true);
//
//        vm.prank(authority);
//        controller.updateMetavestVestingRate(allocation, 20e18);
//
//        msgSig = bytes4(keccak256("setMetaVestGovVariables(address,uint8)"));
//        callData = abi.encodeWithSelector(msgSig, allocation, BaseAllocation.GovType.vested);
//
//        vm.prank(authority);
//        controller.proposeMetavestAmendment(allocation, msgSig, callData);
//
//        vm.prank(grantee);
//        controller.consentToMetavestAmendment(allocation, msgSig, true);
//
//        vm.prank(authority);
//        controller.setMetaVestGovVariables(allocation, BaseAllocation.GovType.vested);
//    }

//    function testEveryUpdateAmendmentFunctionRestricted() public {
//        address allocation = createDummyRestrictedTokenAward();
//        bytes4 msgSig = bytes4(keccak256("updateMetavestTransferability(address,bool)"));
//        bytes memory callData = abi.encodeWithSelector(msgSig, allocation, true);
//
//        vm.prank(authority);
//        controller.proposeMetavestAmendment(allocation, msgSig, callData);
//
//        vm.prank(grantee);
//        controller.consentToMetavestAmendment(allocation, msgSig, true);
//
//        vm.prank(authority);
//        controller.updateMetavestTransferability(allocation, true);
//
//        msgSig = bytes4(keccak256("updateExerciseOrRepurchasePrice(address,uint256)"));
//        callData = abi.encodeWithSelector(msgSig, allocation, 2e18);
//
//        vm.prank(authority);
//        controller.proposeMetavestAmendment(allocation, msgSig, callData);
//
//        vm.prank(grantee);
//        controller.consentToMetavestAmendment(allocation, msgSig, true);
//
//        vm.prank(authority);
//        controller.updateExerciseOrRepurchasePrice(allocation, 2e18);
//
//        msgSig = bytes4(keccak256("removeMetavestMilestone(address,uint256)"));
//        callData = abi.encodeWithSelector(msgSig, allocation, 0);
//
//        vm.prank(authority);
//        controller.proposeMetavestAmendment(allocation, msgSig, callData);
//
//        vm.prank(grantee);
//        controller.consentToMetavestAmendment(allocation, msgSig, true);
//
//        vm.prank(authority);
//        controller.removeMetavestMilestone(allocation, 0);
//
//        msgSig = bytes4(keccak256("updateMetavestUnlockRate(address,uint160)"));
//        callData = abi.encodeWithSelector(msgSig, allocation, 20e18);
//
//        vm.prank(authority);
//        controller.proposeMetavestAmendment(allocation, msgSig, callData);
//
//        vm.prank(grantee);
//        controller.consentToMetavestAmendment(allocation, msgSig, true);
//
//        vm.prank(authority);
//        controller.updateMetavestUnlockRate(allocation, 20e18);
//
//        msgSig = bytes4(keccak256("updateMetavestVestingRate(address,uint160)"));
//        callData = abi.encodeWithSelector(msgSig, allocation, 20e18);
//
//        vm.prank(authority);
//        controller.proposeMetavestAmendment(allocation, msgSig, callData);
//
//        vm.prank(grantee);
//        controller.consentToMetavestAmendment(allocation, msgSig, true);
//
//        vm.prank(authority);
//        controller.updateMetavestVestingRate(allocation, 20e18);
//
//        msgSig = bytes4(keccak256("setMetaVestGovVariables(address,uint8)"));
//        callData = abi.encodeWithSelector(msgSig, allocation, BaseAllocation.GovType.vested);
//
//        vm.prank(authority);
//        controller.proposeMetavestAmendment(allocation, msgSig, callData);
//
//        vm.prank(grantee);
//        controller.consentToMetavestAmendment(allocation, msgSig, true);
//
//        vm.prank(authority);
//        controller.setMetaVestGovVariables(allocation, BaseAllocation.GovType.vested);
//    }

    function testEveryUpdateAmendmentFunctionVesting() public {
        address allocation = createDummyVestingAllocation();
        bytes4 msgSig = bytes4(keccak256("updateMetavestTransferability(address,bool)"));
        bytes memory callData = abi.encodeWithSelector(msgSig, allocation, true);

        vm.prank(authority);
        controller.proposeMetavestAmendment(allocation, msgSig, callData);

        vm.prank(grantee);
        controller.consentToMetavestAmendment(allocation, msgSig, true);

        vm.prank(authority);
        controller.updateMetavestTransferability(allocation, true);

        msgSig = bytes4(keccak256("removeMetavestMilestone(address,uint256)"));
        callData = abi.encodeWithSelector(msgSig, allocation, 0);

        vm.prank(authority);
        controller.proposeMetavestAmendment(allocation, msgSig, callData);

        vm.prank(grantee);
        controller.consentToMetavestAmendment(allocation, msgSig, true);

        vm.prank(authority);
        controller.removeMetavestMilestone(allocation, 0);

        msgSig = bytes4(keccak256("updateMetavestUnlockRate(address,uint160)"));
        callData = abi.encodeWithSelector(msgSig, allocation, 20e18);

        vm.prank(authority);
        controller.proposeMetavestAmendment(allocation, msgSig, callData);

        vm.prank(grantee);
        controller.consentToMetavestAmendment(allocation, msgSig, true);

        vm.prank(authority);
        controller.updateMetavestUnlockRate(allocation, 20e18);

        msgSig = bytes4(keccak256("updateMetavestVestingRate(address,uint160)"));
        callData = abi.encodeWithSelector(msgSig, allocation, 20e18);

        vm.prank(authority);
        controller.proposeMetavestAmendment(allocation, msgSig, callData);

        vm.prank(grantee);
        controller.consentToMetavestAmendment(allocation, msgSig, true);

        vm.prank(authority);
        controller.updateMetavestVestingRate(allocation, 20e18);

        msgSig = bytes4(keccak256("setMetaVestGovVariables(address,uint8)"));
        callData = abi.encodeWithSelector(msgSig, allocation, BaseAllocation.GovType.vested);

        vm.prank(authority);
        controller.proposeMetavestAmendment(allocation, msgSig, callData);

        vm.prank(grantee);
        controller.consentToMetavestAmendment(allocation, msgSig, true);

        vm.prank(authority);
        controller.setMetaVestGovVariables(allocation, BaseAllocation.GovType.vested);
    }

    function test_RevertIf_EveryUpdateAmendmentFunctionVesting() public {
        address allocation = createDummyVestingAllocation();
        bytes4 msgSig = bytes4(keccak256("updateMetavestTransferability(address,bool)"));
        bytes memory callData = abi.encodeWithSelector(msgSig, allocation, true);

        vm.prank(authority);
        controller.proposeMetavestAmendment(allocation, msgSig, callData);

        vm.prank(grantee);
        controller.consentToMetavestAmendment(allocation, msgSig, true);

        vm.prank(authority);
        controller.updateMetavestTransferability(allocation, true);

        msgSig = bytes4(keccak256("removeMetavestMilestone(address,uint256)"));
        callData = abi.encodeWithSelector(msgSig, allocation, 0);

        vm.prank(authority);
        controller.proposeMetavestAmendment(allocation, msgSig, callData);

        vm.prank(grantee);
        controller.consentToMetavestAmendment(allocation, msgSig, true);

        vm.prank(authority);
        controller.removeMetavestMilestone(allocation, 0);

        msgSig = bytes4(keccak256("updateMetavestUnlockRate(address,uint160)"));
        callData = abi.encodeWithSelector(msgSig, allocation, 20e18);

        vm.prank(authority);
        controller.proposeMetavestAmendment(allocation, msgSig, callData);

        vm.prank(grantee);
        controller.consentToMetavestAmendment(allocation, msgSig, true);

        vm.prank(authority);
        controller.updateMetavestUnlockRate(allocation, 20e18);

        msgSig = bytes4(keccak256("updateMetavestVestingRate(address,uint160)"));
        callData = abi.encodeWithSelector(msgSig, allocation, 20e18);

        vm.prank(authority);
        controller.proposeMetavestAmendment(allocation, msgSig, callData);

        vm.prank(grantee);
        controller.consentToMetavestAmendment(allocation, msgSig, true);

        vm.prank(authority);
        controller.updateMetavestVestingRate(allocation, 20e18);

        msgSig = bytes4(keccak256("setMetaVestGovVariables(address,uint8)"));
        callData = abi.encodeWithSelector(msgSig, allocation, BaseAllocation.GovType.vested);

        vm.prank(authority);
        controller.proposeMetavestAmendment(allocation, msgSig, callData);

        vm.prank(authority);
        vm.expectRevert(abi.encodeWithSelector(metavestController.MetaVesTController_AmendmentNeitherMutualNorMajorityConsented.selector));
        controller.setMetaVestGovVariables(allocation, BaseAllocation.GovType.vested);
    }
}
