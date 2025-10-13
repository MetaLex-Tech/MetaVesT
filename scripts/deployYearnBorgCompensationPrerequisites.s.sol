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

contract DeployYearnBorgCompensationPrerequisitesScript is SafeTxHelper, Script {
    using YearnBorgCompensation2025_2026 for YearnBorgCompensation2025_2026.Config;

    /// @dev For running from `forge script`. Provide the deployer private key through env var.
    function run() public virtual {
        deployPrerequisites(
            vm.envUint("DEPLOYER_PRIVATE_KEY"),

            // Ethereum mainnet
            "MetaLexMetaVestYearnBorgCompensationLaunchV1.0",
            YearnBorgCompensation2025_2026.getDefault(vm)
        );
    }

    /// @dev For running in tests
    function deployPrerequisites(
        uint256 deployerPrivateKey,
        string memory saltStr,
        YearnBorgCompensation2025_2026.Config memory config
    ) public virtual returns(
        VestingAllocationFactory
    ) {
        address deployer = vm.addr(deployerPrivateKey);

        console2.log("");
        console2.log("=== DeployYearnBorgCompensationPrerequisitesScript ===");
        console2.log("Deployer: ", deployer);
        console2.log("Salt string: ", saltStr);
        console2.log("");

        bytes32 salt = keccak256(bytes(saltStr));

        vm.startBroadcast(deployerPrivateKey);

        // Deploy MetaVesT pre-requisites

        VestingAllocationFactory vestingAllocationFactory = new VestingAllocationFactory{salt: salt}();

        vm.stopBroadcast();

        // Output logs

        console2.log("Deployed addresses:");
        console2.log("  VestingAllocationFactory: ", address(vestingAllocationFactory));
        console2.log("");

        return vestingAllocationFactory;
    }
}
