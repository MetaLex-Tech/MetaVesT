// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.24;

import {YearnBorgCompensation2025_2026} from "./lib/YearnBorgCompensation2025_2026.sol";
import {YearnBorgCompensationSepolia2025_2026} from "./lib/YearnBorgCompensationSepolia2025_2026.sol";
import {ISafeProxyFactory, IGnosisSafe, GnosisTransaction} from "../test/lib/safe.sol";
import {BorgAuth} from "cybercorps-contracts/src/libs/auth.sol";
import {CyberAgreementRegistry} from "cybercorps-contracts/src/CyberAgreementRegistry.sol";
import {ERC1967Proxy} from "openzeppelin-contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {ERC20} from "openzeppelin-contracts/token/ERC20/ERC20.sol";
import {SafeTxHelper} from "./lib/SafeTxHelper.sol";
import {Script} from "forge-std/Script.sol";
import {VestingAllocationFactory} from "../src/VestingAllocationFactory.sol";
import {console2} from "forge-std/console2.sol";
import {metavestController} from "../src/MetaVesTController.sol";

contract DeployYearnBorgCompensationScript is SafeTxHelper, Script {
    /// @dev For running from `forge script`. Provide the deployer private key through env var.
    function run() public virtual {
        deployCompensation(
            vm.envUint("DEPLOYER_PRIVATE_KEY"),

//            // Ethereum mainnet for 2025-2026
//            "MetaLexMetaVestYearnBorgCompensationLaunchV1.0.2025-2026",
//            YearnBorgCompensation2025_2026.getDefault(vm)

            // Sepolia testnet
            "MetaLexMetaVestYearnBorgCompensationLaunch-testnet-V0.1",
            YearnBorgCompensationSepolia2025_2026.getDefault(vm)
        );
    }

    /// @dev For running in tests
    function deployCompensation(
        uint256 deployerPrivateKey,
        string memory saltStr,
        YearnBorgCompensation2025_2026.Config memory config
    ) public virtual returns(
        metavestController,
        GnosisTransaction[] memory
    ) {
        address deployer = vm.addr(deployerPrivateKey);

        console2.log("");
        console2.log("=== DeployYearnBorgCompensationScript ===");
        console2.log("Deployer: ", deployer);
        console2.log("Salt string: ", saltStr);
        console2.log("Guardian Safe: ", address(config.borgSafe));
        console2.log("CyberAgreementRegistry: ", address(config.registry));
        console2.log("VestingAllocationFactory: ", address(config.vestingAllocationFactory));
        console2.log("");

        bytes32 salt = keccak256(bytes(saltStr));

        vm.startBroadcast(deployerPrivateKey);

        // Deploy MetaVesT Controller

        metavestController controller = metavestController(address(new ERC1967Proxy{salt: salt}(
            address(new metavestController{salt: salt}()),
            abi.encodeWithSelector(
                metavestController.initialize.selector,
                address(config.borgSafe),
                address(config.borgSafe),
                address(config.registry),
                address(config.vestingAllocationFactory),
                address(config.tokenOptionFactory),
                address(config.restrictedTokenFactory)
            )
        )));

        vm.stopBroadcast();

        // Prepare BORG SAFE txs to:
        // 1. Approve paymentToken spending from metavestController
        // 2. Delegate agreement signing to an EOA
        GnosisTransaction[] memory safeTxs = new GnosisTransaction[](2);
        safeTxs[0] = GnosisTransaction({
            to: address(config.paymentToken),
            value: 0,
            data: abi.encodeWithSelector(
                ERC20.approve.selector,
                address(controller),
                config.paymentTokenApprovalCap
            )
        });
        safeTxs[1] = GnosisTransaction({
            to: address(config.registry),
            value: 0,
            data: abi.encodeWithSelector(
                CyberAgreementRegistry.setDelegation.selector,
                config.borgAgreementDelegate,
                block.timestamp + 14 days
            )
        });

        // Output logs

        console2.log("Deployed addresses:");
        console2.log("  MetavesTController: ", address(controller));
        console2.log("");

        console2.log("Safe TXs:");
        for (uint256 i = 0 ; i < safeTxs.length ; i++) {
            console2.log("  #", i);
            console2.log("    to:", safeTxs[i].to);
            console2.log("    value:", safeTxs[i].value);
            console2.log("    data:");
            console2.logBytes(safeTxs[i].data);
            console2.log("");
        }

        return (controller, safeTxs);
    }
}
