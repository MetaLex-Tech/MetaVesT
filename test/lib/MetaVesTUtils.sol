// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.24;

import "../../src/MetaVesTController.sol";
import {Vm} from "forge-std/Test.sol";

library MetaVesTUtils {
    function signAgreementTypedData(
        Vm vm,
        metavestController controller,
        metavestController.SignedAgreementData memory data,
        uint256 privKey
    ) internal view returns (bytes memory signature) {
        bytes32 digest = keccak256(
            abi.encodePacked(
                "\x19\x01",
                controller.DOMAIN_SEPARATOR(),
                _hashSignedAgreementData(controller, data)
            )
        );

        (uint8 v, bytes32 r, bytes32 s) = vm.sign(privKey, digest);
        signature = abi.encodePacked(r, s, v);
        return signature;
    }

    function _hashSignedAgreementData(
        metavestController controller,
        metavestController.SignedAgreementData memory data
    ) internal view returns (bytes32) {
        return keccak256(abi.encode(
            controller.SIGNED_AGREEMENT_DATA_TYPEHASH(),
            data.id,
            keccak256(bytes(data.agreementUri)),
            data._metavestType,
            data.grantee,
            data.recipient,
            _hashAllocaiton(controller, data.allocation),
            _hashMilestones(controller, data.milestones)
        ));
    }

    function _hashAllocaiton(
        metavestController controller,
        BaseAllocation.Allocation memory allocation
    ) internal view returns (bytes32) {
        return keccak256(abi.encode(
            controller.ALLOCATION_TYPEHASH(),
            allocation.tokenContract,
            allocation.tokenStreamTotal,
            allocation.vestingCliffCredit,
            allocation.unlockingCliffCredit,
            allocation.vestingRate,
            allocation.vestingStartTime,
            allocation.unlockRate,
            allocation.unlockStartTime
        ));
    }

    function _hashMilestones(
        metavestController controller,
        BaseAllocation.Milestone[] memory milestones
    ) internal view returns (bytes32) {
        bytes32[] memory hashes = new bytes32[](milestones.length);
        for (uint256 i = 0; i < milestones.length; i++) {
            hashes[i] = _hashMilestone(controller, milestones[i]);
        }
        return keccak256(abi.encodePacked(hashes));
    }

    function _hashMilestone(
        metavestController controller,
        BaseAllocation.Milestone memory milestone
    ) internal view returns (bytes32) {
        return keccak256(abi.encode(
            controller.MILESTONE_TYPEHASH(),
            milestone.milestoneAward,
            milestone.unlockOnCompletion,
            milestone.complete,
            keccak256(abi.encodePacked(milestone.conditionContracts))
        ));
    }
}
