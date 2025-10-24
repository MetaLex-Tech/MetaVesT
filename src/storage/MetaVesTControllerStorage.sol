
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

import {ICyberAgreementRegistry} from "cybercorps-contracts/src/interfaces/ICyberAgreementRegistry.sol";
import {EnumerableSet} from "../lib/EnumberableSet.sol";
import {MetaVestDealLib, MetaVestDeal, MetaVestType} from "../lib/MetaVestDealLib.sol";
import {IAllocationFactory} from "../interfaces/IAllocationFactory.sol";

library MetaVesTControllerStorage {
    using EnumerableSet for EnumerableSet.AddressSet;
    using EnumerableSet for EnumerableSet.Bytes32Set;

    // Storage slot for our struct
    bytes32 constant internal STORAGE_POSITION = keccak256("cybercorp.metavest.controller.storage.v1");

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
        address vestingFactory;
        address tokenOptionFactory;
        address restrictedTokenFactory;
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

    function getStorage() internal pure returns (MetaVesTControllerData storage st) {
        bytes32 position = STORAGE_POSITION;
        assembly {
            st.slot := position
        }
    }

    function createMetavest(bytes32 agreementId, address recipient) internal returns (address) {
        MetaVesTControllerStorage.MetaVesTControllerData storage st = MetaVesTControllerStorage.getStorage();

        MetaVestDeal storage deal = st.deals[agreementId];

        if(deal.metavestType == MetaVestType.Vesting) {
            deal.metavest = createVestingAllocation(deal, recipient);
        } else if(deal.metavestType == MetaVestType.TokenOption) {
            deal.metavest = createTokenOptionAllocation(deal, recipient);
        } else if(deal.metavestType == MetaVestType.RestrictedTokenAward) {
            deal.metavest = createRestrictedTokenAward(deal, recipient);
        } else {
            return address(0);
        }
        st.metavestAgreementIds[deal.metavest] = agreementId;

        return deal.metavest;
    }

    // TODO why doesn't it need conditionCheck?
    function createVestingAllocation(MetaVestDeal storage deal, address recipient) internal returns (address){
        MetaVesTControllerStorage.MetaVesTControllerData storage st = MetaVesTControllerStorage.getStorage();
        address vestingAllocation = IAllocationFactory(st.vestingFactory).createAllocation(
            IAllocationFactory.AllocationType.Vesting,
            deal.grantee,
            recipient,
            address(this),
            deal.allocation,
            deal.milestones,
            address(0),
            0,
            0
        );

        return vestingAllocation;
    }

    // TODO where should we put conditionCheck instead since it will emit events?
    function createTokenOptionAllocation(MetaVestDeal storage deal, address recipient) internal returns (address) {
        MetaVesTControllerStorage.MetaVesTControllerData storage st = MetaVesTControllerStorage.getStorage();
        address tokenOptionAllocation = IAllocationFactory(st.tokenOptionFactory).createAllocation(
            IAllocationFactory.AllocationType.TokenOption,
            deal.grantee,
            recipient,
            address(this),
            deal.allocation,
            deal.milestones,
            deal.paymentToken,
            deal.exercisePrice,
            deal.shortStopDuration
        );

        return tokenOptionAllocation;
    }

    // TODO where should we put conditionCheck instead since it will emit events?
    function createRestrictedTokenAward(MetaVestDeal storage deal, address recipient) internal returns (address){
        MetaVesTControllerStorage.MetaVesTControllerData storage st = MetaVesTControllerStorage.getStorage();
        address restrictedTokenAward = IAllocationFactory(st.restrictedTokenFactory).createAllocation(
            IAllocationFactory.AllocationType.RestrictedToken,
            deal.grantee,
            recipient,
            address(this),
            deal.allocation,
            deal.milestones,
            deal.paymentToken,
            deal.exercisePrice,
            deal.shortStopDuration
        );

        return restrictedTokenAward;
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
        MetaVesTControllerStorage.MetaVesTControllerData storage st = MetaVesTControllerStorage.getStorage();

        // Call internal function to avoid stack-too-deep errors
        dealDraft.agreementId = ICyberAgreementRegistry(st.registry).createContract(
            templateId,
            salt,
            globalValues,
            parties,
            partyValues,
            secretHash,
            address(this),
            expiry
        );

        st.counterPartyValues[dealDraft.agreementId] = partyValues[1];

        ICyberAgreementRegistry(st.registry).signContractFor(
            st.authority, // First party (grantor) should always be the authority
            dealDraft.agreementId,
            partyValues[0],
            signature,
            false, // Not meant for anyone else other than the signer
            "" // Signer == proposer, no secret needed
        );

        st.deals[dealDraft.agreementId] = dealDraft;
        st.dealIds.push(dealDraft.agreementId);

        return dealDraft;
    }

    function signDealAndCreateMetavest(
        address grantee,
        address recipient,
        bytes32 agreementId,
        string[] memory partyValues,
        bytes memory signature,
        string memory secret
    ) external returns (address) {
        MetaVesTControllerStorage.MetaVesTControllerData storage st = MetaVesTControllerStorage.getStorage();

        // Finalize agreement
        ICyberAgreementRegistry(st.registry).signContractFor(grantee, agreementId, partyValues, signature, false, secret);
        ICyberAgreementRegistry(st.registry).finalizeContract(agreementId);

        // Create and provision MetaVesT
        return createMetavest(agreementId, recipient);
    }

    function removeFunctionCondition(address _condition, bytes4 _functionSig) external {
        MetaVesTControllerStorage.MetaVesTControllerData storage st = MetaVesTControllerStorage.getStorage();
        address[] storage conditions = st.functionToConditions[_functionSig];
        for (uint256 i; i < conditions.length; ++i) {
            if (conditions[i] == _condition) {
                conditions[i] = conditions[conditions.length - 1];
                conditions.pop();
                break;
            }
        }
    }
}
