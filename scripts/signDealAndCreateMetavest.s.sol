// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.24;

import {ZkSyncGuardianCompensationConfig2024_2025} from "./lib/ZkSyncGuardianCompensationConfig2024_2025.sol";
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
import {console} from "forge-std/console.sol";
import {metavestController} from "../src/MetaVesTController.sol";

contract SignDealAndCreateMetavestScript is ZkSyncGuardianCompensationConfig2024_2025, SafeTxHelper, Script {

    /// @dev For running from `forge script`. Provide the deployer private key through env var.
    function run() public virtual {
        uint256 granteePrivateKey = vm.envUint("GRANTEE_PRIVATE_KEY");
        run(
            granteePrivateKey,
            registry,
            controller,
            0x0000000000000000000000000000000000000000000000000000000000000000, // TODO TBD
            PartyInfo({ // TODO TBD
                name: "Alice",
                evmAddress: vm.addr(granteePrivateKey),
                contactDetails: "email@company.com",
                _type: "individual"
            })
        );
    }

    /// @dev For running in tests
    function run(
        uint256 granteePrivateKey,
        CyberAgreementRegistry registry,
        metavestController controller,
        bytes32 agreementId,
        PartyInfo memory granteeInfo
    ) public virtual returns(address) {

        // Sign the deal and create MetaVesT

        string[] memory granteePartyValues = _compFormatPartyValues(granteeInfo);
        bytes memory signature = CyberAgreementUtils.signAgreementTypedData(
            vm,
            registry.DOMAIN_SEPARATOR(),
            registry.SIGNATUREDATA_TYPEHASH(),
            agreementId,
            compAgreementUri,
            compGlobalFields,
            compPartyFields,
            _compFormatGlobalValues(
                address(guardianSafe),
                granteeInfo.evmAddress,
                address(zkToken),
                metavestVestingAndUnlockStartTime
            ),
            granteePartyValues,
            granteePrivateKey
        );

        vm.startBroadcast(granteePrivateKey);

        address metavest = controller.signDealAndCreateMetavest(
            granteeInfo.evmAddress,
            granteeInfo.evmAddress,
            agreementId,
            granteePartyValues,
            signature,
            "" // no secrets
        );

        vm.stopBroadcast();

        console.log("Grantee: ", granteeInfo.evmAddress);
        console.log("Grantee Name: ", granteeInfo.name);
        console.log("Guardian Safe: ", address(guardianSafe));
        console.log("CyberAgreementRegistry: ", address(registry));
        console.log("MetavesTController: ", address(controller));
        console.log("Agreement ID:");
        console.logBytes32(agreementId);
        console.log("Created:");
        console.log("  MetavesT: ", address(metavest));

        return address(metavest);
    }
}
