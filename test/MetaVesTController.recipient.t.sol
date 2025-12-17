// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.20;

import {BaseAllocation} from "../src/BaseAllocation.sol";
import {MetaVesTFactory} from "../src/MetaVesTFactory.sol";
import {RestrictedTokenAward} from "../src/RestrictedTokenAllocation.sol";
import {RestrictedTokenFactory} from "../src/RestrictedTokenFactory.sol";
import {Test} from "forge-std/Test.sol";
import {TokenOptionFactory} from "../src/TokenOptionFactory.sol";
import {VestingAllocationFactory} from "../src/VestingAllocationFactory.sol";
import {metavestController} from "../src/MetaVesTController.sol";
import {MockERC20} from "./mocks/MockERC20.sol";

contract MetaVestControllerRecipientTest is Test {
    string saltStr = "MetaVestControllerRecipientTest";
    bytes32 salt = keccak256(bytes(saltStr));

    address deployer = makeAddr("deployer");
    address authority = makeAddr("authority");
    address alice = makeAddr("alice");
    address bob = makeAddr("bob");
    address chad = makeAddr("chad");

    MockERC20 vestingToken = new MockERC20("Vesting Token", "VEST", 6);
    MockERC20 paymentToken = new MockERC20("Payment Token", "PAY", 6);

    MetaVesTFactory controllerFactory;
    metavestController controller;

    function setUp() public {
        vm.startPrank(deployer);

        controllerFactory = new MetaVesTFactory{salt: salt}();

        controller = metavestController(controllerFactory.deployMetavestAndController(
            authority,
            authority,
            address(0),
            address(new VestingAllocationFactory{salt: salt}()),
            address(new TokenOptionFactory{salt: salt}()),
            address(new RestrictedTokenFactory{salt: salt}())
        ));

        // Prepare funds
        vestingToken = new MockERC20("Vesting Token", "VEST", 6);
        paymentToken = new MockERC20("Payment Token", "PAY", 6);

        vestingToken.mint(authority, 10000e6);

        vm.stopPrank();

        vm.startPrank(authority);
        vestingToken.approve(address(controller), 10000e6);
        vm.stopPrank();
    }

    function test_RecipientOverrideUpdatedOnConstruct() public {
        bytes32 salt = keccak256(bytes("test_RecipientOverrideUpdatedOnConstruct"));

        vm.expectEmit(true, true, true, true);
        emit metavestController.MetaVesTController_RecipientOverrideUpdated(chad);
        metavestController testController = metavestController(controllerFactory.deployMetavestAndController(
            authority,
            authority,
            chad,
            address(new VestingAllocationFactory{salt: salt}()),
            address(new TokenOptionFactory{salt: salt}()),
            address(new RestrictedTokenFactory{salt: salt}())
        ));
        assertEq(testController.recipientOverride(), chad, "unexpected recipientOverride");
    }

    function test_updateRecipientOverride() public {
        vm.prank(authority);
        vm.expectEmit(true, true, true, true, address(controller));
        emit metavestController.MetaVesTController_RecipientOverrideUpdated(chad);
        controller.updateRecipientOverride(chad);
        assertEq(controller.recipientOverride(), chad, "unexpected recipientOverride");
    }

    function test_RevertIf_updateRecipientOverrideNotAuthority() public {
        vm.expectRevert(metavestController.MetaVesTController_OnlyAuthority.selector);
        controller.updateRecipientOverride(chad);
    }
}
