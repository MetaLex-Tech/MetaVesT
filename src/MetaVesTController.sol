//SPDX-License-Identifier: AGPL-3.0-only

/*
**************************************
                            MetaVesT Controller
                                     *************************************
                                                                        */

pragma solidity 0.8.20;

//import "./MetaVesT.sol";
import "./interfaces/IAllocationFactory.sol";
import "./BaseAllocation.sol";
import "./RestrictedTokenAllocation.sol";
import "./interfaces/IPriceAllocation.sol";

//interface deleted

/**
 * @title      MetaVesT Controller
 *
 * @notice     Contract for a MetaVesT's authority to configure parameters, confirm milestones, and
 *             other permissioned functions, with some powers checked by the applicable 'dao' or subject to consent
 *             by an applicable affected grantee or a majority-in-governing power of similar token grantees
 **/
contract metavestController is SafeTransferLib {
    /// @dev opinionated time limit for a MetaVesT amendment, one calendar week in seconds
    uint256 internal constant AMENDMENT_TIME_LIMIT = 604800;
    uint256 internal constant ARRAY_LENGTH_LIMIT = 20;
    uint256 internal constant BUFFER = 1e18;

    mapping(address => address[]) public vestingAllocations;
    mapping(address => address[]) public restrictedTokenAllocations;
    mapping(address => address[]) public tokenOptionAllocations;
    mapping(string => address[]) public sets;
    string[] public setNames;

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
    }

    enum metavestType { Vesting, TokenOption, RestrictedTokenAward }

    /// @notice maps a function's signature to a Condition contract address
    mapping(bytes4 => address[]) public functionToConditions;

    /// @notice maps a metavest-parameter-updating function's signature to token contract to whether a majority amendment is pending
    mapping(bytes4 => mapping(string => MajorityAmendmentProposal)) public functionToSetMajorityProposal;

    /// @notice maps a metavest-parameter-updating function's signature to affected grantee address to whether an amendment is pending
    mapping(bytes4 => mapping(address => AmendmentProposal)) public functionToGranteeToAmendmentPending;

    /// @notice tracks if an address has voted for an amendment by mapping a hash of the pertinent details to time they last voted for these details (voter, function and affected grantee)
    mapping(bytes32 => uint256) internal _lastVoted;

    ///
    /// EVENTS
    ///

    event MetaVesTController_AmendmentConsentUpdated(bytes4 indexed msgSig, address indexed grantee, bool inFavor);
    event MetaVesTController_AmendmentProposed(address indexed grant, bytes4 msgSig);
    event MetaVesTController_AuthorityUpdated(address indexed newAuthority);
    event MetaVesTController_ConditionUpdated(address indexed condition, bytes4 functionSig);
    event MetaVesTController_DaoUpdated(address newDao);
    event MetaVesTController_MetaVesTDeployed(address indexed metavest);
    event MetaVesTController_MetaVesTCreated(address indexed grantee, address allocationAddress, uint256 totalAmount);
    event MetaVesTController_MajorityAmendmentProposed(string indexed set, bytes4 msgSig, bytes callData);
    event MetaVesTController_MajorityAmendmentConsentUpdated(string indexed set, bytes4 msgSig, address grantee, bool inFavor);
    event MetaVesTController_SetCreated(string indexed set);
    event MetaVesTController_SetRemoved(string indexed set);
    event MetaVesTController_AddressAddedToSet(string set, address indexed grantee);
    event MetaVesTController_AddressRemovedFromSet(string set, address indexed grantee);

    ///
    /// ERRORS
    ///

    error MetaVesTController_AlreadyVoted();
    error MetaVesTController_OnlyGrantee();
    error MetaVesTController_AmendmentNeitherMutualNorMajorityConsented();
    error MetaVesTController_AmendmentAlreadyPending();
    error MetaVesTController_AmountNotApprovedForTransferFrom();
    error MetaVesTController_CliffGreaterThanTotal();
    error MetaVesTController_ConditionNotSatisfied(address condition);
    error MetaVesTController_IncorrectMetaVesTToken(address grantee);
    error MetaVesTController_IncorrectMetaVesTType();
    error MetaVesTController_LengthMismatch();
    error MetaVesTController_MetaVesTAlreadyExists();
    error MetaVesTController_MetaVesTDoesNotExistForThisGrantee();
    error MetaVesTController_MilestoneIndexCompletedOrDoesNotExist();
    error MetaVesTController_NoPendingAmendment(bytes4 msgSig, address affectedGrantee);
    error MetaVesTController_OnlyAuthority();
    error MetaVesTController_OnlyDAO();
    error MetaVesTController_OnlyPendingAuthority();
    error MetaVesTController_OnlyPendingDao();
    error MetaVesTController_ProposedAmendmentExpired();
    error MetaVesTController_RepurchaseExpired();
    error MetaVesTController_TimeVariableError();
    error MetaVesTController_ZeroAddress();
    error MetaVesTController_ZeroAmount();
    error MetaVesTController_ZeroPrice();
    error MetaVesT_AmountNotApprovedForTransferFrom();
    error MetaVesTController_SetDoesNotExist();
    error MetaVesTController_SetAlreadyExists();
    error MetaVesTController_StringTooLong();

    ///
    /// FUNCTIONS
    ///

    modifier conditionCheck() {
        address[] memory conditions = functionToConditions[msg.sig];
        for (uint256 i; i < conditions.length; ++i) {
            if (!IConditionM(conditions[i]).checkCondition(address(this), msg.sig, "")) {
                revert MetaVesTController_ConditionNotSatisfied(conditions[i]);
            }
        }
        _;
    }

    modifier consentCheck(address _grant, bytes calldata _data) {
        if (isMetavestInSet(_grant)) {
            string memory set = getSetOfMetavest(_grant);
            MajorityAmendmentProposal memory proposal = functionToSetMajorityProposal[msg.sig][set];
            if (_data.length>32)
            {
                if (!proposal.isPending || proposal.totalVotingPower>proposal.currentVotingPower*2 || keccak256(_data[_data.length - 32:]) != proposal.dataHash ) {
                    revert MetaVesTController_AmendmentNeitherMutualNorMajorityConsented();
                }
            }
            else revert MetaVesTController_AmendmentNeitherMutualNorMajorityConsented();
        } else {
            AmendmentProposal memory proposal = functionToGranteeToAmendmentPending[msg.sig][_grant];
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

    /// @param _authority address of the authority who can call the functions in this contract and update each MetaVesT in '_metavest', such as a BORG
    /// @param _dao DAO governance contract address which exercises control over ability of 'authority' to call certain functions via imposing
    /// conditions through 'updateFunctionCondition'.
    constructor(address _authority, address _dao, address _vestingFactory, address _tokenOptionFactory, address _restrictedTokenFactory) {
        if (_authority == address(0)) revert MetaVesTController_ZeroAddress();
        authority = _authority;
        vestingFactory = _vestingFactory;
        tokenOptionFactory = _tokenOptionFactory;
        restrictedTokenFactory = _restrictedTokenFactory;
        dao = _dao;
    }

    /// @notice for a grantee to consent to an update to one of their metavestDetails by 'authority' corresponding to the applicable function in this controller
    /// @param _msgSig function signature of the function in this controller which (if successfully executed) will execute the grantee's metavest detail update
    /// @param _inFavor whether msg.sender consents to the applicable amending function call (rather than assuming true, this param allows a grantee to later revoke decision should 'authority' delay or breach agreement elsewhere)
    function consentToMetavestAmendment(address _grant, bytes4 _msgSig, bool _inFavor) external {
       if (!functionToGranteeToAmendmentPending[_msgSig][_grant].isPending)
            revert MetaVesTController_NoPendingAmendment(_msgSig, _grant);
        address grantee =BaseAllocation(_grant).grantee();
        if(msg.sender!= grantee) revert MetaVesTController_OnlyGrantee();

        functionToGranteeToAmendmentPending[_msgSig][_grant].inFavor = true;
        emit MetaVesTController_AmendmentConsentUpdated(_msgSig, msg.sender, _inFavor);
    }

    /// @notice enables the DAO to toggle whether a function requires Condition contract calls (enabling time delays, signature conditions, etc.)
    /// @dev see https://github.com/MetaLex-Tech/BORG-CORE/tree/main/src/libs/conditions for condition options; note this mechanic requires all conditions satisfied, but logic within such conditions is flexible
    /// @param _condition address of the applicable Condition contract-- pass address(0) to remove the requirement for '_functionSig'
    /// @param _functionSig signature of the function which is having its condition requirement updated
    function updateFunctionCondition(address _condition, bytes4 _functionSig) external onlyDao {
        //call check condition to ensure the condition is valid
        IConditionM(_condition).checkCondition(address(this), msg.sig, "");
        functionToConditions[_functionSig].push(_condition);
        emit MetaVesTController_ConditionUpdated(_condition, _functionSig);
    }

    function removeFunctionCondition(address _condition, bytes4 _functionSig) external onlyDao {
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

    function createMetavest(metavestType _type, address _grantee,  BaseAllocation.Allocation calldata _allocation, BaseAllocation.Milestone[] calldata _milestones, uint256 _exercisePrice, address _paymentToken,  uint256 _shortStopDuration, uint256 _longStopDate) external onlyAuthority conditionCheck returns (address)
    {
        address newMetavest;
        if(_type == metavestType.Vesting)
        {
            newMetavest = createVestingAllocation(_grantee, _allocation, _milestones);
        }
        else if(_type == metavestType.TokenOption)
        {
            newMetavest = createTokenOptionAllocation(_grantee, _exercisePrice, _paymentToken, _shortStopDuration, _allocation, _milestones);
        }
        else if(_type == metavestType.RestrictedTokenAward)
        {
            newMetavest = createRestrictedTokenAward(_grantee, _exercisePrice, _paymentToken, _shortStopDuration, _allocation, _milestones);
        }
        else
        {
            revert MetaVesTController_IncorrectMetaVesTType();
        }
        return newMetavest;
    }
    

    function validateInputParameters(
        address _grantee,
        address _paymentToken,
        uint256 _exercisePrice,
        VestingAllocation.Allocation calldata _allocation
    ) internal pure {
        if (_grantee == address(0) || _allocation.tokenContract == address(0) || _paymentToken == address(0) || _exercisePrice == 0)
            revert MetaVesTController_ZeroAddress();
    }

    function validateAllocation(VestingAllocation.Allocation calldata _allocation) internal pure {
        if (
            _allocation.vestingCliffCredit > _allocation.tokenStreamTotal ||
            _allocation.unlockingCliffCredit > _allocation.tokenStreamTotal
        ) revert MetaVesTController_CliffGreaterThanTotal();
    }

    function validateAndCalculateMilestones(
        VestingAllocation.Milestone[] calldata _milestones
    ) internal pure returns (uint256 _milestoneTotal) {
        if (_milestones.length != 0) {
            if (_milestones.length > ARRAY_LENGTH_LIMIT) revert MetaVesTController_LengthMismatch();
            for (uint256 i; i < _milestones.length; ++i) {
                if (_milestones[i].conditionContracts.length > ARRAY_LENGTH_LIMIT)
                    revert MetaVesTController_LengthMismatch();
                _milestoneTotal += _milestones[i].milestoneAward;
            }
        }
    }

    function validateTokenApprovalAndBalance(address tokenContract, uint256 total) internal view {
        if (
            IERC20M(tokenContract).allowance(authority, address(this)) < total ||
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
            return IAllocationFactory(tokenOptionFactory).createAllocation(
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
            return IAllocationFactory(restrictedTokenFactory).createAllocation(
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


    function createVestingAllocation(address _grantee, VestingAllocation.Allocation calldata _allocation, VestingAllocation.Milestone[] calldata _milestones) internal conditionCheck returns (address){
        //hard code values not to trigger the failure for the 2 parameters that don't matter for this type of allocation
        validateInputParameters(_grantee, address(this), 1, _allocation);
        validateAllocation(_allocation);
        uint256 _milestoneTotal = validateAndCalculateMilestones(_milestones);

        uint256 _total = _allocation.tokenStreamTotal + _milestoneTotal;
        if (_total == 0) revert MetaVesTController_ZeroAmount();
        validateTokenApprovalAndBalance(_allocation.tokenContract, _total);

        address vestingAllocation = IAllocationFactory(vestingFactory).createAllocation(
            IAllocationFactory.AllocationType.Vesting,
            _grantee,
            address(this),
            _allocation,
            _milestones,
            address(0),
            0,
            0
        );
        safeTransferFrom(_allocation.tokenContract, authority, vestingAllocation, _total);

        vestingAllocations[_grantee].push(vestingAllocation);
        return vestingAllocation;
    }

    function createTokenOptionAllocation(address _grantee, uint256 _exercisePrice, address _paymentToken,  uint256 _shortStopDuration, VestingAllocation.Allocation calldata _allocation, VestingAllocation.Milestone[] calldata _milestones) internal conditionCheck returns (address) {
        
        validateInputParameters(_grantee, _paymentToken, _exercisePrice, _allocation);
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

            safeTransferFrom(_allocation.tokenContract, authority, tokenOptionAllocation, _total);
            tokenOptionAllocations[_grantee].push(tokenOptionAllocation);
            return tokenOptionAllocation;
        }

        function createRestrictedTokenAward(address _grantee, uint256 _repurchasePrice, address _paymentToken, uint256 _shortStopDuration, VestingAllocation.Allocation calldata _allocation, VestingAllocation.Milestone[] calldata _milestones) internal conditionCheck returns (address){
            validateInputParameters(_grantee, _paymentToken, _repurchasePrice, _allocation);
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

            safeTransferFrom(_allocation.tokenContract, authority, restrictedTokenAward, _total);
            restrictedTokenAllocations[_grantee].push(restrictedTokenAward);
            return restrictedTokenAward;
        }
    
    function getMetaVestType(address _grant) public view returns (uint256) {
        return BaseAllocation(_grant).getVestingType();
    }

    /// @notice for 'authority' to withdraw tokens from this controller (i.e. which it has withdrawn from 'metavest', typically 'paymentToken')
    /// @param _tokenContract contract address of the token which is being withdrawn
    function withdrawFromController(address _tokenContract) external onlyAuthority {
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
    /// @param _newPrice new exercisePrice (if token option) or (repurchase price if restricted token award) in 'paymentToken' per metavested token
    function updateExerciseOrRepurchasePrice(
        address _grant,
        uint256 _newPrice
    ) external onlyAuthority conditionCheck consentCheck(_grant, msg.data) {
        if (_newPrice == 0) revert MetaVesTController_ZeroPrice();
        IPriceAllocation grant = IPriceAllocation(_grant);
        if(grant.getVestingType()!=2 && grant.getVestingType()!=3) revert MetaVesTController_IncorrectMetaVesTType();
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
        (uint256 milestoneAward, , bool completed) = BaseAllocation(_grant).milestones(_milestoneIndex);
        if(completed || milestoneAward == 0) revert MetaVesTController_MilestoneIndexCompletedOrDoesNotExist();
        BaseAllocation(_grant).removeMilestone(_milestoneIndex);
    }

    /// @notice add a milestone for a '_grantee' (and any transferees) and transfer the milestoneAward amount of tokens
    /// @param _grant address of grantee whose MetaVesT is being updated
    /// @param _milestone new Milestone struct added for '_grant', to be added to their 'milestones' array
    function addMetavestMilestone(address _grant, VestingAllocation.Milestone calldata _milestone) external onlyAuthority {
       
        address _tokenContract = BaseAllocation(_grant).getMetavestDetails().tokenContract;
        if (_milestone.milestoneAward == 0) revert MetaVesTController_ZeroAmount();
        if (
            IERC20M(_tokenContract).allowance(msg.sender, address(this)) < _milestone.milestoneAward ||
            IERC20M(_tokenContract).balanceOf(msg.sender) < _milestone.milestoneAward
        ) revert MetaVesT_AmountNotApprovedForTransferFrom();

        // send the new milestoneAward to 'metavest'
        safeTransferFrom(_tokenContract, msg.sender, _grant, _milestone.milestoneAward);
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
    function terminateMetavestVesting(address _grant) external onlyAuthority conditionCheck {
        _resetAmendmentParams(_grant, msg.sig);
        BaseAllocation(_grant).terminate();
    }

    function setMetaVestGovVariables(address _grant, BaseAllocation.GovType _govType) external onlyAuthority consentCheck(_grant, msg.data){
        BaseAllocation(_grant).setGovVariables(_govType);
    }

    /// @notice allows the 'authority' to propose a replacement to their address. First step in two-step address change, as '_newAuthority' will subsequently need to call 'acceptAuthorityRole()'
    /// @dev use care in updating 'authority' as it must have the ability to call 'acceptAuthorityRole()', or once it needs to be replaced, 'updateAuthority()'
    /// @param _newAuthority new address for pending 'authority', who must accept the role by calling 'acceptAuthorityRole'
    function initiateAuthorityUpdate(address _newAuthority) external onlyAuthority {
        if (_newAuthority == address(0)) revert MetaVesTController_ZeroAddress();
        _pendingAuthority = _newAuthority;
    }

    /// @notice allows the pending new authority to accept the role transfer
    /// @dev access restricted to the address stored as '_pendingauthority' to accept the two-step change. Transfers 'authority' role to the caller (reflected in 'metavest') and deletes '_pendingauthority' to reset.
    function acceptAuthorityRole() external {
        if (msg.sender != _pendingAuthority) revert MetaVesTController_OnlyPendingAuthority();
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
        if (msg.sender != _pendingDao) revert MetaVesTController_OnlyPendingDao();
        delete _pendingDao;
        dao = msg.sender;
        emit MetaVesTController_DaoUpdated(msg.sender);
    }

    /// @notice for 'authority' to propose a metavest detail amendment
    /// @param _grant address of the grantee whose metavest is being updated
    /// @param _msgSig function signature of the function in this controller which (if successfully executed) will execute the metavest detail update
    function proposeMetavestAmendment(
        address _grant,
        bytes4 _msgSig,
        bytes memory _callData
    ) external onlyAuthority {
            //override existing amendment if it exists
            functionToGranteeToAmendmentPending[_msgSig][_grant] = AmendmentProposal(
                true,
                keccak256(_callData),
                false
            );
        emit MetaVesTController_AmendmentProposed(_grant, _msgSig);
    }

        /// @notice for 'authority' to propose a metavest detail amendment
    /// @param setName name of the set for majority set amendment proposal
    /// @param _msgSig function signature of the function in this controller which (if successfully executed) will execute the metavest detail update
    /// @param _callData data for the amendement
    function proposeMajorityMetavestAmendment(
        string memory setName,
        bytes4 _msgSig,
        bytes calldata _callData
    ) external onlyAuthority {
        //if the majority proposal is already pending and not expired, revert
        if (functionToSetMajorityProposal[_msgSig][setName].isPending && block.timestamp > functionToSetMajorityProposal[_msgSig][setName].time)
            revert MetaVesTController_AmendmentAlreadyPending();

        uint256 totalVotingPower;
        for (uint256 i; i < sets[setName].length; ++i) {
            totalVotingPower += BaseAllocation(sets[setName][i]).getGoverningPower();
        }
        functionToSetMajorityProposal[_msgSig][setName] = MajorityAmendmentProposal(
        totalVotingPower,
        0,
        block.timestamp,
        true,
        keccak256(_callData[_callData.length - 32:]),
        new address[](0)    
        );
        emit MetaVesTController_MajorityAmendmentProposed(setName, _msgSig, _callData);
    }

    /// @notice for a grantees to vote upon a metavest update for which they share a common amount of 'tokenGoverningPower'
    /// @param _msgSig function signature of the function in this controller which (if successfully executed) will execute the metavest detail update
    /// @param _inFavor whether msg.sender is in favor of the applicable amendment
    function voteOnMetavestAmendment(address _grant, string memory _setName, bytes4 _msgSig, bool _inFavor) external {

        if(BaseAllocation(_grant).grantee() != msg.sender) revert MetaVesTController_OnlyGrantee();
        if (!functionToSetMajorityProposal[_msgSig][_setName].isPending) revert MetaVesTController_NoPendingAmendment(_msgSig, _grant);
        if (!_checkFunctionToTokenToAmendmentTime(_msgSig, _setName))
            revert MetaVesTController_ProposedAmendmentExpired();
        uint256 _callerPower =  BaseAllocation(_grant).getGoverningPower();

        metavestController.MajorityAmendmentProposal storage proposal = functionToSetMajorityProposal[_msgSig][_setName];
        
        //check if the grant has already voted.
        for (uint256 i; i < proposal.voters.length; ++i) {
            if (proposal.voters[i] == _grant) revert MetaVesTController_AlreadyVoted();
        }
        //add the msg.sender's vote
        if (_inFavor) {
            proposal.voters.push(_grant);
            proposal.currentVotingPower += _callerPower;
        } 
    }

    /// @notice resets applicable amendment variables because either the applicable amending function has been successfully called or a pending amendment is being overridden with a new one
    function _resetAmendmentParams(address _grantee, bytes4 _msgSig) internal {
        delete functionToGranteeToAmendmentPending[_msgSig][_grantee];
    }

    /// @notice check whether the applicable proposed amendment has expired
    function _checkFunctionToTokenToAmendmentTime(bytes4 _msgSig, string memory _setName) internal view returns (bool) {
        //check the majority proposal time
        return (block.timestamp < functionToSetMajorityProposal[_msgSig][_setName].time + AMENDMENT_TIME_LIMIT);
    }

    function createSet(string memory _name) external onlyAuthority {
        //check if name does not already exist
        if (sets[_name].length != 0) revert MetaVesTController_SetAlreadyExists();
        if(doesSetExist(_name)) revert MetaVesTController_SetAlreadyExists();
        //check string length does not exceed 256 characters
        if (bytes(_name).length > 512) revert MetaVesTController_StringTooLong();
        setNames.push(_name);
        emit MetaVesTController_SetCreated(_name);
    }

    function removeSet(string memory _name) external onlyAuthority {
        for (uint256 i; i < setNames.length; ++i) {
            if (keccak256(bytes(setNames[i])) == keccak256(bytes(_name))) {
                setNames[i] = setNames[setNames.length - 1];
                setNames.pop();
                emit MetaVesTController_SetRemoved(_name);
                return;
            }
        }
    }

    function doesSetExist(string memory _name) internal view returns (bool) {
        for (uint256 i; i < setNames.length; ++i) {
            if (keccak256(bytes(setNames[i])) == keccak256(bytes(_name))) return true;
        }
        return false;
    }

    function isMetavestInSet(address _metavest) internal view returns (bool) {
        for (uint256 i; i < setNames.length; ++i) {
            for (uint256 j; j < sets[setNames[i]].length; ++j) {
                if (sets[setNames[i]][j] == _metavest) return true;
            }
        }
        return false;
    }

    function getSetOfMetavest(address _metavest) internal view returns (string memory) {
        for (uint256 i; i < setNames.length; ++i) {
            for (uint256 j; j < sets[setNames[i]].length; ++j) {
                if (sets[setNames[i]][j] == _metavest) return setNames[i];
            }
        }
        return "";
    }

    function addMetaVestToSet(string memory _name, address _metaVest) external onlyAuthority {
        if(!doesSetExist(_name)) revert MetaVesTController_SetDoesNotExist();
        if(isMetavestInSet(_metaVest)) revert MetaVesTController_MetaVesTAlreadyExists();
        sets[_name].push(_metaVest);
    }

    function removeMetaVestFromSet(string memory _name, address _metaVest) external onlyAuthority {
        if(!doesSetExist(_name)) revert MetaVesTController_SetDoesNotExist();
        for (uint256 i; i < sets[_name].length; ++i) {
            if (sets[_name][i] == _metaVest) {
                sets[_name][i] = sets[_name][sets[_name].length - 1];
                sets[_name].pop();
                return;
            }
        }
    }
}
