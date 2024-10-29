//SPDX-License-Identifier: AGPL-3.0-only

/*
**************************************
                            MetaVesT Controller
                                     *************************************
                                                                        */

pragma solidity 0.8.20;

import "./interfaces/IAllocationFactory.sol";
import "./BaseAllocation.sol";
import "./interfaces/IPriceAllocation.sol";
import "./lib/EnumberableSet.sol";

/**
 * @title      MetaVesT Controller
 *
 * @author     MetaLeX Labs, Inc.
 *
 * @notice     Contract for a MetaVesT's authority to configure parameters, confirm milestones, and
 *             other permissioned functions, with some powers checked by the applicable 'dao' or subject to consent
 *             by an applicable affected grantee or a majority-in-governing power of similar token grantees
 **/
contract metavestController is SafeTransferLib {
    using EnumerableSet for EnumerableSet.AddressSet;
    using EnumerableSet for EnumerableSet.Bytes32Set;
    /// @dev opinionated time limit for a MetaVesT amendment, one calendar week in seconds
    uint256 internal constant AMENDMENT_TIME_LIMIT = 604800;
    uint256 internal constant ARRAY_LENGTH_LIMIT = 20;

    mapping(bytes32 => EnumerableSet.AddressSet) private sets;
    EnumerableSet.Bytes32Set private setNames;

    address public authority;
    address public dao;
    address public vestingFactory;
    address public tokenOptionFactory;
    address public restrictedTokenFactory;
    address internal _pendingAuthority;
    address internal _pendingDao;

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
        mapping(address => bool) changeApplied;
        mapping(address => uint256) voterPower;
    }

    enum metavestType {
        Vesting,
        TokenOption,
        RestrictedTokenAward
    }

    /// @notice maps a function's signature to a Condition contract address
    mapping(bytes4 => address[]) public functionToConditions;

    /// @notice maps a metavest-parameter-updating function's signature to token contract to whether a majority amendment is pending
    mapping(bytes4 => mapping(bytes32 => MajorityAmendmentProposal))
        public functionToSetMajorityProposal;

    /// @notice maps a metavest-parameter-updating function's signature to affected grantee address to whether an amendment is pending
    mapping(bytes4 => mapping(address => AmendmentProposal))
        public functionToGranteeToAmendmentPending;

    /// @notice tracks if an address has voted for an amendment by mapping a hash of the pertinent details to time they last voted for these details (voter, function and affected grantee)
    mapping(bytes32 => uint256) internal _lastVoted;

    mapping(bytes32 => bool) public setMajorityVoteActive;

    ///
    /// EVENTS
    ///

    event MetaVesTController_AmendmentConsentUpdated(
        bytes4 indexed msgSig,
        address indexed grantee,
        bool inFavor
    );
    event MetaVesTController_AmendmentProposed(
        address indexed grant,
        bytes4 msgSig
    );
    event MetaVesTController_AuthorityUpdated(address indexed newAuthority);
    event MetaVesTController_ConditionUpdated(
        address indexed condition,
        bytes4 functionSig
    );
    event MetaVesTController_DaoUpdated(address newDao);
    event MetaVesTController_MajorityAmendmentProposed(
        string indexed set,
        bytes4 msgSig,
        bytes callData,
        uint256 totalVotingPower
    );
    event MetaVesTController_MajorityAmendmentVoted(
        string indexed set,
        bytes4 msgSig,
        address grantee,
        bool inFavor,
        uint256 votingPower,
        uint256 currentVotingPower,
        uint256 totalVotingPower
    );
    event MetaVesTController_SetCreated(string indexed set);
    event MetaVesTController_SetRemoved(string indexed set);
    event MetaVesTController_AddressAddedToSet(
        string set,
        address indexed grantee
    );
    event MetaVesTController_AddressRemovedFromSet(
        string set,
        address indexed grantee
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
    error MetaVesTController_NoPendingAmendment(
        bytes4 msgSig,
        address affectedGrantee
    );
    error MetaVesTController_OnlyAuthority();
    error MetaVesTController_OnlyDAO();
    error MetaVesTController_OnlyPendingAuthority();
    error MetaVesTController_OnlyPendingDao();
    error MetaVesTController_ProposedAmendmentExpired();
    error MetaVesTController_ZeroAddress();
    error MetaVesTController_ZeroAmount();
    error MetaVesTController_ZeroPrice();
    error MetaVesT_AmountNotApprovedForTransferFrom();
    error MetaVesTController_SetDoesNotExist();
    error MetaVestController_MetaVestNotInSet();
    error MetaVesTController_SetAlreadyExists();
    error MetaVesTController_StringTooLong();

    ///
    /// FUNCTIONS
    ///

    modifier conditionCheck() {
        address[] memory conditions = functionToConditions[msg.sig];
        for (uint256 i; i < conditions.length; ++i) {
            if (
                !IConditionM(conditions[i]).checkCondition(
                    address(this),
                    msg.sig,
                    ""
                )
            ) {
                revert MetaVesTController_ConditionNotSatisfied(conditions[i]);
            }
        }
        _;
    }

    modifier consentCheck(address _grant, bytes calldata _data) {
        if (isMetavestInSet(_grant)) {
            bytes32 set = getSetOfMetavest(_grant);
            MajorityAmendmentProposal
                storage proposal = functionToSetMajorityProposal[msg.sig][set];
            if (proposal.changeApplied[_grant])
                revert MetaVesTController_AmendmentCanOnlyBeAppliedOnce();
            if (_data.length > 32 && _data.length < 69) {
                if (
                    !proposal.isPending ||
                    proposal.totalVotingPower >
                    proposal.currentVotingPower * 2 ||
                    keccak256(_data[_data.length - 32:]) != proposal.dataHash
                ) {
                    revert MetaVesTController_AmendmentNeitherMutualNorMajorityConsented();
                }
            } else
                revert MetaVesTController_AmendmentNeitherMutualNorMajorityConsented();
        } else {
            AmendmentProposal
                storage proposal = functionToGranteeToAmendmentPending[msg.sig][
                    _grant
                ];
            if (!proposal.inFavor || proposal.dataHash != keccak256(_data)) {
                revert MetaVesTController_AmendmentNeitherMutualNorMajorityConsented();
            }
        }
        _;
    }

    modifier onlyAuthority() {
        if (msg.sender != authority) revert MetaVesTController_OnlyAuthority();
        _;
    }

    modifier onlyDao() {
        if (msg.sender != dao) revert MetaVesTController_OnlyDAO();
        _;
    }

    /// @param _authority address of the authority who can call the functions in this contract and update each MetaVesT, such as a BORG
    /// @param _dao DAO governance contract address which exercises control over ability of 'authority' to call certain functions via imposing conditions through 'updateFunctionCondition'.
    /// @param _vestingFactory vesting allocation factory (VestingAllocationFactory.sol) contract address
    /// @param _tokenOptionFactory token option factory (TokenOptionFactory.sol) contract address
    /// @param _restrictedTokenFactory restricted token award factory (RestrictedTokenFactory.sol) contract address
    constructor(
        address _authority,
        address _dao,
        address _vestingFactory,
        address _tokenOptionFactory,
        address _restrictedTokenFactory
    ) {
        if (_authority == address(0)) revert MetaVesTController_ZeroAddress();
        authority = _authority;
        vestingFactory = _vestingFactory;
        tokenOptionFactory = _tokenOptionFactory;
        restrictedTokenFactory = _restrictedTokenFactory;
        dao = _dao;
    }

    /// @notice for a grantee to consent to an update to one of their metavestDetails by 'authority' corresponding to the applicable function in this controller
    /// @param _grant address of grantee providing (or revoking) consent
    /// @param _msgSig function signature of the function in this controller which (if successfully executed) will execute the grantee's metavest detail update
    /// @param _inFavor whether msg.sender consents to the applicable amending function call (rather than assuming true, this param allows a grantee to later revoke decision should 'authority' delay or breach agreement elsewhere)
    function consentToMetavestAmendment(
        address _grant,
        bytes4 _msgSig,
        bool _inFavor
    ) external {
        if (!functionToGranteeToAmendmentPending[_msgSig][_grant].isPending)
            revert MetaVesTController_NoPendingAmendment(_msgSig, _grant);
        address grantee = BaseAllocation(_grant).grantee();
        if (msg.sender != grantee)
            revert MetaVesTController_OnlyGranteeMayCall();

        functionToGranteeToAmendmentPending[_msgSig][_grant].inFavor = _inFavor;
        emit MetaVesTController_AmendmentConsentUpdated(
            _msgSig,
            msg.sender,
            _inFavor
        );
    }

    /// @notice enables the DAO to toggle whether a function requires Condition contract calls (enabling time delays, signature conditions, etc.)
    /// @dev see https://github.com/MetaLex-Tech/BORG-CORE/tree/main/src/libs/conditions for condition options; note this mechanic requires all conditions satisfied, but logic within such conditions is flexible
    /// @param _condition address of the applicable Condition contract-- pass address(0) to remove the requirement for '_functionSig'
    /// @param _functionSig signature of the function which is having its condition requirement updated
    function updateFunctionCondition(
        address _condition,
        bytes4 _functionSig
    ) external onlyDao {
        //call check condition to ensure the condition is valid
        IConditionM(_condition).checkCondition(address(this), msg.sig, "");
        //check to ensure the condition is unique
        for (uint256 i; i < functionToConditions[_functionSig].length; ++i) {
            if (functionToConditions[_functionSig][i] == _condition)
                revert MetaVestController_DuplicateCondition();
        }
        functionToConditions[_functionSig].push(_condition);
        emit MetaVesTController_ConditionUpdated(_condition, _functionSig);
    }

    /// @notice enables the DAO to remove a function condition
    /// @param _condition address of the applicable Condition contract
    /// @param _functionSig signature of the function which is having its condition requirement removed
    function removeFunctionCondition(
        address _condition,
        bytes4 _functionSig
    ) external onlyDao {
        address[] storage conditions = functionToConditions[_functionSig];
        for (uint256 i; i < conditions.length; ++i) {
            if (conditions[i] == _condition) {
                conditions[i] = conditions[conditions.length - 1];
                conditions.pop();
                break;
            }
        }
        emit MetaVesTController_ConditionUpdated(_condition, _functionSig);
    }

    /// @notice allows `authority` to create a new MetaVesT for `_grantee` via the applicable factory contract
    /// @param _type metavestType enum corresponding to a vesting, token option, or restricted token award metavest that is being created
    /// @param _grantee address of the grantee receiving the MetaVesT
    /// @param _allocation BaseAllocation.Allocation struct details of the allocation applicable to this grantee
    /// @param _milestones array of BaseAllocation.Milestone structs, setting out the milestones (if any) for this grantee
    /// @param _exercisePrice if _type == TokenOption, the token option exercise price; If _type == RestrictedToken, this corresponds to the _repurchasePrice
    /// @param _paymentToken contract address for the token used to pay for token option exercises (for grantee, if a token option) or restricted token repurchases (for authority, if a restricted token award)
    /// @param _shortStopDuration if _type == TokenOption, length of period before vesting stop time and exercise deadline; if _type == RestrictedToken, length of period before lapse stop time and repurchase deadline
    function createMetavest(
        metavestType _type,
        address _grantee,
        BaseAllocation.Allocation calldata _allocation,
        BaseAllocation.Milestone[] calldata _milestones,
        uint256 _exercisePrice,
        address _paymentToken,
        uint256 _shortStopDuration
    ) external onlyAuthority conditionCheck returns (address) {
        address newMetavest;
        if (_type == metavestType.Vesting) {
            newMetavest = createVestingAllocation(
                _grantee,
                _allocation,
                _milestones
            );
        } else if (_type == metavestType.TokenOption) {
            newMetavest = createTokenOptionAllocation(
                _grantee,
                _exercisePrice,
                _paymentToken,
                _shortStopDuration,
                _allocation,
                _milestones
            );
        } else if (_type == metavestType.RestrictedTokenAward) {
            newMetavest = createRestrictedTokenAward(
                _grantee,
                _exercisePrice,
                _paymentToken,
                _shortStopDuration,
                _allocation,
                _milestones
            );
        } else {
            revert MetaVesTController_IncorrectMetaVesTType();
        }
        return newMetavest;
    }

    /// @notice validates certain metavest parameters as being nonzero
    function validateInputParameters(
        address _grantee,
        address _paymentToken,
        uint256 _exercisePrice,
        VestingAllocation.Allocation calldata _allocation
    ) internal pure {
        if (
            _grantee == address(0) ||
            _allocation.tokenContract == address(0) ||
            _paymentToken == address(0) ||
            _exercisePrice == 0
        ) revert MetaVesTController_ZeroAddress();
    }

    /// @notice validates allocation cliff details
    function validateAllocation(
        VestingAllocation.Allocation calldata _allocation
    ) internal pure {
        if (
            _allocation.vestingCliffCredit > _allocation.tokenStreamTotal ||
            _allocation.unlockingCliffCredit > _allocation.tokenStreamTotal
        ) revert MetaVesTController_CliffGreaterThanTotal();
    }

    /// @notice validates milestones as being proper in length and nonzero in amount
    function validateAndCalculateMilestones(
        VestingAllocation.Milestone[] calldata _milestones
    ) internal pure returns (uint256 _milestoneTotal) {
        if (_milestones.length != 0) {
            if (_milestones.length > ARRAY_LENGTH_LIMIT)
                revert MetaVesTController_LengthMismatch();
            for (uint256 i; i < _milestones.length; ++i) {
                if (
                    _milestones[i].conditionContracts.length >
                    ARRAY_LENGTH_LIMIT
                ) revert MetaVesTController_LengthMismatch();
                if (_milestones[i].milestoneAward == 0)
                    revert MetaVesTController_ZeroAmount();
                _milestoneTotal += _milestones[i].milestoneAward;
            }
        }
    }

    /// @notice validates token approvals and balances of authority
    function validateTokenApprovalAndBalance(
        address tokenContract,
        uint256 total
    ) internal view {
        if (
            IERC20M(tokenContract).allowance(authority, address(this)) <
            total ||
            IERC20M(tokenContract).balanceOf(authority) < total
        ) revert MetaVesTController_AmountNotApprovedForTransferFrom();
    }

    function createAndInitializeTokenOptionAllocation(
        address _grantee,
        address _paymentToken,
        uint256 _exercisePrice,
        uint256 _shortStopDuration,
        VestingAllocation.Allocation calldata _allocation,
        VestingAllocation.Milestone[] calldata _milestones
    ) internal returns (address) {
        return
            IAllocationFactory(tokenOptionFactory).createAllocation(
                IAllocationFactory.AllocationType.TokenOption,
                _grantee,
                address(this),
                _allocation,
                _milestones,
                _paymentToken,
                _exercisePrice,
                _shortStopDuration
            );
    }

    function createAndInitializeRestrictedTokenAward(
        address _grantee,
        address _paymentToken,
        uint256 _repurchasePrice,
        uint256 _shortStopDuration,
        VestingAllocation.Allocation calldata _allocation,
        VestingAllocation.Milestone[] calldata _milestones
    ) internal returns (address) {
        return
            IAllocationFactory(restrictedTokenFactory).createAllocation(
                IAllocationFactory.AllocationType.RestrictedToken,
                _grantee,
                address(this),
                _allocation,
                _milestones,
                _paymentToken,
                _repurchasePrice,
                _shortStopDuration
            );
    }

    /// @notice creates a new vesting allocation MetaVesT for `_grantee`
    function createVestingAllocation(
        address _grantee,
        VestingAllocation.Allocation calldata _allocation,
        VestingAllocation.Milestone[] calldata _milestones
    ) internal returns (address) {
        //hard code values not to trigger the failure for the 2 parameters that don't matter for this type of allocation
        validateInputParameters(_grantee, address(this), 1, _allocation);
        validateAllocation(_allocation);
        uint256 _milestoneTotal = validateAndCalculateMilestones(_milestones);

        uint256 _total = _allocation.tokenStreamTotal + _milestoneTotal;
        if (_total == 0) revert MetaVesTController_ZeroAmount();
        validateTokenApprovalAndBalance(_allocation.tokenContract, _total);

        address vestingAllocation = IAllocationFactory(vestingFactory)
            .createAllocation(
                IAllocationFactory.AllocationType.Vesting,
                _grantee,
                address(this),
                _allocation,
                _milestones,
                address(0),
                0,
                0
            );
        safeTransferFrom(
            _allocation.tokenContract,
            authority,
            vestingAllocation,
            _total
        );

        return vestingAllocation;
    }

    /// @notice creates a new token option MetaVesT for `_grantee`
    function createTokenOptionAllocation(
        address _grantee,
        uint256 _exercisePrice,
        address _paymentToken,
        uint256 _shortStopDuration,
        VestingAllocation.Allocation calldata _allocation,
        VestingAllocation.Milestone[] calldata _milestones
    ) internal conditionCheck returns (address) {
        validateInputParameters(
            _grantee,
            _paymentToken,
            _exercisePrice,
            _allocation
        );
        validateAllocation(_allocation);
        uint256 _milestoneTotal = validateAndCalculateMilestones(_milestones);

        uint256 _total = _allocation.tokenStreamTotal + _milestoneTotal;
        if (_total == 0) revert MetaVesTController_ZeroAmount();
        validateTokenApprovalAndBalance(_allocation.tokenContract, _total);

        address tokenOptionAllocation = createAndInitializeTokenOptionAllocation(
                _grantee,
                _paymentToken,
                _exercisePrice,
                _shortStopDuration,
                _allocation,
                _milestones
            );

        safeTransferFrom(
            _allocation.tokenContract,
            authority,
            tokenOptionAllocation,
            _total
        );
        return tokenOptionAllocation;
    }

    /// @notice creates a new restricted token award MetaVesT for `_grantee`
    function createRestrictedTokenAward(
        address _grantee,
        uint256 _repurchasePrice,
        address _paymentToken,
        uint256 _shortStopDuration,
        VestingAllocation.Allocation calldata _allocation,
        VestingAllocation.Milestone[] calldata _milestones
    ) internal conditionCheck returns (address) {
        validateInputParameters(
            _grantee,
            _paymentToken,
            _repurchasePrice,
            _allocation
        );
        validateAllocation(_allocation);
        uint256 _milestoneTotal = validateAndCalculateMilestones(_milestones);

        uint256 _total = _allocation.tokenStreamTotal + _milestoneTotal;
        if (_total == 0) revert MetaVesTController_ZeroAmount();
        validateTokenApprovalAndBalance(_allocation.tokenContract, _total);

        address restrictedTokenAward = createAndInitializeRestrictedTokenAward(
            _grantee,
            _paymentToken,
            _repurchasePrice,
            _shortStopDuration,
            _allocation,
            _milestones
        );

        safeTransferFrom(
            _allocation.tokenContract,
            authority,
            restrictedTokenAward,
            _total
        );
        return restrictedTokenAward;
    }

    /// @notice getter function to return a grantee's vesting type
    /// @param _grant grantee's address
    function getMetaVestType(address _grant) public view returns (uint256) {
        return BaseAllocation(_grant).getVestingType();
    }

    /// @notice for 'authority' to withdraw tokens from this controller (i.e. which it has withdrawn from 'metavest', typically 'paymentToken')
    /// @param _tokenContract contract address of the token which is being withdrawn
    function withdrawFromController(
        address _tokenContract
    ) external onlyAuthority {
        uint256 _balance = IERC20M(_tokenContract).balanceOf(address(this));
        if (_balance == 0) revert MetaVesTController_ZeroAmount();

        safeTransfer(_tokenContract, authority, _balance);
    }

    /// @notice for 'authority' to toggle whether '_grantee''s MetaVesT is transferable-- does not revoke previous transfers, but does cause such transferees' MetaVesTs transferability to be similarly updated
    /// @param _grant address whose MetaVesT's (and whose transferees' MetaVesTs') transferability is being updated
    /// @param _isTransferable whether transferability is to be updated to transferable (true) or nontransferable (false)
    function updateMetavestTransferability(
        address _grant,
        bool _isTransferable
    ) external onlyAuthority conditionCheck consentCheck(_grant, msg.data) {
        _resetAmendmentParams(_grant, msg.sig);
        BaseAllocation(_grant).updateTransferability(_isTransferable);
    }

    /// @notice for the controller to update either exercisePrice or repurchasePrice for a '_grantee' and their transferees, as applicable depending on the '_grantee''s MetaVesTType
    /// @param _grant address of grantee whose applicable price is being updated
    /// @param _newPrice new exercisePrice (if token option) or (repurchase price if restricted token award) as 'paymentToken' per 1 metavested token in vesting token decimals but only up to payment decimal precision
    function updateExerciseOrRepurchasePrice(
        address _grant,
        uint256 _newPrice
    ) external onlyAuthority conditionCheck consentCheck(_grant, msg.data) {
        if (_newPrice == 0) revert MetaVesTController_ZeroPrice();
        IPriceAllocation grant = IPriceAllocation(_grant);
        if (grant.getVestingType() != 2 && grant.getVestingType() != 3)
            revert MetaVesTController_IncorrectMetaVesTType();
        _resetAmendmentParams(_grant, msg.sig);
        grant.updatePrice(_newPrice);
    }

    /// @notice removes a milestone from '_grantee''s MetaVesT if such milestone has not yet been confirmed, also making the corresponding 'milestoneAward' tokens withdrawable by controller
    /// @param _grant address of grantee whose MetaVesT is being updated
    /// @param _milestoneIndex element of the '_grantee''s 'milestones' array to be removed
    function removeMetavestMilestone(
        address _grant,
        uint256 _milestoneIndex
    ) external onlyAuthority conditionCheck consentCheck(_grant, msg.data) {
        _resetAmendmentParams(_grant, msg.sig);
        (uint256 milestoneAward, , bool completed) = BaseAllocation(_grant)
            .milestones(_milestoneIndex);
        if (completed || milestoneAward == 0)
            revert MetaVesTController_MilestoneIndexCompletedOrDoesNotExist();
        BaseAllocation(_grant).removeMilestone(_milestoneIndex);
    }

    /// @notice add a milestone for a '_grantee' (and any transferees) and transfer the milestoneAward amount of tokens
    /// @param _grant address of grantee whose MetaVesT is being updated
    /// @param _milestone new Milestone struct added for '_grant', to be added to their 'milestones' array
    function addMetavestMilestone(
        address _grant,
        VestingAllocation.Milestone calldata _milestone
    ) external onlyAuthority {
        address _tokenContract = BaseAllocation(_grant)
            .getMetavestDetails()
            .tokenContract;
        if (_milestone.milestoneAward == 0)
            revert MetaVesTController_ZeroAmount();
        if (_milestone.conditionContracts.length > ARRAY_LENGTH_LIMIT)
            revert MetaVesTController_LengthMismatch();
        if (_milestone.complete == true)
            revert MetaVesTController_MilestoneIndexCompletedOrDoesNotExist();
        if (
            IERC20M(_tokenContract).allowance(msg.sender, address(this)) <
            _milestone.milestoneAward ||
            IERC20M(_tokenContract).balanceOf(msg.sender) <
            _milestone.milestoneAward
        ) revert MetaVesT_AmountNotApprovedForTransferFrom();

        // send the new milestoneAward to 'metavest'
        safeTransferFrom(
            _tokenContract,
            msg.sender,
            _grant,
            _milestone.milestoneAward
        );
        BaseAllocation(_grant).addMilestone(_milestone);
    }

    /// @notice for 'authority' to update a MetaVesT's unlockRate (including any transferees)
    /// @dev an '_unlockRate' of 0 is permissible to enable temporary freezes of allocation unlocks by authority
    /// @param _grant address of grantee whose MetaVesT is being updated
    /// @param _unlockRate token unlock rate in tokens per second
    function updateMetavestUnlockRate(
        address _grant,
        uint160 _unlockRate
    ) external onlyAuthority conditionCheck consentCheck(_grant, msg.data) {
        _resetAmendmentParams(_grant, msg.sig);
        BaseAllocation(_grant).updateUnlockRate(_unlockRate);
    }

    /// @notice for 'authority' to update a MetaVesT's vestingRate if the vest has been terminated and previously unlock rate set to 0
    /// @param _grant address of grantee whose MetaVesT is being updated
    /// @param _unlockRate token vesting rate in tokens per second
    function emergencyUpdateMetavestUnlockRate(
        address _grant,
        uint160 _unlockRate
    ) external onlyAuthority conditionCheck {
        //get unlock rate from the _grant
        (, , , , , uint160 unlockRate, , ) = BaseAllocation(_grant)
            .allocation();
        if (BaseAllocation(_grant).terminated() == false || unlockRate != 0)
            revert MetaVesTController_EmergencyUnlockNotSatisfied();
        BaseAllocation(_grant).updateUnlockRate(_unlockRate);
    }

    /// @notice for 'authority' to update a MetaVesT's vestingRate (including any transferees)
    /// @dev a '_vestingRate' of 0 is permissible to enable temporary freezes of allocation vestings by authority, but to permanently terminate vesting, call 'terminateMetavestVesting'
    /// @param _grant address of grantee whose MetaVesT is being updated
    /// @param _vestingRate token vesting rate in tokens per second
    function updateMetavestVestingRate(
        address _grant,
        uint160 _vestingRate
    ) external onlyAuthority conditionCheck consentCheck(_grant, msg.data) {
        _resetAmendmentParams(_grant, msg.sig);
        BaseAllocation(_grant).updateVestingRate(_vestingRate);
    }

    /// @notice for authority to update a MetaVesT's stopTime and/or shortStopTime, as applicable (including any transferees)
    /// @dev if '_shortStopTime' has already occurred, it will be ignored in MetaVest.sol. Allows stop times before block.timestamp to enable accelerated schedules.
    /// @param _grant address of grantee whose MetaVesT is being updated
    /// @param _shortStopTime if token option, vesting stop time and exercise deadline; if restricted token award, lapse stop time and repurchase deadline -- must be <= vestingStopTime
    function updateMetavestStopTimes(
        address _grant,
        uint48 _shortStopTime
    ) external onlyAuthority conditionCheck consentCheck(_grant, msg.data) {
        _resetAmendmentParams(_grant, msg.sig);
        BaseAllocation(_grant).updateStopTimes(_shortStopTime);
    }

    /// @notice for 'authority' to irrevocably terminate (stop) this '_grantee''s vesting (including transferees), but preserving the unlocking schedule for any already-vested tokens, so their MetaVesT is not deleted
    /// @dev returns unvested remainder to 'authority' but preserves MetaVesT for all vested tokens up until call. To temporarily/revocably stop vesting, use 'updateVestingRate'
    /// @param _grant: address of grantee whose MetaVesT's vesting is being stopped
    function terminateMetavestVesting(
        address _grant
    ) external onlyAuthority conditionCheck {
        _resetAmendmentParams(_grant, msg.sig);
        BaseAllocation(_grant).terminate();
    }

    /// @notice for `authority` to set the `GovType` for a grantee's MetaVesT
    /// @param _grant the applicable grantee's address
    /// @param _govType BaseAllocation.GovType struct corresponding to the governance for this grantee's MetaVesT
    function setMetaVestGovVariables(
        address _grant,
        BaseAllocation.GovType _govType
    ) external onlyAuthority consentCheck(_grant, msg.data) {
        _resetAmendmentParams(_grant, msg.sig);
        BaseAllocation(_grant).setGovVariables(_govType);
    }

    /// @notice allows the 'authority' to propose a replacement to their address. First step in two-step address change, as '_newAuthority' will subsequently need to call 'acceptAuthorityRole()'
    /// @dev use care in updating 'authority' as it must have the ability to call 'acceptAuthorityRole()', or once it needs to be replaced, 'updateAuthority()'
    /// @param _newAuthority new address for pending 'authority', who must accept the role by calling 'acceptAuthorityRole'
    function initiateAuthorityUpdate(
        address _newAuthority
    ) external onlyAuthority {
        if (_newAuthority == address(0))
            revert MetaVesTController_ZeroAddress();
        _pendingAuthority = _newAuthority;
    }

    /// @notice allows the pending new authority to accept the role transfer
    /// @dev access restricted to the address stored as '_pendingauthority' to accept the two-step change. Transfers 'authority' role to the caller (reflected in 'metavest') and deletes '_pendingauthority' to reset.
    function acceptAuthorityRole() external {
        if (msg.sender != _pendingAuthority)
            revert MetaVesTController_OnlyPendingAuthority();
        delete _pendingAuthority;
        authority = msg.sender;
        emit MetaVesTController_AuthorityUpdated(msg.sender);
    }

    /// @notice allows the 'dao' to propose a replacement to their address. First step in two-step address change, as '_newDao' will subsequently need to call 'acceptDaoRole()'
    /// @dev use care in updating 'dao' as it must have the ability to call 'acceptDaoRole()'
    /// @param _newDao new address for pending 'dao', who must accept the role by calling 'acceptDaoRole'
    function initiateDaoUpdate(address _newDao) external onlyDao {
        if (_newDao == address(0)) revert MetaVesTController_ZeroAddress();
        _pendingDao = _newDao;
    }

    /// @notice allows the pending new dao to accept the role transfer
    /// @dev access restricted to the address stored as '_pendingDao' to accept the two-step change. Transfers 'dao' role to the caller (reflected in 'metavest') and deletes '_pendingDao' to reset.
    /// no 'conditionCheck' necessary as it more properly contained in 'initiateAuthorityUpdate'
    function acceptDaoRole() external {
        if (msg.sender != _pendingDao)
            revert MetaVesTController_OnlyPendingDao();
        delete _pendingDao;
        dao = msg.sender;
        emit MetaVesTController_DaoUpdated(msg.sender);
    }

    /// @notice for 'authority' to propose a metavest detail amendment
    /// @param _grant address of the grantee whose metavest is being updated
    /// @param _msgSig function signature of the function in this controller which (if successfully executed) will execute the metavest detail update
    /// @param _callData data corresponding to the proposed amendment
    function proposeMetavestAmendment(
        address _grant,
        bytes4 _msgSig,
        bytes memory _callData
    ) external onlyAuthority {
        //override existing amendment if it exists
        functionToGranteeToAmendmentPending[_msgSig][
            _grant
        ] = AmendmentProposal(true, keccak256(_callData), false);
        emit MetaVesTController_AmendmentProposed(_grant, _msgSig);
    }

    /// @notice for 'authority' to propose a metavest detail amendment
    /// @param setName name of the set for majority set amendment proposal
    /// @param _msgSig function signature of the function in this controller which (if successfully executed) will execute the metavest detail update
    /// @param _callData data for the amendment
    function proposeMajorityMetavestAmendment(
        string memory setName,
        bytes4 _msgSig,
        bytes calldata _callData
    ) external onlyAuthority {
        if (!doesSetExist(setName)) revert MetaVesTController_SetDoesNotExist();
        if (_callData.length != 68) revert MetaVesTController_LengthMismatch();
        bytes32 nameHash = keccak256(bytes(setName));
        //if the majority proposal is already pending and not expired, revert
        if (
            (functionToSetMajorityProposal[_msgSig][nameHash].isPending &&
                block.timestamp <
                functionToSetMajorityProposal[_msgSig][nameHash].time +
                    AMENDMENT_TIME_LIMIT) || setMajorityVoteActive[nameHash]
        ) revert MetaVesTController_AmendmentAlreadyPending();

        MajorityAmendmentProposal
            storage proposal = functionToSetMajorityProposal[_msgSig][nameHash];
        proposal.isPending = true;
        proposal.dataHash = keccak256(_callData[_callData.length - 32:]);
        proposal.time = block.timestamp;
        proposal.voters = new address[](0);
        proposal.currentVotingPower = 0;

        uint256 totalVotingPower;
        for (uint256 i; i < sets[nameHash].length(); ++i) {
            uint256 _votingPower = BaseAllocation(sets[nameHash].at(i))
                .getMajorityVotingPower();
            totalVotingPower += _votingPower;
            proposal.voterPower[sets[nameHash].at(i)] = _votingPower;
            proposal.changeApplied[sets[nameHash].at(i)] = false;
        }
        proposal.totalVotingPower = totalVotingPower;

        setMajorityVoteActive[nameHash] = true;
        emit MetaVesTController_MajorityAmendmentProposed(
            setName,
            _msgSig,
            _callData,
            totalVotingPower
        );
    }

    /// @notice for 'authority' to cancel a metavest majority amendment
    /// @param _setName name of the set for majority set amendment proposal
    /// @param _msgSig function signature of the function in this controller which (if successfully executed) will execute the metavest detail update
    function cancelExpiredMajorityMetavestAmendment(
        string memory _setName,
        bytes4 _msgSig
    ) external onlyAuthority {
        if (!doesSetExist(_setName))
            revert MetaVesTController_SetDoesNotExist();
        bytes32 nameHash = keccak256(bytes(_setName));
        if (
            !setMajorityVoteActive[nameHash] ||
            block.timestamp <
            functionToSetMajorityProposal[_msgSig][nameHash].time +
                AMENDMENT_TIME_LIMIT
        ) revert MetaVesTController_AmendmentCannotBeCanceled();
        setMajorityVoteActive[nameHash] = false;
    }

    /// @notice for a grantees to vote upon a metavest update for which they share a common amount of 'tokenGoverningPower'
    /// @param _grant address of the grantee
    /// @param _setName name of the set for majority set amendment proposal
    /// @param _msgSig function signature of the function in this controller which (if successfully executed) will execute the metavest detail update
    /// @param _inFavor whether msg.sender is in favor of the applicable amendment
    function voteOnMetavestAmendment(
        address _grant,
        string memory _setName,
        bytes4 _msgSig,
        bool _inFavor
    ) external {
        bytes32 nameHash = keccak256(bytes(_setName));
        if (BaseAllocation(_grant).grantee() != msg.sender)
            revert MetaVesTController_OnlyGranteeMayCall();
        if (!isMetavestInSet(_grant, _setName))
            revert MetaVesTController_SetDoesNotExist();
        if (!functionToSetMajorityProposal[_msgSig][nameHash].isPending)
            revert MetaVesTController_NoPendingAmendment(_msgSig, _grant);
        if (!_checkFunctionToTokenToAmendmentTime(_msgSig, _setName))
            revert MetaVesTController_ProposedAmendmentExpired();

        metavestController.MajorityAmendmentProposal
            storage proposal = functionToSetMajorityProposal[_msgSig][nameHash];
        uint256 _callerPower = proposal.voterPower[_grant];

        //check if the grant has already voted.
        for (uint256 i; i < proposal.voters.length; ++i) {
            if (proposal.voters[i] == _grant)
                revert MetaVesTController_AlreadyVoted();
        }
        //add the msg.sender's vote
        if (_inFavor) {
            proposal.voters.push(_grant);
            proposal.currentVotingPower += _callerPower;
        }
        emit MetaVesTController_MajorityAmendmentVoted(
            _setName,
            _msgSig,
            _grant,
            _inFavor,
            _callerPower,
            proposal.currentVotingPower,
            proposal.totalVotingPower
        );
    }

    /// @notice resets applicable amendment variables because either the applicable amending function has been successfully called or a pending amendment is being overridden with a new one
    function _resetAmendmentParams(address _grant, bytes4 _msgSig) internal {
        if (isMetavestInSet(_grant)) {
            bytes32 set = getSetOfMetavest(_grant);
            MajorityAmendmentProposal
                storage proposal = functionToSetMajorityProposal[_msgSig][set];
            proposal.changeApplied[_grant] = true;
            setMajorityVoteActive[set] = false;
        }
        delete functionToGranteeToAmendmentPending[_msgSig][_grant];
    }

    /// @notice check whether the applicable proposed amendment has expired
    function _checkFunctionToTokenToAmendmentTime(
        bytes4 _msgSig,
        string memory _setName
    ) internal view returns (bool) {
        //check the majority proposal time
        bytes32 nameHash = keccak256(bytes(_setName));
        return (block.timestamp <
            functionToSetMajorityProposal[_msgSig][nameHash].time +
                AMENDMENT_TIME_LIMIT);
    }

    /// @notice for `authority` to create a setName
    /// @param _name setName being created
    function createSet(string memory _name) external onlyAuthority {
        bytes32 nameHash = keccak256(bytes(_name));
        if (bytes(_name).length == 0) revert MetaVesTController_ZeroAddress();
        if (setNames.contains(nameHash))
            revert MetaVesTController_SetAlreadyExists();
        if (bytes(_name).length > 512)
            revert MetaVesTController_StringTooLong();

        setNames.add(nameHash);
        emit MetaVesTController_SetCreated(_name);
    }

    /// @notice for `authority` to remove a setName
    /// @param _name setName being removed
    function removeSet(string memory _name) external onlyAuthority {
        bytes32 nameHash = keccak256(bytes(_name));
        if (setMajorityVoteActive[nameHash])
            revert MetaVesTController_AmendmentAlreadyPending();
        if (!setNames.contains(nameHash))
            revert MetaVesTController_SetDoesNotExist();

        // Remove all addresses from the set starting from the last element
        for (uint256 i = sets[nameHash].length(); i > 0; i--) {
            address _grant = sets[nameHash].at(i - 1);
            sets[nameHash].remove(_grant);
        }

        setNames.remove(nameHash);
        emit MetaVesTController_SetRemoved(_name);
    }

    function doesSetExist(string memory _name) internal view returns (bool) {
        return setNames.contains(keccak256(bytes(_name)));
    }

    function isMetavestInSet(address _metavest) internal view returns (bool) {
        uint256 length = setNames.length();
        for (uint256 i = 0; i < length; i++) {
            bytes32 nameHash = setNames.at(i);
            if (sets[nameHash].contains(_metavest)) {
                return true;
            }
        }
        return false;
    }

    function isMetavestInSet(
        address _metavest,
        string memory _setName
    ) internal view returns (bool) {
        bytes32 nameHash = keccak256(bytes(_setName));
        return sets[nameHash].contains(_metavest);
    }

    function getSetOfMetavest(
        address _metavest
    ) internal view returns (bytes32) {
        uint256 length = setNames.length();
        for (uint256 i = 0; i < length; i++) {
            bytes32 nameHash = setNames.at(i);
            if (sets[nameHash].contains(_metavest)) {
                return nameHash;
            }
        }
        return "";
    }

    /// @notice for `authority` to add a MetaVesT to a set
    /// @param _name setName to which the MetaVesT is being added
    /// @param _metaVest address of the MetaVesT being added
    function addMetaVestToSet(
        string memory _name,
        address _metaVest
    ) external onlyAuthority {
        bytes32 nameHash = keccak256(bytes(_name));
        if (!setNames.contains(nameHash))
            revert MetaVesTController_SetDoesNotExist();
        if (isMetavestInSet(_metaVest))
            revert MetaVesTController_MetaVesTAlreadyExists();
        if (setMajorityVoteActive[nameHash])
            revert MetaVesTController_AmendmentAlreadyPending();

        sets[nameHash].add(_metaVest);
        emit MetaVesTController_AddressAddedToSet(_name, _metaVest);
    }

    /// @notice for `authority` to remove a MetaVesT from a set
    /// @param _name setName from which the MetaVesT is being removed
    /// @param _metaVest address of the MetaVesT being removed
    function removeMetaVestFromSet(
        string memory _name,
        address _metaVest
    ) external onlyAuthority {
        bytes32 nameHash = keccak256(bytes(_name));
        if (!setNames.contains(nameHash))
            revert MetaVesTController_SetDoesNotExist();
        if (setMajorityVoteActive[nameHash])
            revert MetaVesTController_AmendmentAlreadyPending();
        if (!sets[nameHash].contains(_metaVest))
            revert MetaVestController_MetaVestNotInSet();

        sets[nameHash].remove(_metaVest);
        emit MetaVesTController_AddressRemovedFromSet(_name, _metaVest);
    }
}
