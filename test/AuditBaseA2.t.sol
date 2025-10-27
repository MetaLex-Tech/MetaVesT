pragma solidity ^0.8.20;

import "forge-std/Test.sol";

import "../test/amendement.t.sol";

contract EvilGrant {

    function grantee () public view returns (address) {
        return address(0x31337);
    }
    function getGoverningPower() public view returns (uint256) {
        return 99999999999999999999999999999;
    }
}

contract Audit is MetaVestControllerTest {
    function test_RevertIf_AuditArbitraryVote() public {
        // template from testVoteOnMetavestAmendment
        bytes4 msgSig = bytes4(keccak256("updateMetavestTransferability(address,bool)"));
        bytes memory callData = abi.encodeWithSelector(msgSig, address(vestingAllocation), true);

        vm.prank(authority);
        controller.addMetaVestToSet("testSet", address(vestingAllocation));

        vm.prank(authority);
        controller.proposeMajorityMetavestAmendment("testSet", msgSig, callData);

        address attacker = address(0x31337);
        address evil_grant = address(new EvilGrant());

        vm.prank(attacker);
        vm.expectRevert(abi.encodeWithSelector(MetaVesTControllerStorage.MetaVesTController_SetDoesNotExist.selector));
        controller.voteOnMetavestAmendment(address(evil_grant), "testSet", msgSig, true);

        (uint256 totalVotingPower, uint256 currentVotingPower, , ,  ) = controller.functionToSetMajorityProposal(msgSig, "testSet");
        console.log("attacker made vote and power is" , currentVotingPower);
    }

    function test_RevertIf_AuditRemoveConfirmedMilestone() public {
        // template from testRemoveMilestone
        address vestingAllocation = createDummyVestingAllocation();
        VestingAllocation(vestingAllocation).confirmMilestone(0);

        address[] memory addresses = new address[](1);
        addresses[0] = vestingAllocation;
        bytes4 selector = bytes4(keccak256("removeMetavestMilestone(address,uint256)"));
        bytes memory msgData = abi.encodeWithSelector(selector, vestingAllocation, 0);
        vm.prank(authority);
        controller.proposeMetavestAmendment(vestingAllocation, controller.removeMetavestMilestone.selector, msgData);

        vm.prank(grantee);
        controller.consentToMetavestAmendment(vestingAllocation, controller.removeMetavestMilestone.selector, true);
        vm.expectRevert(abi.encodeWithSelector(MetaVesTControllerStorage.MetaVesTController_MilestoneIndexCompletedOrDoesNotExist.selector));
        vm.prank(authority);
        controller.removeMetavestMilestone(vestingAllocation, 0);
    }

    function testAuditProposeMajorityMetavestAmendmentExpire() public {
        // template from testProposeMajorityMetavestAmendment
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

        // proposal expired
        uint256 AMENDMENT_TIME_LIMIT = 604800;
        vm.warp(block.timestamp + AMENDMENT_TIME_LIMIT + 1);

        // MetaVesTController_AmendmentAlreadyPending even expired
        vm.prank(authority);
        vm.expectRevert();
        controller.proposeMajorityMetavestAmendment("testSet", msgSig, callData);
    }

    function testAuditModifiedCalldataProposal() public {
        // template from testCreateSetWithThreeTokenOptionsAndChangeExercisePrice
        address allocation1 = createDummyTokenOptionAllocation();
        address allocation2 = createDummyTokenOptionAllocation();
        address allocation3 = createDummyTokenOptionAllocation();

        vm.startPrank(authority);
        controller.addMetaVestToSet("testSet", allocation1);
        controller.addMetaVestToSet("testSet", allocation2);
        controller.addMetaVestToSet("testSet", allocation3);
        vm.stopPrank();
        assertTrue(TokenOptionAllocation(allocation1).exercisePrice() == 1e18);

        vm.warp(block.timestamp + 25 seconds);

        paymentToken.mint(grantee, 4000e18);

        vm.startPrank(grantee);
        paymentToken.approve(address(allocation1), 2000e18);
        paymentToken.approve(address(allocation2), 2000e18);
        TokenOptionAllocation(allocation1).exerciseTokenOption(TokenOptionAllocation(allocation1).getAmountExercisable());
        TokenOptionAllocation(allocation2).exerciseTokenOption(TokenOptionAllocation(allocation2).getAmountExercisable());
        vm.stopPrank();

        bytes4 msgSig = bytes4(keccak256("updateExerciseOrRepurchasePrice(address,uint256)"));
        bytes memory callData = abi.encodeWithSelector(msgSig, allocation1, 2e18);

        vm.prank(authority);
        controller.proposeMajorityMetavestAmendment("testSet", msgSig, callData);

        vm.prank(grantee);
        controller.voteOnMetavestAmendment(allocation1, "testSet", msgSig, true);

        vm.prank(grantee);
        controller.voteOnMetavestAmendment(allocation2, "testSet", msgSig, true);

        // Call function with a different value from the consent should fail
        vm.prank(authority);
        vm.expectRevert(MetaVesTControllerStorage.MetaVesTController_AmendmentNeitherMutualNorMajorityConsented.selector);
        controller.updateExerciseOrRepurchasePrice(allocation1, 999999999999999999999e18);

        // Using lower-level call would still fail internally
        vm.prank(authority);
        bytes memory p = abi.encodeWithSelector(msgSig, allocation1, 999999999999999999999e18);
        address(controller).call(p);

        // Verify exercise price is still not changed
        assertEq(TokenOptionAllocation(allocation1).exercisePrice(), 1e18, "exercise price should not change");
    }

    function testAuditConsentToMetavestAmendmentInFlavor() public {
        // template from testRemoveMilestone
        address vestingAllocation = createDummyVestingAllocation();
        VestingAllocation(vestingAllocation).confirmMilestone(0);

        address[] memory addresses = new address[](1);
        addresses[0] = vestingAllocation;
        bytes4 selector = bytes4(keccak256("removeMetavestMilestone(address,uint256)"));
        bytes memory msgData = abi.encodeWithSelector(selector, vestingAllocation, 0);
        vm.prank(authority);
        controller.proposeMetavestAmendment(vestingAllocation, controller.removeMetavestMilestone.selector, msgData);

        vm.prank(grantee);
        controller.consentToMetavestAmendment(vestingAllocation, controller.removeMetavestMilestone.selector, false);
        // emit MetaVesTController_AmendmentConsentUpdated(msgSig: 0x75b89e4f00000000000000000000000000000000000000000000000000000000, grantee: ECAdd: [0x0000000000000000000000000000000000000006], inFavor: false)
        console.log("expected inFavor: false");
        MetaVesTControllerStorage.AmendmentProposal memory proposal = controller.functionToGranteeToAmendmentPending(selector, vestingAllocation);
        console.log("output: ", proposal.inFavor);
        assertEq(proposal.inFavor, false);

    }

    function test_RevertIf_AuditProposeMajorityMetavestAmendmentNewGranteeDuringProposal() public {
        // template from testProposeMajorityMetavestAmendment
        address mockAllocation2 = createDummyVestingAllocation();
        address mockAllocation3 = createDummyVestingAllocation();
        address mockAllocation4 = createDummyVestingAllocation();
        address mockAllocation5 = createDummyVestingAllocation();
        address mockAllocation6 = createDummyVestingAllocation();
        address mockAllocation7 = createDummyVestingAllocation();
        bytes4 msgSig = bytes4(keccak256("updateMetavestTransferability(address,bool)"));
        bytes memory callData = abi.encodeWithSelector(msgSig, mockAllocation2, true);

        vm.prank(authority);
        controller.addMetaVestToSet("testSet", mockAllocation2);
        vm.warp(block.timestamp + 1 days);
        vm.prank(authority);
        controller.proposeMajorityMetavestAmendment("testSet", msgSig, callData);

        vm.startPrank(authority);
        vm.expectRevert(abi.encodeWithSelector(MetaVesTControllerStorage.MetaVesTController_AmendmentAlreadyPending.selector));
        controller.addMetaVestToSet("testSet", mockAllocation3);
        vm.expectRevert(abi.encodeWithSelector(MetaVesTControllerStorage.MetaVesTController_AmendmentAlreadyPending.selector));
        controller.addMetaVestToSet("testSet", mockAllocation4);
        vm.expectRevert(abi.encodeWithSelector(MetaVesTControllerStorage.MetaVesTController_AmendmentAlreadyPending.selector));
        controller.addMetaVestToSet("testSet", mockAllocation5);
        vm.expectRevert(abi.encodeWithSelector(MetaVesTControllerStorage.MetaVesTController_AmendmentAlreadyPending.selector));
        controller.addMetaVestToSet("testSet", mockAllocation6);
        vm.expectRevert(abi.encodeWithSelector(MetaVesTControllerStorage.MetaVesTController_AmendmentAlreadyPending.selector));
        controller.addMetaVestToSet("testSet", mockAllocation7);
        vm.stopPrank();

        vm.startPrank(grantee);
        controller.voteOnMetavestAmendment(mockAllocation2, "testSet", msgSig, true);
        vm.expectRevert(abi.encodeWithSelector(MetaVesTControllerStorage.MetaVesTController_SetDoesNotExist.selector));
        controller.voteOnMetavestAmendment(mockAllocation3, "testSet", msgSig, true);
        vm.expectRevert(abi.encodeWithSelector(MetaVesTControllerStorage.MetaVesTController_SetDoesNotExist.selector));
        controller.voteOnMetavestAmendment(mockAllocation4, "testSet", msgSig, true);
        vm.expectRevert(abi.encodeWithSelector(MetaVesTControllerStorage.MetaVesTController_SetDoesNotExist.selector));
        controller.voteOnMetavestAmendment(mockAllocation5, "testSet", msgSig, true);
        vm.expectRevert(abi.encodeWithSelector(MetaVesTControllerStorage.MetaVesTController_SetDoesNotExist.selector));
        controller.voteOnMetavestAmendment(mockAllocation6, "testSet", msgSig, true);
        vm.expectRevert(abi.encodeWithSelector(MetaVesTControllerStorage.MetaVesTController_SetDoesNotExist.selector));
        controller.voteOnMetavestAmendment(mockAllocation7, "testSet", msgSig, true);
        vm.stopPrank();

        (uint256 totalVotingPower, uint256 currentVotingPower,,,) = controller.functionToSetMajorityProposal(msgSig, "testSet");
        console.log("totalVotingPower: ", totalVotingPower);
        console.log("currentVotingPower: ", currentVotingPower);
    }

    function testCreateSetAddVestingThenRemoveSet() public {

        // template from testCreateSetAddVestingThenRemoveSet
        address allocation1 = createDummyVestingAllocation();
        address allocation2 = createDummyVestingAllocation();
        address allocation3 = createDummyVestingAllocation();

        vm.startPrank(authority);
        controller.createSet("testSetB");
        controller.addMetaVestToSet("testSetB", allocation1);
        controller.addMetaVestToSet("testSetB", allocation2);
        controller.addMetaVestToSet("testSetB", allocation3);
        controller.removeSet("testSetB");
        controller.createSet("testSetB");
        vm.stopPrank();

    }

}