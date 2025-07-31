//SPDX-License-Identifier: AGPL-3.0-only

pragma solidity ^0.8.18;

import "../src/MetaVesTController.sol";
import "../src/MetaVesTFactory.sol";
import "../src/RestrictedTokenFactory.sol";
import "../src/TokenOptionFactory.sol";
import "../src/VestingAllocationFactory.sol";
import "../src/interfaces/zk-governance/IZkTokenV1.sol";
import "forge-std/Test.sol";

/// @dev foundry framework testing of MetaVesTFactory.sol
/// forge t --via-ir

/// @notice test contract for MetaVesTFactory using Foundry
contract MetaVesTFactoryTest is Test {
//    // zkSync Era Sepolia @ 5576300
//    address zkTokenAdmin = 0x0d9DD6964692a0027e1645902536E7A3b34AA1d7;
//    IZkTokenV1 zkToken = IZkTokenV1(0x69e5DC39E2bCb1C17053d2A4ee7CAEAAc5D36f96);
//    IZkCappedMinterV2Factory zkCappedMinterFactory = IZkCappedMinterV2Factory(0x329CE320a0Ef03F8c0E01195604b5ef7D3Fb150E);
////    // zkSync Era mainnet
////    address zkTokenAdmin = 0xe5d21A9179CA2E1F0F327d598D464CcF60d89c3d;
////    IZkTokenV1 zkToken = IZkTokenV1(0x5A7d6b2F92C77FAD6CCaBd7EE0624E64907Eaf3E);
////    IZkCappedMinterV2Factory zkCappedMinterFactory = IZkCappedMinterV2Factory(0x0400E6bc22B68686Fb197E91f66E199C6b0DDD6a);
//
//    IZkCappedMinterV2 zkCappedMinter;
//
//    MetaVesTFactory internal factory;
//    metavestController controller;
//    address factoryAddr;
//    address dai_addr = 0x3e622317f8C93f7328350cF0B56d9eD4C620C5d6;
//    VestingAllocationFactory _factory;// = new VestingAllocationFactory();
//    RestrictedTokenFactory _factory2;// = new RestrictedTokenFactory();
//    TokenOptionFactory _factory3;// = new TokenOptionFactory();
//
//    bytes32 salt = keccak256("MetaVesTFactoryTest");
//
//    event MetaVesT_Deployment(
//        address newMetaVesT,
//        address authority,
//        address controller,
//        address dao,
//        address paymentToken
//    );
//
//    function setUp() public {
//         _factory = new VestingAllocationFactory();
//         _factory2 = new RestrictedTokenFactory();
//         _factory3 = new TokenOptionFactory();
//        factory = new MetaVesTFactory();
//        factoryAddr = address(factory);
//        address _authority = address(0xa);
//
//        address _dao = address(0xB);
//        address _paymentToken = address(0xC);
//
//        controller = metavestController(factory.deployMetavestAndController(_authority, _dao, address(_factory), address(_factory2), address(_factory3)));
//
//        // Deploy ZK Capped Minter v2
//        zkCappedMinter = IZkCappedMinterV2(zkCappedMinterFactory.createCappedMinter(
//            address(zkToken),
//            address(controller), // Grant controller admin privilege so it can grant minter privilege to deployed MetaVesT
//            1000e18,
//            uint48(block.timestamp), // start now
//            uint48(block.timestamp + 365 days * 2),
//            uint256(salt)
//        ));
//
//        vm.prank(_authority);
//        controller.setZkCappedMinter(address(zkCappedMinter));
//    }
//
//    function testDeployMetavestAndController() public {
//        address _authority = address(0xa);
//        address _dao = address(0xB);
//        address _paymentToken = address(0xC);
//        address grantee = address(0xD);
//        RestrictedTokenFactory restrictedTokenFactory = new RestrictedTokenFactory();
//
//        BaseAllocation.Allocation memory allocation = BaseAllocation.Allocation({
//            tokenContract: address(zkToken),
//            tokenStreamTotal: 1000e18,
//            vestingCliffCredit: 100e18,
//            unlockingCliffCredit: 100e18,
//            vestingRate: 10e18,
//            vestingStartTime: uint48(block.timestamp),
//            unlockRate: 10e18,
//            unlockStartTime: uint48(block.timestamp)
//        });
//
//        BaseAllocation.Milestone[] memory milestones = new BaseAllocation.Milestone[](1);
//        milestones[0] = BaseAllocation.Milestone({
//            milestoneAward: 100e18,
//            unlockOnCompletion: true,
//            complete: false,
//            conditionContracts: new address[](0)
//        });
//
//        //token.approve(address(controller), 1100e18);
//
//        VestingAllocation vestingAllocation = VestingAllocation(controller.createMetavest(
//            metavestController.metavestType.Vesting,
//            grantee,
//            allocation,
//            milestones,
//            0,
//            address(0),
//            0,
//            0
//
//        ));
//
//        assertEq(zkToken.balanceOf(address(vestingAllocation)), 0, "Vesting contract should not have any token (it mints on-demand)");
//        assertEq(vestingAllocation.getAmountWithdrawable(), 100e18, "Should be able to withdraw cliff amount");
//    }
//
//    function test_RevertIf_ControllerZeroAddress() public {
//        address _authority = address(0);
//        address _dao = address(0);
//        address _paymentToken = address(0);
//        vm.expectRevert(abi.encodeWithSelector(MetaVesTFactory.MetaVesTFactory_ZeroAddress.selector));
//        factory.deployMetavestAndController(_authority, _dao, address(0), address(0), address(0));
//    }
}
