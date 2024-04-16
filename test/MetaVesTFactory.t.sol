//SPDX-License-Identifier: AGPL-3.0-only

pragma solidity ^0.8.18;

import "forge-std/Test.sol";
import "src/MetaVesTFactory.sol";

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

    function testDeployMetavestAndController(address _authority, address _dao, address _paymentToken) public {
        if (_authority == address(0) || _paymentToken == address(0)) vm.expectRevert();
        factory.deployMetavestAndController(_authority, _dao, _paymentToken);
    }
}
