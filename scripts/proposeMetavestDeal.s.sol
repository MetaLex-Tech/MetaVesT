// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.24;

import {ZkSyncGuardianCompensation2024_2025} from "./lib/ZkSyncGuardianCompensation2024_2025.sol";
import {ZkSyncGuardianCompensationSepolia2024_2025} from "./lib/ZkSyncGuardianCompensationSepolia2024_2025.sol";
import {BaseAllocation} from "../src/BaseAllocation.sol";
import {BorgAuth} from "cybercorps-contracts/src/libs/auth.sol";
import {CyberAgreementRegistry} from "cybercorps-contracts/src/CyberAgreementRegistry.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {ISafeProxyFactory, IGnosisSafe} from "../test/lib/safe.sol";
import {IZkCappedMinterV2Factory} from "../src/interfaces/zk-governance/IZkCappedMinterV2Factory.sol";
import {CyberAgreementUtils} from "./lib/CyberAgreementUtils.sol";
import {SafeTxHelper} from "./lib/SafeTxHelper.sol";
import {Script} from "forge-std/Script.sol";
import {VestingAllocationFactory} from "../src/VestingAllocationFactory.sol";
import {ZkCappedMinterV2} from "zk-governance/l2-contracts/src/ZkCappedMinterV2.sol";
import {ZkTokenV2} from "zk-governance/l2-contracts/src/ZkTokenV2.sol";
import {console2} from "forge-std/console2.sol";
import {metavestController} from "../src/MetaVesTController.sol";

contract ProposeMetaVestDealScript is SafeTxHelper, Script {
    using ZkSyncGuardianCompensation2024_2025 for ZkSyncGuardianCompensation2024_2025.Config;

    /// @dev For running from `forge script`. Provide the deployer private key through env var.
    function run() public virtual {
        ZkSyncGuardianCompensation2024_2025.Config memory defaultConfig = ZkSyncGuardianCompensationSepolia2024_2025.getDefault(vm);
        runSingle(
            vm.envUint("DEPLOYER_PRIVATE_KEY"), // proposerPrivateKey
            vm.envOr("GUARDIAN_BORG_DELEGATE_PRIVATE_KEY", uint256(0)), // guardianSafeDelegatePrivateKey
            defaultConfig.guardians[0],
            vm.envUint("AGREEMENT_SALT"), // agreementSalt
            defaultConfig
        );
    }

    /// @dev For running in tests
    function runSingle(
        uint256 proposerPrivateKey,
        uint256 guardianSafeDelegatePrivateKey,
        ZkSyncGuardianCompensation2024_2025.GuardianCompInfo memory guardianInfo,
        uint256 agreementSalt,
        ZkSyncGuardianCompensation2024_2025.Config memory config
    ) public virtual returns(bytes32) {
        return runSingle(
            proposerPrivateKey,
            guardianSafeDelegatePrivateKey,
            guardianInfo,
            agreementSalt,
            // Default guardian allocations
            config.parseAllocation(),
            config
        );
    }

    /// @dev For running in tests
    function runSingle(
        uint256 proposerPrivateKey,
        uint256 guardianSafeDelegatePrivateKey,
        ZkSyncGuardianCompensation2024_2025.GuardianCompInfo memory guardianInfo,
        uint256 agreementSalt,
        BaseAllocation.Allocation memory allocation,
        ZkSyncGuardianCompensation2024_2025.Config memory config
    ) public virtual returns(bytes32) {

        address guardianSafeDelegate = guardianSafeDelegatePrivateKey != 0
            ? vm.addr(guardianSafeDelegatePrivateKey)
            : address(0);
        address proposer = vm.addr(proposerPrivateKey);

        console2.log("");
        console2.log("=== ProposeMetaVestDealScript ===");
        console2.log("Proposer: ", proposer);
        console2.log("Guardian SAFE Delegate (if private key available): ", guardianSafeDelegate);
        console2.log("Guardian Safe: ", address(config.guardianSafe));
        console2.log("ZK token: ", address(config.zkToken));
        console2.log("CyberAgreementRegistry: ", address(config.registry));
        console2.log("VestingAllocationFactory: ", address(config.vestingAllocationFactory));
        console2.log("MetavesTController: ", address(config.controller));
        console2.log("ZkCappedMinterV2: ", address(config.zkCappedMinter));
        console2.log("");

        // Assume Guardian SAFE already delegate signing to the deployer

        // Propose a new deal

        uint48 startTime = config.metavestVestingAndUnlockStartTime;

        address[] memory parties = new address[](2);
        parties[0] = address(config.guardianSafe);
        parties[1] = guardianInfo.partyInfo.evmAddress;

        string[] memory globalValues = config.formatCompGlobalValues(vm, guardianInfo.partyInfo.evmAddress);
        string[][] memory partyValues = ZkSyncGuardianCompensation2024_2025.formatPartyValues(
            vm,
            config.guardianSafeInfo,
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

        bytes memory signature = (guardianSafeDelegatePrivateKey != 0)
            ? CyberAgreementUtils.signAgreementTypedData(
                config.registry,
                expectedContractId,
                agreementUri,
                guardianInfo.compTemplate.globalFields,
                guardianInfo.compTemplate.partyFields,
                globalValues,
                partyValues[0],
                guardianSafeDelegatePrivateKey
            )
            : guardianInfo.signature;

        if (signature.length > 0) {
            // Has valid signature, proceed to proposal
            vm.startBroadcast(proposerPrivateKey);

            bytes32 contractId = config.controller.proposeAndSignDeal(
                guardianInfo.compTemplate.id,
                agreementSalt,
                metavestController.metavestType.Vesting,
                guardianInfo.partyInfo.evmAddress,
                allocation,
                config.milestones,
                globalValues,
                parties,
                partyValues,
                signature,
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

            return bytes32(0);
        }
    }
}
