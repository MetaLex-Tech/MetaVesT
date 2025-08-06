// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.24;

import "forge-std/Test.sol";
import "../../src/MetaVesTController.sol";
import "../../src/VestingAllocationFactory.sol";
import "../../src/interfaces/zk-governance/IZkTokenV1.sol";
import {BorgAuth} from "cybercorps-contracts/src/libs/auth.sol";
import {CyberAgreementRegistry} from "cybercorps-contracts/src/CyberAgreementRegistry.sol";
import {CyberAgreementUtils} from "cybercorps-contracts/test/libs/CyberAgreementUtils.sol";

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

    string agreementUri = "ipfs.io/ipfs/[cid]";
    string[] globalFields;
    string[] partyFields;

    BorgAuth auth;
    CyberAgreementRegistry registry;

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

    function _proposeAndSignDeal(
        bytes32 templateId,
        address authority,
        address grantee,
        uint256 granteePrivateKey,
        BaseAllocation.Allocation memory allocation,
        BaseAllocation.Milestone[] memory milestones,
        string[] memory globalValues,
        string[] memory partyValues,
        uint256 expiry
    ) internal returns(bytes32) {
        return _proposeAndSignDeal(
            templateId, authority, grantee, granteePrivateKey, allocation, milestones, globalValues, partyValues, expiry,
            "" // Not expecting revert
        );
    }

    function _proposeAndSignDeal(
        bytes32 templateId,
        address authority,
        address grantee,
        uint256 granteePrivateKey,
        BaseAllocation.Allocation memory allocation,
        BaseAllocation.Milestone[] memory milestones,
        string[] memory globalValues,
        string[] memory partyValues,
        uint256 expiry,
        bytes memory expectRevertData
    ) internal returns(bytes32) {
        uint256 contractSalt = block.timestamp;

        address[] memory allParties = new address[](1);
        allParties[0] = grantee;
        bytes32 expectedContractId = keccak256(
            abi.encode(
                templateId,
                contractSalt,
                globalValues,
                allParties
            )
        );

        bytes memory signature = CyberAgreementUtils.signAgreementTypedData(
            vm,
            registry.DOMAIN_SEPARATOR(),
            registry.SIGNATUREDATA_TYPEHASH(),
            expectedContractId,
            agreementUri,
            globalFields,
            partyFields,
            globalValues,
            partyValues,
            granteePrivateKey
        );

        if (expectRevertData.length > 0) {
            vm.expectRevert(expectRevertData);
        }
        vm.prank(authority);
        bytes32 contractId = controller.proposeAndSignDeal(
            contractSalt,
            templateId,
            metavestController.metavestType.Vesting,
            grantee,
            grantee,
            allocation,
            milestones,
            globalValues,
            partyValues,
            signature,
            expiry
        );

        if (expectRevertData.length == 0) {
            assertEq(contractId, expectedContractId, "Unexpected contract ID");
            return contractId;
        } else {
            return 0;
        }
    }
}
