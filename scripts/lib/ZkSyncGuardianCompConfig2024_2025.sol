// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.28;

import {ZkSyncGuardianCompConfigBase} from "./ZkSyncGuardianCompConfigBase.sol";
import {CommonBase} from "forge-std/Base.sol";
import {ZkCappedMinterV2} from "zk-governance/l2-contracts/src/ZkCappedMinterV2.sol";
import {CyberAgreementRegistry} from "cybercorps-contracts/src/CyberAgreementRegistry.sol";
import {IZkCappedMinterV2} from "../../src/interfaces/zk-governance/IZkCappedMinterV2.sol";
import {IGnosisSafe} from "../../test/lib/safe.sol";
import {BaseAllocation} from "../../src/BaseAllocation.sol";
import {VestingAllocationFactory} from "../../src/VestingAllocationFactory.sol";

contract ZkSyncGuardianCompConfig2024_2025 is ZkSyncGuardianCompConfigBase {
    // ZK Governance
    // Vote: https://vote.zknation.io/dao/proposal/14920227315823844313255249182525601975564035647349569740836448589354658768084?govId=eip155:324:0xb83FF6501214ddF40C91C9565d095400f3F45746
    IZkCappedMinterV2 zkCappedMinter = IZkCappedMinterV2(0xE555FC98E45637D1B45e60E4fc05cF0F22836156);

    // MetaVesT deployment
    CyberAgreementRegistry registry = CyberAgreementRegistry(address(0)); // TODO TBD
    VestingAllocationFactory vestingAllocationFactory = VestingAllocationFactory(address(0)); // TODO TBD

    // MetaLeX <> zkSync Guardian BORG Service Agreement parameters
    uint256 serviceAgreementExpiry = 1788220800;

    constructor() {
        // Vesting parameters

        guardians = new address[](6);
        guardians[0] = 0xDeaDbeefdEAdbeefdEadbEEFdeadbeEFdEaDbeeF; // TODO TBD
        guardians[1] = 0xDeaDbeefdEAdbeefdEadbEEFdeadbeEFdEaDbeeF; // TODO TBD
        guardians[2] = 0xDeaDbeefdEAdbeefdEadbEEFdeadbeEFdEaDbeeF; // TODO TBD
        guardians[3] = 0xDeaDbeefdEAdbeefdEadbEEFdeadbeEFdEaDbeeF; // TODO TBD
        guardians[4] = 0xDeaDbeefdEAdbeefdEadbEEFdeadbeEFdEaDbeeF; // TODO TBD
        guardians[5] = 0xDeaDbeefdEAdbeefdEadbEEFdeadbeEFdEaDbeeF; // TODO TBD

        fixedAnnualCompensation = 625e3 ether;
        metavestVestingAndUnlockStartTime = 1725148800; // 2024/09/01 00:00 UTC (means by the deployment @ 2025/09/01 it would've been fully unlocked)
    }
}
