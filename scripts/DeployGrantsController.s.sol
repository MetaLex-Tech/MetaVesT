// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.24;

import {Script} from "forge-std/Script.sol";
import {console2} from "forge-std/console2.sol";
import {ERC1967Proxy} from "openzeppelin-contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {BorgAuth} from "cybercorps-contracts/src/libs/auth.sol";
import {CyberAgreementRegistry} from "cybercorps-contracts/src/CyberAgreementRegistry.sol";
import {MetaVesTControllerFactory} from "../src/MetaVesTControllerFactory.sol";
import {metavestController} from "../src/MetaVesTController.sol";

/// @title DeployGrantsController
/// @notice Deploys a registry-gated MetaVesT controller for cyberCORPs equity-award grants.
///         Chain-agnostic — run against Base (8453) or Ethereum mainnet (1) by selecting the
///         RPC: `forge script ... --rpc-url base` or `--rpc-url ethereum`.
///
/// The deploy is permissionless: the signer can be any funded throwaway EOA — it never
/// becomes the authority. Provide the signer on the CLI (so no raw key sits in env):
///   --private-key 0x<64-hex>           OR
///   --account <name> --sender 0x<addr> (encrypted keystore via `cast wallet import`) OR
///   --ledger --sender 0x<addr>
/// `authority` (who controls grants) is the GRANT_AUTHORITY you pass (the corp officer/
/// BorgAuth address). The factory is governed by the registry's own BorgAuth (registry.AUTH()).
///
/// The vesting scrip is NOT deployed here — that is a corp-owner op via the corp's
/// IssuanceManager.deployCyberScrip (force-ops off for allocation-authority mode).
///
/// Env:
///   CYBER_AGREEMENT_REGISTRY  the CyberAgreementRegistry on the target chain
///   GRANT_AUTHORITY           the corp officer/BorgAuth address that will control grants
///   GRANT_DAO                 optional condition/governance contract (default 0x0)
///   FACTORY                   optional existing MetaVesTControllerFactory; 0x0 => deploy a new one
///   SALT                      CREATE2 salt string (vary per corp for distinct addresses)
contract DeployGrantsController is Script {
    function run() public {
        CyberAgreementRegistry registry =
            CyberAgreementRegistry(vm.envAddress("CYBER_AGREEMENT_REGISTRY"));
        address authority = vm.envAddress("GRANT_AUTHORITY");
        address dao = vm.envOr("GRANT_DAO", address(0));
        address existingFactory = vm.envOr("FACTORY", address(0));
        bytes32 salt = keccak256(bytes(vm.envOr("SALT", string("metalex-grants-v1"))));

        BorgAuth auth = registry.AUTH();

        console2.log("=== DeployGrantsController ===");
        console2.log("chainid:           ", block.chainid);
        console2.log("deployer (sender): ", msg.sender);
        console2.log("registry:          ", address(registry));
        console2.log("registry AUTH:     ", address(auth));
        console2.log("grant authority:   ", authority);
        console2.log("dao:               ", dao);

        require(authority != address(0), "GRANT_AUTHORITY required");

        vm.startBroadcast();

        MetaVesTControllerFactory factory;
        if (existingFactory == address(0)) {
            // Implementations + factory proxy use plain CREATE (nonce-based) so a
            // re-run never collides; salt determinism is reserved for the per-corp
            // controller below. One factory per (chain, registry) — reuse via FACTORY=.
            factory = MetaVesTControllerFactory(address(new ERC1967Proxy(
                address(new MetaVesTControllerFactory()),
                abi.encodeWithSelector(
                    MetaVesTControllerFactory.initialize.selector,
                    address(auth),
                    address(registry),
                    address(new metavestController())
                )
            )));
            console2.log("deployed factory:  ", address(factory));
        } else {
            factory = MetaVesTControllerFactory(existingFactory);
            console2.log("using factory:     ", address(factory));
        }

        address controller = factory.deployMetavestController(salt, authority, dao);

        vm.stopBroadcast();

        console2.log("");
        console2.log(">>> controller:    ", controller);
        console2.log(">>> factory:       ", address(factory));
        console2.log("Record `controller` as the corp's metaVestController, and reuse `factory` (FACTORY=) for other corps on this chain.");
    }
}
