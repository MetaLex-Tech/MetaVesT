// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.24;

import {YearnBorgCompensation2025_2026} from "./lib/YearnBorgCompensation2025_2026.sol";
import {BaseAllocation} from "../src/BaseAllocation.sol";
import {BorgAuth} from "cybercorps-contracts/src/libs/auth.sol";
import {CyberAgreementRegistry} from "cybercorps-contracts/src/CyberAgreementRegistry.sol";
import {ERC1967Proxy} from "openzeppelin-contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {ISafeProxyFactory, IGnosisSafe} from "../test/lib/safe.sol";
import {CyberAgreementUtils} from "./lib/CyberAgreementUtils.sol";
import {SafeTxHelper} from "./lib/SafeTxHelper.sol";
import {Script} from "forge-std/Script.sol";
import {VestingAllocationFactory} from "../src/VestingAllocationFactory.sol";
import {console2} from "forge-std/console2.sol";
import {metavestController} from "../src/MetaVesTController.sol";
import {MetaVestDealLib, MetaVestDeal} from "../src/lib/MetaVestDealLib.sol";

contract ProposeMetaVestDealScript is SafeTxHelper, Script {
    using MetaVestDealLib for MetaVestDeal;
    using YearnBorgCompensation2025_2026 for YearnBorgCompensation2025_2026.Config;

    /// @dev For running from `forge script`. Provide the deployer private key through env var.
    function run() public virtual {
        YearnBorgCompensation2025_2026.Config memory defaultConfig = YearnBorgCompensation2025_2026.getDefault(vm);
        runSingle(
            vm.envUint("DEPLOYER_PRIVATE_KEY"), // proposerPrivateKey
            vm.envOr("BORG_DELEGATE_PRIVATE_KEY", uint256(0)), // borgSafeDelegatePrivateKey
            defaultConfig.compRecipients[0],
            vm.envUint("AGREEMENT_SALT"), // agreementSalt
            defaultConfig
        );
    }

    /// @dev For running in tests
    function runSingle(
        uint256 proposerPrivateKey,
        uint256 borgSafeDelegatePrivateKey,
        YearnBorgCompensation2025_2026.CompInfo memory recipientInfo,
        uint256 agreementSalt,
        YearnBorgCompensation2025_2026.Config memory config
    ) public virtual returns(bytes32) {
        return runSingle(
            proposerPrivateKey,
            borgSafeDelegatePrivateKey,
            recipientInfo,
            agreementSalt,
            // Default guardian allocations
            config.parseAllocation(),
            config
        );
    }

    /// @dev For running in tests
    function runSingle(
        uint256 proposerPrivateKey,
        uint256 borgSafeDelegatePrivateKey,
        YearnBorgCompensation2025_2026.CompInfo memory guardianInfo,
        uint256 agreementSalt,
        BaseAllocation.Allocation memory allocation,
        YearnBorgCompensation2025_2026.Config memory config
    ) public virtual returns(bytes32) {

        console2.log("");
        console2.log("=== ProposeMetaVestDealScript ===");
        console2.log("Proposer: ", vm.addr(proposerPrivateKey));
        console2.log("Guardian SAFE Delegate (if private key available): ", borgSafeDelegatePrivateKey != 0
            ? vm.addr(borgSafeDelegatePrivateKey)
            : address(0));
        console2.log("Guardian Safe: ", address(config.borgSafe));
        console2.log("Payment token: ", address(config.paymentToken));
        console2.log("CyberAgreementRegistry: ", address(config.registry));
        console2.log("VestingAllocationFactory: ", address(config.vestingAllocationFactory));
        console2.log("MetavesTController: ", address(config.controller));
        console2.log("");

        // Assume Guardian SAFE already delegate signing to the deployer

        // Propose a new deal

        address[] memory parties = new address[](2);
        parties[0] = address(config.borgSafe);
        parties[1] = guardianInfo.partyInfo.evmAddress;

        string[] memory globalValues = config.formatCompGlobalValues(vm, guardianInfo.partyInfo.evmAddress);
        string[][] memory partyValues = YearnBorgCompensation2025_2026.formatPartyValues(
            vm,
            config.borgSafeInfo,
            guardianInfo.partyInfo
        );

        bytes32 expectedContractId = keccak256(
            abi.encode(
                guardianInfo.compTemplate.id,
                agreementSalt, // salt,
                globalValues,
                parties
            )
        );

        (string memory agreementUri, ) = config.registry.templates(guardianInfo.compTemplate.id);

        if (borgSafeDelegatePrivateKey != 0 || guardianInfo.signature.length > 0) { // has signature
            // Has valid signature, proceed to proposal
            vm.startBroadcast(proposerPrivateKey);

            bytes32 contractId = config.controller.proposeAndSignDeal(
                guardianInfo.compTemplate.id,
                agreementSalt,
                MetaVestDealLib.draft().setVesting(
                    guardianInfo.partyInfo.evmAddress,
                    allocation,
                    config.milestones
                ),
                globalValues,
                parties,
                partyValues,
                (borgSafeDelegatePrivateKey != 0)
                    ? CyberAgreementUtils.signAgreementTypedData(
                        config.registry,
                        expectedContractId,
                        agreementUri,
                        guardianInfo.compTemplate.globalFields,
                        guardianInfo.compTemplate.partyFields,
                        globalValues,
                        partyValues[0],
                        borgSafeDelegatePrivateKey
                    )
                    : guardianInfo.signature,
                bytes32(0), // no secrets
                block.timestamp + 365 days * 2 // 2 years after deployment
            );

            vm.stopBroadcast();

            console2.log("Created:");
            console2.log("  Agreement ID:");
            console2.logBytes32(contractId);
            console2.log("");

            return contractId;

        } else {
            // Does not have valid signature, prompt for offline signing
            console2.log("Signature required: please sign the following EIP-712 typed data:");
            console2.log("  (can be signed with command `cast wallet sign --data '<paste json string here>'`)");
            console2.log("==== JSON data start ====");
            console2.log(CyberAgreementUtils.formatAgreementTypedDataJson(
                config.registry,
                expectedContractId,
                agreementUri,
                guardianInfo.compTemplate.globalFields,
                guardianInfo.compTemplate.partyFields,
                globalValues,
                partyValues[0]
            ));
            console2.log("==== JSON data end ====");

            return expectedContractId;
        }
    }
}
