// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {ERC1967Proxy} from "openzeppelin-contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {UUPSUpgradeable} from "openzeppelin-contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import {Initializable} from "openzeppelin-contracts-upgradeable/proxy/utils/Initializable.sol";
import {BorgAuth} from "cybercorps-contracts/src/libs/auth.sol";
import {CyberAgreementRegistry} from "cybercorps-contracts/src/CyberAgreementRegistry.sol";
import {MetaVesTControllerFactory} from "../src/MetaVesTControllerFactory.sol";
import {metavestController} from "../src/MetaVesTController.sol";
import {ERC1967ProxyLib} from "./lib/ERC1967ProxyLib.sol";

contract MockRefImplementation is UUPSUpgradeable {
    string public constant DEPLOY_VERSION = "test";

    // UUPS upgrade authorization
    function _authorizeUpgrade(
        address newImplementation
    ) internal override {}
}

contract MetaVesTControllerFactoryTest is Test {
    using ERC1967ProxyLib for address;

    bytes32 salt = keccak256("MetaVesTControllerFactoryTest");

    BorgAuth auth;
    CyberAgreementRegistry registry;
    MetaVesTControllerFactory metavestControllerFactory;
    address refImplAddr;

    uint256 deployerPrivateKey;
    address deployer;
    uint256 alicePrivateKey;
    address alice;
    uint256 bobPrivateKey;
    address bob;

    function setUp() public {
        (deployer, deployerPrivateKey) = makeAddrAndKey("deployer");
        (alice, alicePrivateKey) = makeAddrAndKey("alice");
        (bob, bobPrivateKey) = makeAddrAndKey("bob");

        auth = new BorgAuth{salt: salt}(deployer);
        registry = CyberAgreementRegistry(address(new ERC1967Proxy{salt: salt}(
            address(new CyberAgreementRegistry{salt: salt}()),
            abi.encodeWithSelector(
                CyberAgreementRegistry.initialize.selector,
                address(auth)
            )
        )));

        // create2 all the way down so the outcome is consistent
        refImplAddr = address(new metavestController{salt: salt}());
        metavestControllerFactory = MetaVesTControllerFactory(address(new ERC1967Proxy{salt: salt}(
            address(new MetaVesTControllerFactory{salt: salt}()),
            abi.encodeWithSelector(
                MetaVesTControllerFactory.initialize.selector,
                address(auth),
                address(registry),
                refImplAddr
            )
        )));
    }

    function test_sanityCheck() public {
        assertEq(address(metavestControllerFactory.AUTH()), address(auth), "unexpected auth");
        assertEq(metavestControllerFactory.getRegistry(), address(registry), "unexpected registry");
        // Make sure reference implementation address is also create2()
        assertEq(metavestControllerFactory.getRefImplementation(), refImplAddr, "unexpected reference implementation");
    }

    function test_RevertIf_InitializeImplementation() public {
        MetaVesTControllerFactory impl = new MetaVesTControllerFactory();
        vm.expectRevert(Initializable.InvalidInitialization.selector);
        impl.initialize(
            address(0), // no-op
            address(0), // no-op
            address(0) // no-op
        );
    }

    /// @notice Should be able to deploy a MetavestController with correct parameters
    function test_deployMetavestController() public {
        vm.expectEmit(true, true, true, true, address(metavestControllerFactory));
        emit MetaVesTControllerFactory.MetaVesTControllerDeployed(
            metavestControllerFactory.computeMetavestControllerAddress(salt, alice, bob),
            alice,
            bob
        );
        metavestController controller = metavestController(metavestControllerFactory.deployMetavestController(
            salt,
            alice, // authority
            bob // dao
        ));
        assertEq(controller.authority(), alice, "unexpected authority");
        assertEq(controller.dao(), bob, "unexpected dao");
        assertEq(controller.registry(), address(registry), "unexpected registry");
        assertEq(controller.upgradeFactory(), address(metavestControllerFactory), "unexpected factory");
    }

    /// @notice Should be able to deterministically compute the MetevestController address
    function test_computeMetavestControllerAddress() public {
        assertEq(
            metavestControllerFactory.computeMetavestControllerAddress(salt, alice, bob),
            metavestControllerFactory.deployMetavestController(salt, alice, bob),
            "unexpected deployed address"
        );
    }

    function test_setRegistry() public {
        address newRegistry = address(123); // no-op
        vm.expectEmit(true, true, true, true, address(metavestControllerFactory));
        emit MetaVesTControllerFactory.RegistrySet(newRegistry);
        vm.prank(deployer);
        metavestControllerFactory.setRegistry(newRegistry);
        assertEq(metavestControllerFactory.getRegistry(), newRegistry, "unexpected registry");
    }

    function test_RevertIf_setRegistryNotOwner() public {
        vm.expectRevert(abi.encodeWithSelector(BorgAuth.BorgAuth_NotAuthorized.selector, auth.OWNER_ROLE(), alice));
        vm.prank(alice);
        metavestControllerFactory.setRegistry(address(123));
    }

    function test_setRefImplementation() public {
        address newRefImplementation = address(new MockRefImplementation());
        vm.expectEmit(true, true, true, true, address(metavestControllerFactory));
        emit MetaVesTControllerFactory.RefImplementationSet(newRefImplementation, "test");
        vm.prank(deployer);
        metavestControllerFactory.setRefImplementation(newRefImplementation);
        assertEq(metavestControllerFactory.getRefImplementation(), newRefImplementation, "unexpected reference implementation");
    }

    function test_RevertIf_setRefImplementationNotOwner() public {
        vm.expectRevert(abi.encodeWithSelector(BorgAuth.BorgAuth_NotAuthorized.selector, auth.OWNER_ROLE(), alice));
        vm.prank(alice);
        metavestControllerFactory.setRefImplementation(address(123));
    }

    function test_Upgrade() public {
        address newImpl = address(new MetaVesTControllerFactory());
        vm.startPrank(deployer);
        metavestControllerFactory.upgradeToAndCall(newImpl, "");
        vm.stopPrank();
        assertEq(
            address(metavestControllerFactory).getErc1967Implementation(),
            newImpl,
            "unexpected implementation"
        );
    }

    function test_RevertIf_UpgradeFactoryNonOwner() public {
        vm.expectRevert(abi.encodeWithSelector(BorgAuth.BorgAuth_NotAuthorized.selector, auth.OWNER_ROLE(), alice));
        vm.prank(alice);
        metavestControllerFactory.upgradeToAndCall(address(123), "");
    }
}
