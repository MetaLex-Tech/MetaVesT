//SPDX-License-Identifier: AGPL-3.0-only

/*
************************************
                            MetaVesTFactory
                                    ************************************
                                                                      */

pragma solidity ^0.8.24;

import {metavestController} from "./MetaVesTController.sol";
import {MetaVesTControllerFactoryStorage} from "./storage/MetaVesTControllerFactoryStorage.sol";
import {BorgAuthACL} from "cybercorps-contracts/src/libs/auth.sol";
import {UUPSUpgradeable} from "openzeppelin-contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import {ERC1967Proxy} from "openzeppelin-contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {Create2} from "openzeppelin-contracts/utils/Create2.sol";

/**
 * @title      MetaVesT Controller Factory
 *
 * @notice     Deploy a new instance of MetaVesTController, which in turn deploys a new MetaVesT it controls
 *
 *
 */
contract MetaVesTControllerFactory is BorgAuthACL, UUPSUpgradeable {
    event RegistrySet(address registry);
    event RefImplementationSet(address refImplementation, string version);
    event MetaVesTControllerDeployed(
        address controller,
        address authority,
        address dao
    );

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    function initialize(address auth, address registry, address refImplementation) public initializer {
        // Initialize BorgAuthACL
        __BorgAuthACL_init(auth);

        MetaVesTControllerFactoryStorage.StorageData storage s = MetaVesTControllerFactoryStorage.getStorageData();
        s.registry = registry;
        s.refImplementation = refImplementation;
    }

    /// @notice Deploy a MetaVesTController specifying authority address, DAO staking/voting contract address
    /// each individual grantee's will have his own MetaVesT contract, and deployed MetaVesTs are amendable by 'authority' via the controller contract
    /// @dev Each deployed MetaVesTController has its own set of conditions for admin operations such as MetaVesT creation/termination and parameters, etc.
    /// the MetaVesT created by the MetaVesTController is immutable, but the 'authority' which has access control within the controller may replace itself
    function deployMetavestController(bytes32 salt, address authority, address dao) external returns (address) {
        MetaVesTControllerFactoryStorage.StorageData storage s = MetaVesTControllerFactoryStorage.getStorageData();
        metavestController controller = metavestController(address(new ERC1967Proxy{salt: salt}(
            MetaVesTControllerFactoryStorage.getStorageData().refImplementation,
            abi.encodeWithSelector(
                metavestController.initialize.selector,
                authority,
                dao,
                s.registry,
                address(this)
            )
        )));
        emit MetaVesTControllerDeployed(
            address(controller),
            authority,
            dao
        );
        return address(controller);
    }

    // ========================
    // Getter / Setter
    // ========================

    /// @notice Get the CyberAgreementRegistry used for MetaVesT deals
    /// @return CyberAgreementRegistry contract address
    function getRegistry() public view returns (address) {
        return MetaVesTControllerFactoryStorage.getStorageData().registry;
    }

    /// @notice Set the CyberAgreementRegistry used for MetaVesT deals
    /// @dev Only callable by addresses with the owner role
    /// @param registry Address of the new implementation
    function setRegistry(address registry) public onlyOwner {
        MetaVesTControllerFactoryStorage.getStorageData().registry = registry;
        emit RegistrySet(registry);
    }

    /// @notice Get the reference implementation contract for the next deployments
    /// @return Current reference implementation contract address
    function getRefImplementation() public view returns (address) {
        return MetaVesTControllerFactoryStorage.getStorageData().refImplementation;
    }

    /// @notice Set the reference implementation contract for the next deployments
    /// @dev Only callable by addresses with the admin role
    /// @param newImplementation Address of the new implementation
    function setRefImplementation(address newImplementation) public onlyOwner {
        MetaVesTControllerFactoryStorage.getStorageData().refImplementation = newImplementation;
        emit RefImplementationSet(newImplementation, metavestController(newImplementation).DEPLOY_VERSION());
    }

    /// @notice Computes the deterministic address for an MetavestController
    /// @param salt Salt used for CREATE2
    /// @return computedAddress The precomputed address of the proxy
    function computeMetavestControllerAddress(bytes32 salt, address authority, address dao) external view returns (address) {
        return Create2.computeAddress(
            salt,
            keccak256(abi.encodePacked(
                type(ERC1967Proxy).creationCode,
                abi.encode(
                    MetaVesTControllerFactoryStorage.getStorageData().refImplementation,
                    abi.encodeWithSelector(
                        metavestController.initialize.selector,
                        authority,
                        dao,
                        MetaVesTControllerFactoryStorage.getStorageData().registry,
                        address(this)
                    )
                )
            ))
        );
    }

    // ========================
    // UUPSUpgradeable
    // ========================

    function _authorizeUpgrade(address newImplementation) internal virtual override onlyOwner {}
}
