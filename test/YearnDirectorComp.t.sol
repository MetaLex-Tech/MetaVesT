// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.20;

import {ERC20} from "openzeppelin-contracts/token/ERC20/ERC20.sol";
import {BaseAllocation} from "../src/BaseAllocation.sol";
import {RestrictedTokenFactory} from "../src/RestrictedTokenFactory.sol";
import {Test, console2} from "forge-std/Test.sol";
import {TokenOptionFactory} from "../src/TokenOptionFactory.sol";
import {VestingAllocationFactory} from "../src/VestingAllocationFactory.sol";
import {VestingAllocation} from "../src/VestingAllocation.sol";
import {metavestController} from "../src/MetaVesTController.sol";
import {DeployYearnDirectorCompScript} from "../scripts/deploy.yearn-director-comp.s.sol";
import {YearnDirectorCompSepolia2025} from "../scripts/lib/YearnDirectorCompSepolia2025.sol";
import {YearnDirectorComp2025} from "../scripts/lib/YearnDirectorComp2025.sol";
import {GnosisTransaction} from "../scripts/lib/safe.sol";

contract YearnDirectorCompTest is Test {
    string saltStr = "YearnDirectorCompTest";
    bytes32 salt = keccak256(bytes(saltStr));

    uint256 deployerPrivateKey = vm.envUint("DEPLOYER_PRIVATE_KEY");
    address deployer;

    // Test with mainnet configs
    YearnDirectorComp2025.Config config = YearnDirectorComp2025.getDefault();
    YearnDirectorComp2025.GrantInfo[] grants;

    /// @notice Assumes Sepolia testnet
    function setUp() public virtual {
        (deployer, deployerPrivateKey) = makeAddrAndKey("deployer");

        // Deploy controllers and prepare txs for grants
        YearnDirectorComp2025.GrantInfo[] memory loadedGrants;
        GnosisTransaction[] memory provisionSafeTxs;
        GnosisTransaction[] memory grantSafeTxs;
        (
            config.controller,
            loadedGrants,
            provisionSafeTxs,
            grantSafeTxs,

        ) = (new DeployYearnDirectorCompScript()).runWithArgs(
            saltStr,
            deployerPrivateKey,
            config
        );

        // Simulate authority creating the grants
        vm.startPrank(config.authority);
        deal(address(config.vestingToken), config.authority, 5000e6);
        ERC20(config.vestingToken).approve(address(config.controller), 5000e6);

        console2.log("Provisioning Safe funds...");
        for (uint256 i = 0; i < provisionSafeTxs.length; i++) {
            (bool success, bytes memory ret) = provisionSafeTxs[i].to.call{value: provisionSafeTxs[i].value}(provisionSafeTxs[i].data);
            assertTrue(success, string(abi.encodePacked("call #", vm.toString(i + 1), " failed: ", vm.toString(ret))));
        }

        console2.log("Deploying grants:");
        for (uint256 i = 0; i < grantSafeTxs.length; i++) {
            (bool success, bytes memory ret) = grantSafeTxs[i].to.call{value: grantSafeTxs[i].value}(grantSafeTxs[i].data);
            assertTrue(success, string(abi.encodePacked("call #", vm.toString(i + 1), " failed: ", vm.toString(ret))));
            loadedGrants[i].metavest = abi.decode(ret, (address));
            grants.push(loadedGrants[i]); // Save it to storage
            console2.log("  #%s: %s", vm.toString(i + 1), loadedGrants[i].metavest);
        }
        console2.log("");
        vm.stopPrank();
    }

    function test_sanityCheck() public {
        // Verify grant parameters
        for (uint256 i = 0; i < grants.length; i++) {
            VestingAllocation vault = VestingAllocation(grants[i].metavest);
            
            assertEq(vault.controller(), address(config.controller), string(abi.encodePacked("unexpected controller for grant #", vm.toString(i))));

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
        }
    }

    /// @notice Grantee should be able to withdraw all after fully unlocked
    function test_withdrawal() public {
        vm.warp(config.vestingAndUnlockStartTime + 365 days);

        for (uint256 i = 0; i < grants.length; i++) {
            ERC20 vestingToken = ERC20(config.vestingToken);
            VestingAllocation vault = VestingAllocation(grants[i].metavest);
            uint256 vestingTokenBalanceBefore = vestingToken.balanceOf(grants[i].grantee);

            vm.startPrank(grants[i].grantee);
            vault.withdraw(grants[i].amount);
            assertEq(vestingToken.balanceOf(grants[i].grantee) - vestingTokenBalanceBefore, grants[i].amount, "unexpected vesting token amount after withdrawal");
            vm.stopPrank();
        }
    }
}
