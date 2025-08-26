// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.24;

import {ZkSyncGuardianCompensation2024_2025} from "./lib/ZkSyncGuardianCompensation2024_2025.sol";
import {ZkSyncGuardianCompensationSepolia2024_2025} from "./lib/ZkSyncGuardianCompensationSepolia2024_2025.sol";
import {ISafeProxyFactory, IGnosisSafe, GnosisTransaction} from "../test/lib/safe.sol";
import {BorgAuth} from "cybercorps-contracts/src/libs/auth.sol";
import {CyberAgreementRegistry} from "cybercorps-contracts/src/CyberAgreementRegistry.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {ZkCappedMinterV2} from "zk-governance/l2-contracts/src/ZkCappedMinterV2.sol";
import {IZkCappedMinterV2Factory} from "../src/interfaces/zk-governance/IZkCappedMinterV2Factory.sol";
import {SafeTxHelper} from "./lib/SafeTxHelper.sol";
import {Script} from "forge-std/Script.sol";
import {VestingAllocationFactory} from "../src/VestingAllocationFactory.sol";
import {console2} from "forge-std/console2.sol";
import {metavestController} from "../src/MetaVesTController.sol";

contract DeployTestZkCappedMinterScript is SafeTxHelper, Script {
    /// @dev For running from `forge script`. Provide the deployer private key through env var.
    function run() public virtual {
        run(
            vm.envUint("DEPLOYER_PRIVATE_KEY"),

            // zkSync Sepolia for 2024-2025
            "MetaLexMetaVestZkSyncGuardianCompensationTestnetV0.1.2024-2025",
            IZkCappedMinterV2Factory(0x329CE320a0Ef03F8c0E01195604b5ef7D3Fb150E),
            ZkSyncGuardianCompensationSepolia2024_2025.getDefault()

            // zkSync Sepolia for 2025-2026
//            "MetaLexMetaVestZkSyncGuardianCompensationTestnetV0.1.2025-2026",
//            IZkCappedMinterV2Factory(0x329CE320a0Ef03F8c0E01195604b5ef7D3Fb150E),
//            ZkSyncGuardianCompensationSepolia2025_2026.getDefault()
        );
    }

    /// @dev For running in tests
    function run(
        uint256 deployerPrivateKey,
        string memory saltStr,
        IZkCappedMinterV2Factory zkCappedMinterFactory,
        ZkSyncGuardianCompensation2024_2025.Config memory config
    ) public virtual returns(
        address
    ) {
        address deployer = vm.addr(deployerPrivateKey);

        uint256 startTime = block.timestamp + 5 minutes;

        console2.log("");
        console2.log("=== DeployTestZkCappedMinterScript ===");
        console2.log("Deployer: ", deployer);
        console2.log("Salt string: ", saltStr);
        console2.log("Start time: ", startTime);
        console2.log("ZK Token: ", address(config.zkToken));
        console2.log("Guardian SAFE: ", address(config.guardianSafe));
        console2.log("");

        bytes32 salt = keccak256(bytes(saltStr));

        vm.startBroadcast(deployerPrivateKey);

        // Deploy MetaVesT Controller

        ZkCappedMinterV2 zkCappedMinter = ZkCappedMinterV2(zkCappedMinterFactory.createCappedMinter(
            address(config.zkToken),
            address(config.guardianSafe),
            8.5e6 ether,
            uint48(startTime),
            uint48(startTime + 365 days * 2),
            uint256(salt)
        ));

        // Grant capped minter permission

        config.zkToken.grantRole(config.zkToken.MINTER_ROLE(), address(zkCappedMinter));

        vm.stopBroadcast();

        // Output logs

        console2.log("Deployed addresses:");
        console2.log("  ZK Capped Minter v2: ", address(zkCappedMinter));
        console2.log("");

        return address(zkCappedMinter);
    }
}
