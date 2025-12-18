// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.28;

import {Vm} from "forge-std/Vm.sol";
import {CommonBase} from "forge-std/Base.sol";
import {console2} from "forge-std/Console2.sol";
import {BaseAllocation} from "../../src/BaseAllocation.sol";
import {metavestController} from "../../src/MetaVesTController.sol";

library AbstractBeta {
    Vm constant vm = Vm(address(uint160(uint256(keccak256("hevm cheat code")))));

    error UnexpectedControllerType(uint256 controllerType);

    enum ControllerType {
        WithoutOverride,
        WithOverride
    }

    struct Config {

        // External dependencies

        address vestingToken;
        address paymentToken;

        // Authority

        address dao;
        address authority;
        address escrowMultisig;

        uint48 vestingAndUnlockStartTime;
        uint160 vestingAndUnlockRate;
        uint128 vestingAndUnlockCliff;
        uint256 exercisePrice;
        uint256 shortStopDuration;

        // Grants (without override) (grantee can specify their desired recipient addresses)
        metavestController controllerWithoutOverride;

        // Grants (with override) (authority overrides all grantees' recipient address)
        metavestController controllerWithOverride;
    }

    struct GrantInfo {
        address grantee;
        uint256 amount;
        ControllerType controllerType;
        address metavest;
    }
    
    function getDefault() internal view returns(Config memory) {
        return Config({

            // External dependencies

            vestingToken: 0xDeaDbeefdEAdbeefdEadbEEFdeadbeEFdEaDbeeF, // TODO TBD: Abstract token
            paymentToken: 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48, // TODO TBD: USDC?

            // Authority

            dao: 0xDeaDbeefdEAdbeefdEadbEEFdeadbeEFdEaDbeeF, // TODO TBD
            authority: 0xDeaDbeefdEAdbeefdEadbEEFdeadbeEFdEaDbeeF, // TODO TBD
            escrowMultisig: 0xDeaDbeefdEAdbeefdEadbEEFdeadbeEFdEaDbeeF, // TODO TBD

            // Sat Jan  1 00:00:00 UTC 2028
            // Will update the start times once finalized
            vestingAndUnlockStartTime: 1830297600, // TODO TBD
            vestingAndUnlockRate: 1, // TODO TBD
            vestingAndUnlockCliff: 0, // TODO TBD
            exercisePrice: 1e6, // TODO TBD
            shortStopDuration: 0, // TODO TBD

            // Grants (without override) (grantee can specify their desired recipient addresses)
            controllerWithoutOverride: metavestController(0xDeaDbeefdEAdbeefdEadbEEFdeadbeEFdEaDbeeF), // TODO TBD

            // Grants (with override) (authority overrides all grantees' recipient address)
            controllerWithOverride: metavestController(0xDeaDbeefdEAdbeefdEadbEEFdeadbeEFdEaDbeeF) // TODO TBD
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
                controllerType: ControllerType(vm.envUint(string(abi.encodePacked("GRANTEE_CONTROLLER_TYPE_", vm.toString(i))))),
                metavest: address(0)
            });

            if (grants[i].controllerType > ControllerType.WithOverride) {
                revert UnexpectedControllerType(uint256(grants[i].controllerType));
            }
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
