// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.28;

import {Vm} from "forge-std/Vm.sol";
import {CommonBase} from "forge-std/Base.sol";
import {console2} from "forge-std/Console2.sol";
import {BaseAllocation} from "../../src/BaseAllocation.sol";
import {metavestController} from "../../src/MetaVesTController.sol";

library YearnDirectorComp2025 {
    Vm constant vm = Vm(address(uint160(uint256(keccak256("hevm cheat code")))));

    struct Config {

        // External dependencies

        address vestingToken;
        address paymentToken;

        // Authority

        address dao;
        address authority;

        uint48 vestingAndUnlockStartTime;
        uint160 vestingAndUnlockRate;
        uint128 vestingAndUnlockCliff;
        uint256 exercisePrice;
        uint256 shortStopDuration;

        // Grants
        metavestController controller;
    }

    struct GrantInfo {
        address grantee;
        uint256 amount;
        address metavest;
    }
    
    function getDefault() internal view returns(Config memory) {
        return Config({

            // External dependencies

            vestingToken: 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48, // USDC
            paymentToken: address(0), // no-op

            // Authority

            dao: 0xFEB4acf3df3cDEA7399794D0869ef76A6EfAff52, // ychad.eth
            authority: 0xFEB4acf3df3cDEA7399794D0869ef76A6EfAff52, // ychad.eth

            vestingAndUnlockStartTime: 1756684800, // TODO TBD: for now it is 2025/09/01 00:00 UTC
            vestingAndUnlockRate: 159, // ceil(5000e6 / (365 * 24 * 3600))
            vestingAndUnlockCliff: 0, // no cliff
            exercisePrice: 0, // no-op
            shortStopDuration: 0, // no-op

            // Grants
            controller: metavestController(0xDeaDbeefdEAdbeefdEadbEEFdeadbeEFdEaDbeeF) // TODO TBD
        });
    }

    function loadGrants() internal view returns(GrantInfo[] memory grants) {
        uint256 numGrantees = vm.envOr("NUM_GRANTEES", uint256(0));
        console2.log("Loading number of grantees: %d", numGrantees);

        grants = new GrantInfo[](numGrantees);
        for (uint i = 0; i < numGrantees ; i++) {
            grants[i] = GrantInfo({
                grantee: address(uint160(vm.envUint(string(abi.encodePacked("GRANTEE_ADDR_", vm.toString(i)))))),
                amount: vm.envUint(string(abi.encodePacked("GRANTEE_AMOUNT_", vm.toString(i)))),
                metavest: address(0)
            });
        }
    }

    function parseAllocation(Config memory config, GrantInfo memory grant) internal view returns(BaseAllocation.Allocation memory) {
        return BaseAllocation.Allocation({
            tokenContract: address(config.vestingToken),
            tokenStreamTotal: grant.amount,
            vestingCliffCredit: config.vestingAndUnlockCliff,
            unlockingCliffCredit: config.vestingAndUnlockCliff,
            vestingRate: config.vestingAndUnlockRate,
            vestingStartTime: config.vestingAndUnlockStartTime,
            unlockRate: config.vestingAndUnlockRate,
            unlockStartTime: config.vestingAndUnlockStartTime
        });
    }
}
