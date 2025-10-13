// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.28;

import {Vm} from "forge-std/Vm.sol";
import {CommonBase} from "forge-std/Base.sol";
import {CyberAgreementRegistry} from "cybercorps-contracts/src/CyberAgreementRegistry.sol";
import {IGnosisSafe} from "../../test/lib/safe.sol";
import {BaseAllocation} from "../../src/BaseAllocation.sol";
import {VestingAllocationFactory} from "../../src/VestingAllocationFactory.sol";
import {metavestController} from "../../src/MetaVesTController.sol";
import {YearnBorgCompensation2025_2026} from "./YearnBorgCompensation2025_2026.sol";

library YearnBorgCompensationSepolia2025_2026 {

    function getDefault(Vm vm) internal view returns(YearnBorgCompensation2025_2026.Config memory) {
        IGnosisSafe borgSafe = IGnosisSafe(0x4F22ba82a6B71F7305d1be7Ae7323811f9D555Ab); // dev safe
        IGnosisSafe metalexSafe = IGnosisSafe(0x4F22ba82a6B71F7305d1be7Ae7323811f9D555Ab); // dev safe

        return YearnBorgCompensation2025_2026.Config({

            // External dependencies

            paymentToken: 0x1c7D4B196Cb0C7B01d743Fbc6116a902379C7238, // testnet USDC by Circle
            
            // Yearn BORG

            borgSafe: borgSafe,
            borgSafeInfo: YearnBorgCompensation2025_2026.PartyInfo({
                name: "Yearn BORG Test",
                evmAddress: address(borgSafe)
            }),
            borgAgreementDelegate: 0x5ff4e90Efa2B88cf3cA92D63d244a78a88219Abf,

            // MetaLeX

            metalexSafe: metalexSafe,
            registry: CyberAgreementRegistry(0xa9E808B8eCBB60Bb19abF026B5b863215BC4c134),
            vestingAllocationFactory: VestingAllocationFactory(0xDeaDbeefdEAdbeefdEadbEEFdeadbeEFdEaDbeeF), // TODO TBD
            controller: metavestController(0xDeaDbeefdEAdbeefdEadbEEFdeadbeEFdEaDbeeF), // TODO TBD

            // Yearn BORG Compensation Agreement

            compRecipients: YearnBorgCompensation2025_2026.loadGuardianAndComps(vm),
            paymentTokenApprovalCap: 5000e6, // 5000 USDC * 1 recipient
            fixedAnnualCompensation: 5000e6, // 5000 USDC
            metavestVestingAndUnlockStartTime: 1756684800, // 2025/09/01 00:00 UTC
            milestones: new BaseAllocation.Milestone[](0)
        });
    }
}
