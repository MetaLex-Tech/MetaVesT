// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.28;

import {CommonBase} from "forge-std/Base.sol";
import {ZkCappedMinterV2} from "zk-governance/l2-contracts/src/ZkCappedMinterV2.sol";
import {CyberAgreementRegistry} from "cybercorps-contracts/src/CyberAgreementRegistry.sol";
import {IZkTokenV1} from "../../src/interfaces/zk-governance/IZkTokenV1.sol";
import {IZkCappedMinterV2Factory} from "../../src/interfaces/zk-governance/IZkCappedMinterV2Factory.sol";
import {IGnosisSafe} from "../../test/lib/safe.sol";
import {BaseAllocation} from "../../src/BaseAllocation.sol";
import {VestingAllocationFactory} from "../../src/VestingAllocationFactory.sol";

contract ZkSyncGuardianCompensationConfigBase is CommonBase {
    // Assume zkSync Era mainnet @ 64202885

    // MetaLeX SAFE

    IGnosisSafe metalexSafe = IGnosisSafe(0x99ba28257DbDB399b53bF59Aa5656480f3bdc5bc);

    // zkSync Guardian SAFE

    IGnosisSafe guardianSafe = IGnosisSafe(0x06E19F3CEafBC373329973821ee738021A58F0E3);

    // ZK Governance

    IZkTokenV1 zkToken = IZkTokenV1(0x5A7d6b2F92C77FAD6CCaBd7EE0624E64907Eaf3E);

    // Deployments

    CyberAgreementRegistry registry = CyberAgreementRegistry(address(0)); // TODO TBD
    VestingAllocationFactory vestingAllocationFactory = VestingAllocationFactory(address(0)); // TODO TBD
}
