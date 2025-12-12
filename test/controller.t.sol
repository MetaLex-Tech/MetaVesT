// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.20;

import {console2} from "forge-std/console2.sol";
import {Initializable} from "openzeppelin-contracts-upgradeable/proxy/utils/Initializable.sol";
import "../src/RestrictedTokenAllocation.sol";
import "../src/TokenOptionAllocation.sol";
import "../src/VestingAllocation.sol";
import "../src/interfaces/IAllocationFactory.sol";
import "./lib/MetaVesTControllerTestBaseExtended.sol";
import "./mocks/MockCondition.sol";
import {ERC1967ProxyLib} from "./lib/ERC1967ProxyLib.sol";

contract MetaVestControllerTest is MetaVesTControllerTestBaseExtended {
    using MetaVestDealLib for MetaVestDeal;

    function test_RevertIf_InitializeImplementation() public {
        metavestController controllerImpl = new metavestController();
        vm.expectRevert(Initializable.InvalidInitialization.selector);
        controllerImpl.initialize(
            address(123), // no-op
            address(123), // no-op
            address(123), // no-op
            address(123) // no-op
        );
    }

    function testCreateVestingAllocation() public {
        bytes32 contractIdAlice = _proposeAndSignDeal(
            templateId,
            block.timestamp, // salt
            delegatePrivateKey,
            MetaVestDealLib.draft().setVesting(
                alice,
                BaseAllocation.Allocation({
                    tokenContract: address(vestingToken),
                    tokenStreamTotal: 60 ether,
                    vestingCliffCredit: 30 ether,
                    unlockingCliffCredit: 30 ether,
                    vestingRate: 1 ether,
                    vestingStartTime: uint48(block.timestamp),
                    unlockRate: 1 ether,
                    unlockStartTime: uint48(block.timestamp)
                }),
                new BaseAllocation.Milestone[](0)
            ),
            "Alice",
            metavestExpiry
        );

        VestingAllocation vestingAllocationAlice = VestingAllocation(_granteeSignDeal(
            contractIdAlice,
            alice, // grantee
            alice, // recipient
            alicePrivateKey,
            "Alice"
        ));

        assertEq(controller.getDeal(contractIdAlice).metavest, address(vestingAllocationAlice), "deal data should be updated with MetaVesT address");

        // Grantees should be able to withdraw all remaining tokens after sufficient time passed
        skip(61);
        _granteeWithdrawAndAsserts(vestingAllocationAlice, 60 ether, "Alice full");
    }

    function testCreateTokenOptionAllocation() public {
        BaseAllocation.Milestone[] memory milestones = new BaseAllocation.Milestone[](1);
        milestones[0] = BaseAllocation.Milestone({
            milestoneAward: 100e18,
            unlockOnCompletion: true,
            complete: false,
            conditionContracts: new address[](0)
        });

        bytes32 contractIdAlice = _proposeAndSignDeal(
            templateId,
            block.timestamp, // salt
            delegatePrivateKey,
            MetaVestDealLib.draft().setTokenOption(
                alice,
                address(paymentToken),
                1e18, // exercisePrice
                365 days, // shortStopDuration
                BaseAllocation.Allocation({
                    tokenContract: address(vestingToken),
                    tokenStreamTotal: 1000e18,
                    vestingCliffCredit: 100e18,
                    unlockingCliffCredit: 100e18,
                    vestingRate: 10e18,
                    vestingStartTime: uint48(block.timestamp),
                    unlockRate: 10e18,
                    unlockStartTime: uint48(block.timestamp)
                }),
                milestones
            ),
            "Alice",
            metavestExpiry,
            ""
        );

        TokenOptionAllocation metavestAlice = TokenOptionAllocation(_granteeSignDeal(
            contractIdAlice,
            alice, // grantee
            alice, // recipient
            alicePrivateKey,
            "Alice"
        ));

        assertEq(vestingToken.balanceOf(address(metavestAlice)), 1100e18, "Vesting contract should have token in escrow");
    }

    function testCreateRestrictedTokenAward() public {
        BaseAllocation.Milestone[] memory milestones = new BaseAllocation.Milestone[](1);
        milestones[0] = BaseAllocation.Milestone({
            milestoneAward: 100e18,
            unlockOnCompletion: true,
            complete: false,
            conditionContracts: new address[](0)
        });

        bytes32 contractIdAlice = _proposeAndSignDeal(
            templateId,
            block.timestamp, // salt
            delegatePrivateKey,
            MetaVestDealLib.draft().setTokenOption(
                alice,
                address(paymentToken),
                1e18, // exercisePrice
                365 days, // shortStopDuration
                BaseAllocation.Allocation({
                    tokenContract: address(vestingToken),
                    tokenStreamTotal: 1000e18,
                    vestingCliffCredit: 100e18,
                    unlockingCliffCredit: 100e18,
                    vestingRate: 10e18,
                    vestingStartTime: uint48(block.timestamp),
                    unlockRate: 10e18,
                    unlockStartTime: uint48(block.timestamp)
                }),
                milestones
            ),
            "Alice",
            metavestExpiry,
            ""
        );

        RestrictedTokenAward metavestAlice = RestrictedTokenAward(_granteeSignDeal(
            contractIdAlice,
            alice, // grantee
            alice, // recipient
            alicePrivateKey,
            "Alice"
        ));

        assertEq(vestingToken.balanceOf(address(metavestAlice)), 1100e18);
    }

    function testUpdateTransferability() public {
        uint256 startTimestamp = block.timestamp;
        address vestingAllocation = createDummyVestingAllocation();
        address[] memory addresses = new address[](1);
        addresses[0] = vestingAllocation;
        //compute msg.data for updateMetavestTransferability(vestingAllocation, true)
        bytes4 selector = controller.updateMetavestTransferability.selector;
        bytes memory msgData = abi.encodeWithSelector(selector, vestingAllocation, true);
        vm.prank(authority);
        controller.proposeMetavestAmendment(vestingAllocation, controller.updateMetavestTransferability.selector, msgData);
        vm.prank(grantee);
        controller.consentToMetavestAmendment(vestingAllocation, controller.updateMetavestTransferability.selector, true);
        vm.prank(authority);
        controller.updateMetavestTransferability(vestingAllocation, true);
        vm.prank(grantee);
        VestingAllocation(vestingAllocation).transferRights(transferee);
        vm.prank(transferee);
        VestingAllocation(vestingAllocation).confirmTransfer();
        uint256 newTimestamp = startTimestamp + 100; // 101
        vm.warp(newTimestamp);
        skip(10);
        vm.prank(transferee);
        uint256 balance = VestingAllocation(vestingAllocation).getAmountWithdrawable();


    //warp ahead 100 blocks

        vm.prank(transferee);
        VestingAllocation(vestingAllocation).withdraw(balance);

       // assertTrue(BaseAllocation(vestingAllocation).transferable());
    }

    function testGetGovPower() public {
       address vestingAllocation = createDummyVestingAllocation();
       BaseAllocation(vestingAllocation).getGoverningPower();
    }

     function testProposeMajorityMetavestAmendment() public {
        address vestingAllocation = createDummyVestingAllocation();
        bytes4 msgSig = bytes4(keccak256("updateMetavestTransferability(address,bool)"));
        bytes memory callData = abi.encodeWithSelector(msgSig, vestingAllocation, true);

        vm.prank(authority);
        controller.addMetaVestToSet("testSet", vestingAllocation);
        vm.warp(block.timestamp + 1 days);
        vm.prank(authority);
        controller.proposeMajorityMetavestAmendment("testSet", msgSig, callData);

        vm.prank(grantee);
        controller.voteOnMetavestAmendment(vestingAllocation, "testSet", msgSig, true);

        vm.prank(authority);
        controller.updateMetavestTransferability(vestingAllocation, true);
    }


     function test_RevertIf_ReProposeMajorityMetavestAmendment() public {
        address mockAllocation2 = createDummyVestingAllocation();
        bytes4 msgSig = bytes4(keccak256("updateMetavestTransferability(address,bool)"));
        bytes memory callData = abi.encodeWithSelector(msgSig, mockAllocation2, true);

        vm.prank(authority);
        controller.addMetaVestToSet("testSet", mockAllocation2);
        vm.warp(block.timestamp + 1 days);
        vm.prank(authority);
        controller.proposeMajorityMetavestAmendment("testSet", msgSig, callData);
        vm.warp(block.timestamp + 30 days);
        /*
        vm.prank(grantee);
        controller.voteOnMetavestAmendment(mockAllocation2, "testSet", msgSig, true);

        vm.prank(authority);
        controller.updateMetavestTransferability(mockAllocation2, true);*/
        vm.expectRevert(abi.encodeWithSelector(MetaVesTControllerStorage.MetaVesTController_AmendmentAlreadyPending.selector));
        vm.prank(authority);
        controller.proposeMajorityMetavestAmendment("testSet", msgSig, callData);
    }

    function testReProposeMajorityMetavestAmendment() public {
        address mockAllocation2 = createDummyVestingAllocation();
        bytes4 msgSig = bytes4(keccak256("updateMetavestTransferability(address,bool)"));
        bytes memory callData = abi.encodeWithSelector(msgSig, mockAllocation2, true);

        vm.prank(authority);
        controller.addMetaVestToSet("testSet", mockAllocation2);
        vm.warp(block.timestamp + 1 days);
        vm.prank(authority);
        controller.proposeMajorityMetavestAmendment("testSet", msgSig, callData);
        vm.warp(block.timestamp + 30 days);

        vm.prank(authority);
        controller.cancelExpiredMajorityMetavestAmendment("testSet", msgSig);

        vm.prank(authority);
        controller.proposeMajorityMetavestAmendment("testSet", msgSig, callData);

    }

    function test_RevertIf_RemoveNonExistantMetaVestFromSet() public {
        address mockAllocation2 = createDummyVestingAllocation();
        vm.startPrank(authority);
      //  controller.createSet("testSet");
        vm.expectRevert(abi.encodeWithSelector(MetaVesTControllerStorage.MetaVestController_MetaVestNotInSet.selector));
        controller.removeMetaVestFromSet("testSet", mockAllocation2);
    }


    function testUpdateExercisePrice() public {
        address tokenOptionAllocation = createDummyTokenOptionAllocation();

        //compute msg.data for updateExerciseOrRepurchasePrice(tokenOptionAllocation, 2e18)
        bytes4 selector = controller.updateExerciseOrRepurchasePrice.selector;
        bytes memory msgData = abi.encodeWithSelector(selector, tokenOptionAllocation, 2e18);

        vm.prank(authority);
        controller.proposeMetavestAmendment(tokenOptionAllocation, controller.updateExerciseOrRepurchasePrice.selector, msgData);

        vm.prank(grantee);
        controller.consentToMetavestAmendment(tokenOptionAllocation, controller.updateExerciseOrRepurchasePrice.selector, true);

        vm.prank(authority);
        controller.updateExerciseOrRepurchasePrice(tokenOptionAllocation, 2e18);

        assertEq(TokenOptionAllocation(tokenOptionAllocation).exercisePrice(), 2e18);
    }

    function testRemoveMilestone() public {
        address vestingAllocation = createDummyVestingAllocation();
        //create array of addresses and include vestingAllocation address
        address[] memory addresses = new address[](1);
        addresses[0] = vestingAllocation;
        bytes4 selector = bytes4(keccak256("removeMetavestMilestone(address,uint256)"));
        bytes memory msgData = abi.encodeWithSelector(selector, vestingAllocation, 0);
        vm.prank(authority);
        controller.proposeMetavestAmendment(vestingAllocation, controller.removeMetavestMilestone.selector, msgData);
        vm.prank(grantee);
        //consent to amendment for the removemetavestmilestone method sig function consentToMetavestAmendment(address _metavest, bytes4 _msgSig, bool _inFavor) external {
        controller.consentToMetavestAmendment(vestingAllocation, controller.removeMetavestMilestone.selector, true);
        vm.prank(authority);
        controller.removeMetavestMilestone(vestingAllocation, 0);

        //BaseAllocation.Milestone memory milestone = BaseAllocation(vestingAllocation).milestones(0);
        //assertEq(milestone.milestoneAward, 0);
    }

    function testAddMilestone() public {
        address vestingAllocation = createDummyVestingAllocation();

        BaseAllocation.Milestone memory newMilestone = BaseAllocation.Milestone({
            milestoneAward: 50 ether,
            unlockOnCompletion: true,
            complete: false,
            conditionContracts: new address[](0)
        });

        uint256 balanceBefore = vestingToken.balanceOf(address(vestingAllocation));
        vm.prank(authority);
        controller.addMetavestMilestone(vestingAllocation, newMilestone);
        assertEq(
            vestingToken.balanceOf(address(vestingAllocation)) - balanceBefore,
            50 ether,
            "vesting contract should receive token amount add by the milestone"
        );

        (uint256 milestoneAward, , ) = BaseAllocation(vestingAllocation).milestones(1);
        assertEq(milestoneAward, 50 ether, "milestone should be added");
    }

    function testUpdateUnlockRate() public {
        address vestingAllocation = createDummyVestingAllocation();
        address[] memory addresses = new address[](1);
        addresses[0] = vestingAllocation;
        bytes4 selector = controller.updateMetavestUnlockRate.selector;
        bytes memory msgData = abi.encodeWithSelector(selector, vestingAllocation, 20e18);
        vm.prank(authority);
        controller.proposeMetavestAmendment(vestingAllocation, controller.updateMetavestUnlockRate.selector, msgData);
        vm.prank(grantee);
        controller.consentToMetavestAmendment(vestingAllocation, controller.updateMetavestUnlockRate.selector, true);
        vm.prank(authority);
        controller.updateMetavestUnlockRate(vestingAllocation, 20e18);

        BaseAllocation.Allocation memory updatedAllocation = BaseAllocation(vestingAllocation).getMetavestDetails();
        assertEq(updatedAllocation.unlockRate, 20e18);
    }

    function testUpdateUnlockRateZeroEmergency() public {
        address vestingAllocation = createDummyVestingAllocation();
        address[] memory addresses = new address[](1);
        addresses[0] = vestingAllocation;
        bytes4 selector = controller.updateMetavestUnlockRate.selector;
        bytes memory msgData = abi.encodeWithSelector(selector, vestingAllocation, 0);
        vm.prank(authority);
        controller.proposeMetavestAmendment(vestingAllocation, controller.updateMetavestUnlockRate.selector, msgData);
        vm.prank(grantee);
        controller.consentToMetavestAmendment(vestingAllocation, controller.updateMetavestUnlockRate.selector, true);
        vm.prank(authority);
        controller.updateMetavestUnlockRate(vestingAllocation, 0);

        BaseAllocation.Allocation memory updatedAllocation = BaseAllocation(vestingAllocation).getMetavestDetails();
        assertEq(updatedAllocation.unlockRate, 0);
        vm.prank(authority);
        controller.terminateMetavestVesting(vestingAllocation);
        vm.prank(authority);
        controller.emergencyUpdateMetavestUnlockRate(vestingAllocation, 1e20);
        updatedAllocation = BaseAllocation(vestingAllocation).getMetavestDetails();
        assertEq(updatedAllocation.unlockRate, 1e20);
    }

    function test_RevertIf_UpdateUnlockRateZeroEmergency() public {
        address vestingAllocation = createDummyVestingAllocation();
        address[] memory addresses = new address[](1);
        addresses[0] = vestingAllocation;
        bytes4 selector = controller.updateMetavestUnlockRate.selector;
        bytes memory msgData = abi.encodeWithSelector(selector, vestingAllocation, 0);
        vm.prank(authority);
        controller.proposeMetavestAmendment(vestingAllocation, controller.updateMetavestUnlockRate.selector, msgData);
        vm.prank(grantee);
        controller.consentToMetavestAmendment(vestingAllocation, controller.updateMetavestUnlockRate.selector, true);
        vm.prank(authority);
        controller.terminateMetavestVesting(vestingAllocation);

        vm.expectRevert(abi.encodeWithSelector(MetaVesTControllerStorage.MetaVesTController_EmergencyUnlockNotSatisfied.selector));
        vm.prank(authority);
        controller.emergencyUpdateMetavestUnlockRate(vestingAllocation, 1e20);
        BaseAllocation.Allocation memory updatedAllocation = BaseAllocation(vestingAllocation).getMetavestDetails();
        assertEq(updatedAllocation.unlockRate, 10e18);
    }

    function test_RevertIf_UpdateUnlockRateZeroEmergencyTerminated() public {
        address vestingAllocation = createDummyVestingAllocation();
        address[] memory addresses = new address[](1);
        addresses[0] = vestingAllocation;
        bytes4 selector = controller.updateMetavestUnlockRate.selector;
        bytes memory msgData = abi.encodeWithSelector(selector, vestingAllocation, 0);
        vm.prank(authority);
        controller.proposeMetavestAmendment(vestingAllocation, controller.updateMetavestUnlockRate.selector, msgData);
        vm.prank(grantee);
        controller.consentToMetavestAmendment(vestingAllocation, controller.updateMetavestUnlockRate.selector, true);
                vm.prank(grantee);
        controller.consentToMetavestAmendment(vestingAllocation, controller.updateMetavestUnlockRate.selector, true);
        vm.prank(authority);
        controller.updateMetavestUnlockRate(vestingAllocation, 0);

        BaseAllocation.Allocation memory updatedAllocation = BaseAllocation(vestingAllocation).getMetavestDetails();
        assertEq(updatedAllocation.unlockRate, 0);

        vm.expectRevert(abi.encodeWithSelector(MetaVesTControllerStorage.MetaVesTController_EmergencyUnlockNotSatisfied.selector));
        vm.prank(authority);
        controller.emergencyUpdateMetavestUnlockRate(vestingAllocation, 1e20);
        updatedAllocation = BaseAllocation(vestingAllocation).getMetavestDetails();
        assertEq(updatedAllocation.unlockRate, 0);
    }

    function testUpdateVestingRate() public {
        address vestingAllocation = createDummyVestingAllocation();
        address[] memory addresses = new address[](1);
        addresses[0] = vestingAllocation;
        bytes4 selector = controller.updateMetavestVestingRate.selector;
        bytes memory msgData = abi.encodeWithSelector(selector, vestingAllocation, 20e18);
        vm.prank(authority);
        controller.proposeMetavestAmendment(vestingAllocation, controller.updateMetavestVestingRate.selector, msgData);
        vm.prank(grantee);
        controller.consentToMetavestAmendment(vestingAllocation, controller.updateMetavestVestingRate.selector, true);
        vm.prank(authority);
        controller.updateMetavestVestingRate(vestingAllocation, 20e18);

        BaseAllocation.Allocation memory updatedAllocation = BaseAllocation(vestingAllocation).getMetavestDetails();
        assertEq(updatedAllocation.vestingRate, 20e18);
    }

    function testUpdateStopTimes() public {

        address metavest = createDummyRestrictedTokenAward();
         address[] memory addresses = new address[](1);
        addresses[0] = metavest;
        bytes4 selector = bytes4(keccak256("updateMetavestStopTimes(address,uint48)"));
        bytes memory msgData = abi.encodeWithSelector(selector, metavest, uint48(block.timestamp + 500 days));

        vm.prank(authority);
        controller.proposeMetavestAmendment(metavest, controller.updateMetavestStopTimes.selector, msgData);

        vm.prank(grantee);
        controller.consentToMetavestAmendment(metavest, controller.updateMetavestStopTimes.selector, true);
        uint48 newShortStopTime = uint48(block.timestamp + 500 days);

        vm.prank(authority);
        controller.updateMetavestStopTimes(metavest, newShortStopTime);
    }

    function testTerminateVesting() public {
        address vestingAllocation = createDummyVestingAllocation();
        vm.prank(authority);
        controller.terminateMetavestVesting(vestingAllocation);

        assertTrue(BaseAllocation(vestingAllocation).terminated());
    }

    function testRepurchaseTokens() public {
        uint256 startingPaymentTokenBalance = paymentToken.balanceOf(grantee);
        address restrictedTokenAward = createDummyRestrictedTokenAward();
        uint256 repurchaseAmount = 5e18;
        uint256 startingVestingTokenBalance = vestingToken.balanceOf(authority);
        uint256 payment = RestrictedTokenAward(restrictedTokenAward).getPaymentAmount(repurchaseAmount);

        vm.startPrank(authority);

        controller.terminateMetavestVesting(restrictedTokenAward);
        paymentToken.approve(address(restrictedTokenAward), payment);

        vm.warp(block.timestamp + 20 days);

        RestrictedTokenAward(restrictedTokenAward).repurchaseTokens(repurchaseAmount);

        vm.stopPrank();

        assertEq(vestingToken.balanceOf(authority), startingVestingTokenBalance + repurchaseAmount);

        vm.prank(grantee);
        RestrictedTokenAward(restrictedTokenAward).claimRepurchasedTokens();
        assertEq(paymentToken.balanceOf(grantee), startingPaymentTokenBalance + payment);
    }

    function testRepurchaseTokensSpecifiedRecipient() public {
        uint256 startingPaymentTokenBalance = paymentToken.balanceOf(grantee);
        address restrictedTokenAward = createDummyRestrictedTokenAward(bob); // set bob as the recipient
        uint256 repurchaseAmount = 5e18;
        uint256 startingVestingTokenBalance = vestingToken.balanceOf(authority);
        uint256 payment = RestrictedTokenAward(restrictedTokenAward).getPaymentAmount(repurchaseAmount);

        vm.startPrank(authority);

        controller.terminateMetavestVesting(restrictedTokenAward);
        paymentToken.approve(address(restrictedTokenAward), payment);

        vm.warp(block.timestamp + 20 days);

        RestrictedTokenAward(restrictedTokenAward).repurchaseTokens(repurchaseAmount);

        vm.stopPrank();

        assertEq(vestingToken.balanceOf(authority), startingVestingTokenBalance + repurchaseAmount);

        vm.prank(grantee);
        vm.expectEmit(true, true, true, true);
        emit BaseAllocation.MetaVesT_Withdrawn(grantee, bob, address(paymentToken), payment);
        RestrictedTokenAward(restrictedTokenAward).claimRepurchasedTokens();
        assertEq(paymentToken.balanceOf(bob) - startingPaymentTokenBalance, payment, "Bob should receive the payment as the specified recipient");
    }

    function testRepurchaseTokensFuture() public {
        uint256 startingPaymentTokenBalance = paymentToken.balanceOf(grantee);
        address restrictedTokenAward = createDummyRestrictedTokenAwardFuture();

        uint256 startingVestingTokenBalance = vestingToken.balanceOf(authority);

        vm.startPrank(authority);

        controller.terminateMetavestVesting(restrictedTokenAward);
        uint256 repurchaseAmount = RestrictedTokenAward(restrictedTokenAward).getAmountRepurchasable();
        uint256 payment = RestrictedTokenAward(restrictedTokenAward).getPaymentAmount(repurchaseAmount);
        paymentToken.approve(address(restrictedTokenAward), payment);
        vm.warp(block.timestamp + 20 days);

        RestrictedTokenAward(restrictedTokenAward).repurchaseTokens(repurchaseAmount);

        vm.stopPrank();

        assertEq(vestingToken.balanceOf(authority), startingVestingTokenBalance +repurchaseAmount);

        vm.prank(grantee);
        RestrictedTokenAward(restrictedTokenAward).claimRepurchasedTokens();
        console2.log(vestingToken.balanceOf(restrictedTokenAward));
        assertEq(paymentToken.balanceOf(grantee), startingPaymentTokenBalance + payment);

    }

    function testTerminateTokensFuture() public {
        address vestingAllocation = createDummyVestingAllocationLargeFuture();
        vm.prank(authority);
        controller.terminateMetavestVesting(vestingAllocation);
    }

    function testUpdateAuthority() public {
        address newAuthority = address(0x4);
        vm.prank(authority);
        controller.initiateAuthorityUpdate(newAuthority);

        vm.prank(newAuthority);
        controller.acceptAuthorityRole();

        assertEq(controller.authority(), newAuthority);
    }

    function testUpdateDao() public {
        address newDao = address(0x5);

        vm.prank(dao);
        controller.initiateDaoUpdate(newDao);

        vm.prank(newDao);
        controller.acceptDaoRole();

        assertEq(controller.dao(), newDao);
    }

    function testWithdrawFromController() public {
        uint256 amount = 100e18;
        vm.startPrank(authority);

        paymentToken.transfer(address(controller), amount);

        uint256 initialBalance = paymentToken.balanceOf(authority);
        controller.withdrawFromController(address(paymentToken));
        uint256 finalBalance = paymentToken.balanceOf(authority);

        vm.stopPrank();

        assertEq(finalBalance - initialBalance, amount);
        assertEq(paymentToken.balanceOf(address(controller)), 0);
    }

    function test_RevertIf_CreateMetavestWithZeroAddress() public {
        BaseAllocation.Milestone[] memory milestones = new BaseAllocation.Milestone[](0);

        // Guardians to sign agreements and register on MetaVesTController
        bytes32 contractIdAlice = _proposeAndSignDeal(
            templateId,
            block.timestamp, // salt
            delegatePrivateKey,
            MetaVestDealLib.draft().setVesting(
                alice, // = grantee
                BaseAllocation.Allocation({
                    tokenContract: address(0), // zero address
                    tokenStreamTotal: 1000 ether,
                    vestingCliffCredit: 100 ether,
                    unlockingCliffCredit: 100 ether,
                    vestingRate: 10 ether,
                    vestingStartTime: uint48(block.timestamp),
                    unlockRate: 10 ether,
                    unlockStartTime: uint48(block.timestamp)
                }),
                milestones
            ),
            "Alice",
            metavestExpiry
        );

        _granteeSignDeal(
            contractIdAlice,
            alice, // grantee
            alice, // recipient
            alicePrivateKey,
            "Alice",
            abi.encodeWithSelector(MetaVesTControllerStorage.MetaVesTController_ZeroAddress.selector)
        );
    }

    function testTerminateVestAndRecovers() public {
        address vestingAllocation = createDummyVestingAllocation();
        uint256 snapshot = vestingToken.balanceOf(authority);
        VestingAllocation(vestingAllocation).confirmMilestone(0);
        vm.warp(block.timestamp + 50 seconds);

        uint256 authorityBalanceBefore = vestingToken.balanceOf(address(authority));
        vm.prank(authority);
        controller.terminateMetavestVesting(vestingAllocation);
        assertEq(vestingToken.balanceOf(
            address(authority)) - authorityBalanceBefore,
            400 ether, // 1000 + 1000 - 1000 - 100 - 10 * 50
            "authority should receive unvested funds"
        );

        vm.startPrank(grantee);
        VestingAllocation(vestingAllocation).withdraw(VestingAllocation(vestingAllocation).getAmountWithdrawable());
        vm.stopPrank();
        assertEq(vestingToken.balanceOf(vestingAllocation), 0);
    }

    function testTerminateVestAndRecoverSlowUnlock() public {
        address vestingAllocation = createDummyVestingAllocationSlowUnlock();
        uint256 snapshot = vestingToken.balanceOf(authority);
        VestingAllocation(vestingAllocation).confirmMilestone(0);
        vm.warp(block.timestamp + 25 seconds);
        vm.prank(authority);
        controller.terminateMetavestVesting(vestingAllocation);
        vm.startPrank(grantee);
        VestingAllocation(vestingAllocation).withdraw(VestingAllocation(vestingAllocation).getAmountWithdrawable());
        vm.warp(block.timestamp + 25 seconds);
        VestingAllocation(vestingAllocation).withdraw(VestingAllocation(vestingAllocation).getAmountWithdrawable());
        vm.stopPrank();
        assertEq(vestingToken.balanceOf(vestingAllocation), 0);
    }

    function testTerminateRecoverAll() public {
        address vestingAllocation = createDummyVestingAllocationLarge();
        uint256 snapshot = vestingToken.balanceOf(authority);
        vm.warp(block.timestamp + 25 seconds);

        uint256 authorityBalanceBefore = vestingToken.balanceOf(address(authority));
        vm.prank(authority);
        controller.terminateMetavestVesting(vestingAllocation);
        assertEq(vestingToken.balanceOf(
            address(authority)) - authorityBalanceBefore,
            750 ether, // 1000 - 10 * 25
            "authority should receive unvested funds"
        );

        vm.startPrank(grantee);
        VestingAllocation(vestingAllocation).withdraw(VestingAllocation(vestingAllocation).getAmountWithdrawable());
        vm.stopPrank();
        assertEq(vestingToken.balanceOf(vestingAllocation), 0);
    }

    function testTerminateRecoverChunksBefore() public {
        address vestingAllocation = createDummyVestingAllocationLarge();
        uint256 snapshot = vestingToken.balanceOf(authority);
        vm.warp(block.timestamp + 25 seconds);
        vm.startPrank(grantee);
        VestingAllocation(vestingAllocation).withdraw(VestingAllocation(vestingAllocation).getAmountWithdrawable());
        vm.stopPrank();
        vm.warp(block.timestamp + 25 seconds);

        uint256 authorityBalanceBefore = vestingToken.balanceOf(address(authority));
        vm.prank(authority);
        controller.terminateMetavestVesting(vestingAllocation);
        assertEq(vestingToken.balanceOf(
            address(authority)) - authorityBalanceBefore,
            500 ether, // 1000 - 10 * 50
            "authority should receive unvested funds"
        );

        vm.startPrank(grantee);
        VestingAllocation(vestingAllocation).withdraw(VestingAllocation(vestingAllocation).getAmountWithdrawable());
        vm.stopPrank();
        assertEq(vestingToken.balanceOf(vestingAllocation), 0);
    }

    function testConfirmingMilestoneRestrictedTokenAllocation() public {
        address metavest = createDummyRestrictedTokenAward();
        RestrictedTokenAward(metavest).confirmMilestone(0);
        vm.warp(block.timestamp + 50 seconds);
        vm.startPrank(grantee);
        RestrictedTokenAward(metavest).withdraw(RestrictedTokenAward(metavest).getAmountWithdrawable());
        vm.stopPrank();
    }

    function testConfirmingMilestoneTokenOption() public {
        address metavest = createDummyTokenOptionAllocation();
        TokenOptionAllocation(metavest).confirmMilestone(0);
        vm.warp(block.timestamp + 50 seconds);

        // Fund grantee
        uint256 vestingTokenExercisable = TokenOptionAllocation(metavest).getAmountExercisable();
        uint256 paymentTokenAmount = TokenOptionAllocation(metavest).getPaymentAmount(vestingTokenExercisable);
        paymentToken.mint(grantee, paymentTokenAmount);

        vm.startPrank(grantee);
        //exercise max available
        paymentToken.approve(metavest, TokenOptionAllocation(metavest).getPaymentAmount(TokenOptionAllocation(metavest).getAmountExercisable()));
        TokenOptionAllocation(metavest).exerciseTokenOption(vestingTokenExercisable);
        TokenOptionAllocation(metavest).withdraw(VestingAllocation(metavest).getAmountWithdrawable());
        vm.stopPrank();
    }

    function testUnlockMilestoneNotUnlocked() public {
        address metavest = createDummyVestingAllocationNoUnlock();
        VestingAllocation(metavest).confirmMilestone(0);
        vm.warp(block.timestamp + 50 seconds);
        vm.startPrank(grantee);
        VestingAllocation(metavest).withdraw(VestingAllocation(metavest).getAmountWithdrawable());
        vm.warp(block.timestamp + 1050 seconds);
        VestingAllocation(metavest).withdraw(VestingAllocation(metavest).getAmountWithdrawable());
        vm.stopPrank();
    }

    function testTerminateTokenOptionAndRecover() public {
        address tokenOptionAllocation = createDummyTokenOptionAllocation();
        vm.warp(block.timestamp + 25 seconds);

        // Fund grantee
        paymentToken.mint(grantee, 350e18);

        vm.prank(grantee);
        paymentToken.approve(tokenOptionAllocation, 350e18);

        vm.prank(grantee);
        TokenOptionAllocation(tokenOptionAllocation).exerciseTokenOption(350e18);

        vm.prank(authority);
        controller.terminateMetavestVesting(tokenOptionAllocation);

        vm.startPrank(grantee);
        vm.warp(block.timestamp + 1 days + 25 seconds);
        assertEq(TokenOptionAllocation(tokenOptionAllocation).getAmountExercisable(), 0);
        TokenOptionAllocation(tokenOptionAllocation).withdraw(TokenOptionAllocation(tokenOptionAllocation).getAmountWithdrawable());
        vm.stopPrank();
        assertEq(vestingToken.balanceOf(tokenOptionAllocation), 0);
        vm.warp(block.timestamp + 365 days);
        vm.prank(authority);
        TokenOptionAllocation(tokenOptionAllocation).recoverForfeitTokens();
    }

    function testTerminateEarlyTokenOptionAndRecover() public {
        address tokenOptionAllocation = createDummyTokenOptionAllocation();
        vm.warp(block.timestamp + 5 seconds);

        vm.startPrank(authority);

        controller.terminateMetavestVesting(tokenOptionAllocation);
        vm.warp(block.timestamp + 365 days);
        TokenOptionAllocation(tokenOptionAllocation).recoverForfeitTokens();

        vm.stopPrank();
    }

    function testTerminateRestrictedTokenAwardAndRecover() public {
        address restrictedTokenAward = createDummyRestrictedTokenAward();
        vm.warp(block.timestamp + 25 seconds);

        vm.prank(authority);
        controller.terminateMetavestVesting(restrictedTokenAward);

        vm.startPrank(grantee);
        RestrictedTokenAward(restrictedTokenAward).withdraw(RestrictedTokenAward(restrictedTokenAward).getAmountWithdrawable());
        vm.stopPrank();

        uint256 amt = RestrictedTokenAward(restrictedTokenAward).getAmountRepurchasable();
        uint256 payamt = RestrictedTokenAward(restrictedTokenAward).getPaymentAmount(amt);
        vm.warp(block.timestamp + 20 days);

        vm.startPrank(authority);

        paymentToken.approve(address(restrictedTokenAward), payamt);
        RestrictedTokenAward(restrictedTokenAward).repurchaseTokens(amt);

        vm.stopPrank();

        vm.prank(grantee);
        RestrictedTokenAward(restrictedTokenAward).claimRepurchasedTokens();
        
        assertEq(vestingToken.balanceOf(restrictedTokenAward), 0);
        assertEq(paymentToken.balanceOf(restrictedTokenAward), 0);
    }

    function testChangeVestingAndUnlockingRate() public {
        address restrictedTokenAward = createDummyRestrictedTokenAward();
        vm.warp(block.timestamp + 25 seconds);

        bytes4 msgSig = bytes4(keccak256("updateMetavestUnlockRate(address,uint160)"));
        bytes memory callData = abi.encodeWithSelector(msgSig, restrictedTokenAward, 50e18);

        vm.prank(authority);
        controller.proposeMetavestAmendment(restrictedTokenAward, msgSig, callData);

        vm.prank(grantee);
        controller.consentToMetavestAmendment(restrictedTokenAward, msgSig, true);

        vm.prank(authority);
        controller.updateMetavestUnlockRate(restrictedTokenAward, 50e18);

        msgSig = bytes4(keccak256("updateMetavestVestingRate(address,uint160)"));
        callData = abi.encodeWithSelector(msgSig, restrictedTokenAward, 50e18);

        vm.prank(authority);
        controller.proposeMetavestAmendment(restrictedTokenAward, msgSig, callData);

        vm.prank(grantee);
        controller.consentToMetavestAmendment(restrictedTokenAward, msgSig, true);

        vm.prank(authority);
        controller.updateMetavestVestingRate(restrictedTokenAward, 50e18);

        vm.startPrank(grantee);
        RestrictedTokenAward(restrictedTokenAward).withdraw(RestrictedTokenAward(restrictedTokenAward).getAmountWithdrawable());
        vm.stopPrank();

    }

    function testZeroReclaim() public {
        address restrictedTokenAward = createDummyRestrictedTokenAward();
        vm.warp(block.timestamp + 15 seconds);
        vm.startPrank(grantee);
        RestrictedTokenAward(restrictedTokenAward).withdraw(RestrictedTokenAward(restrictedTokenAward).getAmountWithdrawable());
        vm.stopPrank();
        //create call data to propose setting vesting to 0
        bytes4 msgSig = bytes4(keccak256("updateMetavestVestingRate(address,uint160)"));
        bytes memory callData = abi.encodeWithSelector(msgSig, restrictedTokenAward, 0);

        vm.prank(authority);
        controller.proposeMetavestAmendment(restrictedTokenAward, msgSig, callData);

        vm.prank(grantee);
        controller.consentToMetavestAmendment(restrictedTokenAward, msgSig, true);

        vm.prank(authority);
        controller.updateMetavestVestingRate(restrictedTokenAward, 0);

        vm.startPrank(authority);
        controller.terminateMetavestVesting(restrictedTokenAward);
        vm.warp(block.timestamp + 155 days);
        uint256 amt = RestrictedTokenAward(restrictedTokenAward).getAmountRepurchasable();
        uint256 payamt = RestrictedTokenAward(restrictedTokenAward).getPaymentAmount(amt);
        paymentToken.approve(address(restrictedTokenAward), payamt);
        RestrictedTokenAward(restrictedTokenAward).repurchaseTokens(amt);
                 vm.stopPrank();
        vm.prank(grantee);
        RestrictedTokenAward(restrictedTokenAward).claimRepurchasedTokens();
        console2.log(vestingToken.balanceOf(restrictedTokenAward));
    }

    function testZeroReclaimVesting() public {
        address vestingAllocation = createDummyVestingAllocation();
        vm.warp(block.timestamp + 15 seconds);
        vm.startPrank(grantee);
        VestingAllocation(vestingAllocation).withdraw(VestingAllocation(vestingAllocation).getAmountWithdrawable());
        vm.stopPrank();
        //create call data to propose setting vesting to 0
        bytes4 msgSig = bytes4(keccak256("updateMetavestVestingRate(address,uint160)"));
        bytes memory callData = abi.encodeWithSelector(msgSig, vestingAllocation, 0);

        vm.prank(authority);
        controller.proposeMetavestAmendment(vestingAllocation, msgSig, callData);

        vm.prank(grantee);
        controller.consentToMetavestAmendment(vestingAllocation, msgSig, true);

        vm.prank(authority);
        controller.updateMetavestVestingRate(vestingAllocation, 0);

        vm.startPrank(authority);
        controller.terminateMetavestVesting(vestingAllocation);
        vm.stopPrank();
    }

    function testSlightReduc() public {
        address vestingAllocation = createDummyVestingAllocation();
        vm.warp(block.timestamp + 5 seconds);
        vm.startPrank(grantee);
        VestingAllocation(vestingAllocation).withdraw(VestingAllocation(vestingAllocation).getAmountWithdrawable());
        vm.stopPrank();
        //create call data to propose setting vesting to 0
        bytes4 msgSig = bytes4(keccak256("updateMetavestVestingRate(address,uint160)"));
        bytes memory callData = abi.encodeWithSelector(msgSig, vestingAllocation, 80e18);

        vm.prank(authority);
        controller.proposeMetavestAmendment(vestingAllocation, msgSig, callData);

        vm.prank(grantee);
        controller.consentToMetavestAmendment(vestingAllocation, msgSig, true);

        vm.prank(authority);
        controller.updateMetavestVestingRate(vestingAllocation, 80e18);
        vm.warp(block.timestamp + 5 seconds);
        vm.startPrank(authority);
        controller.terminateMetavestVesting(vestingAllocation);
        vm.stopPrank();
        vm.warp(block.timestamp + 155 seconds);
        vm.startPrank(grantee);
        VestingAllocation(vestingAllocation).withdraw(VestingAllocation(vestingAllocation).getAmountWithdrawable());
        vm.stopPrank();
    }

    function testLargeReduc() public {
        address vestingAllocation = createDummyVestingAllocation();
        vm.warp(block.timestamp + 5 seconds);
        vm.startPrank(grantee);
        VestingAllocation(vestingAllocation).withdraw(VestingAllocation(vestingAllocation).getAmountWithdrawable());
        vm.stopPrank();
        //create call data to propose setting vesting to 0
        bytes4 msgSig = bytes4(keccak256("updateMetavestVestingRate(address,uint160)"));
        bytes memory callData = abi.encodeWithSelector(msgSig, vestingAllocation, 10e18);

        vm.prank(authority);
        controller.proposeMetavestAmendment(vestingAllocation, msgSig, callData);

        vm.prank(grantee);
        controller.consentToMetavestAmendment(vestingAllocation, msgSig, true);

        vm.prank(authority);
        controller.updateMetavestVestingRate(vestingAllocation, 10e18);
        vm.warp(block.timestamp + 5 seconds);
        vm.startPrank(authority);
        controller.terminateMetavestVesting(vestingAllocation);
        vm.stopPrank();
        vm.warp(block.timestamp + 155 seconds);
        vm.startPrank(grantee);
        VestingAllocation(vestingAllocation).withdraw(VestingAllocation(vestingAllocation).getAmountWithdrawable());
        vm.stopPrank();
    }

    function testLargeReducOption() public {
        address restrictedTokenAward = createDummyTokenOptionAllocation();
        vm.warp(block.timestamp + 5 seconds);

        {
            // Fund grantee
            uint256 vestingTokenExercisableAmount = TokenOptionAllocation(restrictedTokenAward).getAmountExercisable();
            uint256 paymentTokenAmount = TokenOptionAllocation(restrictedTokenAward).getPaymentAmount(vestingTokenExercisableAmount);
            deal(address(paymentToken), grantee, paymentTokenAmount);
            uint256 vestingTokenBalanceBefore = vestingToken.balanceOf(grantee);
            uint256 paymentTokenBalanceBefore = paymentToken.balanceOf(grantee);

            vm.startPrank(grantee);
            //approve amount to exercise by getting amount to exercise and price
            paymentToken.approve(restrictedTokenAward, paymentTokenAmount);
            TokenOptionAllocation(restrictedTokenAward).exerciseTokenOption(vestingTokenExercisableAmount);
            RestrictedTokenAward(restrictedTokenAward).withdraw(RestrictedTokenAward(restrictedTokenAward).getAmountWithdrawable());
            vm.stopPrank();

            assertEq(vestingToken.balanceOf(grantee) - vestingTokenBalanceBefore, 150 ether, "grantee should have exercised 100 + 10 * 5 = 150 tokens");
            assertEq(paymentTokenBalanceBefore - paymentToken.balanceOf(grantee), 75 ether, "grantee should have paid 150 * 0.5 = 75 tokens");
        }

        //create call data to propose setting vesting to 0
        bytes4 msgSig = bytes4(keccak256("updateMetavestVestingRate(address,uint160)"));
        bytes memory callData = abi.encodeWithSelector(msgSig, restrictedTokenAward, 20e18);

        vm.prank(authority);
        controller.proposeMetavestAmendment(restrictedTokenAward, msgSig, callData);

        vm.prank(grantee);
        controller.consentToMetavestAmendment(restrictedTokenAward, msgSig, true);

        vm.prank(authority);
        controller.updateMetavestVestingRate(restrictedTokenAward, 20e18);
        vm.warp(block.timestamp + 5 seconds);
        vm.startPrank(authority);
        controller.terminateMetavestVesting(restrictedTokenAward);
        vm.stopPrank();
        vm.warp(block.timestamp + 155 seconds);

        {
            // Fund grantee
            uint256 vestingTokenExercisableAmount = TokenOptionAllocation(restrictedTokenAward).getAmountExercisable();
            uint256 paymentTokenAmount = TokenOptionAllocation(restrictedTokenAward).getPaymentAmount(vestingTokenExercisableAmount);
            deal(address(paymentToken), grantee, paymentTokenAmount);
            uint256 vestingTokenBalanceBefore = vestingToken.balanceOf(grantee);
            uint256 paymentTokenBalanceBefore = paymentToken.balanceOf(grantee);

            vm.startPrank(grantee);

            paymentToken.approve(restrictedTokenAward, paymentTokenAmount);
            TokenOptionAllocation(restrictedTokenAward).exerciseTokenOption(vestingTokenExercisableAmount);
            RestrictedTokenAward(restrictedTokenAward).withdraw(RestrictedTokenAward(restrictedTokenAward).getAmountWithdrawable());
            vm.stopPrank();

            assertEq(vestingToken.balanceOf(grantee) - vestingTokenBalanceBefore, 150 ether, "grantee should have exercised 100 + 20 * (5 + 5) - 150 = 150 tokens");
            assertEq(paymentTokenBalanceBefore - paymentToken.balanceOf(grantee), 75 ether, "grantee should have paid 150 * 0.5 = 75 tokens");
        }
    }

    function testReclaim() public {
        address restrictedTokenAward = createDummyRestrictedTokenAward();
        vm.warp(block.timestamp + 15 seconds);
        vm.startPrank(grantee);
        RestrictedTokenAward(restrictedTokenAward).withdraw(RestrictedTokenAward(restrictedTokenAward).getAmountWithdrawable());
        assertEq(vestingToken.balanceOf(grantee), 250 ether, "grantee should receive 100 + 10 * 15 = 250 tokens");
        vm.stopPrank();

        vm.startPrank(authority);
        controller.terminateMetavestVesting(restrictedTokenAward);
        vm.warp(block.timestamp + 155 days);
        uint256 amt = RestrictedTokenAward(restrictedTokenAward).getAmountRepurchasable();
        uint256 payamt = RestrictedTokenAward(restrictedTokenAward).getPaymentAmount(amt);

        uint256 authorityVestingTokenBalanceBefore = vestingToken.balanceOf(authority);
        paymentToken.approve(address(restrictedTokenAward), payamt);
        RestrictedTokenAward(restrictedTokenAward).repurchaseTokens(amt);
        assertEq(vestingToken.balanceOf(authority) - authorityVestingTokenBalanceBefore, 1750 ether, "authority should have repurchased 1000 + 1000 - 250 = 1750 token");
        vm.stopPrank();

        vm.prank(grantee);
        RestrictedTokenAward(restrictedTokenAward).claimRepurchasedTokens();
        assertEq(paymentToken.balanceOf(grantee), 1750 ether, "grantee should receive repurchase payment of 1750 * 1 = 1750 tokens");
    }

    function test_RevertIf_UpdateExercisePriceForVesting() public {
        address vestingAllocation = createDummyVestingAllocation();

        vm.prank(authority);
        vm.expectRevert(MetaVesTControllerStorage.MetaVesTController_AmendmentNeitherMutualNorMajorityConsented.selector);
        controller.updateExerciseOrRepurchasePrice(vestingAllocation, 2e18);
    }

    function test_RevertIf_RepurchaseTokensBeforeShortStop() public {
        address restrictedTokenAward = createDummyRestrictedTokenAward();

        // Terminate, then immediate repurchase before short stop date
        vm.startPrank(authority);
        controller.terminateMetavestVesting(restrictedTokenAward);
        vm.expectRevert(BaseAllocation.MetaVesT_ShortStopTimeNotReached.selector);
        RestrictedTokenAward(restrictedTokenAward).repurchaseTokens(500e18);
        vm.stopPrank();
    }

    function test_RevertIf_RepurchaseTokensInsufficientAllowance() public {
        address restrictedTokenAward = createDummyRestrictedTokenAward();

        vm.startPrank(authority);

        // Terminate, then fast forward time to after the short stop date
        controller.terminateMetavestVesting(restrictedTokenAward);
        vm.warp(block.timestamp + 1 days);

        // Not approving any tokens
        vm.expectRevert(SafeTransferLib.TransferFromFailed.selector);
        RestrictedTokenAward(restrictedTokenAward).repurchaseTokens(500e18);

        vm.stopPrank();
    }

    function test_RevertIf_InitiateAuthorityUpdateNonAuthority() public {
        vm.prank(address(0x1234));
        vm.expectRevert(abi.encodeWithSelector(MetaVesTControllerStorage.MetaVesTController_OnlyAuthority.selector));
        controller.initiateAuthorityUpdate(address(0x5678));
    }

    function test_RevertIf_AcceptAuthorityRoleNonPendingAuthority() public {
        vm.prank(authority);
        controller.initiateAuthorityUpdate(address(0x5678));

        vm.prank(address(0x1234));
        vm.expectRevert(abi.encodeWithSelector(MetaVesTControllerStorage.MetaVesTController_OnlyPendingAuthority.selector));
        controller.acceptAuthorityRole();
    }

    function test_RevertIf_InitiateDaoUpdateNonDao() public {
        vm.prank(address(0x1234));
        vm.expectRevert(abi.encodeWithSelector(MetaVesTControllerStorage.MetaVesTController_OnlyDAO.selector));
        controller.initiateDaoUpdate(address(0x5678));
    }

    function test_RevertIf_AcceptDaoRoleNonPendingDao() public {
        vm.prank(dao);
        controller.initiateDaoUpdate(address(0x5678));

        vm.prank(address(0x1234));
        vm.expectRevert(abi.encodeWithSelector(MetaVesTControllerStorage.MetaVesTController_OnlyPendingDao.selector));
        controller.acceptDaoRole();
    }

    function testUpdateFunctionCondition() public {
        bytes4 functionSig = bytes4(keccak256("testFunction()"));
      /*      constructor(
        address[] memory _signers,
        uint256 _threshold,
        Logic _logic
    ) */
        address[] memory signers = new address[](2);
        signers[0] = address(0x1);
        signers[1] = address(0x2);
        SignatureCondition condition = new SignatureCondition(signers, 1, SignatureCondition.Logic.AND);

        vm.prank(dao);
        controller.updateFunctionCondition(address(condition), functionSig);

        assertEq(controller.functionToConditions(functionSig, 0), address(condition));
    }

    function test_RevertIf_UpdateFunctionConditionNonDao() public {
        bytes4 functionSig = bytes4(keccak256("updateMetavestStopTimes(address,uint48)"));
        address condition = address(0x1234);
        vm.expectRevert(abi.encodeWithSelector(MetaVesTControllerStorage.MetaVesTController_OnlyDAO.selector));
        controller.updateFunctionCondition(condition, functionSig);
    }


    function testRemoveFunctionCondition() public {
        bytes4 functionSig = bytes4(keccak256("updateMetavestStopTimes(address,uint48)"));
      /*      constructor(
        address[] memory _signers,
        uint256 _threshold,
        Logic _logic
    ) */
        address[] memory signers = new address[](2);
        signers[0] = address(0x1);
        signers[1] = address(0x2);
        SignatureCondition condition = new SignatureCondition(signers, 1, SignatureCondition.Logic.AND);

        vm.prank(dao);
        controller.updateFunctionCondition(address(condition), functionSig);
        assert(controller.functionToConditions(functionSig, 0) == address(condition));
        vm.prank(dao);
        controller.removeFunctionCondition(address(condition), functionSig);
    }

    function test_RevertIf_CheckFunctionCondition() public {
        bytes4 functionSig = bytes4(keccak256("signDealAndCreateMetavest(address,address,bytes32,string[],bytes,string)"));
      /*      constructor(
        address[] memory _signers,
        uint256 _threshold,
        Logic _logic
    ) */
        address[] memory signers = new address[](2);
        signers[0] = address(0x1);
        signers[1] = address(0x2);
        SignatureCondition condition = new SignatureCondition(signers, 1, SignatureCondition.Logic.AND);

        vm.prank(dao);
        controller.updateFunctionCondition(address(condition), functionSig);
        assert(controller.functionToConditions(functionSig, 0) == address(condition));
        // create a dummy metavest
        createDummyVestingAllocation(
            abi.encodeWithSelector(MetaVesTControllerStorage.MetaVesTController_ConditionNotSatisfied.selector, condition) // Expected revert
        );
    }

    function test_RevertIf_AddDuplicateCondition() public {
        bytes4 functionSig = bytes4(keccak256("createMetavest(uint8,address,(uint256,uint128,uint128,uint160,uint48,uint160,uint48,address),(uint256,bool,bool,address[])[],uint256,address,uint256,uint256)"));
      /*      constructor(
        address[] memory _signers,
        uint256 _threshold,
        Logic _logic
    ) */
        address[] memory signers = new address[](2);
        signers[0] = address(0x1);
        signers[1] = address(0x2);
        SignatureCondition condition = new SignatureCondition(signers, 1, SignatureCondition.Logic.AND);

        vm.prank(dao);
        controller.updateFunctionCondition(address(condition), functionSig);
        assert(controller.functionToConditions(functionSig, 0) == address(condition));
        vm.prank(dao);
        vm.expectRevert(abi.encodeWithSelector(MetaVesTControllerStorage.MetaVestController_DuplicateCondition.selector));
        controller.updateFunctionCondition(address(condition), functionSig);
    }
}
