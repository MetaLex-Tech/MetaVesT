// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import "../../src/MetaVesTController.sol";
import {ERC1967Proxy} from "openzeppelin-contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {BorgAuth} from "cybercorps-contracts/src/libs/auth.sol";
import {CyberAgreementRegistry} from "cybercorps-contracts/src/CyberAgreementRegistry.sol";
import {CyberAgreementUtils} from "cybercorps-contracts/test/libs/CyberAgreementUtils.sol";
import {MockERC20} from "../mocks/MockERC20.sol";
import {MetaVesTControllerFactory} from "../../src/MetaVesTControllerFactory.sol";
import {MetaVestDealLib, MetaVestDeal} from "../../src/lib/MetaVestDealLib.sol";

contract MetaVesTControllerTestBase is Test {
    using MetaVestDealLib for MetaVestDeal;

    MockERC20 vestingToken;
    MockERC20 paymentToken;

    address deployer = address(0x2);
    address guardianSafe = address(0x3);

    uint256 alicePrivateKey = 1;
    address alice = vm.addr(alicePrivateKey);
    uint256 bobPrivateKey = 2;
    address bob = vm.addr(bobPrivateKey);
    uint256 chadPrivateKey = 3;
    address chad = vm.addr(chadPrivateKey);
    uint256 delegatePrivateKey = 4;
    address delegate = vm.addr(delegatePrivateKey);

    bytes32 salt = keccak256("MetaVesTControllerTestBase");

    bytes32 templateId = bytes32(uint256(123));
    string agreementUri = "ipfs.io/ipfs/[cid]";
    string[] globalFields;
    string[] partyFields;

    BorgAuth auth;
    CyberAgreementRegistry registry;

    MetaVesTControllerFactory metavestControllerFactory;

    metavestController controller;

    function setUp() public virtual {
        vestingToken = new MockERC20("Vesting Token", "VEST", 18);
        paymentToken = new MockERC20("Payment Token", "PAY", 18);
        vm.label(address(vestingToken), "VEST");
        vm.label(address(paymentToken), "PAY");

        vm.startPrank(deployer);

        // Deploy CyberAgreementRegistry and prepare templates

        auth = new BorgAuth{salt: salt}(deployer);
        registry = CyberAgreementRegistry(address(new ERC1967Proxy{salt: salt}(
            address(new CyberAgreementRegistry{salt: salt}()),
            abi.encodeWithSelector(
                CyberAgreementRegistry.initialize.selector,
                address(auth)
            )
        )));

        globalFields = new string[](11);
        globalFields[0] = "metavestType";
        globalFields[1] = "grantor";
        globalFields[2] = "grantee";
        globalFields[3] = "tokenContract";
        globalFields[4] = "tokenStreamTotal";
        globalFields[5] = "vestingCliffCredit";
        globalFields[6] = "unlockingCliffCredit";
        globalFields[7] = "vestingRate";
        globalFields[8] = "vestingStartTime";
        globalFields[9] = "unlockRate";
        globalFields[10] = "unlockStartTime";

        partyFields = new string[](4);
        partyFields[0] = "name";
        partyFields[1] = "evmAddress";
        partyFields[2] = "contactDetails";
        partyFields[3] = "type";

        registry.createTemplate(
            templateId,
            "ZkSyncGuardianCompensation",
            agreementUri,
            globalFields,
            partyFields
        );

        // create2 all the way down so the outcome is consistent
        metavestControllerFactory = MetaVesTControllerFactory(address(new ERC1967Proxy{salt: salt}(
            address(new MetaVesTControllerFactory{salt: salt}()),
            abi.encodeWithSelector(
                MetaVesTControllerFactory.initialize.selector,
                address(auth),
                address(registry),
                new metavestController{salt: salt}()
            )
        )));

        vm.stopPrank();
    }

    function _granteeWithdrawAndAsserts(VestingAllocation vestingAllocation, uint256 amount, string memory assertName) internal {
        address grantee = vestingAllocation.grantee();
        uint256 balanceBefore = vestingToken.balanceOf(grantee);

        vm.prank(grantee);
        vestingAllocation.withdraw(amount);

        assertEq(vestingToken.balanceOf(grantee), balanceBefore + amount, string(abi.encodePacked(assertName, ": unexpected received amount")));
        assertEq(vestingToken.balanceOf(address(vestingAllocation)), 0, string(abi.encodePacked(assertName, ": vesting contract should not have any token (it mints on-demand)")));
    }

    /// @notice Shortcut for:
    /// - no revert
    /// - automatically generate the correct parties
    function _proposeAndSignDeal(
        bytes32 templateId,
        uint256 agreementSalt,
        uint256 grantorOrDelegatePrivateKey,
        MetaVestDeal memory dealDraft,
        string memory partyName,
        uint256 expiry
    ) internal returns(bytes32) {
        return _proposeAndSignDeal(
            templateId,
            agreementSalt,
            grantorOrDelegatePrivateKey,
            dealDraft,
            partyName,
            expiry,
            ""
        );
    }

    /// @notice Shortcut for:
    /// - automatically generate the correct parties
    function _proposeAndSignDeal(
        bytes32 templateId,
        uint256 agreementSalt,
        uint256 grantorOrDelegatePrivateKey,
        MetaVestDeal memory dealDraft,
        string memory partyName,
        uint256 expiry,
        bytes memory expectRevertData
    ) internal returns(bytes32) {
        address[] memory parties = new address[](2);
        parties[0] = address(guardianSafe);
        parties[1] = dealDraft.grantee;

        return _proposeAndSignDeal(
            templateId,
            agreementSalt,
            grantorOrDelegatePrivateKey,
            parties,
            dealDraft,
            partyName,
            expiry,
            expectRevertData
        );
    }

    function _proposeAndSignDeal(
        bytes32 templateId,
        uint256 agreementSalt,
        uint256 grantorOrDelegatePrivateKey,
        address[] memory parties,
        MetaVestDeal memory dealDraft,
        string memory partyName,
        uint256 expiry,
        bytes memory expectRevertData
    ) internal returns(bytes32) {
        string[] memory globalValues = new string[](11);
        globalValues[0] = vm.toString(uint256(dealDraft.metavestType)); // metavestType
        globalValues[1] = vm.toString(address(guardianSafe)); // grantor
        globalValues[2] = vm.toString(dealDraft.grantee); // grantee
        globalValues[3] = vm.toString(dealDraft.allocation.tokenContract); // tokenContract
        globalValues[4] = vm.toString(dealDraft.allocation.tokenStreamTotal / 1 ether); //tokenStreamTotal (human-readable)
        globalValues[5] = vm.toString(dealDraft.allocation.vestingCliffCredit / 1 ether); // vestingCliffCredit (human-readable)
        globalValues[6] = vm.toString(dealDraft.allocation.unlockingCliffCredit / 1 ether); // unlockingCliffCredit (human-readable)
        globalValues[7] = vm.toString(dealDraft.allocation.vestingRate * 365 days / 1 ether); // vestingRate (annually) (human-readable)
        globalValues[8] = vm.toString(dealDraft.allocation.vestingStartTime); // vestingStartTime
        globalValues[9] = vm.toString(dealDraft.allocation.unlockRate * 365 days / 1 ether); // unlockRate (annually) (human-readable)
        globalValues[10] = vm.toString(dealDraft.allocation.unlockStartTime); // unlockStartTime

        // TODO what to do with milestones, which could be of dynamic lengths

        string[][] memory partyValues = new string[][](2);
        partyValues[0] = new string[](4);
        partyValues[0][0] = "Guardian BORG";
        partyValues[0][1] = vm.toString(address(guardianSafe));
        partyValues[0][2] = "guardian-safe@company.com";
        partyValues[0][3] = "Foundation";
        partyValues[1] = new string[](4);
        partyValues[1][0] = partyName;
        partyValues[1][1] = vm.toString(dealDraft.grantee); // evmAddress
        partyValues[1][2] = "email@company.com";
        partyValues[1][3] = "individual";

        bytes32 expectedContractId = keccak256(
            abi.encode(
                templateId,
                agreementSalt,
                globalValues,
                parties
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
            partyValues[0],
            grantorOrDelegatePrivateKey
        );

        if (expectRevertData.length > 0) {
            vm.expectRevert(expectRevertData);
        }
        bytes32 contractId = controller.proposeAndSignDeal(
            templateId,
            agreementSalt,
            dealDraft,
            globalValues,
            parties,
            partyValues,
            signature,
            bytes32(0), // no secrets
            expiry
        );

        if (expectRevertData.length == 0) {
            assertEq(contractId, expectedContractId, "Unexpected contract ID");
            return contractId;
        } else {
            return 0;
        }
    }

    function _granteeSignDeal(
        bytes32 contractId,
        address grantee,
        address recipient,
        uint256 granteePrivateKey,
        string memory partyName
    ) internal returns(address) {
        return _granteeSignDeal(
            contractId, grantee, recipient, granteePrivateKey, partyName,
            "" // Not expecting revert
        );
    }

    function _granteeSignDeal(
        bytes32 contractId,
        address grantee,
        address recipient,
        uint256 granteePrivateKey,
        string memory partyName,
        bytes memory expectRevertData
    ) internal returns(address) {
        MetaVestDeal memory deal = controller.getDeal(contractId);

        string[] memory globalValues = new string[](11);
        globalValues[0] = vm.toString(uint256(deal.metavestType)); // metavestType
        globalValues[1] = vm.toString(address(guardianSafe)); // grantor
        globalValues[2] = vm.toString(grantee); // grantee
        globalValues[3] = vm.toString(deal.allocation.tokenContract); // tokenContract
        globalValues[4] = vm.toString(deal.allocation.tokenStreamTotal / 1 ether); //tokenStreamTotal (human-readable)
        globalValues[5] = vm.toString(deal.allocation.vestingCliffCredit / 1 ether); // vestingCliffCredit (human-readable)
        globalValues[6] = vm.toString(deal.allocation.unlockingCliffCredit / 1 ether); // unlockingCliffCredit (human-readable)
        globalValues[7] = vm.toString(deal.allocation.vestingRate * 365 days / 1 ether); // vestingRate (annually) (human-readable)
        globalValues[8] = vm.toString(deal.allocation.vestingStartTime); // vestingStartTime
        globalValues[9] = vm.toString(deal.allocation.unlockRate * 365 days / 1 ether); // unlockRate (annually) (human-readable)
        globalValues[10] = vm.toString(deal.allocation.unlockStartTime); // unlockStartTime

        string[] memory partyValues = new string[](4);
        partyValues[0] = partyName;
        partyValues[1] = vm.toString(grantee); // evmAddress
        partyValues[2] = "email@company.com"; // Make sure it matches the proposed deal
        partyValues[3] = "individual"; // Make sure it matches the proposed deal

        bytes memory signature = CyberAgreementUtils.signAgreementTypedData(
            vm,
            registry.DOMAIN_SEPARATOR(),
            registry.SIGNATUREDATA_TYPEHASH(),
            contractId,
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
        address metavest = controller.signDealAndCreateMetavest(
            grantee,
            recipient,
            contractId,
            partyValues,
            signature,
            "" // no secrets
        );

        if (expectRevertData.length == 0) {
            return metavest;
        } else {
            return address(0);
        }
    }
}
