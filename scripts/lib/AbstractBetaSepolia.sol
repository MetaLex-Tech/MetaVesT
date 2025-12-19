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

            vestingToken: 0xB9E5Ae881f36083cB914205F19EAa265D76eeF53, // mock vesting token
            paymentToken: 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48, // mock payment token

            // Authority

            dao: 0x8E9603BcB5D974Ed9C870510F3665F67CE5c5bDe, // dev wallet
            authority: 0x8E9603BcB5D974Ed9C870510F3665F67CE5c5bDe, // dev wallet
            escrowMultisig: 0x8E9603BcB5D974Ed9C870510F3665F67CE5c5bDe, // dev wallet

            // Sat Jan  1 00:00:00 UTC 2028
            // Will update the start times once finalized
            vestingAndUnlockStartTime: 1830297600,
            vestingAndUnlockRate: 100 ether,
            vestingAndUnlockCliff: 0,
            exercisePrice: 10e6,
            shortStopDuration: 0,

            // Grants (without override) (grantee can specify their desired recipient addresses)
            controllerWithoutOverride: metavestController(0xDeaDbeefdEAdbeefdEadbEEFdeadbeEFdEaDbeeF), // TODO TBD

            // Grants (with override) (authority overrides all grantees' recipient address)
            controllerWithOverride: metavestController(0xDeaDbeefdEAdbeefdEadbEEFdeadbeEFdEaDbeeF) // TODO TBD
        });
    }
}
