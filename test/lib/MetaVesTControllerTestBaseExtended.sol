// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.20;

import {console2} from "forge-std/console2.sol";
import {Initializable} from "openzeppelin-contracts-upgradeable/proxy/utils/Initializable.sol";
import "../../src/RestrictedTokenAllocation.sol";
import "../../src/TokenOptionAllocation.sol";
import "../../src/VestingAllocation.sol";
import "../../src/interfaces/IAllocationFactory.sol";
import "./MetaVesTControllerTestBase.sol";
import "../mocks/MockCondition.sol";
import {ERC1967ProxyLib} from "./ERC1967ProxyLib.sol";

contract MetaVesTControllerTestBaseExtended is MetaVesTControllerTestBase {
    using ERC1967ProxyLib for address;
    using MetaVestDealLib for MetaVestDeal;

    address authority = guardianSafe;
    address dao = guardianSafe;
    address grantee = alice;
    address transferee = address(0x101);

    // Parameters
    uint48 metavestExpiry = uint48(block.timestamp + 1600); // MetaVest expires 1600 seconds later

    function setUp() public override {
        MetaVesTControllerTestBase.setUp();

        vm.startPrank(deployer);

        // Deploy MetaVesT controller
        controller = metavestController(metavestControllerFactory.deployMetavestController(
            salt,
            guardianSafe,
            guardianSafe
        ));

        vm.stopPrank();

        // Prepare funds (vesting token)
        vestingToken.mint(
            address(guardianSafe),
            9999 ether
        );
        vm.prank(address(guardianSafe));
        vestingToken.approve(address(controller), 9999 ether);

        // Prepare funds (payment token)
        paymentToken.mint(
            address(guardianSafe),
            9999 ether
        );
        vm.prank(address(guardianSafe));
        paymentToken.approve(address(controller), 9999 ether);

        vm.startPrank(guardianSafe);
        controller.createSet("testSet");
        vm.stopPrank();

        // Guardian SAFE to delegate signing to an EOA
        vm.prank(guardianSafe);
        registry.setDelegation(delegate, block.timestamp + 365 days * 3); // This is a hack. One should not delegate signing for this long
        assertTrue(registry.isValidDelegate(guardianSafe, delegate), "delegate should be Guardian SAFE's delegate");
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
            delegatePrivateKey,
            MetaVestDealLib.draft().setVesting(
                alice, // = grantee
                BaseAllocation.Allocation({
                    tokenContract: address(vestingToken),
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

        return _granteeSignDeal(
            contractIdAlice,
            alice, // grantee
            alice, // recipient
            alicePrivateKey,
            "Alice",
            expectRevertData
        );
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
            delegatePrivateKey,
            MetaVestDealLib.draft().setVesting(
                alice, // = grantee
                BaseAllocation.Allocation({
                    tokenContract: address(vestingToken),
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

        return _granteeSignDeal(
            contractIdAlice,
            alice, // grantee
            alice, // recipient
            alicePrivateKey,
            "Alice"
        );
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
            delegatePrivateKey,
            MetaVestDealLib.draft().setVesting(
                alice, // = grantee
                BaseAllocation.Allocation({
                    tokenContract: address(vestingToken),
                    tokenStreamTotal: 1000 ether,
                    vestingCliffCredit: 100 ether,
                    unlockingCliffCredit: 100 ether,
                    vestingRate: 10 ether,
                    vestingStartTime: uint48(block.timestamp),
                    unlockRate: 5 ether,
                    unlockStartTime: uint48(block.timestamp)
                }),
                milestones
            ),
            "Alice",
            metavestExpiry
        );

        return _granteeSignDeal(
            contractIdAlice,
            alice, // grantee
            alice, // recipient
            alicePrivateKey,
            "Alice"
        );
    }

    // Helper functions to create dummy allocations for testing
    function createDummyVestingAllocationLarge() internal returns (address) {
        BaseAllocation.Milestone[] memory milestones = new BaseAllocation.Milestone[](0);

        // Guardians to sign agreements and register on MetaVesTController
        bytes32 contractIdAlice = _proposeAndSignDeal(
            templateId,
            block.timestamp, // salt
            delegatePrivateKey,
            MetaVestDealLib.draft().setVesting(
                alice, // = grantee
                BaseAllocation.Allocation({
                    tokenContract: address(vestingToken),
                    tokenStreamTotal: 1000 ether,
                    vestingCliffCredit: 0 ether,
                    unlockingCliffCredit: 0 ether,
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

        return _granteeSignDeal(
            contractIdAlice,
            alice, // grantee
            alice, // recipient
            alicePrivateKey,
            "Alice"
        );
    }

    // Helper functions to create dummy allocations for testing
    function createDummyVestingAllocationLargeFuture() internal returns (address) {
        BaseAllocation.Milestone[] memory milestones = new BaseAllocation.Milestone[](0);

        // Guardians to sign agreements and register on MetaVesTController
        bytes32 contractIdAlice = _proposeAndSignDeal(
            templateId,
            block.timestamp, // salt
            delegatePrivateKey,
            MetaVestDealLib.draft().setVesting(
                alice, // = grantee
                BaseAllocation.Allocation({
                    tokenContract: address(vestingToken),
                    tokenStreamTotal: 1000 ether,
                    vestingCliffCredit: 0 ether,
                    unlockingCliffCredit: 0 ether,
                    vestingRate: 10 ether,
                    vestingStartTime: uint48(block.timestamp + 2000),
                    unlockRate: 10 ether,
                    unlockStartTime: uint48(block.timestamp + 2000)
                }),
                milestones
            ),
            "Alice",
            metavestExpiry
        );

        return _granteeSignDeal(
            contractIdAlice,
            alice, // grantee
            alice, // recipient
            alicePrivateKey,
            "Alice"
        );
    }

    function createDummyTokenOptionAllocation() internal returns (address) {
        return createDummyTokenOptionAllocation(""); // Expect no reverts
    }

    function createDummyTokenOptionAllocation(bytes memory expectRevertData) internal returns (address) {
        BaseAllocation.Milestone[] memory milestones = new BaseAllocation.Milestone[](1);
        milestones[0] = BaseAllocation.Milestone({
            milestoneAward: 1000e18,
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
                5e17, // exercisePrice
                1 days, // shortStopDuration
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

        return _granteeSignDeal(
            contractIdAlice,
            alice, // grantee
            alice, // recipient
            alicePrivateKey,
            "Alice"
        );
    }

    function createDummyRestrictedTokenAward() internal returns (address) {
        return createDummyRestrictedTokenAward(alice, "");
    }

    function createDummyRestrictedTokenAward(address recipient) internal returns (address) {
        return createDummyRestrictedTokenAward(recipient, "");
    }

    function createDummyRestrictedTokenAward(address recipient, bytes memory expectRevertData) internal returns (address) {
        BaseAllocation.Milestone[] memory milestones = new BaseAllocation.Milestone[](1);
        milestones[0] = BaseAllocation.Milestone({
            milestoneAward: 1000e18,
            unlockOnCompletion: true,
            complete: false,
            conditionContracts: new address[](0)
        });

        bytes32 contractIdAlice = _proposeAndSignDeal(
            templateId,
            block.timestamp, // salt
            delegatePrivateKey,
            MetaVestDealLib.draft().setRestrictedToken(
                alice,
                address(paymentToken),
                1e18, // exercisePrice
                1 days, // shortStopDuration
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

        return _granteeSignDeal(
            contractIdAlice,
            alice, // grantee
            recipient,
            alicePrivateKey,
            "Alice"
        );
    }

    function createDummyRestrictedTokenAwardFuture() internal returns (address) {
        BaseAllocation.Milestone[] memory milestones = new BaseAllocation.Milestone[](1);
        milestones[0] = BaseAllocation.Milestone({
            milestoneAward: 1000e18,
            unlockOnCompletion: true,
            complete: false,
            conditionContracts: new address[](0)
        });

        bytes32 contractIdAlice = _proposeAndSignDeal(
            templateId,
            block.timestamp, // salt
            delegatePrivateKey,
            MetaVestDealLib.draft().setRestrictedToken(
                alice,
                address(paymentToken),
                1e18, // exercisePrice
                1 days, // shortStopDuration
                BaseAllocation.Allocation({
                    tokenContract: address(vestingToken),
                    tokenStreamTotal: 1000e18,
                    vestingCliffCredit: 100e18,
                    unlockingCliffCredit: 100e18,
                    vestingRate: 10e18,
                    vestingStartTime: uint48(block.timestamp + 1000),
                    unlockRate: 10e18,
                    unlockStartTime: uint48(block.timestamp + 1000)
                }),
                milestones
            ),
            "Alice",
            metavestExpiry,
            ""
        );

        return _granteeSignDeal(
            contractIdAlice,
            alice, // grantee
            alice, // recipient
            alicePrivateKey,
            "Alice"
        );
    }
}
