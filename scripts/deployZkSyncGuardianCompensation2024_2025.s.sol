// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.24;

import {ZkSyncGuardianCompensationConfig2024_2025} from "./lib/ZkSyncGuardianCompensationConfig2024_2025.sol";
import {ISafeProxyFactory, IGnosisSafe, GnosisTransaction} from "../test/lib/safe.sol";
import {BorgAuth} from "cybercorps-contracts/src/libs/auth.sol";
import {CyberAgreementRegistry} from "cybercorps-contracts/src/CyberAgreementRegistry.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {IZkCappedMinterV2} from "../src/interfaces/zk-governance/IZkCappedMinterV2.sol";
import {SafeTxHelper} from "./lib/SafeTxHelper.sol";
import {Script} from "forge-std/Script.sol";
import {VestingAllocationFactory} from "../src/VestingAllocationFactory.sol";
import {console2} from "forge-std/console2.sol";
import {metavestController} from "../src/MetaVesTController.sol";

contract DeployZkSyncGuardianCompensation2024_2025Script is ZkSyncGuardianCompensationConfig2024_2025, SafeTxHelper, Script {
    // Assume zkSync Era mainnet @ 64166260

    /// @dev For running from `forge script`. Provide the deployer private key through env var.
    function run() public virtual {
        run(
            vm.envUint("DEPLOYER_PRIVATE_KEY"),
            registry,
            vestingAllocationFactory
        );
    }

    /// @dev For running in tests
    function run(
        uint256 deployerPrivateKey,
        CyberAgreementRegistry _registry,
        VestingAllocationFactory _vestingAllocationFactory
    ) public virtual returns(
        metavestController,
        GnosisTransaction[] memory
    ) {
        address deployer = vm.addr(deployerPrivateKey);
        registry = _registry;
        vestingAllocationFactory = _vestingAllocationFactory;

        string memory saltStr = "MetaLexMetaVestZkSyncGuardianCompensationLaunchV1.0.2024-2025";
        bytes32 salt = keccak256(bytes(saltStr));

        vm.startBroadcast(deployerPrivateKey);

        // Deploy MetaVesT Controller

        metavestController controller = metavestController(address(new ERC1967Proxy{salt: salt}(
            address(new metavestController{salt: salt}()),
            abi.encodeWithSelector(
                metavestController.initialize.selector,
                address(guardianSafe),
                address(guardianSafe),
                address(registry),
                address(vestingAllocationFactory)
            )
        )));

        vm.stopBroadcast();

        // Prepare Guardian SAFE txs to:
        // 1. Grant MetaVesT Controller MINTER ROLE
        // 2. Set MetaVesT Controller's ZK Capped Minter
        GnosisTransaction[] memory safeTxs = new GnosisTransaction[](2);
        safeTxs[0] = GnosisTransaction({
            to: address(zkCappedMinter),
            value: 0,
            data: abi.encodeWithSelector(
                IZkCappedMinterV2.grantRole.selector,
                zkCappedMinter.MINTER_ROLE(),
                address(controller)
            )
        });
        safeTxs[1] = GnosisTransaction({
            to: address(controller),
            value: 0,
            data: abi.encodeWithSelector(
                controller.setZkCappedMinter.selector,
                address(zkCappedMinter)
            )
        });

        // Output logs

        console2.log("Deployer: ", deployer);
        console2.log("salt: ", saltStr);
        console2.log("Guardian Safe: ", address(guardianSafe));
        console2.log("CyberAgreementRegistry: ", address(registry));
        console2.log("VestingAllocationFactory: ", address(vestingAllocationFactory));
        console2.log("");

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
