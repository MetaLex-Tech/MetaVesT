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
import {SafeUtils} from "../scripts/lib/SafeUtils.sol";
import {YearnDirectorCompTest} from "./YearnDirectorComp.t.sol";

contract YearnDirectorCompAcceptanceTest is YearnDirectorCompTest {
    function setUp() public override {
        // Assume the deploy scripts has been run successfully, so we won't do it again

        // Simulate authority creating the grants through the imported Safe txs
        SafeUtils.SafeTxImport memory safeTxImport = SafeUtils.parseSafeTxJson(vm.readFile("./res/safeTxs-production.yearn-director-compensation.2025.json"));
        YearnDirectorComp2025.GrantInfo[] memory loadedGrants = YearnDirectorComp2025.loadGrants();

        vm.startPrank(config.authority);
        deal(address(config.vestingToken), config.authority, 5000e6);
        ERC20(config.vestingToken).approve(address(config.controller), 5000e6);

        console2.log("Executing Safe txs...");
        uint256 provisionSafeTxNum = safeTxImport.transactions.length - loadedGrants.length;
        for (uint256 i = 0; i < safeTxImport.transactions.length; i++) {
            (bool success, bytes memory ret) = safeTxImport.transactions[i].to.call{value: vm.parseUint(safeTxImport.transactions[i].value)}(safeTxImport.transactions[i].data);
            assertTrue(success, string(abi.encodePacked("Safe tx #", vm.toString(i + 1), " failed: ", vm.toString(ret))));

            if (i >= provisionSafeTxNum) {
                uint256 j = i - provisionSafeTxNum;
                loadedGrants[j].metavest = abi.decode(ret, (address));
                grants.push(loadedGrants[j]); // Save it to storage
                console2.log("  Deployed metavest for grant #%s: %s", vm.toString(j + 1), loadedGrants[j].metavest);
            }
        }

        console2.log("");
        vm.stopPrank();
    }

    // Rest of the tests are defined in the parent contract
}
