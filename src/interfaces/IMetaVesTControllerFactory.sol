//SPDX-License-Identifier: AGPL-3.0-only

pragma solidity ^0.8.24;

interface IMetaVesTControllerFactory {
    function getRegistry() external view returns(address);
    function setRegistry(address registry) external;

    function getRefImplementation() external view returns(address);
    function setRefImplementation(address newImplementation) external;
}
