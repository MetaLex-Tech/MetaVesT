//SPDX-License-Identifier: AGPL-3.0-only

pragma solidity ^0.8.18;

import "forge-std/Test.sol";
import "../src/MetaVesTFactory.sol";
import "../src/MetaVesTController.sol";
import "../src/VestingAllocationFactory.sol";
import "../src/TokenOptionFactory.sol";
import "../src/RestrictedTokenFactory.sol";
import "../lib/zk-governance/l2-contracts/src/ZkTokenV2.sol";
import "../lib/zk-governance/l2-contracts/src/ZkCappedMinterFactory.sol";

interface IERC20 {
    function transfer(address recipient, uint256 amount) external returns (bool);
    function balanceOf(address account) external view returns (uint256);
    function approve(address spender, uint256 amount) external returns (bool);

}

/// @dev foundry framework testing of MetaVesTFactory.sol
/// forge t --via-ir

/// @notice test contract for MetaVesTFactory using Foundry
contract MetaVesTFactoryTest is Test {
    MetaVesTFactory internal factory;
    address factoryAddr;
    address dai_addr = 0x3e622317f8C93f7328350cF0B56d9eD4C620C5d6;
            VestingAllocationFactory _factory;// = new VestingAllocationFactory();
        RestrictedTokenFactory _factory2;// = new RestrictedTokenFactory();
        TokenOptionFactory _factory3;// = new TokenOptionFactory();

    event MetaVesT_Deployment(
        address newMetaVesT,
        address authority,
        address controller,
        address dao,
        address paymentToken
    );

    function setUp() public {
         _factory = new VestingAllocationFactory();
         _factory2 = new RestrictedTokenFactory();
         _factory3 = new TokenOptionFactory();
        factory = new MetaVesTFactory();
        factoryAddr = address(factory);
        address _authority = address(0xa);

        address _dao = address(0xB);
        address _paymentToken = address(0xC);
        RestrictedTokenFactory restrictedTokenFactory = new RestrictedTokenFactory();

        ZkTokenV2 zkToken = new ZkTokenV2();
        ZkCappedMinterFactory zkMinterFactory = new ZkCappedMinterFactory(0x0);
        
        address _controller = factory.deployMetavestAndController(_authority, _dao, address(_factory), address(_factory2), address(_factory3), address(zkMinterFactory), address(zkToken));
    }

    function testDeployMetavestAndController() public {
        address _authority = address(0xa);
        address _dao = address(0xB);
        address _paymentToken = address(0xC);
        RestrictedTokenFactory restrictedTokenFactory = new RestrictedTokenFactory();

        ZkTokenV2 zkToken = new ZkTokenV2();
        ZkCappedMinterFactory zkMinterFactory = new ZkCappedMinterFactory(0x0);

        address _controller = factory.deployMetavestAndController(_authority, _dao, address(_factory), address(_factory2), address(_factory3), address(zkMinterFactory), address(zkToken));
        metavestController controller = metavestController(_controller);
    }

    function testFailControllerZeroAddress() public {
        address _authority = address(0);
        address _dao = address(0);
        address _paymentToken = address(0);
        factory.deployMetavestAndController(_authority, _dao, address(0), address(0), address(0), address(0), address(0));
    }   


}
