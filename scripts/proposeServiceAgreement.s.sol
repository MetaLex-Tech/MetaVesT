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
import {console2} from "forge-std/console2.sol";
import {metavestController} from "../src/MetaVesTController.sol";

contract ProposeServiceAgreementScript is ZkSyncGuardianCompensationConfig2024_2025, SafeTxHelper, Script {

    /// @dev For running from `forge script`. Provide the deployer private key through env var.
    function run() public virtual {
        run(
            vm.envUint("METALEX_SAFE_DELEGATE_PRIVATE_KEY"),
            registry
        );
    }

    /// @dev For running in tests
    function run(
        uint256 proposerPrivateKey,
        CyberAgreementRegistry _registry
    ) public virtual returns(bytes32) {
        address metalexProposer = vm.addr(proposerPrivateKey);
        registry = _registry;

        // Assume Guardian SAFE already delegate signing to the deployer

        // Propose a new deal

        address[] memory parties = new address[](2);
        parties[0] = address(metalexSafe);
        parties[1] = address(guardianSafe);

        string[] memory globalValues = _serviceFormatGlobalValues(serviceAgreementExpiry);
        string[][] memory partyValues = _serviceFormatPartyValues(address(metalexProposer), address(guardianSafe));

        uint256 agreementSalt = block.timestamp;

        bytes32 expectedContractId = keccak256(
            abi.encode(
                serviceTemplateId,
                agreementSalt, // salt,
                globalValues,
                parties
            )
        );

        bytes memory signature = CyberAgreementUtils.signAgreementTypedData(
            vm,
            registry.DOMAIN_SEPARATOR(),
            registry.SIGNATUREDATA_TYPEHASH(),
            expectedContractId,
            serviceAgreementUri,
            serviceGlobalFields,
            servicePartyFields,
            globalValues,
            partyValues[0],
            proposerPrivateKey
        );

        vm.startBroadcast(proposerPrivateKey);

        bytes32 contractId = registry.createContract(
            serviceTemplateId,
            agreementSalt,
            globalValues,
            parties,
            partyValues,
            bytes32(0), // no secrets
            address(0), // no finalizer
            serviceAgreementExpiry
        );

        registry.signContract(
            contractId,
            partyValues[0],
            signature,
            false, // fillUnallocated
            "" // no secrets
        );

        vm.stopBroadcast();

        console2.log("MetaLeX proposer: ", address(metalexProposer));
        console2.log("Guardian Safe: ", address(guardianSafe));
        console2.log("CyberAgreementRegistry: ", address(registry));
        console2.log("Created:");
        console2.log("  Agreement ID:");
        console2.logBytes32(contractId);

        return contractId;
    }
}
