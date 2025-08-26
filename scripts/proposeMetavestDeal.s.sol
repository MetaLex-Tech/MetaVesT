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
import {console} from "forge-std/console.sol";
import {metavestController} from "../src/MetaVesTController.sol";

contract ProposeMetaVestDealScript is SafeTxHelper, Script {
    using ZkSyncGuardianCompensation2024_2025 for ZkSyncGuardianCompensation2024_2025.Config;

    /// @dev For running from `forge script`. Provide the deployer private key through env var.
    function run() public virtual {
        run(
            vm.envUint("GUARDIAN_BORG_DELEGATE_PRIVATE_KEY"),
            ZkSyncGuardianCompensation2024_2025.PartyInfo({
                name: "Alice",
                evmAddress: 0x48d206948C366396a86A449DdD085FDbfC280B4b,
                contactDetails: "email@company.com",
                _type: "individual"
            }),
            ZkSyncGuardianCompensation2024_2025.getDefault()
        );
    }

    /// @dev For running in tests
    function run(
        uint256 proposerPrivateKey,
        ZkSyncGuardianCompensation2024_2025.PartyInfo memory guardianInfo,
        ZkSyncGuardianCompensation2024_2025.Config memory config
    ) public virtual returns(bytes32) {
        return run(
            proposerPrivateKey, guardianInfo,
            // Default guardian allocations
            config._parseAllocation(address(config.zkToken), config.metavestVestingAndUnlockStartTime),
            config
        );
    }

    /// @dev For running in tests
    function run(
        uint256 proposerPrivateKey,
        ZkSyncGuardianCompensation2024_2025.PartyInfo memory guardianInfo,
        BaseAllocation.Allocation memory allocation,
        ZkSyncGuardianCompensation2024_2025.Config memory config
    ) public virtual returns(bytes32) {

        address proposer = vm.addr(proposerPrivateKey);

        // Assume Guardian SAFE already delegate signing to the deployer

        // Propose a new deal

        uint48 startTime = config.metavestVestingAndUnlockStartTime;

        address[] memory parties = new address[](2);
        parties[0] = address(config.guardianSafe);
        parties[1] = guardianInfo.evmAddress;

        string[] memory globalValues = config._compFormatGlobalValues(
            vm,
            address(config.guardianSafe),
            guardianInfo.evmAddress,
            address(config.zkToken),
            startTime
        );
        string[][] memory partyValues = ZkSyncGuardianCompensation2024_2025._compFormatPartyValues(
            vm,
            config.guardianSafeInfo,
            guardianInfo
        );

        uint256 agreementSalt = block.timestamp;

        bytes32 expectedContractId = keccak256(
            abi.encode(
                config.compTemplateId,
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
            config.compAgreementUri,
            config.compGlobalFields,
            config.compPartyFields,
            globalValues,
            partyValues[0],
            proposerPrivateKey
        );

        vm.startBroadcast(proposerPrivateKey);

        bytes32 contractId = config.controller.proposeAndSignDeal(
            config.compTemplateId,
            agreementSalt,
            metavestController.metavestType.Vesting,
            guardianInfo.evmAddress,
            allocation,
            config.milestones,
            globalValues,
            parties,
            partyValues,
            signature,
            bytes32(0), // no secrets
            block.timestamp + 30 days * 2
        );

        vm.stopBroadcast();

        console.log("Proposer: ", proposer);
        console.log("Guardian Safe: ", address(config.guardianSafe));
        console.log("ZK token: ", address(config.zkToken));
        console.log("CyberAgreementRegistry: ", address(config.registry));
        console.log("VestingAllocationFactory: ", address(config.vestingAllocationFactory));
        console.log("MetavesTController: ", address(config.controller));
        console.log("ZkCappedMinterV2: ", address(config.zkCappedMinter));
        console.log("Created:");
        console.log("  Agreement ID:");
        console.logBytes32(contractId);

        return contractId;
    }
}
