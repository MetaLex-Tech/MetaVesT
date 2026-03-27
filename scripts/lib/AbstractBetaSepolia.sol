// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.28;

import {Vm} from "forge-std/Vm.sol";
import {CommonBase} from "forge-std/Base.sol";
import {console2} from "forge-std/Console2.sol";
import {BaseAllocation} from "../../src/BaseAllocation.sol";
import {metavestController} from "../../src/MetaVesTController.sol";
import {AbstractBeta} from "./AbstractBeta.sol";

library AbstractBetaSepolia {
    Vm constant vm = Vm(address(uint160(uint256(keccak256("hevm cheat code")))));

    function getDefault() internal view returns(AbstractBeta.Config memory) {
        return AbstractBeta.Config({

            // External dependencies

            vestingToken: 0xA581b1b0D31B0528C20801E56EeEaF0834a8C907, // mock vesting token
            paymentToken: 0xB9E5Ae881f36083cB914205F19EAa265D76eeF53, // mock payment token

            // Authority

            dao: 0x4F22ba82a6B71F7305d1be7Ae7323811f9D555Ab, // dev Safe
            authority: 0x4F22ba82a6B71F7305d1be7Ae7323811f9D555Ab, // dev Safe
            escrowMultisig: 0x4F22ba82a6B71F7305d1be7Ae7323811f9D555Ab, // dev Safe

            // Sat Jan  1 00:00:00 UTC 2028
            // Will update the start times once finalized
            unlockStartTime: 1830297600,
            exercisePrice: 1e6,
            shortStopDuration: 0,

            // Grants (without override) (grantee can specify their desired recipient addresses)
            controllerWithoutOverride: metavestController(0xCEf4761CC320Fdc28034f00B754E8b608028f420),

            // Grants (with override) (authority overrides all grantees' recipient address)
            controllerWithOverride: metavestController(0x387116083c8788426Fc91d6689972e2ad6d54512)
        });
    }
}
