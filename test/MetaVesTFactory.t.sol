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


        ZkTokenV2 zkToken = ZkTokenV2(0x3D65a7e2960ac3820262b847b4C4dCB50F225f1a);
        ZkCappedMinterFactory zkMinterFactory = ZkCappedMinterFactory(0x25BDFa33Fb8873701DDbeeD3f09edD173Ac71A1b);
        
        address _controller = factory.deployMetavestAndController(_authority, _dao, address(_factory), address(_factory2), address(_factory3), address(zkMinterFactory), address(zkToken));
    }

    function testDeployMetavestAndController() public {
        address _authority = address(0xa);
        address _dao = address(0xB);
        address _paymentToken = address(0xC);
        address grantee = address(0xD);
        RestrictedTokenFactory restrictedTokenFactory = new RestrictedTokenFactory();

        ZkTokenV2 zkToken = ZkTokenV2(0x3D65a7e2960ac3820262b847b4C4dCB50F225f1a);
        ZkCappedMinterFactory zkMinterFactory = ZkCappedMinterFactory(0x25BDFa33Fb8873701DDbeeD3f09edD173Ac71A1b);

        address _controller = factory.deployMetavestAndController(_authority, _dao, address(_factory), address(_factory2), address(_factory3), address(zkMinterFactory), address(zkToken));
        metavestController controller = metavestController(_controller);
                BaseAllocation.Allocation memory allocation = BaseAllocation.Allocation({
            tokenContract: address(token),
            tokenStreamTotal: 1000e18,
            vestingCliffCredit: 100e18,
            unlockingCliffCredit: 100e18,
            vestingRate: 10e18,
            vestingStartTime: uint48(block.timestamp),
            unlockRate: 10e18,
            unlockStartTime: uint48(block.timestamp)
        });

        BaseAllocation.Milestone[] memory milestones = new BaseAllocation.Milestone[](1);
        milestones[0] = BaseAllocation.Milestone({
            milestoneAward: 100e18,
            unlockOnCompletion: true,
            complete: false,
            conditionContracts: new address[](0)
        });

        //token.approve(address(controller), 1100e18);

        address vestingAllocation = controller.createMetavest(
            metavestController.metavestType.Vesting,
            grantee,
            allocation,
            milestones,
            0,
            address(0),
            0,
            0
            
        );

        assertEq(token.balanceOf(vestingAllocation), 1100e18);,9u
    }

    function testFailControllerZeroAddress() public {
        address _authority = address(0);
        address _dao = address(0);
        address _paymentToken = address(0);
        factory.deployMetavestAndController(_authority, _dao, address(0), address(0), address(0), address(0), address(0));
    }   


}
