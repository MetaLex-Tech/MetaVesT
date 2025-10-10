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

contract DeployYearnBorgCompensationScript is SafeTxHelper, Script {
    /// @dev For running from `forge script`. Provide the deployer private key through env var.
    function run() public virtual {
        deployCompensation(
            vm.envUint("DEPLOYER_PRIVATE_KEY"),

            // Ethereum mainnet for 2025-2026
            "MetaLexMetaVestYearnBorgCompensationLaunchV1.0.2025-2026",
            YearnBorgCompensation2025_2026.getDefault(vm)
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
                address(config.vestingAllocationFactory)
            )
        )));

        vm.stopBroadcast();

        // TODO WIP: re-purpose to provision USDC funds
        // Prepare Guardian SAFE txs to:
        // 1. Grant MetaVesT Controller MINTER ROLE
        // 2. Set MetaVesT Controller's ZK Capped Minter
        GnosisTransaction[] memory safeTxs = new GnosisTransaction[](2);
//        safeTxs[0] = GnosisTransaction({
//            to: address(config.zkCappedMinter),
//            value: 0,
//            data: abi.encodeWithSelector(
//                IZkCappedMinterV2.grantRole.selector,
//                config.zkCappedMinter.MINTER_ROLE(),
//                address(controller)
//            )
//        });
//        safeTxs[1] = GnosisTransaction({
//            to: address(controller),
//            value: 0,
//            data: abi.encodeWithSelector(
//                controller.setZkCappedMinter.selector,
//                address(config.zkCappedMinter)
//            )
//        });

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
