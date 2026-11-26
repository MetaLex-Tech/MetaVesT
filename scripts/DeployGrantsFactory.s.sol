// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.24;

import {Script} from "forge-std/Script.sol";
import {console2} from "forge-std/console2.sol";
import {ERC1967Proxy} from "openzeppelin-contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {BorgAuth} from "cybercorps-contracts/src/libs/auth.sol";
import {CyberAgreementRegistry} from "cybercorps-contracts/src/CyberAgreementRegistry.sol";
import {MetaVesTControllerFactory} from "../src/MetaVesTControllerFactory.sol";
import {metavestController} from "../src/MetaVesTController.sol";

/// @title DeployGrantsFactory
/// @notice Deploys only the shared MetaVesT controller factory for cyberCORPs grants on one
///         chain. It does the same factory deploy as DeployGrantsController.s.sol, but it does
///         not deploy a controller for a company. Each company's controller is deployed later,
///         on demand, from the app.
///
/// The deploy is permissionless. The signer can be any funded EOA and never becomes an
/// authority: the factory is governed by the registry's own BorgAuth (registry.AUTH()).
/// Give the signer on the CLI, not in env:
///   --ledger --sender 0x<addr>  OR  --account <name> --sender 0x<addr>  OR  --private-key 0x<hex>
///
/// Linked libraries that are not yet on the chain are deployed by forge through the
/// deterministic CREATE2 deployer. With the same compiler output, they land at the same
/// addresses as on Ethereum and Base.
///
/// Env:
///   CYBER_AGREEMENT_REGISTRY  the CyberAgreementRegistry on the target chain
///   EXPECTED_AUTH             optional; when set, the run refuses unless registry.AUTH() matches
///   CREATE2_SALT              optional bytes32; when set, all creations go through the CREATE2
///                             deployer with this salt (use this for smart-contract wallets)
contract DeployGrantsFactory is Script {
    function run() public {
        CyberAgreementRegistry registry = CyberAgreementRegistry(vm.envAddress("CYBER_AGREEMENT_REGISTRY"));
        BorgAuth auth = registry.AUTH();
        address expectedAuth = vm.envOr("EXPECTED_AUTH", address(0));
        require(address(auth) != address(0), "registry AUTH is zero");
        require(expectedAuth == address(0) || address(auth) == expectedAuth, "registry AUTH mismatch");

        console2.log("=== DeployGrantsFactory ===");
        console2.log("chainid:           ", block.chainid);
        console2.log("deployer (sender): ", msg.sender);
        console2.log("registry:          ", address(registry));
        console2.log("registry AUTH:     ", address(auth));

        // CREATE2 mode sends every creation through the deterministic CREATE2 deployer, so a
        // smart-contract wallet can deploy and the addresses do not depend on the signer.
        bytes32 salt = vm.envOr("CREATE2_SALT", bytes32(0));
        address factoryImplementation;
        address refImplementation;
        MetaVesTControllerFactory factory;

        vm.startBroadcast();
        if (salt == bytes32(0)) {
            factoryImplementation = address(new MetaVesTControllerFactory());
            refImplementation = address(new metavestController());
        } else {
            factoryImplementation = address(new MetaVesTControllerFactory{salt: salt}());
            refImplementation = address(new metavestController{salt: salt}());
        }
        bytes memory init = abi.encodeWithSelector(
            MetaVesTControllerFactory.initialize.selector, address(auth), address(registry), refImplementation
        );
        factory = MetaVesTControllerFactory(
            salt == bytes32(0)
                ? address(new ERC1967Proxy(factoryImplementation, init))
                : address(new ERC1967Proxy{salt: salt}(factoryImplementation, init))
        );
        vm.stopBroadcast();

        require(address(factory.AUTH()) == address(auth), "factory AUTH mismatch");

        require(factory.getRegistry() == address(registry), "factory registry mismatch");
        require(factory.getRefImplementation() == refImplementation, "factory ref implementation mismatch");

        console2.log("");
        console2.log(">>> factory (proxy):          ", address(factory));
        console2.log(">>> factoryImplementation:    ", factoryImplementation);
        console2.log(">>> refImplementation:        ", refImplementation);
        console2.log("Pin these in metalex-webapp METAVEST_GRANTS_FACTORY and METAVEST_GRANTS_FACTORY_CONFIG.");
    }
}
