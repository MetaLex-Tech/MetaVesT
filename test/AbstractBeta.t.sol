// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.20;

import {ERC20} from "openzeppelin-contracts/token/ERC20/ERC20.sol";
import {BaseAllocation} from "../src/BaseAllocation.sol";
import {RestrictedTokenAward} from "../src/RestrictedTokenAllocation.sol";
import {RestrictedTokenFactory} from "../src/RestrictedTokenFactory.sol";
import {Test, console2} from "forge-std/Test.sol";
import {TokenOptionFactory} from "../src/TokenOptionFactory.sol";
import {VestingAllocationFactory} from "../src/VestingAllocationFactory.sol";
import {metavestController} from "../src/MetaVesTController.sol";
import {DeployAbstractBetaScript} from "../scripts/deploy.abstract-beta.s.sol";
import {AbstractBetaSepolia} from "../scripts/lib/AbstractBetaSepolia.sol";
import {AbstractBeta} from "../scripts/lib/AbstractBeta.sol";
import {GnosisTransaction} from "../scripts/lib/safe.sol";

contract AbstractBetaTest is Test {
    string saltStr = "AbstractBetaTest";
    bytes32 salt = keccak256(bytes(saltStr));

    uint256 deployerPrivateKey = vm.envUint("DEPLOYER_PRIVATE_KEY");
    address deployer;

    AbstractBeta.Config config = AbstractBetaSepolia.getDefault();
    AbstractBeta.GrantInfo[] grants;

    /// @notice Assumes Sepolia testnet
    function setUp() public {
        (deployer, deployerPrivateKey) = makeAddrAndKey("deployer");

        // Deploy controllers and prepare txs for grants
        AbstractBeta.GrantInfo[] memory loadedGrants;
        GnosisTransaction[] memory safeTxs;
        (
            config.controllerWithoutOverride,
            config.controllerWithOverride,
            loadedGrants,
            safeTxs
        ) = (new DeployAbstractBetaScript()).runWithArgs(
            saltStr,
            deployerPrivateKey,
            config
        );

        // Simulate authority creating the grants
        vm.startPrank(config.authority);
        deal(address(config.vestingToken), config.authority, 100_000_000_000 ether);
        ERC20(config.vestingToken).approve(address(config.controllerWithoutOverride), 100_000_000_000 ether);
        ERC20(config.vestingToken).approve(address(config.controllerWithOverride), 100_000_000_000 ether);

        console2.log("Deploying grants:");
        for (uint256 i = 0; i < safeTxs.length; i++) {
            (bool success, bytes memory ret) = safeTxs[i].to.call{value: safeTxs[i].value}(safeTxs[i].data);
            assertTrue(success, string(abi.encodePacked("call #", vm.toString(i), " failed: ", vm.toString(ret))));
            loadedGrants[i].metavest = abi.decode(ret, (address));
            grants.push(loadedGrants[i]); // Save it to storage
            console2.log("  #%s: %s", vm.toString(i), loadedGrants[i].metavest);
        }
        console2.log("");
        vm.stopPrank();
    }

    function test_sanityCheck() public {
        // Verify grant parameters
        for (uint256 i = 0; i < grants.length; i++) {
            RestrictedTokenAward vault = RestrictedTokenAward(grants[i].metavest);

            metavestController controller = AbstractBeta.getController(config, grants[i].controllerType);

            assertEq(vault.controller(), address(controller), string(abi.encodePacked("unexpected controller for grant #", vm.toString(i))));

            (
                uint256 tokenStreamTotal,
                uint128 vestingCliffCredit,
                uint128 unlockingCliffCredit,
                uint160 vestingRate,
                uint48 vestingStartTime,
                uint160 unlockRate,
                uint48 unlockStartTime,
                address tokenContract
            ) = vault.allocation();
            assertEq(tokenStreamTotal, grants[i].amount, string(abi.encodePacked("unexpected tokenStreamTotal for grant #", vm.toString(i))));
            assertEq(vestingCliffCredit, config.vestingAndUnlockCliff, string(abi.encodePacked("unexpected vestingCliffCredit for grant #", vm.toString(i))));
            assertEq(unlockingCliffCredit, config.vestingAndUnlockCliff, string(abi.encodePacked("unexpected unlockingCliffCredit for grant #", vm.toString(i))));
            assertEq(vestingRate, config.vestingAndUnlockRate, string(abi.encodePacked("unexpected vestingRate for grant #", vm.toString(i))));
            assertEq(unlockRate, config.vestingAndUnlockRate, string(abi.encodePacked("unexpected unlockRate for grant #", vm.toString(i))));
            assertEq(vestingStartTime, config.vestingAndUnlockStartTime, string(abi.encodePacked("unexpected vestingStartTime for grant #", vm.toString(i))));
            assertEq(unlockStartTime, config.vestingAndUnlockStartTime, string(abi.encodePacked("unexpected unlockStartTime for grant #", vm.toString(i))));
            assertEq(tokenContract, config.vestingToken, string(abi.encodePacked("unexpected vestingToken for grant #", vm.toString(i))));
            assertEq(vault.paymentToken(), config.paymentToken, string(abi.encodePacked("unexpected paymentToken for grant #", vm.toString(i))));
        }
    }

    /// @notice Authority should be able to update the start times
    function test_updateStartTimes() public {
        uint48 now = uint48(block.timestamp);

        // 60 days later
        vm.warp(now + 60 days);

        // (1) Add all vaults to sets

        string memory setName = "grants";
//    string setNameVestingStartTime = "updateMetavestVestingStartTime";
//    string setNameUnlockStartTime = "updateMetavestUnlockStartTime";

        vm.startPrank(config.authority);

        config.controllerWithoutOverride.createSet(setName);
        config.controllerWithOverride.createSet(setName);
//        config.controllerWithoutOverride.createSet(setNameVestingStartTime);
//        config.controllerWithOverride.createSet(setNameVestingStartTime);
//        config.controllerWithoutOverride.createSet(setNameUnlockStartTime);
//        config.controllerWithOverride.createSet(setNameUnlockStartTime);

        for (uint256 i = 0; i < grants.length; i++) {
            metavestController controller = AbstractBeta.getController(config, grants[i].controllerType);
            controller.addMetaVestToSet(setName, grants[i].metavest);
//            metavestController(safeTxs[i].to).addMetaVestToSet(setNameVestingStartTime, loadedGrants[i].metavest);
//            metavestController(safeTxs[i].to).addMetaVestToSet(setNameUnlockStartTime, loadedGrants[i].metavest);
        }

        vm.stopPrank();

        // (2a) Propose amendment for updating vestingStartTime

        vm.startPrank(config.authority);
        config.controllerWithoutOverride.proposeMajorityMetavestAmendment(
            setName,
            metavestController.updateMetavestVestingStartTime.selector,
            abi.encodeWithSelector(
                metavestController.updateMetavestVestingStartTime.selector,
                address(0), // no-op
                now + 90 days
            )
        );
        config.controllerWithOverride.proposeMajorityMetavestAmendment(
            setName,
            metavestController.updateMetavestVestingStartTime.selector,
            abi.encodeWithSelector(
                metavestController.updateMetavestVestingStartTime.selector,
                address(0), // no-op
                now + 90 days
            )
        );
        vm.stopPrank();

        // Approve amendment
        for (uint256 i = 0; i < grants.length; i++) {
            metavestController controller = AbstractBeta.getController(config, grants[i].controllerType);
            vm.prank(grants[i].grantee);
            controller.voteOnMetavestAmendment(grants[i].metavest, setName, metavestController.updateMetavestVestingStartTime.selector, true);
        }

        // Execute amendment
        vm.startPrank(config.authority);
        for (uint256 i = 0; i < grants.length; i++) {
            metavestController controller = AbstractBeta.getController(config, grants[i].controllerType);
            controller.updateMetavestVestingStartTime(grants[i].metavest, now + 90 days);

            {
                (,,,, uint48 vestingStartTime,, uint48 unlockStartTime,) = RestrictedTokenAward(grants[0].metavest).allocation();
                assertEq(vestingStartTime, now + 90 days, string(abi.encodePacked("unexpected vestingStartTime after amendment for grant #", vm.toString(i))));
            }
        }
        vm.stopPrank();

        // (2b) Propose amendment for updating unlockStartTime

        vm.startPrank(config.authority);
        config.controllerWithoutOverride.proposeMajorityMetavestAmendment(
            setName,
            metavestController.updateMetavestUnlockStartTime.selector,
            abi.encodeWithSelector(
                metavestController.updateMetavestUnlockStartTime.selector,
                address(0), // no-op
                now + 90 days
            )
        );
        config.controllerWithOverride.proposeMajorityMetavestAmendment(
            setName,
            metavestController.updateMetavestUnlockStartTime.selector,
            abi.encodeWithSelector(
                metavestController.updateMetavestUnlockStartTime.selector,
                address(0), // no-op
                now + 90 days
            )
        );
        vm.stopPrank();

        // Approve amendment
        for (uint256 i = 0; i < grants.length; i++) {
            metavestController controller = AbstractBeta.getController(config, grants[i].controllerType);
            vm.prank(grants[i].grantee);
            controller.voteOnMetavestAmendment(grants[i].metavest, setName, metavestController.updateMetavestUnlockStartTime.selector, true);
        }

        // Execute amendment
        vm.startPrank(config.authority);
        for (uint256 i = 0; i < grants.length; i++) {
            metavestController controller = AbstractBeta.getController(config, grants[i].controllerType);
            controller.updateMetavestUnlockStartTime(grants[i].metavest, now + 90 days);

            {
                (,,,, uint48 vestingStartTime,, uint48 unlockStartTime,) = RestrictedTokenAward(grants[0].metavest).allocation();
                assertEq(unlockStartTime, now + 90 days, string(abi.encodePacked("unexpected unlockStartTime after amendment for grant #", vm.toString(i))));
            }
        }
        vm.stopPrank();

        // Simulate and verify withdrawal on new schedules

        vm.warp(now + 90 days + 200); // enough time to withdraw all

        for (uint256 i = 0; i < grants.length; i++) {
            ERC20 vestingToken = ERC20(config.vestingToken);
            RestrictedTokenAward vault = RestrictedTokenAward(grants[i].metavest);
            address recipient = vault.getRecipient();
            uint256 vestingTokenBalanceBefore = vestingToken.balanceOf(recipient);

            vm.startPrank(grants[i].grantee);
            vault.withdraw(grants[i].amount);
            assertEq(vestingToken.balanceOf(recipient) - vestingTokenBalanceBefore, grants[i].amount, "unexpected vesting token amount after withdrawal");
            vm.stopPrank();
        }
    }
}
