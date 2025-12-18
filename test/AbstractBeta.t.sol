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

            metavestController controller = (grants[i].controllerType == AbstractBeta.ControllerType.WithoutOverride)
                ? config.controllerWithoutOverride
                : config.controllerWithOverride;

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
}