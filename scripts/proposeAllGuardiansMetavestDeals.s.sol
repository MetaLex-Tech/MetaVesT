// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.24;

import {ZkSyncGuardianCompensation2024_2025} from "./lib/ZkSyncGuardianCompensation2024_2025.sol";
import {ZkSyncGuardianCompensationSepolia2024_2025} from "./lib/ZkSyncGuardianCompensationSepolia2024_2025.sol";
import {ProposeMetaVestDealScript} from "./proposeMetavestDeal.s.sol";
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

contract ProposeAllGuardiansMetaVestDealScript is ProposeMetaVestDealScript {
    /// @dev For running from `forge script`. Provide the deployer private key through env var.
    function run() public override {
        run(
            vm.envUint("GUARDIAN_BORG_DELEGATE_PRIVATE_KEY"),

            // zkSync Sepolia for 2024-2025
            ZkSyncGuardianCompensationSepolia2024_2025.getDefault(vm)
        );
    }

    /// @dev For running in tests
    function run(
        uint256 proposerPrivateKey,
        ZkSyncGuardianCompensation2024_2025.Config memory config
    ) public virtual returns(bytes32[] memory) {

        address proposer = vm.addr(proposerPrivateKey);

        console2.log("");
        console2.log("=== ProposeAllGuardiansMetaVestDealScript ===");
        console2.log("Proposer: ", proposer);
        console2.log("CyberAgreementRegistry: ", address(config.registry));
        console2.log("VestingAllocationFactory: ", address(config.vestingAllocationFactory));
        console2.log("MetavesTController: ", address(config.controller));
        console2.log("");

        bytes32[] memory agreementIds = new bytes32[](config.guardians.length);

        for (uint256 i = 0; i < config.guardians.length; i++) {
            console2.log("Proposing to Guardian #%d", i + 1);
            console2.log("  name:", config.guardians[i].name);
            console2.log("  address:", config.guardians[i].evmAddress);
            console2.log("");

            agreementIds[i] = run(
                proposerPrivateKey,
                config.guardians[i],
                config
            );
        }
        
        console2.log("Created:");
        for (uint256 i = 0; i < agreementIds.length; i++) {
            console2.log("  Agreement ID #%d:", i + 1);
            console2.logBytes32(agreementIds[i]);
            console2.log("");
        }

        return agreementIds;
    }
}
