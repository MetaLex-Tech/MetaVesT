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

contract ProposeMetaVestDealScript is ZkSyncGuardianCompensationConfig2024_2025, SafeTxHelper, Script {

    /// @dev For running from `forge script`. Provide the deployer private key through env var.
    function run() public virtual {
        run(
            vm.envUint("GUARDIAN_BORG_DELEGATE_PRIVATE_KEY"),
            registry,
            controller,
            guardianSafeInfo,
            PartyInfo({
                name: "Alice",
                evmAddress: 0x48d206948C366396a86A449DdD085FDbfC280B4b,
                contactDetails: "email@company.com",
                _type: "individual"
            })
        );
    }

    /// @dev For running in tests
    function run(
        uint256 proposerPrivateKey,
        CyberAgreementRegistry registry,
        metavestController controller,
        PartyInfo memory guardianSafeInfo,
        PartyInfo memory guardianInfo
    ) public virtual returns(bytes32) {
        return run(
            proposerPrivateKey, registry, controller, guardianSafeInfo, guardianInfo,
            // Default guardian allocations
            _parseAllocation(address(zkToken), metavestVestingAndUnlockStartTime)
        );
    }

    /// @dev For running in tests
    function run(
        uint256 proposerPrivateKey,
        CyberAgreementRegistry registry,
        metavestController controller,
        PartyInfo memory guardianSafeInfo,
        PartyInfo memory guardianInfo,
        BaseAllocation.Allocation memory allocation
    ) public virtual returns(bytes32) {

        address proposer = vm.addr(proposerPrivateKey);

        // Assume Guardian SAFE already delegate signing to the deployer

        // Propose a new deal

        uint48 startTime = metavestVestingAndUnlockStartTime;

        address[] memory parties = new address[](2);
        parties[0] = address(guardianSafe);
        parties[1] = guardianInfo.evmAddress;

        string[] memory globalValues = _compFormatGlobalValues(
            address(guardianSafe),
            guardianInfo.evmAddress,
            address(zkToken),
            startTime
        );
        string[][] memory partyValues = _compFormatPartyValues(guardianSafeInfo, guardianInfo);

        uint256 agreementSalt = block.timestamp;

        bytes32 expectedContractId = keccak256(
            abi.encode(
                compTemplateId,
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
            compAgreementUri,
            compGlobalFields,
            compPartyFields,
            globalValues,
            partyValues[0],
            proposerPrivateKey
        );

        vm.startBroadcast(proposerPrivateKey);

        bytes32 contractId = controller.proposeAndSignDeal(
            compTemplateId,
            agreementSalt,
            metavestController.metavestType.Vesting,
            guardianInfo.evmAddress,
            allocation,
            milestones,
            globalValues,
            parties,
            partyValues,
            signature,
            bytes32(0), // no secrets
            block.timestamp + 30 days * 2
        );

        vm.stopBroadcast();

        console.log("Proposer: ", proposer);
        console.log("Guardian Safe: ", address(guardianSafe));
        console.log("ZK token: ", address(zkToken));
        console.log("CyberAgreementRegistry: ", address(registry));
        console.log("VestingAllocationFactory: ", address(vestingAllocationFactory));
        console.log("MetavesTController: ", address(controller));
        console.log("ZkCappedMinterV2: ", address(zkCappedMinter));
        console.log("Created:");
        console.log("  Agreement ID:");
        console.logBytes32(contractId);

        return contractId;
    }
}
