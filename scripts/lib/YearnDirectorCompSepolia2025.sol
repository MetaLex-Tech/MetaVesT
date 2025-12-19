// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.28;

import {Vm} from "forge-std/Vm.sol";
import {CommonBase} from "forge-std/Base.sol";
import {console2} from "forge-std/Console2.sol";
import {BaseAllocation} from "../../src/BaseAllocation.sol";
import {metavestController} from "../../src/MetaVesTController.sol";
import {YearnDirectorComp2025} from "./YearnDirectorComp2025.sol";

library YearnDirectorCompSepolia2025 {
    Vm constant vm = Vm(address(uint160(uint256(keccak256("hevm cheat code")))));

    function getDefault() internal view returns(YearnDirectorComp2025.Config memory) {
        return YearnDirectorComp2025.Config({

            // External dependencies

            vestingToken: 0xB9E5Ae881f36083cB914205F19EAa265D76eeF53, // mock vesting token
            paymentToken: address(0), // no-op

            // Authority

            dao: 0x4F22ba82a6B71F7305d1be7Ae7323811f9D555Ab, // dev Safe
            authority: 0x4F22ba82a6B71F7305d1be7Ae7323811f9D555Ab, // dev Safe

            vestingAndUnlockStartTime: 1756684800, // TODO TBD: for now it is 2025/09/01 00:00 UTC
            vestingAndUnlockRate: 159, // ceil(5000e6 / (365 * 24 * 3600))
            vestingAndUnlockCliff: 0, // no cliff
            exercisePrice: 0, // no-op
            shortStopDuration: 0, // no-op

            // Grants
            controller: metavestController(0xDeaDbeefdEAdbeefdEadbEEFdeadbeEFdEaDbeeF) // TODO TBD
        });
    }
}
