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

contract ExecuteSafeTxScript is SafeTxHelper, Script {
    /// @dev For running from `forge script`. Provide the deployer private key through env var.
    function run() public virtual {
        run(
            vm.envUint("DEPLOYER_PRIVATE_KEY"),

//            ZkSyncGuardianCompensationSepolia2024_2025.getDefault().guardianSafe, // safe
//            0x6F26e588f28bf67C016EEA19CA90c4E41B70d499, // to
//            0, // value
//            hex"2f2ff15d9f2df0fed2c77648de5860a4cc508cd0818c85b8b8a1ab4ceeef8d981c8956a6000000000000000000000000856a8aea8a37a338e2490384bb790cd87b5caae4" // data

//            ZkSyncGuardianCompensationSepolia2024_2025.getDefault().guardianSafe, // safe
//            0x856A8Aea8a37A338e2490384Bb790cD87b5CaaE4, // to
//            0, // value
//            hex"66e261840000000000000000000000006f26e588f28bf67c016eea19ca90c4e41b70d499" // data

            ZkSyncGuardianCompensationSepolia2024_2025.getDefault().guardianSafe, // safe
            address(ZkSyncGuardianCompensationSepolia2024_2025.getDefault().registry), // to
            0, // value
            abi.encodeWithSelector(
                CyberAgreementRegistry.setDelegation.selector,
                0x5ff4e90Efa2B88cf3cA92D63d244a78a88219Abf,
                block.timestamp + 365 days * 3 // This is a hack, one should not delegate signing for this long
            ) // data
        );
    }

    /// @dev For running in tests
    function run(
        uint256 deployerPrivateKey,
        IGnosisSafe safe,
        address to,
        uint256 value,
        bytes memory data
    ) public virtual {
        address deployer = vm.addr(deployerPrivateKey);

        console2.log("");
        console2.log("=== ExecuteSafeTxScript ===");
        console2.log("Deployer: ", deployer);
        console2.log("SAFE: ", address(safe));
        console2.log("to: ", to);
        console2.log("value: ", value);
        console2.log("data: ");
        console2.logBytes(data);
        console2.log("");

        vm.startBroadcast(deployerPrivateKey);

        // Guardian SAFE to set MetaVesT Controller's ZK Capped Minter
        _signAndExecSafeTransaction(
            deployerPrivateKey,
            address(safe),
            to,
            value,
            data
        );

        vm.stopBroadcast();
    }
}
