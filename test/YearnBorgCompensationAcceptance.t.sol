// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.20;

import {console2} from "forge-std/console2.sol";
import {CyberAgreementRegistry} from "cybercorps-contracts/src/CyberAgreementRegistry.sol";
import {YearnBorgCompensationTest} from "./YearnBorgCompensation.t.sol";
import {metavestController} from "../src/MetaVesTController.sol";
import {VestingAllocationFactory} from "../src/VestingAllocationFactory.sol";
import {MetaVesTControllerTestBase} from "./lib/MetaVesTControllerTestBase.sol";
import {GnosisTransaction} from "./lib/safe.sol";
import {CreateAllTemplatesScript} from "../scripts/createAllTemplates.s.sol";
import {DeployYearnBorgCompensationPrerequisitesScript} from "../scripts/deployYearnBorgCompensationPrerequisites.s.sol";
import {DeployYearnBorgCompensationScript} from "../scripts/deployYearnBorgCompensation.s.sol";
import {ProposeAllGuardiansMetaVestDealScript} from "../scripts/proposeAllGuardiansMetavestDeals.s.sol";
import {ProposeMetaVestDealScript} from "../scripts/proposeMetavestDeal.s.sol";
import {SignDealAndCreateMetavestScript} from "../scripts/signDealAndCreateMetavest.s.sol";
import {YearnBorgCompensation2025_2026} from "../scripts/lib/YearnBorgCompensation2025_2026.sol";
import {YearnBorgCompensationSepolia2025_2026} from "../scripts/lib/YearnBorgCompensationSepolia2025_2026.sol";

// Test with existing deployment
// - Assume existing deployment on Sepolia testnet
// - Phases deployed/completed are commented out to reflect real-world conditions
// - Phases not yet completed will be simulated
// - Will use same environment variables as the real deployment, but some of them will be overridden so we could test
contract YearnBorgCompensationAcceptanceTest is YearnBorgCompensationTest {

    function setUp() override public {
        agreementSalt = 1760138399; // Fixed agreement salt so we can do offline signatures

        // Override accounts for acceptance tests

        // Use the real deployer
        deployerPrivateKey = vm.envUint("DEPLOYER_PRIVATE_KEY");
        deployer = vm.addr(deployerPrivateKey);

        // Prepare funds for accounts used by the actual deployment scripts
        deal(deployer, 1 ether);
        deal(chad, 1 ether);

        GnosisTransaction[] memory borgSafeTxs;

        config2025_2026 = YearnBorgCompensationSepolia2025_2026.getDefault(vm);

        // Use real Guardians SAFE delegate. We don't have his private key and will use offline signatures instead
        borgDelegate = config2025_2026.borgAgreementDelegate;
        borgDelegatePrivateKey = 0;

        // Override recipient info for tests

        // There will be only one recipient for test
        borgRecipientPrivateKeys = new uint256[](1);
        borgRecipientPrivateKeys[0] = privateKeySalt + 100;
        address recipient = vm.addr(borgRecipientPrivateKeys[0]);
        // Prepare funds for guardians
        deal(recipient, 1 ether);

        YearnBorgCompensation2025_2026.CompInfo memory tempCompInfo;

        // Reduce guardians to the first one
        tempCompInfo = config2025_2026.compRecipients[0];
        config2025_2026.compRecipients = new YearnBorgCompensation2025_2026.CompInfo[](1);
        config2025_2026.compRecipients[0] = tempCompInfo;
        // Override recipient address with one we control, and its offline signature
        config2025_2026.compRecipients[0].partyInfo.evmAddress = recipient;
        // {"domain":{"name":"CyberAgreementRegistry","version":"1","chainId":11155111,"verifyingContract":"0xa9E808B8eCBB60Bb19abF026B5b863215BC4c134"},"message":{"contractId":"0x335ee80c3cd43c1d2e607f145879510e17e385b4cf7d7fbf1f734e70a102d717","legalContractUri":"ipfs://bafkreidefnk2tf6req4tn3bya7pkfkt45i6cppmannb5fz7ncv6mfg6vj4","globalFields":["metavestType","grantor","grantee","tokenContract","tokenStreamTotal","vestingCliffCredit","unlockingCliffCredit","vestingRate","vestingStartTime","unlockRate","unlockStartTime"],"partyFields":["name","evmAddress"],"globalValues":["0","0x4F22ba82a6B71F7305d1be7Ae7323811f9D555Ab","0x600cbFB6b453b1Cd26796eb8f0B4020118638386","0x1c7D4B196Cb0C7B01d743Fbc6116a902379C7238","10","0","0","10","1756684800","10","1756684800"],"partyValues":["Yearn BORG Test","0x4F22ba82a6B71F7305d1be7Ae7323811f9D555Ab"]},"primaryType":"SignatureData","types":{"EIP712Domain":[{"name":"name","type":"string"},{"name":"version","type":"string"},{"name":"chainId","type":"uint256"},{"name":"verifyingContract","type":"address"}],"SignatureData":[{"name":"contractId","type":"bytes32"},{"name":"legalContractUri","type":"string"},{"name":"globalFields","type":"string[]"},{"name":"partyFields","type":"string[]"},{"name":"globalValues","type":"string[]"},{"name":"partyValues","type":"string[]"}]}}
        config2025_2026.compRecipients[0].signature = hex"e8032b150a9af0099daf927799793c84d827ec9a239f0cf6c0b15cbdc0839ad5387a5b9f3a9b3441e2c01352ded51b405bbc6b5e3c34ba66918b4a1597e346d31c";

        // Assume prerequisites have been deployed
        auth = config2025_2026.registry.AUTH();

        // Assume 2025-2026 compensation contracts have been deployed

        // Assume all all templates have been deployed

        // TODO Uncomment to simulate BORG SAFE to execute txs as instructed (payloads are copied directly from a recent production deployment)
//        borgSafeTxs = new GnosisTransaction[](2);
//        borgSafeTxs[0] = GnosisTransaction({
//            to: 0x1c7D4B196Cb0C7B01d743Fbc6116a902379C7238,
//            value: 0,
//            data: hex"095ea7b3000000000000000000000000fa5ab18bd5e02b1d6430e91c32c5cb5e7f43bb650000000000000000000000000000000000000000000000000000000000989680"
//        });
//        borgSafeTxs[1] = GnosisTransaction({
//            to: 0xa9E808B8eCBB60Bb19abF026B5b863215BC4c134,
//            value: 0,
//            data: hex"e988dc910000000000000000000000005ff4e90efa2b88cf3ca92d63d244a78a88219abf0000000000000000000000000000000000000000000000000000000068ffb4dc"
//        });
//        for (uint256 i = 0; i < borgSafeTxs.length; i++) {
//            vm.prank(address(config2025_2026.borgSafe));
//            (borgSafeTxs[i].to).call{value: borgSafeTxs[i].value}(borgSafeTxs[i].data);
//        }
    }
}
