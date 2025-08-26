// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.28;

import {ZkSyncGuardianCompensationConfig2024_2025} from "./ZkSyncGuardianCompensationConfig2024_2025.sol";
import {CommonBase} from "forge-std/Base.sol";
import {ZkCappedMinterV2} from "zk-governance/l2-contracts/src/ZkCappedMinterV2.sol";
import {CyberAgreementRegistry} from "cybercorps-contracts/src/CyberAgreementRegistry.sol";
import {IZkCappedMinterV2} from "../../src/interfaces/zk-governance/IZkCappedMinterV2.sol";
import {IGnosisSafe} from "../../test/lib/safe.sol";
import {BaseAllocation} from "../../src/BaseAllocation.sol";

contract ZkSyncGuardianCompensationConfig2025_2026 is ZkSyncGuardianCompensationConfig2024_2025 {
    // ZK Governance
    // Vote: https://vote.zknation.io/dao/proposal/14920227315823844313255249182525601975564035647349569740836448589354658768084?govId=eip155:324:0xb83FF6501214ddF40C91C9565d095400f3F45746
    IZkCappedMinterV2 zkCappedMinter = IZkCappedMinterV2(0x1358F460bD147C4a6BfDaB75aD2B78C837a11D4A);

    constructor() {
        fixedAnnualCompensation = 625e3 ether;
        metavestVestingAndUnlockStartTime = 1756684800; // 2025/09/01 00:00 UTC

        guardians = new string[](6);
        guardians[0] = 0xDeaDbeefdEAdbeefdEadbEEFdeadbeEFdEaDbeeF; // TODO TBD
        guardians[1] = 0xDeaDbeefdEAdbeefdEadbEEFdeadbeEFdEaDbeeF; // TODO TBD
        guardians[2] = 0xDeaDbeefdEAdbeefdEadbEEFdeadbeEFdEaDbeeF; // TODO TBD
        guardians[3] = 0xDeaDbeefdEAdbeefdEadbEEFdeadbeEFdEaDbeeF; // TODO TBD
        guardians[4] = 0xDeaDbeefdEAdbeefdEadbEEFdeadbeEFdEaDbeeF; // TODO TBD
        guardians[5] = 0xDeaDbeefdEAdbeefdEadbEEFdeadbeEFdEaDbeeF; // TODO TBD
    }
}
