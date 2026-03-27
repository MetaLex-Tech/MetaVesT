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

        uint48 unlockStartTime;
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
        uint128 vestingCliffCredit;
        uint128 unlockingCliffCredit;
        uint160 vestingRate;
        uint48 vestingStartTime;
        uint160 unlockRate;
        // Note unlockStartTime, exercisePrice and shortStopDuration are universal and not grant-specific
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
            unlockStartTime: 1830297600, // TODO TBD
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
                vestingStartTime: uint48(vm.envUint(string(abi.encodePacked("GRANTEE_VESTING_START_TIME_", vm.toString(i))))),
                vestingCliffCredit: uint128(vm.envUint(string(abi.encodePacked("GRANTEE_VESTING_CLIFF_CREDIT_", vm.toString(i))))),
                vestingRate: uint160(vm.envUint(string(abi.encodePacked("GRANTEE_VESTING_RATE_", vm.toString(i))))),
                unlockingCliffCredit: uint128(vm.envUint(string(abi.encodePacked("GRANTEE_UNLOCKING_CLIFF_CREDIT_", vm.toString(i))))),
                unlockRate: uint160(vm.envUint(string(abi.encodePacked("GRANTEE_UNLOCK_RATE_", vm.toString(i))))),
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
            vestingCliffCredit: grant.vestingCliffCredit,
            unlockingCliffCredit: grant.unlockingCliffCredit,
            vestingRate: grant.vestingRate,
            vestingStartTime: grant.vestingStartTime,
            unlockRate: grant.unlockRate,
            unlockStartTime: config.unlockStartTime
        });
    }

    function getController(Config memory config, ControllerType controllerType) external view returns(metavestController) {
        return (controllerType == AbstractBeta.ControllerType.WithoutOverride)
            ? config.controllerWithoutOverride
            : config.controllerWithOverride;
    }
}
