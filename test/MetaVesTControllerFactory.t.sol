// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.24;

import {MetaVesTControllerFactory} from "../src/MetaVesTControllerFactory.sol";
import {Test} from "forge-std/Test.sol";
import {Initializable} from "openzeppelin-contracts-upgradeable/proxy/utils/Initializable.sol";

contract MetaVesTControllerFactoryTest is Test {
    function test_RevertIf_InitializeImplementation() public {
        MetaVesTControllerFactory impl = new MetaVesTControllerFactory();
        vm.expectRevert(Initializable.InvalidInitialization.selector);
        impl.initialize();
    }
}
