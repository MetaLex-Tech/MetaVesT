
/*    .o.                                                                                             
     .888.                                                                                            
    .8"888.                                                                                           
   .8' `888.                                                                                          
  .88ooo8888.                                                                                         
 .8'     `888.                                                                                        
 o88o     o8888o                                                                                       
                                                                                                       
                                                                                                       
                                                                                                       
 ooo        ooooo               .             ooooo                  ooooooo  ooooo                    
 `88.       .888'             .o8             `888'                   `8888    d8'                     
  888b     d'888   .ooooo.  .o888oo  .oooo.    888          .ooooo.     Y888..8P                       
  8 Y88. .P  888  d88' `88b   888   `P  )88b   888         d88' `88b     `8888'                        
  8  `888'   888  888ooo888   888    .oP"888   888         888ooo888    .8PY888.                       
  8    Y     888  888    .o   888 . d8(  888   888       o 888    .o   d8'  `888b                      
 o8o        o888o `Y8bod8P'   "888" `Y888""8o o888ooooood8 `Y8bod8P' o888o  o88888o                    
                                                                                                       
                                                                                                       
                                                                                                       
   .oooooo.                .o8                            .oooooo.                                     
  d8P'  `Y8b              "888                           d8P'  `Y8b                                    
 888          oooo    ooo  888oooo.   .ooooo.  oooo d8b 888           .ooooo.  oooo d8b oo.ooooo.      
 888           `88.  .8'   d88' `88b d88' `88b `888""8P 888          d88' `88b `888""8P  888' `88b     
 888            `88..8'    888   888 888ooo888  888     888          888   888  888      888   888     
 `88b    ooo     `888'     888   888 888    .o  888     `88b    ooo  888   888  888      888   888 .o. 
  `Y8bood8P'      .8'      `Y8bod8P' `Y8bod8P' d888b     `Y8bood8P'  `Y8bod8P' d888b     888bod8P' Y8P 
              .o..P'                                                                     888           
              `Y8P'                                                                     o888o          
 _______________________________________________________________________________________________________

 All software, documentation and other files and information in this repository (collectively, the "Software")
 are copyright MetaLeX Labs, Inc., a Delaware corporation.

 All rights reserved.

 The Software is proprietary and shall not, in part or in whole, be used, copied, modified, merged, published,
 distributed, transmitted, sublicensed, sold, or otherwise used in any form or by any means, electronic or
 mechanical, including photocopying, recording, or by any information storage and retrieval system,
 except with the express prior written permission of the copyright holder.*/

pragma solidity 0.8.28;

import {BaseAllocation, IConditionM, IERC20M} from "../BaseAllocation.sol";
import {EnumerableSet} from "../lib/EnumberableSet.sol";
import {MetaVestDeal, MetaVestDealLib, MetaVestType} from "../lib/MetaVestDealLib.sol";
import {RestrictedTokenFactory} from "../lib/RestrictedTokenFactory.sol";
import {TokenOptionFactory} from "../lib/TokenOptionFactory.sol";
import {VestingAllocationFactory} from "../lib/VestingAllocationFactory.sol";
import {ICyberAgreementRegistry} from "cybercorps-contracts/src/interfaces/ICyberAgreementRegistry.sol";

library MetaVesTControllerStorage {
    using EnumerableSet for EnumerableSet.AddressSet;
    using EnumerableSet for EnumerableSet.Bytes32Set;

    // Storage slot for our struct
    bytes32 internal constant STORAGE_POSITION = keccak256("cybercorp.metavest.controller.storage.v1");

    /// @dev opinionated time limit for a MetaVesT amendment, one calendar week in seconds
    uint256 internal constant AMENDMENT_TIME_LIMIT = 604800;
    uint256 internal constant ARRAY_LENGTH_LIMIT = 20;

    struct AmendmentProposal {
        bool isPending;
        bytes32 dataHash;
        bool inFavor;
    }

    struct MajorityAmendmentProposal {
        uint256 totalVotingPower;
        uint256 currentVotingPower;
        uint256 time;
        bool isPending;
        bytes32 dataHash;
        address[] voters;
        mapping(address => uint256) appliedProposalCreatedAt;
        mapping(address => uint256) voterPower;
    }

    struct MetaVesTControllerData {
        address authority;
        address dao;
        address registry;
        address upgradeFactory;
        address _pendingAuthority;
        address _pendingDao;

        // Simple indexer for UX
        bytes32[] dealIds;

        EnumerableSet.Bytes32Set setNames;

        mapping(bytes32 => EnumerableSet.AddressSet) sets;

        /// @notice maps a function's signature to a Condition contract address
        mapping(bytes4 => address[]) functionToConditions;

        /// @notice maps a metavest-parameter-updating function's signature to token contract to whether a majority amendment is pending
        mapping(bytes4 => mapping(bytes32 => MajorityAmendmentProposal)) functionToSetMajorityProposal;

        /// @notice maps a metavest-parameter-updating function's signature to affected grantee address to whether an amendment is pending
        mapping(bytes4 => mapping(address => AmendmentProposal)) functionToGranteeToAmendmentPending;

        /// @notice tracks if an address has voted for an amendment by mapping a hash of the pertinent details to time they last voted for these details (voter, function and affected grantee)
        mapping(bytes32 => uint256) _lastVoted;

        mapping(bytes32 => bool) setMajorityVoteActive;

        /// @notice granteeId => granteeData
        mapping(bytes32 => MetaVestDeal) deals;

        /// @notice Maps agreement IDs to arrays of counter party values for closed deals.
        mapping(bytes32 => string[]) counterPartyValues;

        /// @notice Map MetaVesT contract address to its corresponding agreement ID
        mapping(address => bytes32) metavestAgreementIds;
    }

    ///
    /// Events
    ///

    event MetaVesTController_AmendmentConsentUpdated(bytes4 indexed msgSig, address indexed grantee, bool inFavor);
    event MetaVesTController_AmendmentProposed(address indexed grant, bytes4 msgSig);
    event MetaVesTController_AuthorityUpdated(address indexed newAuthority);
    event MetaVesTController_ConditionUpdated(address indexed condition, bytes4 functionSig);
    event MetaVesTController_DaoUpdated(address newDao);
    event MetaVesTController_MajorityAmendmentProposed(string indexed set, bytes4 msgSig, bytes callData, uint256 totalVotingPower);
    event MetaVesTController_MajorityAmendmentVoted(string indexed set, bytes4 msgSig, address grantee, bool inFavor, uint256 votingPower, uint256 currentVotingPower, uint256 totalVotingPower);
    event MetaVesTController_SetCreated(string indexed set);
    event MetaVesTController_SetRemoved(string indexed set);
    event MetaVesTController_AddressAddedToSet(string set, address indexed grantee);
    event MetaVesTController_AddressRemovedFromSet(string set, address indexed grantee);
    event MetaVesTController_DealProposed(
        bytes32 indexed agreementId,
        address indexed grantee,
        MetaVestType MetaVestType,
        BaseAllocation.Allocation allocation,
        BaseAllocation.Milestone[] milestones,
        bool hasSecret,
        address registry
    );
    event MetaVesTController_DealFinalizedAndMetaVestCreated(
        bytes32 indexed agreementId,
        address indexed recipient,
        address metavest
    );

    ///
    /// ERRORS
    ///

    error MetaVesTController_AlreadyVoted();
    error MetaVesTController_OnlyGranteeMayCall();
    error MetaVesTController_AmendmentNeitherMutualNorMajorityConsented();
    error MetaVesTController_AmendmentAlreadyPending();
    error MetaVesTController_AmendmentCannotBeCanceled();
    error MetaVesTController_AmountNotApprovedForTransferFrom();
    error MetaVesTController_AmendmentCanOnlyBeAppliedOnce();
    error MetaVesTController_CliffGreaterThanTotal();
    error MetaVesTController_ConditionNotSatisfied(address condition);
    error MetaVesTController_EmergencyUnlockNotSatisfied();
    error MetaVestController_DuplicateCondition();
    error MetaVesTController_IncorrectMetaVesTType();
    error MetaVesTController_LengthMismatch();
    error MetaVesTController_MetaVesTAlreadyExists();
    error MetaVesTController_MilestoneIndexCompletedOrDoesNotExist();
    error MetaVesTController_NoPendingAmendment(bytes4 msgSig, address affectedGrantee);
    error MetaVesTController_OnlyAuthority();
    error MetaVesTController_OnlyDAO();
    error MetaVesTController_OnlyPendingAuthority();
    error MetaVesTController_OnlyPendingDao();
    error MetaVesTController_ProposedAmendmentExpired();
    error MetaVesTController_ZeroAddress();
    error MetaVesTController_ZeroAmount();
    error MetaVesTController_ZeroPrice();
    error MetaVesT_AmountNotApprovedForTransferFrom(); // TODO review needed: should we move it elsewhere?
    error MetaVesTController_SetDoesNotExist();
    error MetaVestController_MetaVestNotInSet();
    error MetaVesTController_SetAlreadyExists();
    error MetaVesTController_StringTooLong();
    error MetaVesTController_TypeNotSupported(MetaVestType _type);
    error MetaVesTController_DealAlreadyFinalized();
    error MetaVesTController_DealVoided();
    error MetaVesTController_CounterPartyNotFound();
    error MetaVesTController_GranteeNotDirectParty();
    error MetaVesTController_PartyValuesLengthMismatch();
    error MetaVesTController_CounterPartyValueMismatch();
    error MetaVesTController_UnknownError(bytes4 error, bytes data);
    error NotRefImplementation();

    function getStorage() internal pure returns (MetaVesTControllerData storage st) {
        bytes32 position = STORAGE_POSITION;
        assembly {
            st.slot := position
        }
    }

    function proposeAndSignDeal(
        bytes32 templateId,
        uint256 salt,
        MetaVestDeal memory dealDraft,
        string[] memory globalValues,
        address[] memory parties,
        string[][] memory partyValues,
        bytes calldata signature,
        bytes32 secretHash,
        uint256 expiry
    ) external returns (MetaVestDeal memory) {
        MetaVesTControllerData storage st = getStorage();

        // Check: verify inputs
        if (parties[1] != dealDraft.grantee) revert MetaVesTController_GranteeNotDirectParty();
        if (partyValues.length < 2) revert MetaVesTController_CounterPartyNotFound();
        if (partyValues[1].length != partyValues[0].length) revert MetaVesTController_PartyValuesLengthMismatch();

        // Call internal function to avoid stack-too-deep errors
        dealDraft.agreementId = ICyberAgreementRegistry(st.registry)
            .createContract(templateId, salt, globalValues, parties, partyValues, secretHash, address(this), expiry);

        st.counterPartyValues[dealDraft.agreementId] = partyValues[1];

        ICyberAgreementRegistry(st.registry)
            .signContractFor(
                st.authority, // First party (grantor) should always be the authority
                dealDraft.agreementId,
                partyValues[0],
                signature,
                false, // Not meant for anyone else other than the signer
                "" // Signer == proposer, no secret needed
            );

        st.deals[dealDraft.agreementId] = dealDraft;
        st.dealIds.push(dealDraft.agreementId);

        emit MetaVesTController_DealProposed(
            dealDraft.agreementId, dealDraft.grantee, dealDraft.metavestType, dealDraft.allocation, dealDraft.milestones,
            secretHash > 0,
            st.registry
        );

        return dealDraft;
    }

    function signDealAndCreateMetavest(
        address grantee,
        address recipient,
        bytes32 agreementId,
        string[] memory partyValues,
        bytes memory signature,
        string memory secret
    ) external returns (address newMetavest, uint256 total) {
        MetaVesTControllerData storage st = getStorage();
        MetaVestDeal storage deal = getStorage().deals[agreementId];

        // Check: verify inputs

        if (ICyberAgreementRegistry(st.registry).isVoided(agreementId)) {
            revert MetaVesTController_DealVoided();
        }
        if (ICyberAgreementRegistry(st.registry).isFinalized(agreementId)) {
            revert MetaVesTController_DealAlreadyFinalized();
        }

        string[] storage counterPartyCheck = st.counterPartyValues[agreementId];
        if (keccak256(abi.encode(counterPartyCheck)) != keccak256(abi.encode(partyValues))) {
            revert MetaVesTController_CounterPartyValueMismatch();
        }

        if (
            deal.grantee == address(0) || recipient == address(0) || deal.allocation.tokenContract == address(0)
                || (deal.metavestType == MetaVestType.TokenOption
                    && deal.paymentToken == address(0)
                    && deal.exercisePrice == 0)
                || (deal.metavestType == MetaVestType.RestrictedTokenAward
                    && deal.paymentToken == address(0)
                    && deal.exercisePrice == 0)
        ) {
            revert MetaVesTController_ZeroAddress();
        }
        if (
            deal.allocation.vestingCliffCredit > deal.allocation.tokenStreamTotal
                || deal.allocation.unlockingCliffCredit > deal.allocation.tokenStreamTotal
        ) {
            revert MetaVesTController_CliffGreaterThanTotal();
        }
        uint256 milestoneTotal = 0;
        if (deal.milestones.length != 0) {
            if (deal.milestones.length > ARRAY_LENGTH_LIMIT) {
                revert MetaVesTController_LengthMismatch();
            }
            for (uint256 i; i < deal.milestones.length; ++i) {
                if (deal.milestones[i].conditionContracts.length > ARRAY_LENGTH_LIMIT) {
                    revert MetaVesTController_LengthMismatch();
                }
                if (deal.milestones[i].milestoneAward == 0) {
                    revert MetaVesTController_ZeroAmount();
                }
                milestoneTotal += deal.milestones[i].milestoneAward;
            }
        }
        total = deal.allocation.tokenStreamTotal + milestoneTotal;
        if (total == 0) {
            revert MetaVesTController_ZeroAmount();
        }
        if (
            IERC20M(deal.allocation.tokenContract).allowance(st.authority, address(this)) < total
                || IERC20M(deal.allocation.tokenContract).balanceOf(st.authority) < total
        ) {
            revert MetaVesTController_AmountNotApprovedForTransferFrom();
        }

        // Interaction: Finalize agreement

        // If the grantee signed the agreement externally (ex. by directly interacting with CyberAgreementRegistry),
        // we will skip the signing step.
        if (!ICyberAgreementRegistry(st.registry).hasSigned(agreementId, grantee)) {
            ICyberAgreementRegistry(st.registry)
                .signContractFor(grantee, agreementId, partyValues, signature, false, secret);
        } else {
            // Already signed in registry; fetch values recorded in the registry and ensure consistency.
            // Theoretically, since the agreement is always close-ended, we could've safely assumed
            // the counterparty values stored in CyberAgreementRegistry vs here are always consistent,
            // but we check it anyways just in case
            string[] memory registryValues = ICyberAgreementRegistry(st.registry).getSignerValues(agreementId, grantee);
            if (keccak256(abi.encode(registryValues)) != keccak256(abi.encode(partyValues))) {
                revert MetaVesTController_CounterPartyValueMismatch();
            }
        }
        ICyberAgreementRegistry(st.registry).finalizeContract(agreementId);

        // Interaction: Create and provision MetaVesT
        if (deal.metavestType == MetaVestType.Vesting) {
            deal.metavest = VestingAllocationFactory.createVestingAllocation(deal, recipient);
        } else if (deal.metavestType == MetaVestType.TokenOption) {
            deal.metavest = TokenOptionFactory.createTokenOptionAllocation(deal, recipient);
        } else if (deal.metavestType == MetaVestType.RestrictedTokenAward) {
            deal.metavest = RestrictedTokenFactory.createRestrictedTokenAward(deal, recipient);
        } else {
            revert MetaVesTController_IncorrectMetaVesTType();
        }
        st.metavestAgreementIds[deal.metavest] = agreementId;

        return (deal.metavest, total);
    }

    function proposeMajorityMetavestAmendment(string memory setName, bytes4 _msgSig, bytes calldata _callData) external {
        MetaVesTControllerData storage st = getStorage();

        // Check: verify inputs

        if(!doesSetExist(setName)) revert MetaVesTController_SetDoesNotExist();
        if(_callData.length!=68) revert MetaVesTController_LengthMismatch();
        bytes32 nameHash = keccak256(bytes(setName));
        //if the majority proposal is already pending and not expired, revert
        if ((st.functionToSetMajorityProposal[_msgSig][nameHash].isPending && block.timestamp < st.functionToSetMajorityProposal[_msgSig][nameHash].time + AMENDMENT_TIME_LIMIT) || st.setMajorityVoteActive[nameHash])
            revert MetaVesTController_AmendmentAlreadyPending();
        
        MajorityAmendmentProposal storage proposal =
            st.functionToSetMajorityProposal[_msgSig][nameHash];
        proposal.isPending = true;
        proposal.dataHash = keccak256(_callData[_callData.length - 32:]);
        proposal.time = block.timestamp;
        proposal.voters = new address[](0);
        proposal.currentVotingPower = 0;

        uint256 totalVotingPower = 0;

        for (uint256 i; i < st.sets[nameHash].length(); ++i) {
            uint256 _votingPower = BaseAllocation(st.sets[nameHash].at(i)).getMajorityVotingPower();
            totalVotingPower += _votingPower;
            proposal.voterPower[st.sets[nameHash].at(i)] = _votingPower;
        }
        proposal.totalVotingPower = totalVotingPower;

        st.setMajorityVoteActive[nameHash] = true;

        emit MetaVesTController_MajorityAmendmentProposed(setName, _msgSig, _callData, totalVotingPower);
    }

    function conditionCheck(bytes4 msgSig) external {
        MetaVesTControllerData storage st = getStorage();
        address[] memory conditions = st.functionToConditions[msgSig];
        for (uint256 i; i < conditions.length; ++i) {
            if (!IConditionM(conditions[i]).checkCondition(address(this), msgSig, "")) {
                revert MetaVesTController_ConditionNotSatisfied(conditions[i]);
            }
        }
    }

    function consentCheck(bytes4 msgSig, address _grant, bytes calldata _data) external {
        MetaVesTControllerData storage st = getStorage();
        if (isMetavestInSet(_grant)) {
            bytes32 set = getSetOfMetavest(_grant);
            MajorityAmendmentProposal storage proposal =
                st.functionToSetMajorityProposal[msgSig][set];
            if (proposal.appliedProposalCreatedAt[_grant] == proposal.time) {
                revert MetaVesTController_AmendmentCanOnlyBeAppliedOnce();
            }
            if (_data.length > 32 && _data.length < 69) {
                if (
                    !proposal.isPending || proposal.totalVotingPower > proposal.currentVotingPower * 2
                        || keccak256(_data[_data.length - 32:]) != proposal.dataHash
                ) {
                    revert MetaVesTController_AmendmentNeitherMutualNorMajorityConsented();
                }
            } else {
                revert MetaVesTController_AmendmentNeitherMutualNorMajorityConsented();
            }
        } else {
            AmendmentProposal storage proposal =
                st.functionToGranteeToAmendmentPending[msgSig][_grant];
            if (!proposal.inFavor || proposal.dataHash != keccak256(_data)) {
                revert MetaVesTController_AmendmentNeitherMutualNorMajorityConsented();
            }
        }
    }

    function isMetavestInSet(address _metavest) internal view returns (bool) {
        MetaVesTControllerData storage st = getStorage();
        uint256 length = st.setNames.length();
        for (uint256 i = 0; i < length; i++) {
            bytes32 nameHash = st.setNames.at(i);
            if (st.sets[nameHash].contains(_metavest)) {
                return true;
            }
        }
        return false;
    }

    function getSetOfMetavest(address _metavest) internal view returns (bytes32) {
        MetaVesTControllerData storage st = getStorage();
        uint256 length = st.setNames.length();
        for (uint256 i = 0; i < length; i++) {
            bytes32 nameHash = st.setNames.at(i);
            if (st.sets[nameHash].contains(_metavest)) {
                return nameHash;
            }
        }
        return "";
    }

    function doesSetExist(string memory _name) internal view returns (bool) {
        return getStorage().setNames.contains(keccak256(bytes(_name)));
    }
}
