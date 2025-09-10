// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.24;

import {ZkSyncGuardianCompensation2024_2025} from "./lib/ZkSyncGuardianCompensation2024_2025.sol";
import {BaseAllocation} from "../src/BaseAllocation.sol";
import {BorgAuth} from "cybercorps-contracts/src/libs/auth.sol";
import {CyberAgreementRegistry} from "cybercorps-contracts/src/CyberAgreementRegistry.sol";
import {CyberAgreementUtils} from "cybercorps-contracts/test/libs/CyberAgreementUtils.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {ISafeProxyFactory, IGnosisSafe} from "../test/lib/safe.sol";
import {IZkCappedMinterV2Factory} from "../src/interfaces/zk-governance/IZkCappedMinterV2Factory.sol";
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
        ZkSyncGuardianCompensation2024_2025.Config memory defaultConfig = ZkSyncGuardianCompensation2024_2025.getDefault(vm);
        runSingle(
            vm.envUint("DEPLOYER_PRIVATE_KEY"), // proposerPrivateKey
            vm.envUint("GUARDIAN_BORG_DELEGATE_PRIVATE_KEY"), // guardianSafeDelegatePrivateKey
            defaultConfig.guardians[0],
            defaultConfig
        );
    }

    /// @dev For running in tests
    function runSingle(
        uint256 proposerPrivateKey,
        uint256 guardianSafeDelegatePrivateKey,
        ZkSyncGuardianCompensation2024_2025.GuardianCompInfo memory guardianInfo,
        ZkSyncGuardianCompensation2024_2025.Config memory config
    ) public virtual returns(bytes32) {
        return runSingle(
            proposerPrivateKey,
            guardianSafeDelegatePrivateKey,
            guardianInfo,
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

        uint256 agreementSalt = block.timestamp;

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
                vm,
                config.registry.DOMAIN_SEPARATOR(),
                config.registry.SIGNATUREDATA_TYPEHASH(),
                expectedContractId,
                agreementUri,
                guardianInfo.compTemplate.globalFields,
                guardianInfo.compTemplate.partyFields,
                globalValues,
                partyValues[0],
                guardianSafeDelegatePrivateKey
            )
            : guardianInfo.signature;

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
    }
}
