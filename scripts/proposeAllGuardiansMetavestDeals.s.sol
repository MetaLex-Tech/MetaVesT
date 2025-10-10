// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.24;

import {GnosisTransaction} from "../test/lib/safe.sol";
import {BaseAllocation} from "../src/BaseAllocation.sol";
import {BorgAuth} from "cybercorps-contracts/src/libs/auth.sol";
import {CyberAgreementRegistry} from "cybercorps-contracts/src/CyberAgreementRegistry.sol";
import {CyberAgreementUtils} from "cybercorps-contracts/test/libs/CyberAgreementUtils.sol";
import {ERC1967Proxy} from "openzeppelin-contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {ISafeProxyFactory, IGnosisSafe} from "../test/lib/safe.sol";
import {ProposeMetaVestDealScript} from "./proposeMetavestDeal.s.sol";
import {SafeTxHelper} from "./lib/SafeTxHelper.sol";
import {Script} from "forge-std/Script.sol";
import {VestingAllocationFactory} from "../src/VestingAllocationFactory.sol";
import {YearnBorgCompensation2025_2026} from "./lib/YearnBorgCompensation2025_2026.sol";
import {console2} from "forge-std/console2.sol";
import {metavestController} from "../src/MetaVesTController.sol";

contract ProposeAllGuardiansMetaVestDealScript is ProposeMetaVestDealScript {
    /// @dev For running from `forge script`. Provide the deployer private key through env var.
    function run() public virtual override {
        runAll(
            // Ethereum mainnet for 2025-2026
            vm.envUint("DEPLOYER_PRIVATE_KEY"), // proposerPrivateKey
            uint256(0), // delegate will sign offline
            uint256(keccak256("MetaLexMetaVestYearnBorgCompensationLaunchV1.0.2025-2026")), // agreementSalt
            YearnBorgCompensation2025_2026.getDefault(vm)
        );
    }

    /// @dev For running in tests
    function runAll(
        uint256 proposerPrivateKey,
        uint256 borgSafeDelegatePrivateKey,
        uint256 agreementSalt,
        YearnBorgCompensation2025_2026.Config memory config
    ) public virtual returns(bytes32[] memory) {

        address proposer = vm.addr(proposerPrivateKey);

        console2.log("");
        console2.log("=== ProposeAllGuardiansMetaVestDealScript ===");
        console2.log("Proposer: ", proposer);
        console2.log("CyberAgreementRegistry: ", address(config.registry));
        console2.log("VestingAllocationFactory: ", address(config.vestingAllocationFactory));
        console2.log("MetavesTController: ", address(config.controller));
        console2.log("");

        bytes32[] memory agreementIds = new bytes32[](config.compRecipients.length);

        for (uint256 i = 0; i < config.compRecipients.length; i++) {
            console2.log("Proposing to Guardian #%d", i + 1);
            console2.log("  name:", config.compRecipients[i].partyInfo.name);
            console2.log("  address:", config.compRecipients[i].partyInfo.evmAddress);
            console2.log("");

            agreementIds[i] = runSingle(
                proposerPrivateKey,
                borgSafeDelegatePrivateKey,
                config.compRecipients[i],
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
        uint256 borgSafeDelegatePrivateKey,
        YearnBorgCompensation2025_2026.CompInfo memory guardianInfo,
        uint256 agreementSalt,
        YearnBorgCompensation2025_2026.Config memory config
    ) public override returns(bytes32) {
        return ProposeMetaVestDealScript.runSingle(
            proposerPrivateKey,
            borgSafeDelegatePrivateKey,
            guardianInfo,
            agreementSalt,
            config
        );
    }

    function runSingle(
        uint256 proposerPrivateKey,
        uint256 borgSafeDelegatePrivateKey,
        YearnBorgCompensation2025_2026.CompInfo memory guardianInfo,
        uint256 agreementSalt,
        BaseAllocation.Allocation memory allocation,
        YearnBorgCompensation2025_2026.Config memory config
    ) public override returns(bytes32) {
        return ProposeMetaVestDealScript.runSingle(
            proposerPrivateKey,
            borgSafeDelegatePrivateKey,
            guardianInfo,
            agreementSalt,
            allocation,
            config
        );
    }
}
