//SPDX-License-Identifier: AGPL-3.0-only

/*
**************************************
                            MetaVesT Controller
                                     *************************************
                                                                        */

pragma solidity ^0.8.18;

import "./MetaVesT.sol";

interface IMetaVesT {
    function addMilestone(address grantee, MetaVesT.Milestone calldata milestone) external;

    function createMetavest(MetaVesT.MetaVesTDetails calldata metavestDetails, uint256 total) external;

    function getGoverningPower(address grantee) external returns (uint256);

    function removeMilestone(uint8 milestoneIndex, address grantee, address tokenContract) external;

    function repurchaseTokens(address grantee, uint256 divisor) external;

    function terminate(address grantee) external;

    function terminateVesting(address grantee) external;

    function metavestDetails(address grantee) external view returns (MetaVesT.MetaVesTDetails memory details);

    function refreshMetavest(address grantee) external;

    function transferees(address grantee) external view returns (address[] memory);

    function updateAuthority(address newAuthority) external;

    function updateDao(address newDao) external;

    function updatePrice(address grantee, uint128 newPrice) external;

    function updateStopTimes(
        address grantee,
        uint48 unlockStopTime,
        uint48 vestingStopTime,
        uint48 shortStopTime
    ) external;

    function updateTransferability(address grantee, bool isTransferable) external;

    function updateUnlockRate(address grantee, uint160 unlockRate) external;

    function updateVestingRate(address grantee, uint160 vestingRate) external;

    function withdrawAll(address tokenAddress) external;
}

/**
 * @title      MetaVesT Controller
 *
 * @notice     Contract for a MetaVesT's authority to configure parameters, confirm milestones, and
 *             other permissioned functions, with some powers checked by the applicable 'dao' or subject to consent
 *             by an applicable affected grantee or a majority-in-governing power of similar token grantees
 **/
contract MetaVesTController is SafeTransferLib {
    /// @dev opinionated time limit for a MetaVesT amendment, one calendar week in seconds
    uint256 internal constant AMENDMENT_TIME_LIMIT = 604800;
    uint256 internal constant ARRAY_LENGTH_LIMIT = 20;
    uint256 internal constant BUFFER = 1e18;
    uint256 internal constant BUFFERED_FIFTY_PERCENT = 50 * 1e16;

    IMetaVesT internal immutable imetavest;
    address public immutable metavest;
    address public immutable paymentToken;

    address public authority;
    address public dao;
    address internal _pendingAuthority;
    address internal _pendingDao;

    /// @notice maps a function's signature to a Condition contract address
    mapping(bytes4 => address[]) public functionToConditions;

    /// @notice maps a metavest-parameter-updating function's signature to the grantee's address whose MetaVesT is being amended to whether such update is mutually agreed between 'authority' and 'grantee'
    mapping(bytes4 => mapping(address => bool)) public functionToGranteeToMutualAgreement;

    /// @notice maps a metavest-parameter-updating function's signature to token contract to whether such update is has been consented to by a voting power majority of such metavest's tokenContract grantees
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

    ///
    /// FUNCTIONS
    ///

    /// @notice implements a condition check if imposed by 'dao'; see https://github.com/MetaLex-Tech/BORG-CORE/tree/main/src/libs/conditions
    /// @dev all conditions must be satisfied, or will revert
    modifier conditionCheck() {
        if (functionToConditions[msg.sig][0] != address(0)) {
            for (uint256 i; i < functionToConditions[msg.sig].length; ++i) {
                address _cond = functionToConditions[msg.sig][i];
                if (!IConditionM(_cond).checkCondition()) revert MetaVesTController_ConditionNotSatisfied(_cond);
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
        MetaVesT _metavest = new MetaVesT(_authority, address(this), _dao, _paymentToken);
        paymentToken = _paymentToken;
        dao = _dao;
        metavest = address(_metavest);
        imetavest = IMetaVesT(address(_metavest));
        emit MetaVesTController_MetaVesTDeployed(metavest);
    }

    /// @notice for a grantee to consent to an update to one of their metavestDetails by 'authority' corresponding to the applicable function in this controller
    /// @param _msgSig function signature of the function in this controller which (if successfully executed) will execute the grantee's metavest detail update
    /// @param _inFavor whether msg.sender consents to the applicable amending function call (rather than assuming true, this param allows a grantee to later revoke decision should 'authority' delay or breach agreement elsewhere)
    function consentToMetavestAmendment(bytes4 _msgSig, bool _inFavor) external {
        if (!functionToGranteeToAmendmentPending[_msgSig][msg.sender])
            revert MetaVesTController_NoPendingAmendment(_msgSig, msg.sender);
        if (
            !_checkFunctionToTokenToAmendmentTime(
                _msgSig,
                imetavest.metavestDetails(msg.sender).allocation.tokenContract
            )
        ) revert MetaVesTController_ProposedAmendmentExpired();

        functionToGranteeToMutualAgreement[_msgSig][msg.sender] = _inFavor;
        emit MetaVesTController_AmendmentConsentUpdated(_msgSig, msg.sender, _inFavor);
    }

    /// @notice enables the DAO to toggle whether a function requires Condition contract calls (enabling time delays, signature conditions, etc.)
    /// @dev see https://github.com/MetaLex-Tech/BORG-CORE/tree/main/src/libs/conditions for condition options; note this mechanic requires all conditions satisfied, but logic within such conditions is flexible
    /// @param _condition address of the applicable Condition contract-- pass address(0) to remove the requirement for '_functionSig'
    /// @param _index index of 'functionToConditions' mapped array which is being updated; if == array length, add a new condition
    /// @param _functionSig signature of the function which is having its condition requirement updated
    function updateFunctionCondition(address _condition, uint256 _index, bytes4 _functionSig) external onlyDao {
        // indexed address may be replaced can be up to the length of the array (and thus adds a new array member if == length)
        if (_index <= functionToConditions[msg.sig].length) functionToConditions[_functionSig][_index] = _condition;
        emit MetaVesTController_ConditionUpdated(_condition, _functionSig);
    }

    /// @notice for 'authority' to create a MetaVesT for a grantee and lock the total token amount ('metavestDetails.allocation.tokenStreamTotal' + all 'milestoneAward's)
    /// @dev msg.sender ('authority') must have approved 'metavest' for 'metavestDetails.allocation.tokenStreamTotal' + all 'milestoneAward's in '_metavestDetails.allocation.tokenContract' prior to calling this function;
    /// requires transfer of exact amount of 'metavestDetails.allocation.tokenStreamTotal' + all 'milestoneAward's along with MetaVesTDetails; event emitted in MetaVesT.sol
    /// @param _metavestDetails: MetaVesTDetails struct containing all applicable details for this '_metavestDetails.grantee'-- but MUST contain grantee, token contract,
    /// amount, and start and stop time; if token option, must contain 'exercisePrice', and if restricted token award, must contain 'repurchasePrice'
    function createMetavestAndLockTokens(
        MetaVesT.MetaVesTDetails calldata _metavestDetails
    ) external onlyAuthority conditionCheck {
        //prevent overwrite of existing MetaVesT
        if (
            imetavest.metavestDetails(_metavestDetails.grantee).grantee != address(0) ||
            _metavestDetails.grantee == authority ||
            _metavestDetails.grantee == address(this)
        ) revert MetaVesTController_MetaVesTAlreadyExists();
        if (_metavestDetails.grantee == address(0) || _metavestDetails.allocation.tokenContract == address(0))
            revert MetaVesTController_ZeroAddress();
        if (
            _metavestDetails.allocation.vestingCliffCredit > _metavestDetails.allocation.tokenStreamTotal ||
            _metavestDetails.allocation.unlockingCliffCredit > _metavestDetails.allocation.tokenStreamTotal
        ) revert MetaVesTController_CliffGreaterThanTotal();
        if (
            _metavestDetails.allocation.vestingStopTime <= _metavestDetails.allocation.vestingStartTime ||
            _metavestDetails.allocation.unlockStopTime <= _metavestDetails.allocation.unlockStartTime
        ) revert MetaVesTController_TimeVariableError();
        if (
            (_metavestDetails.metavestType == MetaVesT.MetaVesTType.OPTION &&
                _metavestDetails.option.exercisePrice == 0) ||
            (_metavestDetails.metavestType == MetaVesT.MetaVesTType.RESTRICTED &&
                _metavestDetails.rta.repurchasePrice == 0)
        ) revert MetaVesTController_ZeroPrice();

        // limit array length
        if (_metavestDetails.milestones.length > ARRAY_LENGTH_LIMIT) revert MetaVesTController_LengthMismatch();

        uint256 _milestoneTotal;
        for (uint256 i; i < _metavestDetails.milestones.length; ++i) {
            _milestoneTotal += _metavestDetails.milestones[i].milestoneAward;
        }
        uint256 _total = _metavestDetails.allocation.tokenStreamTotal + _milestoneTotal;
        if (_total == 0) revert MetaVesTController_ZeroAmount();
        if (
            IERC20M(_metavestDetails.allocation.tokenContract).allowance(msg.sender, metavest) < _total ||
            IERC20M(_metavestDetails.allocation.tokenContract).balanceOf(msg.sender) < _total
        ) revert MetaVesTController_AmountNotApprovedForTransferFrom();

        _tokenGrantees[_metavestDetails.allocation.tokenContract].push(_metavestDetails.grantee);

        imetavest.createMetavest(_metavestDetails, _total);
    }

    /// @notice for 'authority' to withdraw tokens from this controller (i.e. which it has withdrawn from 'metavest', typically 'paymentToken')
    /// @param _tokenContract contract address of the token which is being withdrawn
    function withdrawFromController(address _tokenContract) external onlyAuthority {
        uint256 _balance = IERC20M(_tokenContract).balanceOf(address(this));
        if (_balance == 0) revert MetaVesTController_ZeroAmount();

        safeTransfer(_tokenContract, authority, _balance);
    }

    /// @notice convenience function for any address to initiate a 'withdrawAll' from 'metavest' on behalf of this controller, to this controller. Typically for 'paymentToken'
    /// @dev 'withdrawAll' in MetaVesT will revert if 'controller' has an 'amountWithdrawable' of 0; for 'authority' to withdraw its own 'amountWithdrawable', it must call
    /// 'withdrawAll' directly in 'metavest'. No 'conditionCheck' necessary since it is present in 'withdrawFromController'
    /// @param _tokenContract contract address of the token which is being withdrawn
    function withdrawAllFromMetavestToController(address _tokenContract) external {
        imetavest.withdrawAll(_tokenContract);
    }

    /// @notice for 'authority' to toggle whether '_grantee''s MetaVesT is transferable-- does not revoke previous transfers, but does cause such transferees' MetaVesTs transferability to be similarly updated
    /// @param _grantee address whose MetaVesT's (and whose transferees' MetaVesTs') transferability is being updated
    /// @param _isTransferable whether transferability is to be updated to transferable (true) or nontransferable (false)
    function updateMetavestTransferability(
        address _grantee,
        bool _isTransferable
    ) external onlyAuthority conditionCheck consentCheck(_grantee) {
        _resetAmendmentParams(_grantee, msg.sig);
        imetavest.refreshMetavest(_grantee); // reverts if '_grantee' == address(0) or does not have an active metavest
        imetavest.updateTransferability(_grantee, _isTransferable);
    }

    /// @notice for the controller to update either exercisePrice or repurchasePrice for a '_grantee' and their transferees, as applicable depending on the '_grantee''s MetaVesTType
    /// @param _grantee address of grantee whose applicable price is being updated
    /// @param _newPrice new exercisePrice (if token option) or (repurchase price if restricted token award) in 'paymentToken' per metavested token
    function updateExerciseOrRepurchasePrice(
        address _grantee,
        uint128 _newPrice
    ) external onlyAuthority conditionCheck consentCheck(_grantee) {
        if (_newPrice == 0) revert MetaVesTController_ZeroPrice();
        _resetAmendmentParams(_grantee, msg.sig);
        imetavest.refreshMetavest(_grantee); // reverts if '_grantee' == address(0) or does not have an active metavest
        imetavest.updatePrice(_grantee, _newPrice);
    }

    /// @notice removes a milestone from '_grantee''s MetaVesT if such milestone has not yet been confirmed, also making the corresponding 'milestoneAward' tokens withdrawable by controller
    /// @param _grantee address of grantee whose MetaVesT is being updated
    /// @param _milestoneIndex element of the '_grantee''s 'milestones' array to be removed
    function removeMetavestMilestone(
        address _grantee,
        uint8 _milestoneIndex
    ) external onlyAuthority conditionCheck consentCheck(_grantee) {
        imetavest.refreshMetavest(_grantee);
        MetaVesT.MetaVesTDetails memory _metavest = imetavest.metavestDetails(_grantee);

        // revert if the milestone corresponding to '_milestoneIndex' doesn't exist or has already been completed
        if (_milestoneIndex >= _metavest.milestones.length || _metavest.milestones[_milestoneIndex].complete)
            revert MetaVesTController_MilestoneIndexCompletedOrDoesNotExist();
        _resetAmendmentParams(_grantee, msg.sig);
        imetavest.removeMilestone(_milestoneIndex, _grantee, _metavest.allocation.tokenContract);
    }

    /// @notice add a milestone for a '_grantee' (and any transferees) and transfer the milestoneAward amount of tokens
    /// @param _grantee address of grantee whose MetaVesT is being updated
    /// @param _milestone new Milestone struct added for '_grantee', to be added to their 'milestones' array
    function addMetavestMilestone(address _grantee, MetaVesT.Milestone calldata _milestone) external onlyAuthority {
        imetavest.refreshMetavest(_grantee);
        address _tokenContract = imetavest.metavestDetails(_grantee).allocation.tokenContract;
        if (_milestone.milestoneAward == 0) revert MetaVesTController_ZeroAmount();
        if (
            IERC20M(_tokenContract).allowance(msg.sender, metavest) < _milestone.milestoneAward ||
            IERC20M(_tokenContract).balanceOf(msg.sender) < _milestone.milestoneAward
        ) revert MetaVesT.MetaVesT_AmountNotApprovedForTransferFrom();

        _resetAmendmentParams(_grantee, msg.sig);

        // send the new milestoneAward to 'metavest'
        safeTransferFrom(_tokenContract, msg.sender, metavest, _milestone.milestoneAward);

        imetavest.addMilestone(_grantee, _milestone);
    }

    /// @notice for 'authority' to update a MetaVesT's unlockRate (including any transferees)
    /// @dev an '_unlockRate' of 0 is permissible to enable temporary freezes of allocation unlocks by authority
    /// @param _grantee address of grantee whose MetaVesT is being updated
    /// @param _unlockRate token unlock rate in tokens per second
    function updateMetavestUnlockRate(
        address _grantee,
        uint160 _unlockRate
    ) external onlyAuthority conditionCheck consentCheck(_grantee) {
        _resetAmendmentParams(_grantee, msg.sig);
        imetavest.refreshMetavest(_grantee);
        imetavest.updateUnlockRate(_grantee, _unlockRate);
    }

    /// @notice for 'authority' to update a MetaVesT's vestingRate (including any transferees)
    /// @dev a '_vestingRate' of 0 is permissible to enable temporary freezes of allocation vestings by authority, but to permanently terminate vesting, call 'terminateMetavestVesting'
    /// @param _grantee address of grantee whose MetaVesT is being updated
    /// @param _vestingRate token vesting rate in tokens per second
    function updateMetavestVestingRate(
        address _grantee,
        uint160 _vestingRate
    ) external onlyAuthority conditionCheck consentCheck(_grantee) {
        _resetAmendmentParams(_grantee, msg.sig);
        imetavest.refreshMetavest(_grantee);
        imetavest.updateVestingRate(_grantee, _vestingRate);
    }

    /// @notice for authority to update a MetaVesT's stopTime and/or shortStopTime, as applicable (including any transferees)
    /// @dev if '_shortStopTime' has already occurred, it will be ignored in MetaVest.sol. Allows stop times before block.timestamp to enable accelerated schedules.
    /// @param _grantee address of grantee whose MetaVesT is being updated
    /// @param _unlockStopTime the end of the linear unlock
    /// @param _vestingStopTime if allocation this is the end of the linear vesting; if token option or restricted token award this is the 'long stop time'
    /// @param _shortStopTime if token option, vesting stop time and exercise deadline; if restricted token award, lapse stop time and repurchase deadline -- must be <= vestingStopTime
    function updateMetavestStopTimes(
        address _grantee,
        uint48 _unlockStopTime,
        uint48 _vestingStopTime,
        uint48 _shortStopTime
    ) external onlyAuthority conditionCheck consentCheck(_grantee) {
        if (_grantee != imetavest.metavestDetails(_grantee).grantee)
            revert MetaVesTController_MetaVesTDoesNotExistForThisGrantee();
        if (_vestingStopTime < _shortStopTime) revert MetaVesTController_TimeVariableError();
        _resetAmendmentParams(_grantee, msg.sig);
        imetavest.updateStopTimes(_grantee, _unlockStopTime, _vestingStopTime, _shortStopTime);
    }

    /// @notice for 'authority' to irrevocably terminate (stop) this '_grantee''s vesting (including transferees), but preserving the unlocking schedule for any already-vested tokens, so their MetaVesT is not deleted
    /// @dev returns unvested remainder to 'authority' but preserves MetaVesT for all vested tokens up until call. To temporarily/revocably stop vesting, use 'updateVestingRate'
    /// @param _grantee: address of grantee whose MetaVesT's vesting is being stopped
    function terminateMetavestVesting(address _grantee) external onlyAuthority conditionCheck {
        _resetAmendmentParams(_grantee, msg.sig);
        imetavest.refreshMetavest(_grantee);
        imetavest.terminateVesting(_grantee);
    }

    /// @notice for the applicable authority to terminate and delete this '_grantee''s MetaVesT (including transferees), withdrawing all withdrawable and vested tokens to '_grantee' (accelerating the unlock of vested tokens)
    /// @dev makes all vested tokens for such grantee withdrawable then sends them to grantee,
    /// so as to avoid a mapping overwrite if the grantee's terminateed MetaVesT is replaced with a new one before they can withdraw,
    /// and returns the remainder to 'authority'. Note, because this is subject to a 'consentCheck', 'authority' cannot use this function to bypass repurchase obligations
    /// by simply terminating an RTA instead of repurchasing
    /// @param _grantee address of grantee whose MetaVesT is being terminated
    function terminateMetavest(address _grantee) external onlyAuthority conditionCheck consentCheck(_grantee) {
        _resetAmendmentParams(_grantee, msg.sig);
        imetavest.refreshMetavest(_grantee);
        imetavest.terminate(_grantee);
    }

    /// @notice for 'authority' to repurchase tokens from a restricted token award MetaVesT
    /// @dev does not require '_grantee' consent nor condition check
    /// @param _grantee address whose MetaVesT is subject to the repurchase
    /// @param _divisor divisor corresponding to the fraction of _grantee's repurchasable tokens being repurchased by 'authority'; to repurchase the full available amount, submit '1'
    function repurchaseMetavestTokens(address _grantee, uint256 _divisor) external onlyAuthority {
        imetavest.refreshMetavest(_grantee);
        MetaVesT.MetaVesTDetails memory _metavest = imetavest.metavestDetails(_grantee);
        if (_metavest.metavestType != MetaVesT.MetaVesTType.RESTRICTED)
            revert MetaVesTController_IncorrectMetaVesTType();
        if (_metavest.rta.tokensRepurchasable == 0 || _divisor == 0) revert MetaVesTController_ZeroAmount();
        if (block.timestamp >= _metavest.rta.shortStopTime) revert MetaVesTController_RepurchaseExpired();

        // calculate repurchase payment amount, including transferees, and transfer to 'metavest' where grantee and any transferees will be able to withdraw
        uint256 _amount = _metavest.rta.tokensRepurchasable / _divisor;

        address[] memory _transferees = imetavest.transferees(_grantee);
        if (_transferees.length != 0) {
            for (uint256 i; i < _transferees.length; ++i) {
                address _addr = _transferees[i];
                MetaVesT.MetaVesTDetails memory _mv = imetavest.metavestDetails(_addr);
                _amount += _mv.rta.tokensRepurchasable / _divisor;
            }
        }

        uint256 _payment = _amount * _metavest.rta.repurchasePrice;
        if (
            IERC20M(paymentToken).allowance(msg.sender, metavest) < _payment ||
            IERC20M(paymentToken).balanceOf(msg.sender) < _payment
        ) revert MetaVesT.MetaVesT_AmountNotApprovedForTransferFrom();

        safeTransferFrom(paymentToken, msg.sender, metavest, _payment);
        imetavest.repurchaseTokens(_grantee, _divisor);
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
    function acceptAuthorityRole() external {
        if (msg.sender != _pendingAuthority) revert MetaVesTController_OnlyPendingAuthority();

        delete _pendingAuthority;
        authority = msg.sender;
        imetavest.updateAuthority(msg.sender);

        emit MetaVesTController_AuthorityUpdated(msg.sender);
    }

    /// @notice allows the 'dao' to propose a replacement to their address. First step in two-step address change, as '_newDao' will subsequently need to call 'acceptDaoRole()'
    /// @dev use care in updating 'dao' as it must have the ability to call 'acceptDaoRole()', or once it needs to be replaced, 'updateDao()'
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
        imetavest.updateDao(msg.sender);

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
    ) external {
        for (uint256 i; i < _affectedGrantees.length; ++i) {
            MetaVesT.MetaVesTDetails memory _metavest = imetavest.metavestDetails(_affectedGrantees[i]);
            if (_metavest.allocation.tokenContract != _tokenContract || _affectedGrantees[i] != _metavest.grantee)
                revert MetaVesTController_MetaVesTDoesNotExistForThisGrantee();
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
    function voteOnMetavestAmendment(address[] memory _affectedGrantees, bytes4 _msgSig, bool _inFavor) external {
        imetavest.refreshMetavest(msg.sender); // this will revert if msg.sender does not have a metavest
        MetaVesT.MetaVesTDetails memory _metavest = imetavest.metavestDetails(msg.sender);
        uint256 _callerPower = _metavest.allocation.tokenGoverningPower;
        address _tokenContract = _metavest.allocation.tokenContract;

        if (!_checkFunctionToTokenToAmendmentTime(_msgSig, _tokenContract))
            revert MetaVesTController_ProposedAmendmentExpired();

        uint256 _totalPower;
        // calculate total voting power for this tokenContract (current voting power of all grantees of this token)
        for (uint256 x; x < _tokenGrantees[_tokenContract].length; ++x) {
            address _tokenGrantee = _tokenGrantees[_tokenContract][x];
            // check this otherwise 'getGoverningPower' will revert on the call to 'refreshMetavest' for terminated metavests
            if (imetavest.metavestDetails(_tokenGrantee).grantee == _tokenGrantee)
                _totalPower += imetavest.getGoverningPower(_tokenGrantee);
        }

        for (uint256 i; i < _affectedGrantees.length; ++i) {
            if (!functionToGranteeToAmendmentPending[_msgSig][_affectedGrantees[i]])
                revert MetaVesTController_NoPendingAmendment(_msgSig, _affectedGrantees[i]);
            // make sure the affected grantee has the same token metavested as the msg.sender
            if (
                _metavest.allocation.tokenContract !=
                imetavest.metavestDetails(_affectedGrantees[i]).allocation.tokenContract
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
                    _totalPower;
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
        return (block.timestamp > _functionToTokenToAmendmentTime[_msgSig][_tokenContract] + AMENDMENT_TIME_LIMIT);
    }
}
