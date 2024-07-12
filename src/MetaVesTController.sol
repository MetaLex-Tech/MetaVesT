//SPDX-License-Identifier: AGPL-3.0-only

/*
**************************************
                            MetaVesT Controller
                                     *************************************
                                                                        */

pragma solidity 0.8.20;

//import "./MetaVesT.sol";
import "./VestingAllocation.sol";
import "./RestrictedTokenAllocation.sol";
import "./TokenOptionAllocation.sol";
import "./BaseAllocation.sol";
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
    uint256 internal constant BUFFERED_FIFTY_PERCENT = 50 * 1e16;
    address public immutable paymentToken;

    mapping(address => address[]) public vestingAllocations;
    mapping(address => address[]) public restrictedTokenAllocations;
    mapping(address => address[]) public tokenOptionAllocations;

    address public authority;
    address public dao;
    address internal _pendingAuthority;
    address internal _pendingDao;

    enum metavestType { Vesting, TokenOption, RestrictedTokenAward }

    /// @notice maps a function's signature to a Condition contract address
    mapping(bytes4 => address[]) public functionToConditions;

    /// @notice maps a metavest-parameter-updating function's signature to the grantee's address whose MetaVesT is being amended to whether such update is mutually agreed between 'authority' and 'grantee'
    mapping(bytes4 => mapping(address => bool)) public functionToGranteeToMutualAgreement;

    /// @notice maps a metavest-parameter-updating function's signature to token contract to whether such update has been consented to by a voting power majority of such metavest's tokenContract grantees
    mapping(bytes4 => mapping(address => bool)) public functionToGranteeMajorityConsent;

    /// @notice maps a metavest-parameter-updating function's signature to affected grantee address to whether an amendment is pending
    mapping(bytes4 => mapping(address => bool)) public functionToGranteeToAmendmentPending;

    /// @notice maps a metavest-parameter-updating function's signature to affected grantee address to percentage of votes-in-interest in favor
    mapping(bytes4 => mapping(address => uint256)) public functionToGranteeToPercentageInFavor;

    /// @notice tracks if an address has voted for an amendment by mapping a hash of the pertinent details to time they last voted for these details (voter, function and affected grantee)
    mapping(bytes32 => uint256) internal _lastVoted;

    /// @notice maps a token contract address to each of its grantees
    mapping(address => address[]) internal _tokenGrantees;

    /// @notice time limit start time for proposed metavest amendment, function sig to token contract to amendment proposal time
    mapping(bytes4 => mapping(address => uint256)) internal _functionToTokenToAmendmentTime;

    ///
    /// EVENTS
    ///

    event MetaVesTController_AmendmentConsentUpdated(bytes4 msgSig, address grantee, bool inFavor);
    event MetaVesTController_AmendmentProposed(address[] affectedGrantees, address tokenContract, bytes4 msgSig);
    event MetaVesTController_AuthorityUpdated(address newAuthority);
    event MetaVesTController_ConditionUpdated(address condition, bytes4 functionSig);
    event MetaVesTController_DaoUpdated(address newDao);
    event MetaVesTController_MetaVesTDeployed(address metavest);
    event MetaVesTController_MetaVesTCreated(address grantee, address allocationAddress, uint256 totalAmount);

    ///
    /// ERRORS
    ///

    error MetaVesTController_AlreadyVoted();
    error MetaVesTController_AmendmentNeitherMutualNorMajorityConsented();
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

    ///
    /// FUNCTIONS
    ///

    /// @notice implements a condition check if imposed by 'dao'; see https://github.com/MetaLex-Tech/BORG-CORE/tree/main/src/libs/conditions
    /// @dev all conditions must be satisfied, or will revert
    modifier conditionCheck() {
        // REVIEW: probably read this array into memory from state once for big gas savings (called in a lot of places, and looped over) 
        if (functionToConditions[msg.sig].length != 0) {
            if (functionToConditions[msg.sig][0] != address(0)) { // REVIEW: check if this array will ever be not empty.
                for (uint256 i; i < functionToConditions[msg.sig].length; ++i) {
                    address _cond = functionToConditions[msg.sig][i];
                    // REVIEW: worried about bricking the contract if a condition reverts. Wondering if we should try catch
                    //         and assume reverts pass? That could also be dangerous. Alternatively see `updateFunctionCondition` comment
                    if (!IConditionM(_cond).checkCondition()) revert MetaVesTController_ConditionNotSatisfied(_cond);
                }
            }
        }
        _;
    }

    /// @notice checks whether '_grantee' has consented to 'authority''s update of its metavest via the function corresponding to 'msg.sig' or if
    /// a majority-in-tokenGoverningPower have consented to same, otherwise reverts
    modifier consentCheck(address _grantee) {
        if (
            !functionToGranteeToMutualAgreement[msg.sig][_grantee] &&
            !functionToGranteeMajorityConsent[msg.sig][_grantee]
        ) revert MetaVesTController_AmendmentNeitherMutualNorMajorityConsented();
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
    /// @param _paymentToken contract address of the token used as payment/consideration for 'authority' to repurchase tokens according to a restricted token award, or for 'grantee' to exercise a token option
    constructor(address _authority, address _dao, address _paymentToken) {
        if (_authority == address(0) || _paymentToken == address(0)) revert MetaVesTController_ZeroAddress();
        authority = _authority;
        // REVIEW: seems that some DAOs or grants will not use the functionality that paymentToken enables - don't think it's the end of the world to make it optional?
        paymentToken = _paymentToken;
        dao = _dao;
    }

    /// @notice for a grantee to consent to an update to one of their metavestDetails by 'authority' corresponding to the applicable function in this controller
    /// @param _msgSig function signature of the function in this controller which (if successfully executed) will execute the grantee's metavest detail update
    /// @param _inFavor whether msg.sender consents to the applicable amending function call (rather than assuming true, this param allows a grantee to later revoke decision should 'authority' delay or breach agreement elsewhere)
    function consentToMetavestAmendment(bytes4 _msgSig, bool _inFavor) external {
     /*   if (!functionToGranteeToAmendmentPending[_msgSig][msg.sender])
            revert MetaVesTController_NoPendingAmendment(_msgSig, msg.sender);
        if (
            !_checkFunctionToTokenToAmendmentTime(
                _msgSig,
                imetavest.getMetavestDetails(msg.sender).allocation.tokenContract
            )
        ) revert MetaVesTController_ProposedAmendmentExpired();

        functionToGranteeToMutualAgreement[_msgSig][msg.sender] = _inFavor;
        emit MetaVesTController_AmendmentConsentUpdated(_msgSig, msg.sender, _inFavor);*/
    }

    /// @notice enables the DAO to toggle whether a function requires Condition contract calls (enabling time delays, signature conditions, etc.)
    /// @dev see https://github.com/MetaLex-Tech/BORG-CORE/tree/main/src/libs/conditions for condition options; note this mechanic requires all conditions satisfied, but logic within such conditions is flexible
    /// @param _condition address of the applicable Condition contract-- pass address(0) to remove the requirement for '_functionSig'
    /// @param _index index of 'functionToConditions' mapped array which is being updated; if == array length, add a new condition
    /// @param _functionSig signature of the function which is having its condition requirement updated
    function updateFunctionCondition(address _condition, uint256 _index, bytes4 _functionSig) external onlyDao {
        // indexed address may be replaced can be up to the length of the array (and thus adds a new array member if == length)
        // REVIEW: should revert if it does nothing (i.e. index is too large).
        if (_index <= functionToConditions[_functionSig].length) functionToConditions[_functionSig][_index] = _condition;
        // REVIEW: should require `_condition` implements an interface with ERC165 check.
        emit MetaVesTController_ConditionUpdated(_condition, _functionSig);
    }

    // REVIEW: needs authority check -- all implants and borg
    function createMetavest(metavestType _type, address _grantee,  VestingAllocation.Allocation calldata _allocation, VestingAllocation.Milestone[] calldata _milestones, uint256 _exercisePrice, address _paymentToken,  uint256 _shortStopDuration, uint256 _longStopDate) external conditionCheck returns (address)
    {
        address newMetavest;
        if(_type == metavestType.Vesting)
        {
            newMetavest = createVestingAllocation(_grantee, _allocation, _milestones);
        }
        else if(_type == metavestType.TokenOption)
        {
            newMetavest = createTokenOptionAllocation(_grantee, _exercisePrice, _paymentToken, _shortStopDuration, _longStopDate, _allocation, _milestones);
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


    function createVestingAllocation(address _grantee, VestingAllocation.Allocation calldata _allocation, VestingAllocation.Milestone[] calldata _milestones) internal conditionCheck returns (address){
        if (_grantee == address(0) || _allocation.tokenContract == address(0))
            revert MetaVesTController_ZeroAddress();
        if (
            _allocation.vestingCliffCredit > _allocation.tokenStreamTotal ||
            _allocation.unlockingCliffCredit > _allocation.tokenStreamTotal
        ) revert MetaVesTController_CliffGreaterThanTotal();

        uint256 _milestoneTotal;
        if (_milestones.length != 0) {
            // limit array length
            if (_milestones.length > ARRAY_LENGTH_LIMIT) revert MetaVesTController_LengthMismatch();

            for (uint256 i; i < _milestones.length; ++i) {
                if (_milestones[i].conditionContracts.length > ARRAY_LENGTH_LIMIT)
                    revert MetaVesTController_LengthMismatch();
                _milestoneTotal += _milestones[i].milestoneAward;
            }
        }

        uint256 _total = _allocation.tokenStreamTotal + _milestoneTotal;
        if (_total == 0) revert MetaVesTController_ZeroAmount();
        if (
            IERC20M(_allocation.tokenContract).allowance(authority, address(this)) < _total ||
            IERC20M(_allocation.tokenContract).balanceOf(authority) < _total
        ) revert MetaVesTController_AmountNotApprovedForTransferFrom();

        VestingAllocation vestingAllocation = new VestingAllocation(_grantee, address(this), _allocation, _milestones);
        safeTransferFrom(_allocation.tokenContract, authority, address(vestingAllocation), _total);
        // REVIEW: let's emit an event?
        vestingAllocations[_grantee].push(address(vestingAllocation));
        return address(vestingAllocation);
    }

        /*address _authority,
        address _controller,
        address _paymentToken,
        uint256 _exercisePrice,
        Allocation memory _allocation,
        Milestone[] memory _milestones*/
    function createTokenOptionAllocation(address _grantee, uint256 _exercisePrice, address _paymentToken,  uint256 _shortStopDuration, uint256 _longStopDate, VestingAllocation.Allocation calldata _allocation, VestingAllocation.Milestone[] calldata _milestones) internal conditionCheck returns (address) {
        // REVIEW: May be neater to extract checks comment to all vest types (20+ lines) to internal function, leaving just type specific checks here.
        if (_grantee == address(0) || _allocation.tokenContract == address(0) || _paymentToken == address(0) || _exercisePrice == 0)
            revert MetaVesTController_ZeroAddress();
        if (
            _allocation.vestingCliffCredit > _allocation.tokenStreamTotal ||
            _allocation.unlockingCliffCredit > _allocation.tokenStreamTotal
        ) revert MetaVesTController_CliffGreaterThanTotal();


        uint256 _milestoneTotal;
        if (_milestones.length != 0) {
            // limit array length
            if (_milestones.length > ARRAY_LENGTH_LIMIT) revert MetaVesTController_LengthMismatch();

            for (uint256 i; i < _milestones.length; ++i) {
                if (_milestones[i].conditionContracts.length > ARRAY_LENGTH_LIMIT)
                    revert MetaVesTController_LengthMismatch();
                _milestoneTotal += _milestones[i].milestoneAward;
            }
        }

        uint256 _total = _allocation.tokenStreamTotal + _milestoneTotal;
        if (_total == 0) revert MetaVesTController_ZeroAmount();
        if (
            IERC20M(_allocation.tokenContract).allowance(authority, address(this)) < _total ||
            IERC20M(_allocation.tokenContract).balanceOf(authority) < _total
        ) revert MetaVesTController_AmountNotApprovedForTransferFrom();

        TokenOptionAllocation tokenOptionAllocation = new TokenOptionAllocation(_grantee, address(this), _paymentToken, _exercisePrice, _shortStopDuration, _longStopDate, _allocation, _milestones);
        safeTransferFrom(_allocation.tokenContract, authority, address(tokenOptionAllocation), _total);
        // REVIEW: Emit event.
        tokenOptionAllocations[_grantee].push(address(tokenOptionAllocation));
        return address(tokenOptionAllocation);
    }

        function createRestrictedTokenAward(address _grantee, uint256 _repurchasePrice, address _paymentToken, uint256 _shortStopDuration, VestingAllocation.Allocation calldata _allocation, VestingAllocation.Milestone[] calldata _milestones) internal conditionCheck returns (address){
        // REVIEW: shortStopDuration validation?
        if (_grantee == address(0) || _allocation.tokenContract == address(0) || _paymentToken == address(0) || _repurchasePrice == 0)
            revert MetaVesTController_ZeroAddress();
        if (
            _allocation.vestingCliffCredit > _allocation.tokenStreamTotal ||
            _allocation.unlockingCliffCredit > _allocation.tokenStreamTotal
        ) revert MetaVesTController_CliffGreaterThanTotal();


         uint256 _milestoneTotal;
        if (_milestones.length != 0) {
            // limit array length
            if (_milestones.length > ARRAY_LENGTH_LIMIT) revert MetaVesTController_LengthMismatch();

            for (uint256 i; i < _milestones.length; ++i) {
                if (_milestones[i].conditionContracts.length > ARRAY_LENGTH_LIMIT)
                    revert MetaVesTController_LengthMismatch();
                _milestoneTotal += _milestones[i].milestoneAward;
            }
        }

        uint256 _total = _allocation.tokenStreamTotal + _milestoneTotal;
        if (_total == 0) revert MetaVesTController_ZeroAmount();
        if (
            IERC20M(_allocation.tokenContract).allowance(authority, address(this)) < _total ||
            IERC20M(_allocation.tokenContract).balanceOf(authority) < _total
        ) revert MetaVesTController_AmountNotApprovedForTransferFrom();

        RestrictedTokenAward restrictedTokenAward = new RestrictedTokenAward(_grantee, address(this), _paymentToken, _repurchasePrice, _shortStopDuration, _allocation, _milestones);
        safeTransferFrom(_allocation.tokenContract, authority, address(restrictedTokenAward), _total);
        // REVIEW: event.
        restrictedTokenAllocations[_grantee].push(address(restrictedTokenAward));
        return address(restrictedTokenAward);
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

    /*/// @notice convenience function for any address to initiate a 'withdrawAll' from 'metavest' on behalf of this controller, to this controller. Typically for 'paymentToken'
    /// @dev 'withdrawAll' in MetaVesT will revert if 'controller' has an 'amountWithdrawable' of 0; for 'authority' to withdraw its own 'amountWithdrawable', it must call
    /// 'withdrawAll' directly in 'metavest'. No 'conditionCheck' necessary since it is present in 'withdrawFromController'
    /// @param _tokenContract contract address of the token which is being withdrawn
    function withdrawAllFromMetavestToController(address _tokenContract) external {
        imetavest.withdrawAll(_tokenContract);
    }*/

    /// @notice for 'authority' to toggle whether '_grantee''s MetaVesT is transferable-- does not revoke previous transfers, but does cause such transferees' MetaVesTs transferability to be similarly updated
    /// @param _grant address whose MetaVesT's (and whose transferees' MetaVesTs') transferability is being updated
    /// @param _isTransferable whether transferability is to be updated to transferable (true) or nontransferable (false)
    function updateMetavestTransferability(
        address _grant,
        bool _isTransferable
    ) external onlyAuthority conditionCheck consentCheck(_grant) {
        _resetAmendmentParams(_grant, msg.sig);
        BaseAllocation(_grant).updateTransferability(_isTransferable);
    }

    /// @notice for the controller to update either exercisePrice or repurchasePrice for a '_grantee' and their transferees, as applicable depending on the '_grantee''s MetaVesTType
    /// @param _grant address of grantee whose applicable price is being updated
    /// @param _newPrice new exercisePrice (if token option) or (repurchase price if restricted token award) in 'paymentToken' per metavested token
    function updateExerciseOrRepurchasePrice(
        address _grant,
        uint128 _newPrice
    ) external onlyAuthority conditionCheck consentCheck(_grant) {
        if (_newPrice == 0) revert MetaVesTController_ZeroPrice();
        IPriceAllocation grant = IPriceAllocation(_grant);
        if(grant.getVestingType()!=2 || grant.getVestingType()!=3) revert MetaVesTController_IncorrectMetaVesTType();
        _resetAmendmentParams(_grant, msg.sig);
        grant.updatePrice(_newPrice);
    }

    /// @notice removes a milestone from '_grantee''s MetaVesT if such milestone has not yet been confirmed, also making the corresponding 'milestoneAward' tokens withdrawable by controller
    /// @param _grant address of grantee whose MetaVesT is being updated
    /// @param _milestoneIndex element of the '_grantee''s 'milestones' array to be removed
    function removeMetavestMilestone(
        address _grant,
        uint256 _milestoneIndex
    ) external onlyAuthority conditionCheck consentCheck(_grant) {
        _resetAmendmentParams(_grant, msg.sig);
        BaseAllocation(_grant).removeMilestone(_milestoneIndex);
    }

    /// @notice add a milestone for a '_grantee' (and any transferees) and transfer the milestoneAward amount of tokens
    /// @param _grant address of grantee whose MetaVesT is being updated
    /// @param _milestone new Milestone struct added for '_grant', to be added to their 'milestones' array
    function addMetavestMilestone(address _grant, VestingAllocation.Milestone calldata _milestone) external onlyAuthority {
       
        address _tokenContract = BaseAllocation(_grant).getMetavestDetails().tokenContract;
        if (_milestone.milestoneAward == 0) revert MetaVesTController_ZeroAmount();
        if (
            IERC20M(_tokenContract).allowance(msg.sender, _grant) < _milestone.milestoneAward ||
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
    ) external onlyAuthority conditionCheck consentCheck(_grant) {
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
    ) external onlyAuthority conditionCheck consentCheck(_grant) {
        _resetAmendmentParams(_grant, msg.sig);
        BaseAllocation(_grant).updateVestingRate(_vestingRate);
    }

    /// @notice for authority to update a MetaVesT's stopTime and/or shortStopTime, as applicable (including any transferees)
    /// @dev if '_shortStopTime' has already occurred, it will be ignored in MetaVest.sol. Allows stop times before block.timestamp to enable accelerated schedules.
    /// @param _grant address of grantee whose MetaVesT is being updated
    /// @param _unlockStopTime the end of the linear unlock
    /// @param _vestingStopTime if allocation this is the end of the linear vesting; if token option or restricted token award this is the 'long stop time'
    /// @param _shortStopTime if token option, vesting stop time and exercise deadline; if restricted token award, lapse stop time and repurchase deadline -- must be <= vestingStopTime
    function updateMetavestStopTimes(
        address _grant,
        uint48 _unlockStopTime,
        uint48 _vestingStopTime,
        uint48 _shortStopTime
    ) external onlyAuthority conditionCheck consentCheck(_grant) {
        _resetAmendmentParams(_grant, msg.sig);
        BaseAllocation(_grant).updateStopTimes(_vestingStopTime, _unlockStopTime, _shortStopTime);
    }

    /// @notice for 'authority' to irrevocably terminate (stop) this '_grantee''s vesting (including transferees), but preserving the unlocking schedule for any already-vested tokens, so their MetaVesT is not deleted
    /// @dev returns unvested remainder to 'authority' but preserves MetaVesT for all vested tokens up until call. To temporarily/revocably stop vesting, use 'updateVestingRate'
    /// @param _grant: address of grantee whose MetaVesT's vesting is being stopped
    function terminateMetavestVesting(address _grant) external onlyAuthority conditionCheck {
        _resetAmendmentParams(_grant, msg.sig);
        BaseAllocation(_grant).terminate();
    }

    /// @notice for 'authority' to repurchase tokens from a restricted token award MetaVesT
    /// @dev does not require '_grantee' consent nor condition check; note that for transferees of transferees of this '_grantee',
    /// 'authority' will need to initiate another repurchase (which is not subject to consent or condition checks)
    /// @param _grant address whose MetaVesT is subject to the repurchase
    /// @param _amount divisor corresponding to the fraction of _grantee's repurchasable tokens being repurchased by 'authority'; to repurchase the full available amount, submit '1'
    function repurchaseMetavestTokens(address _grant, uint256 _amount) external onlyAuthority {
        if(BaseAllocation(_grant).getVestingType()!=3) revert MetaVesTController_IncorrectMetaVesTType();

        RestrictedTokenAward rta = RestrictedTokenAward(_grant);
        if (rta.getAmountRepurchasable() == 0 || _amount == 0) revert MetaVesTController_ZeroAmount();
        if (block.timestamp >= rta.shortStopDate()) revert MetaVesTController_RepurchaseExpired();

        uint256 _payment = _amount * rta.repurchasePrice();
        if (
            IERC20M(paymentToken).allowance(msg.sender, _grant) < _payment ||
            IERC20M(paymentToken).balanceOf(msg.sender) < _payment
        ) revert MetaVesT_AmountNotApprovedForTransferFrom();

        // REVIEW: deleted duplicate transfer here. `repurchaseTokens` will transfer the tokens from the authority.
        // REVIEW: repurchasePrice is likely to be a fraction - need to multiply by something to facilitate
        rta.repurchaseTokens(_amount);
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
    /// no 'conditionCheck' necessary as it more properly contained in 'initiateAuthorityUpdate'
    // REVIEW: comment above refers to a condition check, but doesn't appear to be one on `initiateAuthorityUpdate` unless it means `onlyAuthority`.
    function acceptAuthorityRole() external {
        if (msg.sender != _pendingAuthority) revert MetaVesTController_OnlyPendingAuthority();

        delete _pendingAuthority;
        authority = msg.sender;
        //best way to update every contract?
       //BaseAllocation().updateAuthority(msg.sender);

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
    /// @param _affectedGrantees array of address to whom this vote applies, which must have an active metavest with the same '_tokenContract'
    /// @param _tokenContract contract address of the token corresponding to the metavest(s) to be updated, which also dictates which grantees may vote on the amendment
    /// @param _msgSig function signature of the function in this controller which (if successfully executed) will execute the metavest detail update
    function proposeMetavestAmendment(
        address[] memory _affectedGrantees,
        address _tokenContract,
        bytes4 _msgSig
        //parameter
        // REVIEW: should add calldata in here to ensure there's no bait and switch. May also then be able bulk execute.
    ) external onlyAuthority {
        for (uint256 i; i < _affectedGrantees.length; ++i) {
            BaseAllocation.Allocation memory _metavest = BaseAllocation(_affectedGrantees[i]).getMetavestDetails();
            if (_metavest.tokenContract != _tokenContract || _affectedGrantees[i] != BaseAllocation(_affectedGrantees[i]).grantee())
                revert MetaVesTController_MetaVesTDoesNotExistForThisGrantee();
            // REVIEW: Is it ok that an approved but not fully executed amendment is overwritten?
            // override any previous votes for a new proposal
            _resetAmendmentParams(_affectedGrantees[i], _msgSig);

            functionToGranteeToAmendmentPending[_msgSig][_affectedGrantees[i]] = true;
        }

        _functionToTokenToAmendmentTime[_msgSig][_tokenContract] = block.timestamp;

        emit MetaVesTController_AmendmentProposed(_affectedGrantees, _tokenContract, _msgSig);
    }

    /// @notice for a grantees to vote upon a metavest update for which they share a common amount of 'tokenGoverningPower'
    /// @dev each call refreshes the total 'tokenGoverningPower' for the applicable token (by iterating through the '_tokenGrantees' array), so the tracker of votes in favor calculates the percentage in
    /// favor ('functionToGranteeToPercentageInFavor') -- if a call causes this to surpass the 'BUFFER_FIFTY_PERCENT', the 'functionToGranteeMajorityConsent' is updated to true
    /// so the applicable function may be called by 'authority'
    /// @param _affectedGrantees array of address to whom this vote applies, which must have an active metavest with the same tokenContract as msg.sender
    /// @param _msgSig function signature of the function in this controller which (if successfully executed) will execute the metavest detail update
    /// @param _inFavor whether msg.sender is in favor of the applicable amendment
    function voteOnMetavestAmendment(address _grant, address[] memory _affectedGrantees, bytes4 _msgSig, bool _inFavor) external {
    //    imetavest.refreshMetavest(msg.sender); // this will revert if msg.sender does not have a metavest
         BaseAllocation.Allocation memory _metavest = BaseAllocation(_grant).getMetavestDetails();
        uint256 _callerPower =  BaseAllocation(_grant).getGoverningPower();
        address _tokenContract = _metavest.tokenContract;

        if (!_checkFunctionToTokenToAmendmentTime(_msgSig, _tokenContract))
            revert MetaVesTController_ProposedAmendmentExpired();
        // REVIEW: Is there a case where none of the grantees have any governing power? Is that ok? (Auto-consent when this fn is called?)
        uint256 _totalPower;
        // calculate total voting power for this tokenContract (current voting power of all grantees of this token)
       /* for (uint256 x; x < _tokenGrantees[_tokenContract].length; ++x) {
            address _tokenGrantee = _tokenGrantees[_tokenContract][x];
            // check this otherwise 'getGoverningPower' will revert on the call to 'refreshMetavest' for terminated metavests
            if (imetavest.getMetavestDetails(_tokenGrantee).grantee == _tokenGrantee)
                _totalPower += imetavest.getGoverningPower(_tokenGrantee);
        }*/

        for (uint256 i; i < _affectedGrantees.length; ++i) {
            if (!functionToGranteeToAmendmentPending[_msgSig][_affectedGrantees[i]])
                revert MetaVesTController_NoPendingAmendment(_msgSig, _affectedGrantees[i]);
            // make sure the affected grantee has the same token metavested as the msg.sender
            if (
                _metavest.tokenContract !=
                BaseAllocation(_affectedGrantees[i]).getMetavestDetails().tokenContract
            ) revert MetaVesTController_IncorrectMetaVesTToken(_affectedGrantees[i]);

            // use the last voting time as a check against re-votes, as the above '_checkFunctionToTokenToAmendmentTime' will ensure limit to one vote per proposed amendment per grantee
            if (
                block.timestamp - _lastVoted[keccak256(abi.encodePacked(msg.sender, _msgSig, _affectedGrantees[i]))] <
                AMENDMENT_TIME_LIMIT
            ) revert MetaVesTController_AlreadyVoted();

            _lastVoted[keccak256(abi.encodePacked(msg.sender, _msgSig, _affectedGrantees[i]))] = block.timestamp;

            // multiply the caller's power by BUFFER to avoid division issues when dividing by total power to get the adjusted percentage in favor, add it to the mapped value
            if (_inFavor) {
                functionToGranteeToPercentageInFavor[_msgSig][_affectedGrantees[i]] +=
                    (_callerPower * BUFFER) /
                    _totalPower; // REVIEW: divide by zero if no power?
                // if this vote pushes the aggregate adjusted percentage in favor over 50% (50 * 1e16 for this calculation method), update the 'functionToGranteeMajorityConsent' to true
                if (functionToGranteeToPercentageInFavor[_msgSig][_affectedGrantees[i]] > BUFFERED_FIFTY_PERCENT)
                    functionToGranteeMajorityConsent[_msgSig][_affectedGrantees[i]] = true;
                emit MetaVesTController_AmendmentConsentUpdated(_msgSig, _affectedGrantees[i], true);
            }
        }
    }

    /// @notice resets applicable amendment variables because either the applicable amending function has been successfully called or a pending amendment is being overridden with a new one
    function _resetAmendmentParams(address _grantee, bytes4 _msgSig) internal {
        delete functionToGranteeMajorityConsent[_msgSig][_grantee];
        delete functionToGranteeToMutualAgreement[_msgSig][_grantee];
        delete functionToGranteeToPercentageInFavor[_msgSig][_grantee];
        delete functionToGranteeToAmendmentPending[_msgSig][_grantee];
    }

    /// @notice check whether the applicable proposed amendment has expired
    function _checkFunctionToTokenToAmendmentTime(bytes4 _msgSig, address _tokenContract) internal view returns (bool) {
        return (block.timestamp < _functionToTokenToAmendmentTime[_msgSig][_tokenContract] + AMENDMENT_TIME_LIMIT);
    }
}
