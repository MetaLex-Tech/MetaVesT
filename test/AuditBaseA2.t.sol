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
    function testAuditArbitraryVote() public {
        // template from testVoteOnMetavestAmendment
        bytes4 msgSig = bytes4(keccak256("updateMetavestTransferability(address,bool)"));
        bytes memory callData = abi.encodeWithSelector(msgSig, address(mockAllocation), true);

        vm.prank(authority);
        controller.addMetaVestToSet("testSet", address(mockAllocation));

        vm.prank(authority);
        controller.proposeMajorityMetavestAmendment("testSet", msgSig, callData);

        address attacker = address(0x31337);
        address evil_grant = address(new EvilGrant());
        
        vm.prank(attacker);
        controller.voteOnMetavestAmendment(address(evil_grant), "testSet", msgSig, true);

        (uint256 totalVotingPower, uint256 currentVotingPower, , ,  ) = controller.functionToSetMajorityProposal(msgSig, "testSet");
        console.log("attacker made vote and power is" , currentVotingPower);
    }

    function testAuditRemoveConfirmedMilestone() public {
        // template from testRemoveMilestone
        address vestingAllocation = createDummyVestingAllocation();
        VestingAllocation(vestingAllocation).confirmMilestone(0);
        
        address[] memory addresses = new address[](1);
        addresses[0] = vestingAllocation;
        bytes4 selector = bytes4(keccak256("removeMetavestMilestone(address,uint256)"));
        bytes memory msgData = abi.encodeWithSelector(selector, vestingAllocation, 0);
        controller.proposeMetavestAmendment(vestingAllocation, controller.removeMetavestMilestone.selector, msgData);

        vm.prank(grantee);
        controller.consentToMetavestAmendment(vestingAllocation, controller.removeMetavestMilestone.selector, true);
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

        vm.prank(authority);
        controller.addMetaVestToSet("testSet", allocation1);
        controller.addMetaVestToSet("testSet", allocation2);
        controller.addMetaVestToSet("testSet", allocation3);
         assertTrue(TokenOptionAllocation(allocation1).exercisePrice() == 1e18);
         vm.warp(block.timestamp + 25 seconds);

        
        vm.startPrank(grantee);
        ERC20(paymentToken).approve(address(allocation1), 2000e18);
        ERC20(paymentToken).approve(address(allocation2), 2000e18);
 
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

        vm.prank(authority);
        vm.expectRevert();
        controller.updateExerciseOrRepurchasePrice(allocation1, 999999999999999999999e18);

        // Bypass MetaVesTController_AmendmentNeitherMutualNorMajorityConsented
        vm.prank(authority);
        bytes memory p = abi.encodeWithSelector(msgSig, allocation1, 999999999999999999999e18, 2e18);
        address(controller).call(p);

        console.log('Modified excercise price: ', TokenOptionAllocation(allocation1).exercisePrice());
    }

    function testAuditConsentToMetavestAmendmentInFlavor() public {
        // template from testRemoveMilestone
        address vestingAllocation = createDummyVestingAllocation();
        VestingAllocation(vestingAllocation).confirmMilestone(0);
        
        address[] memory addresses = new address[](1);
        addresses[0] = vestingAllocation;
        bytes4 selector = bytes4(keccak256("removeMetavestMilestone(address,uint256)"));
        bytes memory msgData = abi.encodeWithSelector(selector, vestingAllocation, 0);
        controller.proposeMetavestAmendment(vestingAllocation, controller.removeMetavestMilestone.selector, msgData);

        vm.prank(grantee);
        controller.consentToMetavestAmendment(vestingAllocation, controller.removeMetavestMilestone.selector, false);
        // emit MetaVesTController_AmendmentConsentUpdated(msgSig: 0x75b89e4f00000000000000000000000000000000000000000000000000000000, grantee: ECAdd: [0x0000000000000000000000000000000000000006], inFavor: false)
        console.log("expected inFavor: false");
        (,,bool inFavor) = controller.functionToGranteeToAmendmentPending(selector, vestingAllocation);
        console.log("output: ", inFavor);
    }

    function testAuditProposeMajorityMetavestAmendmentNewGranteeDuringProposal() public {
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
        controller.addMetaVestToSet("testSet", mockAllocation3);
        controller.addMetaVestToSet("testSet", mockAllocation4);
        controller.addMetaVestToSet("testSet", mockAllocation5);
        controller.addMetaVestToSet("testSet", mockAllocation6);
        controller.addMetaVestToSet("testSet", mockAllocation7);
        vm.stopPrank();
        
        vm.startPrank(grantee);
        controller.voteOnMetavestAmendment(mockAllocation2, "testSet", msgSig, true);
        controller.voteOnMetavestAmendment(mockAllocation3, "testSet", msgSig, true);
        controller.voteOnMetavestAmendment(mockAllocation4, "testSet", msgSig, true);
        controller.voteOnMetavestAmendment(mockAllocation5, "testSet", msgSig, true);
        controller.voteOnMetavestAmendment(mockAllocation6, "testSet", msgSig, true);
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