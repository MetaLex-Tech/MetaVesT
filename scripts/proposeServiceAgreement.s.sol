// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.24;

import {ZkSyncGuardianCompensation2024_2025} from "./lib/ZkSyncGuardianCompensation2024_2025.sol";
import {ZkSyncGuardianCompensationSepolia2024_2025} from "./lib/ZkSyncGuardianCompensationSepolia2024_2025.sol";
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

contract ProposeServiceAgreementScript is SafeTxHelper, Script {
    using ZkSyncGuardianCompensation2024_2025 for ZkSyncGuardianCompensation2024_2025.Config;

    /// @dev For running from `forge script`. Provide the deployer private key through env var.
    function run() public virtual {
        run(
            vm.envUint("METALEX_SAFE_DELEGATE_PRIVATE_KEY"),

            // zkSync Era
//            ZkSyncGuardianCompensation2024_2025.getDefault()

            // zkSync Sepolia
            ZkSyncGuardianCompensationSepolia2024_2025.getDefault()
        );
    }

    /// @dev For running in tests
    function run(
        uint256 proposerPrivateKey,
        ZkSyncGuardianCompensation2024_2025.Config memory config
    ) public virtual returns(bytes32) {

        address metalexProposer = vm.addr(proposerPrivateKey);

        console2.log("");
        console2.log("=== ProposeServiceAgreementScript ===");
        console2.log("MetaLeX proposer: ", address(metalexProposer));
        console2.log("Guardian Safe: ", address(config.guardianSafe));
        console2.log("CyberAgreementRegistry: ", address(config.registry));
        console2.log("");

        // Assume Guardian SAFE already delegate signing to the deployer

        // Propose a new deal

        address[] memory parties = new address[](2);
        parties[0] = address(config.metalexSafe);
        parties[1] = address(config.guardianSafe);

        string[] memory globalValues = ZkSyncGuardianCompensation2024_2025.formatServiceGlobalValues(vm, config.serviceAgreementExpiry);
        string[][] memory partyValues = ZkSyncGuardianCompensation2024_2025.formatPartyValues(vm, config.metalexSafeInfo, config.guardianSafeInfo);

        uint256 agreementSalt = block.timestamp;

        bytes32 expectedContractId = keccak256(
            abi.encode(
                config.serviceTemplateId,
                agreementSalt, // salt,
                globalValues,
                parties
            )
        );

        bytes memory signature = CyberAgreementUtils.signAgreementTypedData(
            vm,
            config.registry.DOMAIN_SEPARATOR(),
            config.registry.SIGNATUREDATA_TYPEHASH(),
            expectedContractId,
            config.serviceAgreementUri,
            config.serviceGlobalFields,
            config.servicePartyFields,
            globalValues,
            partyValues[0],
            proposerPrivateKey
        );

        vm.startBroadcast(proposerPrivateKey);

        bytes32 contractId = config.registry.createContract(
            config.serviceTemplateId,
            agreementSalt,
            globalValues,
            parties,
            partyValues,
            bytes32(0), // no secrets
            address(0), // no finalizer
            config.serviceAgreementExpiry
        );

        config.registry.signContract(
            contractId,
            partyValues[0],
            signature,
            false, // fillUnallocated
            "" // no secrets
        );

        vm.stopBroadcast();

        console2.log("Created:");
        console2.log("  Agreement ID:");
        console2.logBytes32(contractId);
        console2.log("");

        return contractId;
    }
}
