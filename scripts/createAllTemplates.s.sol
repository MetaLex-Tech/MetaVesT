// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.24;

import {YearnBorgCompensation2025_2026} from "./lib/YearnBorgCompensation2025_2026.sol";
import {ISafeProxyFactory, IGnosisSafe, GnosisTransaction} from "../test/lib/safe.sol";
import {BorgAuth} from "cybercorps-contracts/src/libs/auth.sol";
import {CyberAgreementRegistry} from "cybercorps-contracts/src/CyberAgreementRegistry.sol";
import {ERC1967Proxy} from "openzeppelin-contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {SafeTxHelper} from "./lib/SafeTxHelper.sol";
import {Script} from "forge-std/Script.sol";
import {VestingAllocationFactory} from "../src/VestingAllocationFactory.sol";
import {console2} from "forge-std/console2.sol";
import {metavestController} from "../src/MetaVesTController.sol";

contract CreateAllTemplatesScript is SafeTxHelper, Script {
    /// @dev For running from `forge script`
    function run() public virtual {
        // zkSync mainnet
        run(YearnBorgCompensation2025_2026.getDefault(vm));
    }

    /// @dev For running in tests
    function run(
        YearnBorgCompensation2025_2026.Config memory config
    ) public virtual returns(GnosisTransaction[] memory) {
        IGnosisSafe safe;
        YearnBorgCompensation2025_2026.Config memory config;

        // zkSync Era (zkSync Guardians)
        config = YearnBorgCompensation2025_2026.getDefault(vm);

        safe = config.borgSafe;

        GnosisTransaction[] memory safeTxs = new GnosisTransaction[](config.compRecipients.length);
        for (uint i = 0; i < config.compRecipients.length ; i++) {
            YearnBorgCompensation2025_2026.CompInfo memory guardian = config.compRecipients[i];
            safeTxs[i] = GnosisTransaction({
                to: address(config.registry),
                value: 0 ether,
                data: abi.encodeWithSelector(
                    CyberAgreementRegistry.createTemplate.selector,
                    guardian.compTemplate.id,
                    guardian.compTemplate.name,
                    guardian.compTemplate.agreementUri,
                    guardian.compTemplate.globalFields,
                    guardian.compTemplate.partyFields
                )
            });
        }

        // Output logs

        console2.log("");
        console2.log("=== CreateAllTemplatesScript ===");
        console2.log("Safe: ", address(safe));
        console2.log("Safe TXs:");
        for (uint256 i = 0 ; i < safeTxs.length ; i++) {
            console2.log("  #", i);
            console2.log("    to:", safeTxs[i].to);
            console2.log("    value:", safeTxs[i].value);
            console2.log("    data:");
            console2.logBytes(safeTxs[i].data);
            console2.log("");
        }

        return safeTxs;
    }
}
