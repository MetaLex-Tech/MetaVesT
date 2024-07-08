//SPDX-License-Identifier: AGPL-3.0-only

pragma solidity ^0.8.18;

import "forge-std/Test.sol";
import "../src/MetaVesTFactory.sol";
import "../src/MetaVesTController.sol";

/// @dev foundry framework testing of MetaVesTFactory.sol
/// forge t --via-ir

/// @notice test contract for MetaVesTFactory using Foundry
contract MetaVesTFactoryTest is Test {
    MetaVesTFactory internal factory;
    address factoryAddr;

    event MetaVesT_Deployment(
        address newMetaVesT,
        address authority,
        address controller,
        address dao,
        address paymentToken
    );

    function setUp() public {
        factory = new MetaVesTFactory();
        factoryAddr = address(factory);
    }

    function testDeployMetavestAndController() public {
        address _authority = address(0xa);
        address _dao = address(0xB);
        address _paymentToken = address(0xC);
        address _controller = factory.deployMetavestAndController(_authority, _dao, _paymentToken);
        MetaVesTController controller = MetaVesTController(_controller);
        console.log(controller.authority());
        
    }
}
