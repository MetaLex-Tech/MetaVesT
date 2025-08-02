// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.24;

import "forge-std/Test.sol";
import "../../src/MetaVesTController.sol";
import "../../src/VestingAllocationFactory.sol";
import "../../src/interfaces/zk-governance/IZkTokenV1.sol";
import "./MetaVesTUtils.sol";

contract MetaVesTControllerTestBase is Test {
//    // zkSync Era Sepolia @ 5576300
//    address zkTokenAdmin = 0x0d9DD6964692a0027e1645902536E7A3b34AA1d7;
//    IZkTokenV1 zkToken = IZkTokenV1(0x69e5DC39E2bCb1C17053d2A4ee7CAEAAc5D36f96);
//    IZkCappedMinterV2Factory zkCappedMinterFactory = IZkCappedMinterV2Factory(0x329CE320a0Ef03F8c0E01195604b5ef7D3Fb150E);
    // zkSync Era mainnet @ 63631890
    address zkTokenAdmin = 0xe5d21A9179CA2E1F0F327d598D464CcF60d89c3d;
    IZkTokenV1 zkToken = IZkTokenV1(0x5A7d6b2F92C77FAD6CCaBd7EE0624E64907Eaf3E);
    IZkCappedMinterV2Factory zkCappedMinterFactory = IZkCappedMinterV2Factory(0x0400E6bc22B68686Fb197E91f66E199C6b0DDD6a);

    IZkCappedMinterV2 zkCappedMinter;

    address deployer = address(0x2);
    address guardianSafe = address(0x3);

    uint256 alicePrivateKey = 1;
    address alice = vm.addr(alicePrivateKey);
    uint256 bobPrivateKey = 2;
    address bob = vm.addr(bobPrivateKey);
    uint256 chadPrivateKey = 3;
    address chad = vm.addr(chadPrivateKey);

    VestingAllocationFactory vestingAllocationFactory;

    metavestController controller;

    function _granteeWithdrawAndAsserts(VestingAllocation vestingAllocation, uint256 amount, string memory assertName) internal {
        address grantee = vestingAllocation.grantee();
        uint256 balanceBefore = zkToken.balanceOf(grantee);
        vm.prank(grantee);
        vestingAllocation.withdraw(amount);
        assertEq(zkToken.balanceOf(grantee), balanceBefore + amount, string(abi.encodePacked(assertName, ": unexpected received amount")));
        assertEq(zkToken.balanceOf(address(vestingAllocation)), 0, string(abi.encodePacked(assertName, ": vesting contract should not have any token (it mints on-demand)")));
    }

    function _signAndCreateContract(
        address authority,
        address grantee,
        uint256 granteePrivateKey,
        string memory agreementUri,
        BaseAllocation.Allocation memory allocation,
        BaseAllocation.Milestone[] memory milestones
    ) internal returns(bytes32) {
        return _signAndCreateContract(
            authority, grantee, granteePrivateKey, agreementUri, allocation, milestones,
            "" // Not expecting revert
        );
    }

    function _signAndCreateContract(
        address authority,
        address grantee,
        uint256 granteePrivateKey,
        string memory agreementUri,
        BaseAllocation.Allocation memory allocation,
        BaseAllocation.Milestone[] memory milestones,
        bytes memory expectRevertData
    ) internal returns(bytes32) {
        uint256 contractSalt = block.timestamp;
        bytes32 expectedContractId = controller.computeContractId(contractSalt, agreementUri, grantee, grantee, allocation, milestones);
        bytes memory signature = MetaVesTUtils.signAgreementTypedData(
            vm,
            controller,
            metavestController.SignedAgreementData({
                id: expectedContractId,
                agreementUri: agreementUri,
                _metavestType: metavestController.metavestType.Vesting,
                grantee: grantee,
                recipient: grantee,
                allocation: allocation,
                milestones: milestones
            }),
            granteePrivateKey
        );

        if (expectRevertData.length > 0) {
            vm.expectRevert(expectRevertData);
        }
        vm.prank(authority);
        bytes32 contractId = controller.createSignedContract(
            contractSalt,
            metavestController.metavestType.Vesting,
            grantee,
            grantee,
            allocation,
            milestones,
            agreementUri,
            signature
        );

        if (expectRevertData.length == 0) {
            assertEq(contractId, expectedContractId, "Unexpected contract ID");
            return contractId;
        } else {
            return 0;
        }
    }
}
