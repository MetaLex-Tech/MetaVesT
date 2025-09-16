// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.24;

import {GnosisTransaction} from "../test/lib/safe.sol";
import {BaseAllocation} from "../src/BaseAllocation.sol";
import {BorgAuth} from "cybercorps-contracts/src/libs/auth.sol";
import {CyberAgreementRegistry} from "cybercorps-contracts/src/CyberAgreementRegistry.sol";
import {CyberAgreementUtils} from "cybercorps-contracts/test/libs/CyberAgreementUtils.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {ISafeProxyFactory, IGnosisSafe} from "../test/lib/safe.sol";
import {IZkCappedMinterV2Factory} from "../src/interfaces/zk-governance/IZkCappedMinterV2Factory.sol";
import {ProposeMetaVestDealScript} from "./proposeMetavestDeal.s.sol";
import {SafeTxHelper} from "./lib/SafeTxHelper.sol";
import {Script} from "forge-std/Script.sol";
import {VestingAllocationFactory} from "../src/VestingAllocationFactory.sol";
import {ZkCappedMinterV2} from "zk-governance/l2-contracts/src/ZkCappedMinterV2.sol";
import {ZkSyncGuardianCompensation2024_2025} from "./lib/ZkSyncGuardianCompensation2024_2025.sol";
import {ZkSyncGuardianCompensation2025_2026} from "./lib/ZkSyncGuardianCompensation2025_2026.sol";
import {ZkSyncGuardianCompensationSepolia2024_2025} from "./lib/ZkSyncGuardianCompensationSepolia2024_2025.sol";
import {ZkTokenV2} from "zk-governance/l2-contracts/src/ZkTokenV2.sol";
import {console2} from "forge-std/console2.sol";
import {metavestController} from "../src/MetaVesTController.sol";

contract ProposeAllGuardiansMetaVestDealScript is ProposeMetaVestDealScript {
    /// @dev For running from `forge script`. Provide the deployer private key through env var.
    function run() public virtual override {
//        ZkSyncGuardianCompensation2024_2025.Config memory config = ZkSyncGuardianCompensation2024_2025.getDefault(vm);
//
//        // Simulate Guardian SAFE delegation as instructed (payloads are copied directly from a recent production deployment)
//        GnosisTransaction[] memory guardianSafeTxs = new GnosisTransaction[](1);
//        guardianSafeTxs[0] = GnosisTransaction({
//            to: 0x07E0a0BeC742f90f7879830bC917E783dA6a6357,
//            value: 0,
//            data: hex"e988dc91000000000000000000000000a376aaf645dbd9b4f501b2a8a97bc21dca15b0010000000000000000000000000000000000000000000000000000000068db1d80"
//        });
//        for (uint256 i = 0; i < guardianSafeTxs.length; i++) {
//            vm.prank(address(config.guardianSafe));
//            (guardianSafeTxs[i].to).call{value: guardianSafeTxs[i].value}(guardianSafeTxs[i].data);
//        }
//
//        // Verify Guardian SAFE has delegated signing
//        vm.assertTrue(config.registry.isValidDelegate(address(config.guardianSafe), 0xa376AaF645dbd9b4f501B2A8a97bc21DcA15B001), "delegate should be Guardian SAFE's delegate");

        runAll(
            // zkSync Era for 2024-2025
            vm.envUint("DEPLOYER_PRIVATE_KEY"), // proposerPrivateKey
            uint256(0), // delegate will sign offline
            uint256(keccak256("MetaLexMetaVestZkSyncGuardianCompensationLaunchV1.0.2024-2025")), // agreementSalt
            ZkSyncGuardianCompensation2024_2025.getDefault(vm)

            // zkSync Era for 2025-2026
//            vm.envUint("DEPLOYER_PRIVATE_KEY"), // proposerPrivateKey
//            uint256(0), // delegate will sign offline
//            uint256(keccak256("MetaLexMetaVestZkSyncGuardianCompensationLaunchV1.0.2025-2026")), // agreementSalt
//            ZkSyncGuardianCompensation2025_2026.getDefault(vm)
        );
    }

    /// @dev For running in tests
    function runAll(
        uint256 proposerPrivateKey,
        uint256 guardianSafeDelegatePrivateKey,
        uint256 agreementSalt,
        ZkSyncGuardianCompensation2024_2025.Config memory config
    ) public virtual returns(bytes32[] memory) {

        address proposer = vm.addr(proposerPrivateKey);

        console2.log("");
        console2.log("=== ProposeAllGuardiansMetaVestDealScript ===");
        console2.log("Proposer: ", proposer);
        console2.log("CyberAgreementRegistry: ", address(config.registry));
        console2.log("VestingAllocationFactory: ", address(config.vestingAllocationFactory));
        console2.log("MetavesTController: ", address(config.controller));
        console2.log("");

        bytes32[] memory agreementIds = new bytes32[](config.guardians.length);

        for (uint256 i = 0; i < config.guardians.length; i++) {
            console2.log("Proposing to Guardian #%d", i + 1);
            console2.log("  name:", config.guardians[i].partyInfo.name);
            console2.log("  address:", config.guardians[i].partyInfo.evmAddress);
            console2.log("");

            agreementIds[i] = runSingle(
                proposerPrivateKey,
                guardianSafeDelegatePrivateKey,
                config.guardians[i],
                agreementSalt,
                config
            );
        }
        
        console2.log("Created:");
        for (uint256 i = 0; i < agreementIds.length; i++) {
            console2.log("  Agreement ID #%d:", i + 1);
            console2.logBytes32(agreementIds[i]);
            console2.log("");
        }

        return agreementIds;
    }

    function runSingle(
        uint256 proposerPrivateKey,
        uint256 guardianSafeDelegatePrivateKey,
        ZkSyncGuardianCompensation2024_2025.GuardianCompInfo memory guardianInfo,
        uint256 agreementSalt,
        ZkSyncGuardianCompensation2024_2025.Config memory config
    ) public override returns(bytes32) {
        return ProposeMetaVestDealScript.runSingle(
            proposerPrivateKey,
            guardianSafeDelegatePrivateKey,
            guardianInfo,
            agreementSalt,
            config
        );
    }

    function runSingle(
        uint256 proposerPrivateKey,
        uint256 guardianSafeDelegatePrivateKey,
        ZkSyncGuardianCompensation2024_2025.GuardianCompInfo memory guardianInfo,
        uint256 agreementSalt,
        BaseAllocation.Allocation memory allocation,
        ZkSyncGuardianCompensation2024_2025.Config memory config
    ) public override returns(bytes32) {
        return ProposeMetaVestDealScript.runSingle(
            proposerPrivateKey,
            guardianSafeDelegatePrivateKey,
            guardianInfo,
            agreementSalt,
            allocation,
            config
        );
    }
}
