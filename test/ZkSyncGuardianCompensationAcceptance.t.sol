// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.20;

import "../src/MetaVesTController.sol";
import "../src/VestingAllocationFactory.sol";
import "../src/interfaces/zk-governance/IZkCappedMinterV2.sol";
import "../src/interfaces/zk-governance/IZkTokenV1.sol";
import "./lib/MetaVesTControllerTestBase.sol";
import {ZkSyncGuardianCompensationTest} from "./ZkSyncGuardianCompensation.t.sol";
import {CreateAllTemplatesScript} from "../scripts/createAllTemplates.s.sol";
import {CyberAgreementRegistry} from "cybercorps-contracts/src/CyberAgreementRegistry.sol";
import {DeployZkSyncGuardianCompensationPrerequisitesScript} from "../scripts/deployZkSyncGuardianCompensationPrerequisites.s.sol";
import {DeployZkSyncGuardianCompensationScript} from "../scripts/deployZkSyncGuardianCompensation.s.sol";
import {GnosisTransaction} from "./lib/safe.sol";
import {ProposeAllGuardiansMetaVestDealScript} from "../scripts/proposeAllGuardiansMetavestDeals.s.sol";
import {ProposeMetaVestDealScript} from "../scripts/proposeMetavestDeal.s.sol";
import {SignDealAndCreateMetavestScript} from "../scripts/signDealAndCreateMetavest.s.sol";
import {Test} from "forge-std/Test.sol";
import {ZkSyncGuardianCompensation2024_2025} from "../scripts/lib/ZkSyncGuardianCompensation2024_2025.sol";
import {ZkSyncGuardianCompensation2025_2026} from "../scripts/lib/ZkSyncGuardianCompensation2025_2026.sol";
import {console2} from "forge-std/console2.sol";

// Test with existing deployment
// - Assume existing deployment on zkSync Era mainnet
// - Phases deployed/completed are commented out to reflect real-world conditions
// - Phases not yet completed will be simulated
// - Will use same environment variables as the real deployment, but some of them will be overridden so we could test
contract ZkSyncGuardianCompensationAcceptanceTest is ZkSyncGuardianCompensationTest {

    function setUp() override public {
        agreementSalt = 1757616222; // Fixed agreement salt so we can do offline signatures

        // Override accounts for acceptance tests

        // Use the real deployer
        deployerPrivateKey = vm.envUint("DEPLOYER_PRIVATE_KEY");
        deployer = vm.addr(deployerPrivateKey);

        // Use real Guardians SAFE delegate. We don't have his private key and will use offline signatures instead
        guardianDelegate = 0xa376AaF645dbd9b4f501B2A8a97bc21DcA15B001;
        guardianDelegatePrivateKey = 0;

        // Prepare funds for accounts used by the actual deployment scripts
        deal(deployer, 1 ether);
        deal(chad, 1 ether);

        GnosisTransaction[] memory guardianSafeTxs;

        config2024_2025 = ZkSyncGuardianCompensation2024_2025.getDefault(vm);
        config2025_2026 = ZkSyncGuardianCompensation2025_2026.getDefault(vm);

        // Override guardian info for tests

        // There will be only one guardian for test
        guardianPrivateKeys = new uint256[](1);
        guardianPrivateKeys[0] = privateKeySalt + 100;
        address guardian = vm.addr(guardianPrivateKeys[0]);
        // Prepare funds for guardians
        deal(guardian, 1 ether);

        ZkSyncGuardianCompensation2024_2025.GuardianCompInfo memory tempGuardianInfo;

        // Reduce guardians to the first one
        tempGuardianInfo = config2024_2025.guardians[0];
        config2024_2025.guardians = new ZkSyncGuardianCompensation2024_2025.GuardianCompInfo[](1);
        config2024_2025.guardians[0] = tempGuardianInfo;
        // Override guardian address with one we control, and its offline signature
        config2024_2025.guardians[0].partyInfo.evmAddress = guardian;
        config2024_2025.guardians[0].signature = hex"7b3492d39b39cfbbc4c134ff06f4cc68afcb224d6f94c5813ffae53db94d5c8b622457c2abaa2403aba84711f37ae17ffa367f3574cb7cd3a51da4461c017d331b";

        // Reduce guardians to the first one
        tempGuardianInfo = config2025_2026.guardians[0];
        config2025_2026.guardians = new ZkSyncGuardianCompensation2024_2025.GuardianCompInfo[](1);
        config2025_2026.guardians[0] = tempGuardianInfo;
        // Override guardian address with one we control, and its offline signature
        config2025_2026.guardians[0].partyInfo.evmAddress = guardian;
        config2025_2026.guardians[0].signature = hex"144ca44344bc709c156abaa532dd3f049fced51ce43a0aecd888c574ba75e31a47b17f3db279933e2918f3ba11c21e09dc1d5d5652ef9576c7d57ffd4fad546f1c";

        // Assume prerequisites have been deployed
        auth = config2024_2025.registry.AUTH();

        // Assume 2024-2025 compensation contracts have been deployed

        // Assume 2025-2026 compensation contracts have been deployed

        // Assume all all templates have been deployed

        // Simulate MetaLeX SAFE to execute txs as instructed (payloads are copied directly from a recent production deployment)

        guardianSafeTxs = new GnosisTransaction[](5);
        guardianSafeTxs[0] = GnosisTransaction({
            to: 0x07E0a0BeC742f90f7879830bC917E783dA6a6357,
            value: 0,
            data: hex"e988dc91000000000000000000000000a376aaf645dbd9b4f501b2a8a97bc21dca15b0010000000000000000000000000000000000000000000000000000000068db1d80"
        });
        guardianSafeTxs[1] = GnosisTransaction({
            to: 0xE555FC98E45637D1B45e60E4fc05cF0F22836156,
            value: 0,
            data: hex"2f2ff15d9f2df0fed2c77648de5860a4cc508cd0818c85b8b8a1ab4ceeef8d981c8956a6000000000000000000000000d509349af986e7202f2bc4ae49c203e354faafcd"
        });
        guardianSafeTxs[2] = GnosisTransaction({
            to: 0xD509349AF986E7202f2Bc4ae49C203E354faafCD,
            value: 0,
            data: hex"66e26184000000000000000000000000e555fc98e45637d1b45e60e4fc05cf0f22836156"
        });
        guardianSafeTxs[3] = GnosisTransaction({
            to: 0x1358F460bD147C4a6BfDaB75aD2B78C837a11D4A,
            value: 0,
            data: hex"2f2ff15d9f2df0fed2c77648de5860a4cc508cd0818c85b8b8a1ab4ceeef8d981c8956a6000000000000000000000000570d31f59bd0c96a9e1cc889e7e4dbd585d6915b"
        });
        guardianSafeTxs[4] = GnosisTransaction({
            to: 0x570d31F59bD0C96a9e1CC889E7E4dBd585D6915b,
            value: 0,
            data: hex"66e261840000000000000000000000001358f460bd147c4a6bfdab75ad2b78c837a11d4a"
        });

        for (uint256 i = 0; i < guardianSafeTxs.length; i++) {
            vm.prank(address(config2024_2025.guardianSafe));
            (guardianSafeTxs[i].to).call{value: guardianSafeTxs[i].value}(guardianSafeTxs[i].data);
        }

        // Verify Guardian SAFE has delegated signing
        assertTrue(config2024_2025.registry.isValidDelegate(address(config2024_2025.guardianSafe), guardianDelegate), "delegate should be Guardian SAFE's delegate");

        // Vote has been executed as of block 64423211
        // https://vote.zknation.io/dao/proposal/14920227315823844313255249182525601975564035647349569740836448589354658768084?govId=eip155:324:0xb83FF6501214ddF40C91C9565d095400f3F45746
        masterMinter = IZkCappedMinterV2(config2024_2025.zkCappedMinter.MINTABLE());
    }

    function test_AdminToolingCompensation() override public {
        // No-op: disabled since we won't have signatures for it
    }
}
