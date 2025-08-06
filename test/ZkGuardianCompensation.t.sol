// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.20;

import "../src/MetaVesTController.sol";
import "../src/VestingAllocationFactory.sol";
import "../src/interfaces/zk-governance/IZkCappedMinterV2.sol";
import "../src/interfaces/zk-governance/IZkTokenV1.sol";
import "./lib/MetaVesTControllerTestBase.sol";
import {CyberAgreementRegistry} from "cybercorps-contracts/src/CyberAgreementRegistry.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

// Test by forge test --zksync --via-ir
contract ZkGuardianCompensationTest is MetaVesTControllerTestBase {
    // Parameters
    bytes32 templateId = bytes32(uint256(123));
    bytes32 salt = keccak256("MetaLexZkSyncTest");
    uint256 cap = 1e6 ether; // 1M ZK
    uint48 cappedMinterStartTime = 1756684800; // 2025/9/1 UTC
    uint48 cappedMinterExpirationTime = cappedMinterStartTime + 365 days * 2; // Expect to vest over an year with a margin of an extra year for withdrawal

    function setUp() public {
        // Assume deployment 7 days before the vesting starts
        vm.warp(cappedMinterStartTime - 7 days);

        vm.startPrank(deployer);

        // Deploy CyberAgreementRegistry and prepare templates

        // TODO who should be the owner of auth?
        auth = new BorgAuth{salt: salt}(deployer);
        registry = CyberAgreementRegistry(address(new ERC1967Proxy{salt: salt}(
            address(new CyberAgreementRegistry{salt: salt}()),
            abi.encodeWithSelector(
                CyberAgreementRegistry.initialize.selector,
                address(auth)
            )
        )));

        globalFields = new string[](13);
        globalFields[0] = "governingJurisdiction"; // TODO do we need this?
        globalFields[1] = "disputeResolution"; // TODO do we need this?
        globalFields[2] = "metavestType";
        globalFields[3] = "grantee";
        globalFields[4] = "recipient";
        globalFields[5] = "tokenContract";
        globalFields[6] = "tokenStreamTotal";
        globalFields[7] = "vestingCliffCredit";
        globalFields[8] = "unlockingCliffCredit";
        globalFields[9] = "vestingRate";
        globalFields[10] = "vestingStartTime";
        globalFields[11] = "unlockRate";
        globalFields[12] = "unlockStartTime";
        partyFields = new string[](5);
        partyFields[0] = "name";
        partyFields[1] = "evmAddress";
        partyFields[2] = "contactDetails"; // TODO do we need this?
        partyFields[3] = "granteeType"; // TODO do we need this?
        partyFields[4] = "granteeJurisdiction"; // TODO do we need this?

        registry.createTemplate(
            templateId,
            "ZkSyncGuardianCompensation",
            agreementUri,
            globalFields,
            partyFields
        );

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

    // TODO test
//    function test_AdminToolingCompensation() public {
//        (bytes32 contractIdAlice, bytes32 contractIdBob) = _guardiansSignAndTppPass();
//
//        // Vesting starts and a month has passed
//        vm.warp(cappedMinterStartTime + 30 days);
//
//        // Alice creates vesting contract and start withdrawal
//        VestingAllocation vestingAllocationAlice = VestingAllocation(controller.createMetavest(contractIdAlice));
//        _granteeWithdrawAndAsserts(vestingAllocationAlice, uint256(50e3 ether) + uint160(50e3 ether) / 365 days * 30 days, "Alice cliff + first month");
//
//        // Second month
//        skip(30 days);
//
//        // Add new grantee for admin/tooling compensation
//        bytes32 contractIdChad = _proposeAndSignDeal(
//            templateId,
//            guardianSafe,
//            chad,
//            chadPrivateKey,
//            BaseAllocation.Allocation({
//                tokenContract: address(zkToken),
//                // 10k ZK total in one cliff
//                tokenStreamTotal: 10e3 ether,
//                vestingCliffCredit: 10e3 ether,
//                unlockingCliffCredit: 10e3 ether,
//                vestingRate: 0,
//                vestingStartTime: 0,
//                unlockRate: 0,
//                unlockStartTime: 0
//            }),
//            new BaseAllocation.Milestone[](0)
//        );
//        VestingAllocation vestingAllocationChad = VestingAllocation(controller.createMetavest(contractIdChad));
//        _granteeWithdrawAndAsserts(vestingAllocationChad, 10e3 ether, "Chad cliff");
//    }
//
//    function test_RevertIf_NotAuthority() public {
//        // Non Guardian SAFE should not be able to accept agreement and create contract
//        _proposeAndSignDeal(
//            templateId,
//            deployer, // Not authority
//            alice,
//            alicePrivateKey,
//            BaseAllocation.Allocation({
//                tokenContract: address(zkToken),
//                tokenStreamTotal: 1000e18,
//                vestingCliffCredit: 100e18,
//                unlockingCliffCredit: 100e18,
//                vestingRate: 10e18,
//                vestingStartTime: zkCappedMinter.START_TIME(), // start along with capped minter
//                unlockRate: 10e18,
//                unlockStartTime: zkCappedMinter.START_TIME() // start along with capped minter
//            }),
//            new BaseAllocation.Milestone[](0),
//            abi.encodeWithSelector(metavestController.MetaVesTController_OnlyAuthority.selector) // Expected revert
//        );
//    }
//
//    function test_RevertIf_IncorrectAgreementSignature() public {
//        // Register Alice with someone else's signature should fail
//        _proposeAndSignDeal(
//            templateId,
//            guardianSafe,
//            alice,
//            bobPrivateKey, // Use someone else to sign
//            BaseAllocation.Allocation({
//                tokenContract: address(zkToken),
//                tokenStreamTotal: 1000e18,
//                vestingCliffCredit: 100e18,
//                unlockingCliffCredit: 100e18,
//                vestingRate: 10e18,
//                vestingStartTime: zkCappedMinter.START_TIME(), // start along with capped minter
//                unlockRate: 10e18,
//                unlockStartTime: zkCappedMinter.START_TIME() // start along with capped minter
//            }),
//            new BaseAllocation.Milestone[](0),
//            abi.encodeWithSelector(metavestController.MetaVesTController_SignatureVerificationFailed.selector) // Expected revert
//        );
//    }
//
//    function test_DelegateSignature() public {
//        // Alice to delegate to Bob
//        vm.prank(alice);
//        controller.setDelegation(bob, block.timestamp + 60);
//        assertTrue(controller.isValidDelegate(alice, bob), "Bob should be Alice's delegate");
//
//        // Bob should be able to sign for Alice now
//        bytes32 contractId = _proposeAndSignDeal(
//            templateId,
//            guardianSafe,
//            alice,
//            bobPrivateKey, // Use Bob to sign
//            BaseAllocation.Allocation({
//                tokenContract: address(zkToken),
//                tokenStreamTotal: 1000e18,
//                vestingCliffCredit: 100e18,
//                unlockingCliffCredit: 100e18,
//                vestingRate: 10e18,
//                vestingStartTime: zkCappedMinter.START_TIME(), // start along with capped minter
//                unlockRate: 10e18,
//                unlockStartTime: zkCappedMinter.START_TIME() // start along with capped minter
//            }),
//            new BaseAllocation.Milestone[](0)
//        );
//        metavestController.AgreementData memory agreement = controller.getAgreement(contractId);
//        assertEq(agreement.signedData.grantee, alice, "Alice should be the grantee");
//
//        // Wait until expiry
//        skip(61);
//
//        // Bob should no longer be able to sign for Alice
//        assertFalse(controller.isValidDelegate(alice, bob), "Bob should no longer be Alice's delegate");
//        _proposeAndSignDeal(
//            templateId,
//            guardianSafe,
//            alice,
//            bobPrivateKey, // Use Bob to sign
//            BaseAllocation.Allocation({
//                tokenContract: address(zkToken),
//                tokenStreamTotal: 1000e18,
//                vestingCliffCredit: 100e18,
//                unlockingCliffCredit: 100e18,
//                vestingRate: 10e18,
//                vestingStartTime: zkCappedMinter.START_TIME(), // start along with capped minter
//                unlockRate: 10e18,
//                unlockStartTime: zkCappedMinter.START_TIME() // start along with capped minter
//            }),
//            new BaseAllocation.Milestone[](0),
//            abi.encodeWithSelector(metavestController.MetaVesTController_SignatureVerificationFailed.selector) // Expected revert
//        );
//    }

    function _guardiansSignAndTppPass() internal returns(bytes32, bytes32) {
        // Guardians to sign agreements and register on MetaVesTController
        bytes32 contractIdAlice;
        bytes32 contractIdBob;

        {
            string[] memory globalValues = new string[](13);
            globalValues[0] = "test governingJurisdiction"; // TODO do we need this?
            globalValues[1] = "test disputeResolution"; // TODO do we need this?
            globalValues[2] = "0"; // metavestType: Vesting
            globalValues[3] = vm.toString(alice); // grantee
            globalValues[4] = vm.toString(alice); // recipient
            globalValues[5] = vm.toString(address(zkToken)); // tokenContract
            globalValues[6] = vm.toString(uint256(100e3)); //tokenStreamTotal
            globalValues[7] = vm.toString(uint256(50e3)); // vestingCliffCredit
            globalValues[8] = vm.toString(uint256(50e3)); // unlockingCliffCredit
            globalValues[9] = vm.toString(uint160(50e3 ether) / 365 days); // vestingRate
            globalValues[10] = vm.toString(zkCappedMinter.START_TIME()); // vestingStartTime
            globalValues[11] = vm.toString(uint160(50e3 ether) / 365 days); // unlockRate
            globalValues[12] = vm.toString(zkCappedMinter.START_TIME()); // unlockStartTime

            string[] memory partyValues = new string[](5);
            partyValues[0] = "Alice";
            partyValues[1] = vm.toString(alice); // evmAddress
            partyValues[2] = "alice@email.com"; // TODO do we need this?
            partyValues[3] = "individual"; // TODO do we need this?
            partyValues[4] = "test granteeJurisdiction"; // TODO do we need this?

            contractIdAlice = _proposeAndSignDeal(
                templateId,
                guardianSafe,
                alice,
                alicePrivateKey,
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
                globalValues,
                partyValues,
                bytes32(0), // no secrets
                block.timestamp + 3600
            );
        }

        {
            string[] memory globalValues = new string[](13);
            globalValues[0] = "test governingJurisdiction"; // TODO do we need this?
            globalValues[1] = "test disputeResolution"; // TODO do we need this?
            globalValues[2] = "0"; // metavestType: Vesting
            globalValues[3] = vm.toString(bob); // grantee
            globalValues[4] = vm.toString(bob); // recipient
            globalValues[5] = vm.toString(address(zkToken)); // tokenContract
            globalValues[6] = vm.toString(uint256(80e3)); //tokenStreamTotal
            globalValues[7] = vm.toString(uint256(40e3)); // vestingCliffCredit
            globalValues[8] = vm.toString(uint256(40e3)); // unlockingCliffCredit
            globalValues[9] = vm.toString(uint160(40e3 ether) / 365 days); // vestingRate
            globalValues[10] = vm.toString(zkCappedMinter.START_TIME()); // vestingStartTime
            globalValues[11] = vm.toString(uint160(40e3 ether) / 365 days); // unlockRate
            globalValues[12] = vm.toString(zkCappedMinter.START_TIME()); // unlockStartTime

            string[] memory partyValues = new string[](5);
            partyValues[0] = "Bob";
            partyValues[1] = vm.toString(bob); // evmAddress
            partyValues[2] = "bob@email.com"; // TODO do we need this?
            partyValues[3] = "individual"; // TODO do we need this?
            partyValues[4] = "test granteeJurisdiction"; // TODO do we need this?

            contractIdBob = _proposeAndSignDeal(
                templateId,
                guardianSafe,
                bob,
                bobPrivateKey,
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
                globalValues,
                partyValues,
                bytes32(0), // no secrets
                block.timestamp + 3600
            );
        }

        // TPP to review agreements and on-chain parameters, then approve by granting our ZkCappedMinter permissions

        bytes32 minterRole = zkToken.MINTER_ROLE();
        vm.prank(zkTokenAdmin);
        zkToken.grantRole(minterRole, address(zkCappedMinter));

        return (contractIdAlice, contractIdBob);
    }
}
