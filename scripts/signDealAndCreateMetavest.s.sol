// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.24;

import {YearnBorgCompensation2025_2026} from "./lib/YearnBorgCompensation2025_2026.sol";
import {BaseAllocation} from "../src/BaseAllocation.sol";
import {BorgAuth} from "cybercorps-contracts/src/libs/auth.sol";
import {CyberAgreementRegistry} from "cybercorps-contracts/src/CyberAgreementRegistry.sol";
import {CyberAgreementUtils} from "cybercorps-contracts/test/libs/CyberAgreementUtils.sol";
import {ERC1967Proxy} from "openzeppelin-contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {ISafeProxyFactory, IGnosisSafe} from "../test/lib/safe.sol";
import {SafeTxHelper} from "./lib/SafeTxHelper.sol";
import {Script} from "forge-std/Script.sol";
import {VestingAllocationFactory} from "../src/VestingAllocationFactory.sol";
import {console2} from "forge-std/console2.sol";
import {metavestController} from "../src/MetaVesTController.sol";

contract SignDealAndCreateMetavestScript is SafeTxHelper, Script {
    using YearnBorgCompensation2025_2026 for YearnBorgCompensation2025_2026.Config;

    /// @dev For running from `forge script`. Provide the deployer private key through env var.
    function run() public virtual {
        uint256 granteePrivateKey = vm.envUint("GRANTEE_PRIVATE_KEY");
        YearnBorgCompensation2025_2026.Config memory defaultConfig = YearnBorgCompensation2025_2026.getDefault(vm);
        run(
//            granteePrivateKey,
//            0x0000000000000000000000000000000000000000000000000000000000000000, // TODO TBD
//            YearnBorgCompensation2024_2025.PartyInfo({ // TODO TBD
//                name: "Alice",
//                evmAddress: vm.addr(granteePrivateKey)
//            }),
//            YearnBorgCompensation2024_2025.getDefault(vm)

            // zkSync Sepolia
            granteePrivateKey,
            0xd0d7610ca18b8a76a36c7e1241929641c06cce69ddc1161beebe69b72dae6cbf,
            defaultConfig.compRecipients[0],
            defaultConfig
        );
    }

    /// @dev For running in tests
    function run(
        uint256 granteePrivateKey,     
        bytes32 agreementId,
        YearnBorgCompensation2025_2026.CompInfo memory granteeInfo,
        YearnBorgCompensation2025_2026.Config memory config
    ) public virtual returns(address) {

        address signer = vm.addr(granteePrivateKey);

        console2.log("");
        console2.log("=== SignDealAndCreateMetavestScript ===");
        console2.log("Signer: ", signer);
        console2.log("Grantee: ", granteeInfo.partyInfo.evmAddress);
        console2.log("Grantee Name: ", granteeInfo.partyInfo.name);
        console2.log("Guardian Safe: ", address(config.borgSafe));
        console2.log("CyberAgreementRegistry: ", address(config.registry));
        console2.log("MetavesTController: ", address(config.controller));
        console2.log("Agreement ID:");
        console2.logBytes32(agreementId);
        console2.log("");
        
        // Sign the deal and create MetaVesT

        (string memory agreementUri, ) = config.registry.templates(granteeInfo.compTemplate.id);

        string[] memory granteePartyValues = YearnBorgCompensation2025_2026.formatPartyValues(vm, granteeInfo.partyInfo);
        bytes memory signature = CyberAgreementUtils.signAgreementTypedData(
            vm,
            config.registry.DOMAIN_SEPARATOR(),
            config.registry.SIGNATUREDATA_TYPEHASH(),
            agreementId,
            agreementUri,
            granteeInfo.compTemplate.globalFields,
            granteeInfo.compTemplate.partyFields,
            config.formatCompGlobalValues(vm, granteeInfo.partyInfo.evmAddress),
            granteePartyValues,
            granteePrivateKey
        );

        vm.startBroadcast(granteePrivateKey);

        address metavest = config.controller.signDealAndCreateMetavest(
            granteeInfo.partyInfo.evmAddress,
            granteeInfo.partyInfo.evmAddress,
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
