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

contract SignDealAndCreateMetavestScript is SafeTxHelper, Script {
    using ZkSyncGuardianCompensation2024_2025 for ZkSyncGuardianCompensation2024_2025.Config;

    /// @dev For running from `forge script`. Provide the deployer private key through env var.
    function run() public virtual {
        uint256 granteePrivateKey = vm.envUint("GRANTEE_PRIVATE_KEY");
        run(
//            granteePrivateKey,
//            0x0000000000000000000000000000000000000000000000000000000000000000, // TODO TBD
//            ZkSyncGuardianCompensation2024_2025.PartyInfo({ // TODO TBD
//                name: "Alice",
//                evmAddress: vm.addr(granteePrivateKey)
//            }),
//            ZkSyncGuardianCompensation2024_2025.getDefault()

            // zkSync Sepolia
            granteePrivateKey,
            0xd0d7610ca18b8a76a36c7e1241929641c06cce69ddc1161beebe69b72dae6cbf,
            ZkSyncGuardianCompensation2024_2025.PartyInfo({ // TODO TBD
                name: "Alice",
                evmAddress: vm.addr(granteePrivateKey)
            }),
            ZkSyncGuardianCompensationSepolia2024_2025.getDefault()
        );
    }

    /// @dev For running in tests
    function run(
        uint256 granteePrivateKey,     
        bytes32 agreementId,
        ZkSyncGuardianCompensation2024_2025.PartyInfo memory granteeInfo,
        ZkSyncGuardianCompensation2024_2025.Config memory config
    ) public virtual returns(address) {

        address signer = vm.addr(granteePrivateKey);

        console2.log("");
        console2.log("=== SignDealAndCreateMetavestScript ===");
        console2.log("Signer: ", signer);
        console2.log("Grantee: ", granteeInfo.evmAddress);
        console2.log("Grantee Name: ", granteeInfo.name);
        console2.log("Guardian Safe: ", address(config.guardianSafe));
        console2.log("CyberAgreementRegistry: ", address(config.registry));
        console2.log("MetavesTController: ", address(config.controller));
        console2.log("Agreement ID:");
        console2.logBytes32(agreementId);
        console2.log("");
        
        // Sign the deal and create MetaVesT

        string[] memory granteePartyValues = ZkSyncGuardianCompensation2024_2025.formatPartyValues(vm, granteeInfo);
        bytes memory signature = CyberAgreementUtils.signAgreementTypedData(
            vm,
            config.registry.DOMAIN_SEPARATOR(),
            config.registry.SIGNATUREDATA_TYPEHASH(),
            agreementId,
            config.compAgreementUri,
            config.compGlobalFields,
            config.compPartyFields,
            config.formatCompGlobalValues(vm, granteeInfo.evmAddress),
            granteePartyValues,
            granteePrivateKey
        );

        vm.startBroadcast(granteePrivateKey);

        address metavest = config.controller.signDealAndCreateMetavest(
            granteeInfo.evmAddress,
            granteeInfo.evmAddress,
            agreementId,
            granteePartyValues,
            signature,
            "" // no secrets
        );

        vm.stopBroadcast();
        
        console2.log("Created:");
        console2.log("  MetavesT: ", address(metavest));
        console2.log("");

        return address(metavest);
    }
}
