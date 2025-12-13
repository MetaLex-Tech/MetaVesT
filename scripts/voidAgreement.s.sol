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
import {SafeTxHelper} from "./lib/SafeTxHelper.sol";
import {CyberAgreementUtils} from "./lib/CyberAgreementUtils.sol";
import {Script} from "forge-std/Script.sol";
import {ZkCappedMinterV2} from "zk-governance/l2-contracts/src/ZkCappedMinterV2.sol";
import {ZkTokenV2} from "zk-governance/l2-contracts/src/ZkTokenV2.sol";
import {console2} from "forge-std/console2.sol";
import {metavestController} from "../src/MetaVesTController.sol";

contract VoidAgreementScript is SafeTxHelper, Script {
    /// @dev For running from `forge script`. Provide the deployer private key through env var.
    function run() public virtual {
        run(
            // zkSync Era
//            vm.envUint("GRANTEE_PRIVATE_KEY"),
//            ZkSyncGuardianCompensation2024_2025.getDefault(vm)

            // zkSync Sepolia
            vm.envUint("GUARDIAN_BORG_DELEGATE_PRIVATE_KEY"),
//            vm.envUint("GRANTEE_PRIVATE_KEY"),
            0xc519e4ce6730ae9167f4e080f47ac1544405756cf301f0c8316578fc90f95e0a,
            ZkSyncGuardianCompensationSepolia2024_2025.getDefault(vm)
        );
    }

    /// @dev For running in tests
    function run(
        uint256 signerPrivateKey,
        bytes32 agreementId,
        ZkSyncGuardianCompensation2024_2025.Config memory config
    ) public virtual {

        address signer = vm.addr(signerPrivateKey);

        console2.log("");
        console2.log("=== VoidAgreementScript ===");
        console2.log("Signer: ", address(signer));
        console2.log("CyberAgreementRegistry: ", address(config.registry));
        console2.log("Agreement ID:");
        console2.logBytes32(agreementId);
        console2.log("");

        bytes memory signature = CyberAgreementUtils.signVoidTypedData(
            vm,
            config.registry.DOMAIN_SEPARATOR(),
            config.registry.VOIDSIGNATUREDATA_TYPEHASH(),
            agreementId,
            signer,
            signerPrivateKey
        );

        vm.startBroadcast(signerPrivateKey);

        config.registry.voidContractFor(
            agreementId,
            signer,
            signature
        );

        vm.stopBroadcast();
    }
}
