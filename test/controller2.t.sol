// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.20;

import {console2} from "forge-std/console2.sol";
import {Initializable} from "openzeppelin-contracts-upgradeable/proxy/utils/Initializable.sol";
import "../src/RestrictedTokenAllocation.sol";
import "../src/TokenOptionAllocation.sol";
import "../src/VestingAllocation.sol";
import "../src/interfaces/IAllocationFactory.sol";
import "./lib/MetaVesTControllerTestBaseExtended.sol";
import "./mocks/MockCondition.sol";
import {ERC1967ProxyLib} from "./lib/ERC1967ProxyLib.sol";

contract MetaVestControllerTest2 is MetaVesTControllerTestBaseExtended {
    using ERC1967ProxyLib for address;
    using MetaVestDealLib for MetaVestDeal;

    function test_RevertIf_GranteeNotDirectParty() public {
        // Proposal should fail if the grantee is not listed as a direct party (non-delegate).
        // This is to prevent accidentally signing an agreement for other's grant
        address[] memory parties = new address[](2);
        parties[0] = authority;
        parties[1] = bob; // not Alice the grantee

        _proposeAndSignDeal(
            templateId,
            block.timestamp, // salt
            delegatePrivateKey,
            parties,
            MetaVestDealLib.draft().setVesting(
                grantee,
                BaseAllocation.Allocation({
                    tokenContract: address(vestingToken),
                    tokenStreamTotal: 100 ether,
                    vestingCliffCredit: 10 ether,
                    unlockingCliffCredit: 10 ether,
                    vestingRate: 1 ether,
                    vestingStartTime: uint48(block.timestamp),
                    unlockRate: 1 ether,
                    unlockStartTime: uint48(block.timestamp)
                }),
                new BaseAllocation.Milestone[](0)
            ),
            "Alice",
            block.timestamp + 7 days,
            abi.encodeWithSelector(MetaVesTControllerStorage.MetaVesTController_GranteeNotDirectParty.selector) // Expected revert
        );
    }

    function test_RevertIf_IncorrectGrantorSignature() public {
        // Should not be able to propose a deal without grantor's authorization
        _proposeAndSignDeal(
            templateId,
            block.timestamp, // salt
            alicePrivateKey, // Should fail because Alice is not delegated by the grantor
            MetaVestDealLib.draft().setVesting(
                alice, // grantee
                BaseAllocation.Allocation({
                    tokenContract: address(vestingToken),
                    tokenStreamTotal: 100 ether,
                    vestingCliffCredit: 10 ether,
                    unlockingCliffCredit: 10 ether,
                    vestingRate: 1 ether,
                    vestingStartTime: uint48(block.timestamp),
                    unlockRate: 1 ether,
                    unlockStartTime: uint48(block.timestamp)
                }),
                new BaseAllocation.Milestone[](0)
            ),
            "Alice",
            block.timestamp + 7 days,
            abi.encodeWithSelector(CyberAgreementRegistry.SignatureVerificationFailed.selector) // Expected revert
        );
    }

    function test_RevertIf_IncorrectGranteeSignature() public {
        bytes32 contractIdAlice = _proposeAndSignDeal(
            templateId,
            block.timestamp, // salt
            delegatePrivateKey,
            MetaVestDealLib.draft().setVesting(
                alice,
                BaseAllocation.Allocation({
                    tokenContract: address(vestingToken),
                    tokenStreamTotal: 100 ether,
                    vestingCliffCredit: 10 ether,
                    unlockingCliffCredit: 10 ether,
                    vestingRate: 1 ether,
                    vestingStartTime: uint48(block.timestamp),
                    unlockRate: 1 ether,
                    unlockStartTime: uint48(block.timestamp)
                }),
                new BaseAllocation.Milestone[](0)
            ),
            "Alice",
            block.timestamp + 7 days
        );

        // Should not be able to sign Alice's agreement with other's signature
        _granteeSignDeal(
            contractIdAlice,
            alice,
            alice,
            bobPrivateKey, // Wrong signer
            "Alice",
            abi.encodeWithSelector(CyberAgreementRegistry.SignatureVerificationFailed.selector) // Expected revert
        );
    }

    function test_GranteeDelegateSignature() public {
        // Alice to delegate to Bob
        vm.prank(alice);
        registry.setDelegation(bob, block.timestamp + 60);
        assertTrue(registry.isValidDelegate(alice, bob), "Bob should be Alice's delegate");

        // Bob should be able to sign for Alice now
        bytes32 contractId = _proposeAndSignDeal(
            templateId,
            block.timestamp, // salt
            delegatePrivateKey,
            MetaVestDealLib.draft().setVesting(
                alice,
                BaseAllocation.Allocation({
                    tokenContract: address(vestingToken),
                    tokenStreamTotal: 100 ether,
                    vestingCliffCredit: 10 ether,
                    unlockingCliffCredit: 10 ether,
                    vestingRate: 1 ether,
                    vestingStartTime: uint48(block.timestamp),
                    unlockRate: 1 ether,
                    unlockStartTime: uint48(block.timestamp)
                }),
                new BaseAllocation.Milestone[](0)
            ),
            "Alice",
            metavestExpiry
        );
        VestingAllocation vestingAllocation = VestingAllocation(_granteeSignDeal(
            contractId,
            alice,
            alice,
            bobPrivateKey, // Use Bob to sign
            "Alice"
        ));
        assertEq(vestingAllocation.grantee(), alice, "Alice should be the grantee");

        // Wait until expiry
        skip(61);

        // Bob should no longer be able to sign for Alice
        assertFalse(registry.isValidDelegate(alice, bob), "Bob should no longer be Alice's delegate");
    }

    function test_GranteeSignedExternally() public {
        // It should still be able to create metavest if the grantee has signed externally by interacting directly with
        // CyberAgreementRegistry

        bytes32 contractId = _proposeAndSignDeal(
            templateId,
            block.timestamp, // salt
            delegatePrivateKey,
            MetaVestDealLib.draft().setVesting(
                alice,
                BaseAllocation.Allocation({
                    tokenContract: address(vestingToken),
                    tokenStreamTotal: 100 ether,
                    vestingCliffCredit: 10 ether,
                    unlockingCliffCredit: 10 ether,
                    vestingRate: 1 ether,
                    vestingStartTime: uint48(block.timestamp),
                    unlockRate: 1 ether,
                    unlockStartTime: uint48(block.timestamp)
                }),
                new BaseAllocation.Milestone[](0)
            ),
            "Alice",
            metavestExpiry
        );

        // Alice to sign the agreement externally

        MetaVestDeal memory deal = controller.getDeal(contractId);

        string[] memory globalValues = new string[](11);
        globalValues[0] = vm.toString(uint256(MetaVestType.Vesting));
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
        partyValues[0] = "Alice";
        partyValues[1] = vm.toString(grantee); // evmAddress
        partyValues[2] = "email@company.com"; // Make sure it matches the proposed deal
        partyValues[3] = "individual"; // Make sure it matches the proposed deal

        registry.signContractFor(
            alice,
            contractId,
            partyValues,
            CyberAgreementUtils.signAgreementTypedData(
                vm,
                registry.DOMAIN_SEPARATOR(),
                registry.SIGNATUREDATA_TYPEHASH(),
                contractId,
                agreementUri,
                globalFields,
                partyFields,
                globalValues,
                partyValues,
                alicePrivateKey
            ),
            false, // fillUnallocated
            "" // secret
        );
        assertTrue(registry.hasSigned(contractId, alice), "Alice should've signed");

        // Should still be able to create metavest for Alice

        VestingAllocation metavest = VestingAllocation(controller.signDealAndCreateMetavest(
            alice,
            alice,
            contractId,
            partyValues,
            "", // signature no longer needed since Alice has signed externally
            "" // no secrets
        ));
        assertEq(metavest.grantee(), alice, "Alice should be the grantee");
    }

    function test_UpgradeMetaVesTController() public {
        // MetaLeX to release new implementation
        vm.startPrank(deployer);
        address newImplementation = address(new metavestController());
        metavestControllerFactory.setRefImplementation(newImplementation);
        vm.stopPrank();

        // Upgrade to new implementation without initialization data

        // Non-owner should not be able to upgrade it
        vm.expectRevert(abi.encodeWithSelector(MetaVesTControllerStorage.MetaVesTController_OnlyAuthority.selector));
        controller.upgradeToAndCall(newImplementation, "");

        // Owner should be able to upgrade it
        vm.prank(guardianSafe);
        controller.upgradeToAndCall(newImplementation, "");
        assertEq(address(controller).getErc1967Implementation(), newImplementation);

        // Verify the controller still works

        bytes32 contractIdAlice = _proposeAndSignDeal(
            templateId,
            block.timestamp, // salt
            delegatePrivateKey,
            MetaVestDealLib.draft().setVesting(
                alice,
                BaseAllocation.Allocation({
                    tokenContract: address(vestingToken),
                    // 100k ZK total, the first half unlocks with a cliff and the second half unlocks over an year
                    tokenStreamTotal: 60 ether,
                    vestingCliffCredit: 30 ether,
                    unlockingCliffCredit: 30 ether,
                    vestingRate: 1 ether,
                    vestingStartTime: uint48(block.timestamp),
                    unlockRate: 1 ether,
                    unlockStartTime: uint48(block.timestamp)
                }),
                new BaseAllocation.Milestone[](0)
            ),
            "Alice",
            metavestExpiry
        );

        VestingAllocation vestingAllocationAlice = VestingAllocation(_granteeSignDeal(
            contractIdAlice,
            alice, // grantee
            alice, // recipient
            alicePrivateKey,
            "Alice"
        ));
        assertEq(vestingAllocationAlice.grantee(), alice);
    }
}
