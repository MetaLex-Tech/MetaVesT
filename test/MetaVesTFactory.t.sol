//SPDX-License-Identifier: AGPL-3.0-only

pragma solidity ^0.8.18;

import "forge-std/Test.sol";
import "../src/MetaVesTFactory.sol";
import "../src/MetaVesTController.sol";
import "../src/VestingAllocationFactory.sol";
import "../src/TokenOptionFactory.sol";
import "../src/RestrictedTokenFactory.sol";

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
        deal(dai_addr, _authority, 2000 ether);
        address _dao = address(0xB);
        address _paymentToken = address(0xC);
        VestingAllocationFactory _factory = new VestingAllocationFactory();
        RestrictedTokenFactory _factory2 = new RestrictedTokenFactory();
        TokenOptionFactory _factory3 = new TokenOptionFactory();

        address _controller = factory.deployMetavestAndController(_authority, _dao, _paymentToken, address(_factory), address(_factory2), address(_factory3));
        metavestController controller = metavestController(_controller);

         BaseAllocation.Milestone[] memory emptyMilestones;
               BaseAllocation.Allocation memory _metavestDetails = BaseAllocation.Allocation({
                tokenStreamTotal: 2 ether,
                vestingCliffCredit: 0,
                unlockingCliffCredit: 0,
                vestingRate: uint160(10),
                vestingStartTime: uint48(block.timestamp),
                unlockRate: uint160(10),
                unlockStartTime: uint48(block.timestamp),
                tokenContract: dai_addr
            });
        
        vm.prank(_authority);
        IERC20(dai_addr).approve(_controller, 2 ether);

        vm.prank(_authority);
        BaseAllocation vest = BaseAllocation(controller.createMetavest(metavestController.metavestType.Vesting, address(0xDA0), _metavestDetails, emptyMilestones, 0, address(0), 0, 0));
        console.log(controller.authority());
        skip(10);
        
        vm.startPrank(address(0xDA0));
        vest.withdraw(vest.getAmountWithdrawable());
        skip(10);
        vest.withdraw(vest.getAmountWithdrawable());    
    }
}
