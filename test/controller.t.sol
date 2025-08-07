// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.20;

import "../src/RestrictedTokenAllocation.sol";
import "../src/RestrictedTokenFactory.sol";
import "../src/TokenOptionAllocation.sol";
import "../src/TokenOptionFactory.sol";
import "../src/VestingAllocation.sol";
import "../src/VestingAllocationFactory.sol";
import "../src/interfaces/IAllocationFactory.sol";
import "../src/interfaces/zk-governance/IZkTokenV1.sol";
import "./lib/MetaVesTControllerTestBase.sol";
import "./mocks/MockCondition.sol";

contract MetaVestControllerTest is MetaVesTControllerTestBase {
    address authority = guardianSafe;
    address dao = guardianSafe;
    address grantee = alice;
    address transferee = address(0x101);

    // Parameters
    uint256 cap = 2000 ether;
    uint48 cappedMinterStartTime = uint48(block.timestamp); // Minter start now
    uint48 cappedMinterExpirationTime = uint48(cappedMinterStartTime + 1600); // Minter expired 1600 seconds after start

    function setUp() public override {
        MetaVesTControllerTestBase.setUp();

        vm.startPrank(deployer);

        // Deploy MetaVesT controller

        vestingAllocationFactory = new VestingAllocationFactory();

        controller = new metavestController{salt: salt}(
            guardianSafe,
            guardianSafe,
            address(registry),
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

        vm.startPrank(guardianSafe);
        controller.setZkCappedMinter(address(zkCappedMinter));
        controller.createSet("testSet");
        vm.stopPrank();
    }

    function testCreateVestingAllocation() public {
        bytes32 contractIdAlice = _proposeAndSignDeal(
            templateId,
            block.timestamp, // salt
            guardianSafe,
            alice,
            alicePrivateKey,
            BaseAllocation.Allocation({
                tokenContract: address(zkToken),
                // 100k ZK total, the first half unlocks with a cliff and the second half unlocks over an year
                tokenStreamTotal: 60 ether,
                vestingCliffCredit: 30 ether,
                unlockingCliffCredit: 30 ether,
                vestingRate: 1 ether,
                vestingStartTime: zkCappedMinter.START_TIME(), // start along with capped minter
                unlockRate: 1 ether,
                unlockStartTime: zkCappedMinter.START_TIME() // start along with capped minter
            }),
            new BaseAllocation.Milestone[](0),
            "Alice",
            cappedMinterExpirationTime // Same expiry as the minter so grantee can defer vesting contract creation as much as possible
        );

        // TPP to review agreements and on-chain parameters, then approve by granting our ZkCappedMinter permissions

        bytes32 minterRole = zkToken.MINTER_ROLE();
        vm.prank(zkTokenAdmin);
        zkToken.grantRole(minterRole, address(zkCappedMinter));

        // Anyone can create MetaVesT (per agreements) to start vesting
        VestingAllocation vestingAllocationAlice = VestingAllocation(controller.createMetavest(contractIdAlice));

        // Grantees should be able to withdraw all remaining tokens after sufficient time passed
        skip(61);
        _granteeWithdrawAndAsserts(vestingAllocationAlice, 60 ether, "Alice full");
    }

//    function testCreateTokenOptionAllocation() public {
//        BaseAllocation.Allocation memory allocation = BaseAllocation.Allocation({
//            tokenContract: address(zkToken),
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
//        address tokenOptionAllocation = controller.createMetavest(
//            metavestController.metavestType.TokenOption,
//            grantee,
//            allocation,
//            milestones,
//            1e18,
//            address(paymentToken),
//            365 days,
//            0
//        );
//
//        assertEq(zkToken.balanceOf(address(tokenOptionAllocation)), 0, "Vesting contract should not have any token (it mints on-demand)");
//        //assertEq(controller.tokenOptionAllocations(grantee, 0), tokenOptionAllocation);
//    }

//    function testCreateRestrictedTokenAward() public {
//        BaseAllocation.Allocation memory allocation = BaseAllocation.Allocation({
//            tokenContract: address(zkToken),
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
//        address restrictedTokenAward = controller.createMetavest(
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
//
//        assertEq(zkToken.balanceOf(address(restrictedTokenAward)), 0, "Vesting contract should not have any token (it mints on-demand)");
//        //assertEq(controller.restrictedTokenAllocations(grantee, 0), restrictedTokenAward);
//    }

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
        vm.expectRevert(abi.encodeWithSelector(metavestController.MetaVesTController_AmendmentAlreadyPending.selector));
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
        vm.expectRevert(abi.encodeWithSelector(metavestController.MetaVestController_MetaVestNotInSet.selector));
        controller.removeMetaVestFromSet("testSet", mockAllocation2);
    }


//    function testUpdateExercisePrice() public {
//        address tokenOptionAllocation = createDummyTokenOptionAllocation();
//
//        //compute msg.data for updateExerciseOrRepurchasePrice(tokenOptionAllocation, 2e18)
//        bytes4 selector = controller.updateExerciseOrRepurchasePrice.selector;
//        bytes memory msgData = abi.encodeWithSelector(selector, tokenOptionAllocation, 2e18);
//
//        controller.proposeMetavestAmendment(tokenOptionAllocation, controller.updateExerciseOrRepurchasePrice.selector, msgData);
//
//        vm.prank(grantee);
//        controller.consentToMetavestAmendment(tokenOptionAllocation, controller.updateExerciseOrRepurchasePrice.selector, true);
//
//        controller.updateExerciseOrRepurchasePrice(tokenOptionAllocation, 2e18);
//
//        assertEq(TokenOptionAllocation(tokenOptionAllocation).exercisePrice(), 2e18);
//    }

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
            milestoneAward: 50e18,
            unlockOnCompletion: true,
            complete: false,
            conditionContracts: new address[](0)
        });

        vm.prank(authority);
        controller.addMetavestMilestone(vestingAllocation, newMilestone);

       // BaseAllocation.Milestone memory addedMilestone = BaseAllocation(vestingAllocation).milestones[0];
      //  assertEq(addedMilestone.milestoneAward, 50e18);
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

        vm.expectRevert(abi.encodeWithSelector(metavestController.MetaVesTController_EmergencyUnlockNotSatisfied.selector));
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

        vm.expectRevert(abi.encodeWithSelector(metavestController.MetaVesTController_EmergencyUnlockNotSatisfied.selector));
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

//    function testUpdateStopTimes() public {
//
//        address vestingAllocation = createDummyRestrictedTokenAward();
//         address[] memory addresses = new address[](1);
//        addresses[0] = vestingAllocation;
//        bytes4 selector = bytes4(keccak256("updateMetavestStopTimes(address,uint48)"));
//        bytes memory msgData = abi.encodeWithSelector(selector, vestingAllocation, uint48(block.timestamp + 500 days));
//        controller.proposeMetavestAmendment(vestingAllocation, controller.updateMetavestStopTimes.selector, msgData);
//        vm.prank(grantee);
//        controller.consentToMetavestAmendment(vestingAllocation, controller.updateMetavestStopTimes.selector, true);
//        uint48 newShortStopTime = uint48(block.timestamp + 500 days);
//
//        controller.updateMetavestStopTimes(vestingAllocation, newShortStopTime);
//    }

    function testTerminateVesting() public {
        address vestingAllocation = createDummyVestingAllocation();
        vm.prank(authority);
        controller.terminateMetavestVesting(vestingAllocation);

        assertTrue(BaseAllocation(vestingAllocation).terminated());
    }

//    function testRepurchaseTokens() public {
//        uint256 startingBalance = paymentToken.balanceOf(grantee);
//        address restrictedTokenAward = createDummyRestrictedTokenAward();
//        uint256 repurchaseAmount = 5e18;
//        uint256 snapshot = token.balanceOf(authority);
//        uint256 payment = RestrictedTokenAward(restrictedTokenAward).getPaymentAmount(repurchaseAmount);
//        controller.terminateMetavestVesting(restrictedTokenAward);
//        paymentToken.approve(address(restrictedTokenAward), payment);
//        vm.warp(block.timestamp + 20 days);
//        vm.prank(authority);
//        RestrictedTokenAward(restrictedTokenAward).repurchaseTokens(repurchaseAmount);
//
//        assertEq(token.balanceOf(authority), snapshot+repurchaseAmount);
//
//        vm.prank(grantee);
//        RestrictedTokenAward(restrictedTokenAward).claimRepurchasedTokens();
//        assertEq(paymentToken.balanceOf(grantee), startingBalance + payment);
//    }

//    function testRepurchaseTokensFuture() public {
//        uint256 startingBalance = paymentToken.balanceOf(grantee);
//        address restrictedTokenAward = createDummyRestrictedTokenAwardFuture();
//
//        uint256 snapshot = token.balanceOf(authority);
//
//        controller.terminateMetavestVesting(restrictedTokenAward);
//        uint256 repurchaseAmount = RestrictedTokenAward(restrictedTokenAward).getAmountRepurchasable();
//        uint256 payment = RestrictedTokenAward(restrictedTokenAward).getPaymentAmount(repurchaseAmount);
//        paymentToken.approve(address(restrictedTokenAward), payment);
//        vm.warp(block.timestamp + 20 days);
//        vm.prank(authority);
//        RestrictedTokenAward(restrictedTokenAward).repurchaseTokens(repurchaseAmount);
//
//        assertEq(token.balanceOf(authority), snapshot+repurchaseAmount);
//
//        vm.prank(grantee);
//        RestrictedTokenAward(restrictedTokenAward).claimRepurchasedTokens();
//        console.log(token.balanceOf(restrictedTokenAward));
//        assertEq(paymentToken.balanceOf(grantee), startingBalance + payment);
//
//    }

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

    // Helper functions to create dummy allocations for testing
    function createDummyVestingAllocation() internal returns (address) {
        return createDummyVestingAllocation(""); // Expect no reverts
    }

    // Helper functions to create dummy allocations for testing
    function createDummyVestingAllocation(bytes memory expectRevertData) internal returns (address) {
        BaseAllocation.Milestone[] memory milestones = new BaseAllocation.Milestone[](1);
        milestones[0] = BaseAllocation.Milestone({
            milestoneAward: 1000 ether,
            unlockOnCompletion: true,
            complete: false,
            conditionContracts: new address[](0)
        });

        // Guardians to sign agreements and register on MetaVesTController
        bytes32 contractIdAlice = _proposeAndSignDeal(
            templateId,
            block.timestamp, // salt
            guardianSafe,
            alice, // = grantee
            alicePrivateKey,
            BaseAllocation.Allocation({
                tokenContract: address(zkToken),
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

        // TPP to review agreements and on-chain parameters, then approve by granting our ZkCappedMinter permissions
        bytes32 minterRole = zkToken.MINTER_ROLE();
        vm.prank(zkTokenAdmin);
        zkToken.grantRole(minterRole, address(zkCappedMinter));

        if (expectRevertData.length > 0) {
            vm.expectRevert(expectRevertData);
        }
        return controller.createMetavest(contractIdAlice);
    }

    // Helper functions to create dummy allocations for testing
    function createDummyVestingAllocationNoUnlock() internal returns (address) {
        BaseAllocation.Milestone[] memory milestones = new BaseAllocation.Milestone[](1);
        milestones[0] = BaseAllocation.Milestone({
            milestoneAward: 1000 ether,
            unlockOnCompletion: false,
            complete: false,
            conditionContracts: new address[](0)
        });

        // Guardians to sign agreements and register on MetaVesTController
        bytes32 contractIdAlice = _proposeAndSignDeal(
            templateId,
            block.timestamp, // salt
            guardianSafe,
            alice, // = grantee
            alicePrivateKey,
            BaseAllocation.Allocation({
                tokenContract: address(zkToken),
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

        // TPP to review agreements and on-chain parameters, then approve by granting our ZkCappedMinter permissions
        bytes32 minterRole = zkToken.MINTER_ROLE();
        vm.prank(zkTokenAdmin);
        zkToken.grantRole(minterRole, address(zkCappedMinter));

        return controller.createMetavest(contractIdAlice);
    }

    // Helper functions to create dummy allocations for testing
    function createDummyVestingAllocationSlowUnlock() internal returns (address) {
        BaseAllocation.Milestone[] memory milestones = new BaseAllocation.Milestone[](1);
        milestones[0] = BaseAllocation.Milestone({
            milestoneAward: 1000 ether,
            unlockOnCompletion: true,
            complete: false,
            conditionContracts: new address[](0)
        });

        // Guardians to sign agreements and register on MetaVesTController
        bytes32 contractIdAlice = _proposeAndSignDeal(
            templateId,
            block.timestamp, // salt
            guardianSafe,
            alice, // = grantee
            alicePrivateKey,
            BaseAllocation.Allocation({
                tokenContract: address(zkToken),
                tokenStreamTotal: 1000 ether,
                vestingCliffCredit: 100 ether,
                unlockingCliffCredit: 100 ether,
                vestingRate: 10 ether,
                vestingStartTime: uint48(block.timestamp),
                unlockRate: 5 ether,
                unlockStartTime: uint48(block.timestamp)
            }),
            milestones,
            "Alice",
            cappedMinterExpirationTime // Same expiry as the minter so grantee can defer vesting contract creation as much as possible
        );

        // TPP to review agreements and on-chain parameters, then approve by granting our ZkCappedMinter permissions
        bytes32 minterRole = zkToken.MINTER_ROLE();
        vm.prank(zkTokenAdmin);
        zkToken.grantRole(minterRole, address(zkCappedMinter));

        return controller.createMetavest(contractIdAlice);
    }

    // Helper functions to create dummy allocations for testing
    function createDummyVestingAllocationLarge() internal returns (address) {
        BaseAllocation.Milestone[] memory milestones = new BaseAllocation.Milestone[](0);

        // Guardians to sign agreements and register on MetaVesTController
        bytes32 contractIdAlice = _proposeAndSignDeal(
            templateId,
            block.timestamp, // salt
            guardianSafe,
            alice, // = grantee
            alicePrivateKey,
            BaseAllocation.Allocation({
                tokenContract: address(zkToken),
                tokenStreamTotal: 1000 ether,
                vestingCliffCredit: 0 ether,
                unlockingCliffCredit: 0 ether,
                vestingRate: 10 ether,
                vestingStartTime: uint48(block.timestamp),
                unlockRate: 10 ether,
                unlockStartTime: uint48(block.timestamp)
            }),
            milestones,
            "Alice",
            cappedMinterExpirationTime // Same expiry as the minter so grantee can defer vesting contract creation as much as possible
        );

        // TPP to review agreements and on-chain parameters, then approve by granting our ZkCappedMinter permissions
        bytes32 minterRole = zkToken.MINTER_ROLE();
        vm.prank(zkTokenAdmin);
        zkToken.grantRole(minterRole, address(zkCappedMinter));

        return controller.createMetavest(contractIdAlice);
    }

    // Helper functions to create dummy allocations for testing
    function createDummyVestingAllocationLargeFuture() internal returns (address) {
        BaseAllocation.Milestone[] memory milestones = new BaseAllocation.Milestone[](0);

        // Guardians to sign agreements and register on MetaVesTController
        bytes32 contractIdAlice = _proposeAndSignDeal(
            templateId,
            block.timestamp, // salt
            guardianSafe,
            alice, // = grantee
            alicePrivateKey,
            BaseAllocation.Allocation({
                tokenContract: address(zkToken),
                tokenStreamTotal: 1000 ether,
                vestingCliffCredit: 0 ether,
                unlockingCliffCredit: 0 ether,
                vestingRate: 10 ether,
                vestingStartTime: uint48(block.timestamp + 2000),
                unlockRate: 10 ether,
                unlockStartTime: uint48(block.timestamp + 2000)
            }),
            milestones,
            "Alice",
            cappedMinterExpirationTime // Same expiry as the minter so grantee can defer vesting contract creation as much as possible
        );

        // TPP to review agreements and on-chain parameters, then approve by granting our ZkCappedMinter permissions
        bytes32 minterRole = zkToken.MINTER_ROLE();
        vm.prank(zkTokenAdmin);
        zkToken.grantRole(minterRole, address(zkCappedMinter));

        return controller.createMetavest(contractIdAlice);
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
//            milestoneAward: 1000e18,
//            unlockOnCompletion: true,
//            complete: false,
//            conditionContracts: new address[](0)
//        });
//
//        token.approve(address(controller), 2000e18);
//
//        return controller.createMetavest(
//            metavestController.metavestType.TokenOption,
//            grantee,
//            allocation,
//            milestones,
//            5e17,
//            address(paymentToken),
//            1 days,
//            0
//        );
//    }


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
//            milestoneAward: 1000e18,
//            unlockOnCompletion: true,
//            complete: false,
//            conditionContracts: new address[](0)
//        });
//
//        token.approve(address(controller), 2100e18);
//
//        return controller.createMetavest(
//            metavestController.metavestType.RestrictedTokenAward,
//            grantee,
//            allocation,
//            milestones,
//            1e18,
//            address(paymentToken),
//            1 days,
//            0
//
//        );
//    }
//
//    function createDummyRestrictedTokenAwardFuture() internal returns (address) {
//        BaseAllocation.Allocation memory allocation = BaseAllocation.Allocation({
//            tokenContract: address(token),
//            tokenStreamTotal: 1000e18,
//            vestingCliffCredit: 100e18,
//            unlockingCliffCredit: 100e18,
//            vestingRate: 10e18,
//            vestingStartTime: uint48(block.timestamp+1000),
//            unlockRate: 10e18,
//            unlockStartTime: uint48(block.timestamp+1000)
//        });
//
//        BaseAllocation.Milestone[] memory milestones = new BaseAllocation.Milestone[](1);
//        milestones[0] = BaseAllocation.Milestone({
//            milestoneAward: 1000e18,
//            unlockOnCompletion: true,
//            complete: false,
//            conditionContracts: new address[](0)
//        });
//
//        token.approve(address(controller), 2100e18);
//
//        return controller.createMetavest(
//            metavestController.metavestType.RestrictedTokenAward,
//            grantee,
//            allocation,
//            milestones,
//            1e18,
//            address(paymentToken),
//            1 days,
//            0
//
//        );
//    }


    function testGetMetaVestType() public {
        address vestingAllocation = createDummyVestingAllocation();
//        address tokenOptionAllocation = createDummyTokenOptionAllocation();
//        address restrictedTokenAward = createDummyRestrictedTokenAward();

        assertEq(controller.getMetaVestType(vestingAllocation), 1);
//        assertEq(controller.getMetaVestType(tokenOptionAllocation), 2);
//        assertEq(controller.getMetaVestType(restrictedTokenAward), 3);
    }

//    function testWithdrawFromController() public {
//        uint256 amount = 100e18;
//        token.transfer(address(controller), amount);
//
//        uint256 initialBalance = token.balanceOf(authority);
//        controller.withdrawFromController(address(token));
//        uint256 finalBalance = token.balanceOf(authority);
//
//        assertEq(finalBalance - initialBalance, amount);
//        assertEq(token.balanceOf(address(controller)), 0);
//    }

    function test_RevertIf_CreateMetavestWithZeroAddress() public {
        BaseAllocation.Milestone[] memory milestones = new BaseAllocation.Milestone[](0);

        // Guardians to sign agreements and register on MetaVesTController
        bytes32 contractIdAlice = _proposeAndSignDeal(
            templateId,
            block.timestamp, // salt
            guardianSafe,
            alice, // = grantee
            alicePrivateKey,
            BaseAllocation.Allocation({
                tokenContract: address(0),
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

        // TPP to review agreements and on-chain parameters, then approve by granting our ZkCappedMinter permissions
        bytes32 minterRole = zkToken.MINTER_ROLE();
        vm.prank(zkTokenAdmin);
        zkToken.grantRole(minterRole, address(zkCappedMinter));

        vm.expectRevert(abi.encodeWithSelector(metavestController.MetaVesTController_ZeroAddress.selector));
        controller.createMetavest(contractIdAlice);
    }

    function testTerminateVestAndRecovers() public {
        address vestingAllocation = createDummyVestingAllocation();
        uint256 snapshot = zkToken.balanceOf(authority);
        VestingAllocation(vestingAllocation).confirmMilestone(0);
        vm.warp(block.timestamp + 50 seconds);
        vm.prank(authority);
        controller.terminateMetavestVesting(vestingAllocation);
        vm.startPrank(grantee);
        VestingAllocation(vestingAllocation).withdraw(VestingAllocation(vestingAllocation).getAmountWithdrawable());
        vm.stopPrank();
        assertEq(zkToken.balanceOf(authority), 0);
    }

    function testTerminateVestAndRecoverSlowUnlock() public {
        address vestingAllocation = createDummyVestingAllocationSlowUnlock();
        uint256 snapshot = zkToken.balanceOf(authority);
        VestingAllocation(vestingAllocation).confirmMilestone(0);
        vm.warp(block.timestamp + 25 seconds);
        vm.prank(authority);
        controller.terminateMetavestVesting(vestingAllocation);
        vm.startPrank(grantee);
        VestingAllocation(vestingAllocation).withdraw(VestingAllocation(vestingAllocation).getAmountWithdrawable());
        vm.warp(block.timestamp + 25 seconds);
        VestingAllocation(vestingAllocation).withdraw(VestingAllocation(vestingAllocation).getAmountWithdrawable());
        vm.stopPrank();
        assertEq(zkToken.balanceOf(vestingAllocation), 0);
    }

    function testTerminateRecoverAll() public {
        address vestingAllocation = createDummyVestingAllocationLarge();
        uint256 snapshot = zkToken.balanceOf(authority);
         vm.warp(block.timestamp + 25 seconds);
        vm.prank(authority);
        controller.terminateMetavestVesting(vestingAllocation);
        vm.startPrank(grantee);
        VestingAllocation(vestingAllocation).withdraw(VestingAllocation(vestingAllocation).getAmountWithdrawable());
        vm.stopPrank();
        assertEq(zkToken.balanceOf(authority), 0);
    }

        function testTerminateRecoverChunksBefore() public {
        address vestingAllocation = createDummyVestingAllocationLarge();
        uint256 snapshot = zkToken.balanceOf(authority);
        vm.warp(block.timestamp + 25 seconds);
        vm.startPrank(grantee);
        VestingAllocation(vestingAllocation).withdraw(VestingAllocation(vestingAllocation).getAmountWithdrawable());
        vm.stopPrank();
        vm.warp(block.timestamp + 25 seconds);
        vm.prank(authority);
        controller.terminateMetavestVesting(vestingAllocation);
        vm.startPrank(grantee);
        VestingAllocation(vestingAllocation).withdraw(VestingAllocation(vestingAllocation).getAmountWithdrawable());
        vm.stopPrank();
        assertEq(zkToken.balanceOf(authority), 0);
    }

//    function testConfirmingMilestoneRestrictedTokenAllocation() public {
//        address vestingAllocation = createDummyRestrictedTokenAward();
//        uint256 snapshot = token.balanceOf(authority);
//        VestingAllocation(vestingAllocation).confirmMilestone(0);
//        vm.warp(block.timestamp + 50 seconds);
//        vm.startPrank(grantee);
//        VestingAllocation(vestingAllocation).withdraw(VestingAllocation(vestingAllocation).getAmountWithdrawable());
//        vm.stopPrank();
//    }
//
//        function testConfirmingMilestoneTokenOption() public {
//        address vestingAllocation = createDummyTokenOptionAllocation();
//        uint256 snapshot = token.balanceOf(authority);
//        TokenOptionAllocation(vestingAllocation).confirmMilestone(0);
//        vm.warp(block.timestamp + 50 seconds);
//        vm.startPrank(grantee);
//        //exercise max available
//        ERC20Stable(paymentToken).approve(vestingAllocation, TokenOptionAllocation(vestingAllocation).getPaymentAmount(TokenOptionAllocation(vestingAllocation).getAmountExercisable()));
//        TokenOptionAllocation(vestingAllocation).exerciseTokenOption(TokenOptionAllocation(vestingAllocation).getAmountExercisable());
//        TokenOptionAllocation(vestingAllocation).withdraw(VestingAllocation(vestingAllocation).getAmountWithdrawable());
//        vm.stopPrank();
//    }

    function testUnlockMilestoneNotUnlocked() public {
        address vestingAllocation = createDummyVestingAllocationNoUnlock();
        uint256 snapshot = zkToken.balanceOf(authority);
        VestingAllocation(vestingAllocation).confirmMilestone(0);
        vm.warp(block.timestamp + 50 seconds);
        vm.startPrank(grantee);
        VestingAllocation(vestingAllocation).withdraw(VestingAllocation(vestingAllocation).getAmountWithdrawable());
        vm.warp(block.timestamp + 1050 seconds);
        VestingAllocation(vestingAllocation).withdraw(VestingAllocation(vestingAllocation).getAmountWithdrawable());
        vm.stopPrank();
    }

//    function testTerminateTokenOptionAndRecover() public {
//        address tokenOptionAllocation = createDummyTokenOptionAllocation();
//        uint256 snapshot = token.balanceOf(authority);
//        vm.warp(block.timestamp + 25 seconds);
//        vm.prank(grantee);
//        ERC20Stable(paymentToken).approve(tokenOptionAllocation, 350e18);
//        vm.prank(grantee);
//        TokenOptionAllocation(tokenOptionAllocation).exerciseTokenOption(350e18);
//        controller.terminateMetavestVesting(tokenOptionAllocation);
//        vm.startPrank(grantee);
//        vm.warp(block.timestamp + 1 days + 25 seconds);
//        assertEq(TokenOptionAllocation(tokenOptionAllocation).getAmountExercisable(), 0);
//        TokenOptionAllocation(tokenOptionAllocation).withdraw(TokenOptionAllocation(tokenOptionAllocation).getAmountWithdrawable());
//        vm.stopPrank();
//        assertEq(token.balanceOf(tokenOptionAllocation), 0);
//        vm.warp(block.timestamp + 365 days);
//        vm.prank(authority);
//        TokenOptionAllocation(tokenOptionAllocation).recoverForfeitTokens();
//    }

//    function testTerminateEarlyTokenOptionAndRecover() public {
//        address tokenOptionAllocation = createDummyTokenOptionAllocation();
//        uint256 snapshot = token.balanceOf(authority);
//        vm.warp(block.timestamp + 5 seconds);
//       // vm.prank(grantee);
//       /* ERC20Stable(paymentToken).approve(tokenOptionAllocation, 350e18);
//        vm.prank(grantee);
//        TokenOptionAllocation(tokenOptionAllocation).exerciseTokenOption(350e18);*/
//        controller.terminateMetavestVesting(tokenOptionAllocation);
//        vm.warp(block.timestamp + 365 days);
//        vm.prank(authority);
//        TokenOptionAllocation(tokenOptionAllocation).recoverForfeitTokens();
//    }


//    function testTerminateRestrictedTokenAwardAndRecover() public {
//        address restrictedTokenAward = createDummyRestrictedTokenAward();
//        uint256 snapshot = token.balanceOf(authority);
//        vm.warp(block.timestamp + 25 seconds);
//        controller.terminateMetavestVesting(restrictedTokenAward);
//        vm.startPrank(grantee);
//        RestrictedTokenAward(restrictedTokenAward).withdraw(RestrictedTokenAward(restrictedTokenAward).getAmountWithdrawable());
//        vm.stopPrank();
//        uint256 amt = RestrictedTokenAward(restrictedTokenAward).getAmountRepurchasable();
//        uint256 payamt = RestrictedTokenAward(restrictedTokenAward).getPaymentAmount(amt);
//        vm.warp(block.timestamp + 20 days);
//        paymentToken.approve(address(restrictedTokenAward), payamt);
//        RestrictedTokenAward(restrictedTokenAward).repurchaseTokens(amt);
//
//        vm.startPrank(grantee);
//        RestrictedTokenAward(restrictedTokenAward).claimRepurchasedTokens();
//        assertEq(token.balanceOf(restrictedTokenAward), 0);
//        assertEq(paymentToken.balanceOf(restrictedTokenAward), 0);
//    }

//    function testChangeVestingAndUnlockingRate() public {
//        address restrictedTokenAward = createDummyRestrictedTokenAward();
//        uint256 snapshot = token.balanceOf(authority);
//        vm.warp(block.timestamp + 25 seconds);
//
//        bytes4 msgSig = bytes4(keccak256("updateMetavestUnlockRate(address,uint160)"));
//        bytes memory callData = abi.encodeWithSelector(msgSig, restrictedTokenAward, 50e18);
//
//        vm.prank(authority);
//        controller.proposeMetavestAmendment(restrictedTokenAward, msgSig, callData);
//
//        vm.prank(grantee);
//        controller.consentToMetavestAmendment(restrictedTokenAward, msgSig, true);
//
//        vm.prank(authority);
//        controller.updateMetavestUnlockRate(restrictedTokenAward, 50e18);
//
//        msgSig = bytes4(keccak256("updateMetavestVestingRate(address,uint160)"));
//        callData = abi.encodeWithSelector(msgSig, restrictedTokenAward, 50e18);
//
//        vm.prank(authority);
//        controller.proposeMetavestAmendment(restrictedTokenAward, msgSig, callData);
//
//        vm.prank(grantee);
//        controller.consentToMetavestAmendment(restrictedTokenAward, msgSig, true);
//
//        vm.prank(authority);
//        controller.updateMetavestVestingRate(restrictedTokenAward, 50e18);
//
//        vm.startPrank(grantee);
//        RestrictedTokenAward(restrictedTokenAward).withdraw(RestrictedTokenAward(restrictedTokenAward).getAmountWithdrawable());
//        vm.stopPrank();
//
//    }

//    function testZeroReclaim() public {
//        address restrictedTokenAward = createDummyRestrictedTokenAward();
//        vm.warp(block.timestamp + 15 seconds);
//        vm.startPrank(grantee);
//        RestrictedTokenAward(restrictedTokenAward).withdraw(RestrictedTokenAward(restrictedTokenAward).getAmountWithdrawable());
//        vm.stopPrank();
//        //create call data to propose setting vesting to 0
//        bytes4 msgSig = bytes4(keccak256("updateMetavestVestingRate(address,uint160)"));
//        bytes memory callData = abi.encodeWithSelector(msgSig, restrictedTokenAward, 0);
//
//        vm.prank(authority);
//        controller.proposeMetavestAmendment(restrictedTokenAward, msgSig, callData);
//
//        vm.prank(grantee);
//        controller.consentToMetavestAmendment(restrictedTokenAward, msgSig, true);
//
//        vm.prank(authority);
//        controller.updateMetavestVestingRate(restrictedTokenAward, 0);
//
//        vm.startPrank(authority);
//        controller.terminateMetavestVesting(restrictedTokenAward);
//        vm.warp(block.timestamp + 155 days);
//        uint256 amt = RestrictedTokenAward(restrictedTokenAward).getAmountRepurchasable();
//        uint256 payamt = RestrictedTokenAward(restrictedTokenAward).getPaymentAmount(amt);
//        paymentToken.approve(address(restrictedTokenAward), payamt);
//        RestrictedTokenAward(restrictedTokenAward).repurchaseTokens(amt);
//                 vm.stopPrank();
//        vm.prank(grantee);
//        RestrictedTokenAward(restrictedTokenAward).claimRepurchasedTokens();
//        console.log(token.balanceOf(restrictedTokenAward));
//    }

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

//    function testLargeReducOption() public {
//        address restrictedTokenAward = createDummyTokenOptionAllocation();
//        vm.warp(block.timestamp + 5 seconds);
//        vm.startPrank(grantee);
//        //approve amount to exercise by getting amount to exercise and price
//        ERC20Stable(paymentToken).approve(restrictedTokenAward, TokenOptionAllocation(restrictedTokenAward).getPaymentAmount(TokenOptionAllocation(restrictedTokenAward).getAmountExercisable()));
//        TokenOptionAllocation(restrictedTokenAward).exerciseTokenOption(TokenOptionAllocation(restrictedTokenAward).getAmountExercisable());
//        RestrictedTokenAward(restrictedTokenAward).withdraw(RestrictedTokenAward(restrictedTokenAward).getAmountWithdrawable());
//        vm.stopPrank();
//        //create call data to propose setting vesting to 0
//        bytes4 msgSig = bytes4(keccak256("updateMetavestVestingRate(address,uint160)"));
//        bytes memory callData = abi.encodeWithSelector(msgSig, restrictedTokenAward, 10e18);
//
//        vm.prank(authority);
//        controller.proposeMetavestAmendment(restrictedTokenAward, msgSig, callData);
//
//        vm.prank(grantee);
//        controller.consentToMetavestAmendment(restrictedTokenAward, msgSig, true);
//
//        vm.prank(authority);
//        controller.updateMetavestVestingRate(restrictedTokenAward, 10e18);
//        vm.warp(block.timestamp + 5 seconds);
//        vm.startPrank(authority);
//        controller.terminateMetavestVesting(restrictedTokenAward);
//        vm.stopPrank();
//        vm.warp(block.timestamp + 155 seconds);
//        vm.startPrank(grantee);
//         ERC20Stable(paymentToken).approve(restrictedTokenAward, TokenOptionAllocation(restrictedTokenAward).getPaymentAmount(TokenOptionAllocation(restrictedTokenAward).getAmountExercisable()));
//        TokenOptionAllocation(restrictedTokenAward).exerciseTokenOption(TokenOptionAllocation(restrictedTokenAward).getAmountExercisable());
//        RestrictedTokenAward(restrictedTokenAward).withdraw(RestrictedTokenAward(restrictedTokenAward).getAmountWithdrawable());
//        vm.stopPrank();
//        console.log(token.balanceOf(restrictedTokenAward));
//    }



//    function testReclaim() public {
//        address restrictedTokenAward = createDummyRestrictedTokenAward();
//        vm.warp(block.timestamp + 15 seconds);
//        vm.startPrank(grantee);
//        RestrictedTokenAward(restrictedTokenAward).withdraw(RestrictedTokenAward(restrictedTokenAward).getAmountWithdrawable());
//        vm.stopPrank();
//
//        vm.startPrank(authority);
//        controller.terminateMetavestVesting(restrictedTokenAward);
//        vm.warp(block.timestamp + 155 days);
//        uint256 amt = RestrictedTokenAward(restrictedTokenAward).getAmountRepurchasable();
//        uint256 payamt = RestrictedTokenAward(restrictedTokenAward).getPaymentAmount(amt);
//        paymentToken.approve(address(restrictedTokenAward), payamt);
//        RestrictedTokenAward(restrictedTokenAward).repurchaseTokens(amt);
//         vm.stopPrank();
//        vm.prank(grantee);
//        RestrictedTokenAward(restrictedTokenAward).claimRepurchasedTokens();
//        console.log(token.balanceOf(restrictedTokenAward));
//    }



//    function test_RevertIf_UpdateExercisePriceForVesting() public {
//        address vestingAllocation = createDummyVestingAllocation();
//        controller.updateExerciseOrRepurchasePrice(vestingAllocation, 2e18);
//    }

//    function test_RevertIf_RepurchaseTokensAfterExpiry() public {
//        address restrictedTokenAward = createDummyRestrictedTokenAward();
//
//        // Fast forward time to after the short stop date
//        vm.warp(block.timestamp + 366 days);
//
//        RestrictedTokenAward(restrictedTokenAward).repurchaseTokens(500e18);
//    }

//    function test_RevertIf_RepurchaseTokensInsufficientAllowance() public {
//        address restrictedTokenAward = createDummyRestrictedTokenAward();
//
//        // Not approving any tokens
//       RestrictedTokenAward(restrictedTokenAward).repurchaseTokens(500e18);
//    }

    function test_RevertIf_InitiateAuthorityUpdateNonAuthority() public {
        vm.prank(address(0x1234));
        vm.expectRevert(abi.encodeWithSelector(metavestController.MetaVesTController_OnlyAuthority.selector));
        controller.initiateAuthorityUpdate(address(0x5678));
    }

    function test_RevertIf_AcceptAuthorityRoleNonPendingAuthority() public {
        vm.prank(authority);
        controller.initiateAuthorityUpdate(address(0x5678));

        vm.prank(address(0x1234));
        vm.expectRevert(abi.encodeWithSelector(metavestController.MetaVesTController_OnlyPendingAuthority.selector));
        controller.acceptAuthorityRole();
    }

    function test_RevertIf_InitiateDaoUpdateNonDao() public {
        vm.prank(address(0x1234));
        vm.expectRevert(abi.encodeWithSelector(metavestController.MetaVesTController_OnlyDAO.selector));
        controller.initiateDaoUpdate(address(0x5678));
    }

    function test_RevertIf_AcceptDaoRoleNonPendingDao() public {
        vm.prank(dao);
        controller.initiateDaoUpdate(address(0x5678));

        vm.prank(address(0x1234));
        vm.expectRevert(abi.encodeWithSelector(metavestController.MetaVesTController_OnlyPendingDao.selector));
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
        vm.expectRevert(abi.encodeWithSelector(metavestController.MetaVesTController_OnlyDAO.selector));
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
        bytes4 functionSig = bytes4(keccak256("createMetavest(bytes32)"));
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
            abi.encodeWithSelector(metavestController.MetaVesTController_ConditionNotSatisfied.selector, condition) // Expected revert
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
        vm.expectRevert(abi.encodeWithSelector(metavestController.MetaVestController_DuplicateCondition.selector));
        controller.updateFunctionCondition(address(condition), functionSig);
    }

    function test_RevertIf_ExceedCap() public {
        // Add a large grant that exceeds the cap
        bytes32 contractIdChad = _proposeAndSignDeal(
            templateId,
            block.timestamp, // salt
            guardianSafe,
            chad,
            chadPrivateKey,
            BaseAllocation.Allocation({
                tokenContract: address(zkToken),
                tokenStreamTotal: 2001 ether,
                vestingCliffCredit: 2001 ether,
                unlockingCliffCredit: 2001 ether,
                vestingRate: 0,
                vestingStartTime: 0,
                unlockRate: 0,
                unlockStartTime: 0
            }),
            new BaseAllocation.Milestone[](0),
            "Chad",
            cappedMinterExpirationTime // Same expiry as the minter so grantee can defer vesting contract creation as much as possible
        );
        VestingAllocation vestingAllocationChad = VestingAllocation(controller.createMetavest(contractIdChad));

        vm.prank(chad);
        vm.expectRevert(abi.encodeWithSelector(IZkCappedMinterV2.ZkCappedMinterV2__CapExceeded.selector, address(vestingAllocationChad), 2001 ether));
        vestingAllocationChad.withdraw(2001 ether);
    }

    function test_RevertIf_NotAuthority() public {
        // Non Guardian SAFE should not be able to accept agreement and create contract
        _proposeAndSignDeal(
            templateId,
            block.timestamp, // salt
            deployer, // Not authority
            alice,
            alicePrivateKey,
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
            "Alice",
            cappedMinterExpirationTime, // Same expiry as the minter so grantee can defer vesting contract creation as much as possible
            abi.encodeWithSelector(metavestController.MetaVesTController_OnlyAuthority.selector) // Expected revert
        );
    }

    function test_RevertIf_IncorrectAgreementSignature() public {
        // Register Alice with someone else's signature should fail
        _proposeAndSignDeal(
            templateId,
            block.timestamp, // salt
            guardianSafe,
            alice,
            bobPrivateKey, // Use someone else to sign
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
            "Alice",
            cappedMinterExpirationTime, // Same expiry as the minter so grantee can defer vesting contract creation as much as possible
            abi.encodeWithSelector(CyberAgreementRegistry.SignatureVerificationFailed.selector) // Expected revert
        );
    }

    function test_DelegateSignature() public {
        // Alice to delegate to Bob
        vm.prank(alice);
        registry.setDelegation(bob, block.timestamp + 60);
        assertTrue(registry.isValidDelegate(alice, bob), "Bob should be Alice's delegate");

        // Bob should be able to sign for Alice now
        bytes32 contractId = _proposeAndSignDeal(
            templateId,
            block.timestamp, // salt
            guardianSafe,
            alice,
            bobPrivateKey, // Use Bob to sign
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
            "Alice",
            cappedMinterExpirationTime // Same expiry as the minter so grantee can defer vesting contract creation as much as possible
        );
        metavestController.DealData memory deal = controller.getDeal(contractId);
        assertEq(deal.grantee, alice, "Alice should be the grantee");

        // Wait until expiry
        skip(61);

        // Bob should no longer be able to sign for Alice
        assertFalse(registry.isValidDelegate(alice, bob), "Bob should no longer be Alice's delegate");
        _proposeAndSignDeal(
            templateId,
            block.timestamp, // salt
            guardianSafe,
            alice,
            bobPrivateKey, // Use Bob to sign
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
            "Alice",
            cappedMinterExpirationTime, // Same expiry as the minter so grantee can defer vesting contract creation as much as possible
            abi.encodeWithSelector(CyberAgreementRegistry.SignatureVerificationFailed.selector) // Expected revert
        );
    }
}
