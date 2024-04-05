//SPDX-License-Identifier: AGPL-3.0-only

/*
**************************************
                            MetaVesT Controller
                                     *************************************
                                                                        */

pragma solidity ^0.8.18;

import "./MetaVesT.sol";

interface IERC20 {
    function allowance(address owner, address spender) external view returns (uint256);
    function balanceOf(address account) external view returns (uint256);
}

interface IMetaVesT {
    function addMilestone(address grantee, uint256 milestoneAward) external;
    function confirmMilestone(address grantee) external;
    function createMetavest(MetaVesT.MetaVesTDetails calldata metavestDetails, uint256 total) external;
    function createMetavestWithPermit(
        MetaVesT.MetaVesTDetails calldata metavestDetails,
        uint256 total,
        address depositor
    ) external;
    function removeMilestone(
        uint8 milestoneIndex,
        address grantee,
        address tokenContract,
        bool[] memory milestones,
        uint256[] memory milestoneAwards,
        uint256 removedMilestoneAmount
    ) external;
    function repurchaseTokens(address grantee, uint256 divisor) external;
    function terminate(address grantee) external;
    function metavestDetails(address grantee) external view returns (MetaVesT.MetaVesTDetails memory details);
    function transferees(address grantee) external view returns (address[] memory);
    function updateAuthority(address newAuthority) external;
    function updatePrice(address grantee, uint256 newPrice) external;
    function updateTransferability(address grantee, bool isTransferable) external;
    function withdrawAll(address tokenAddress) external;
}

/**
 * @title      MetaVesT Controller
 *
 * @notice     Contract for a MetaVesT's authority to configure parameters, confirm milestones, and
 *             other permissioned functions
 **/
contract MetaVesTController is SafeTransferLib {
    /// @dev limit arrays & loops for gas/size purposes
    uint256 internal constant ARRAY_LENGTH_LIMIT = 20;

    IMetaVesT internal immutable imetavest;
    address public immutable metavest;
    address public immutable paymentToken;

    address public authority;
    address internal _pendingAuthority;

    event MetaVesTController_AuthorityUpdated(address newAuthority);

    error MetaVesTController_AmountNotApprovedForTransferFrom();
    error MetaVesTController_IncorrectAddress();
    error MetaVesTController_IncorrectMetaVesTType();
    error MetaVesTController_LengthMismatch();
    error MetaVesTController_MetaVesTAlreadyExists();
    error MetaVesTController_MilestoneIndexCompletedOrDoesNotExist();
    error MetaVesTController_NoMetaVesT();
    error MetaVesTController_OnlyAuthority();
    error MetaVesTController_OnlyPendingAuthority();
    error MetaVesTController_RepurchaseExpired();
    error MetaVesTController_TimeVariableError();
    error MetaVesTController_ZeroAddress();
    error MetaVesTController_ZeroAmount();
    error MetaVesTController_ZeroPrice();

    modifier onlyAuthority() {
        if (msg.sender != authority) revert MetaVesTController_OnlyAuthority();
        _;
    }

    /// @param _authority address of the authority who can call the functions in this contract and update each MetaVesT in '_metavest', such as a BORG or DAO
    /// @param _dao contract address which may be used for staking/voting in the deployed MetaVesT, typically a DAO pool, governor, staking address. Submit address(0) for no such functionality.
    /// @param _paymentToken contract address of the token used as payment/consideration for 'authority' to repurchase tokens according to a restricted token award, or for 'grantee' to exercise a token option
    constructor(address _authority, address _dao, address _paymentToken) {
        if (_authority == address(0)) revert MetaVesTController_IncorrectAddress();
        authority = _authority;
        MetaVesT _metaVesT = new MetaVesT(_authority, address(this), _dao, _paymentToken);
        paymentToken = _paymentToken;
        metavest = address(_metaVesT);
        imetavest = IMetaVesT(address(_metaVesT));
    }

    /// @notice create a MetaVesT for a grantee and lock the total token amount ('metavestDetails.allocation.tokenStreamTotal' + 'metavestDetails.allocation.cliffCredit' + 'metavestDetails.milestoneAwards') via permit(),  if supported
    /// @dev requires transfer of exact amount of 'metavestDetails.allocation.tokenStreamTotal' + 'metavestDetails.allocation.cliffCredit' + 'metavestDetails.milestoneAwards' along with MetaVesTDetails;
    /// while '_depositor' need not be the 'authority', only 'authority' can set a grantee's 'MetaVesTDetails' by calling this function.
    /// @param _metavestDetails: MetaVesTDetails struct containing all applicable details for this '_metavestDetails.grantee'-- but MUST contain grantee, token contract, some locked amount, and start and stop time
    /// @param _depositor: depositor of the tokens, usually 'authority'
    /// @param _deadline: deadline for usage of the permit approval signature
    /// @param v: ECDSA sig parameter
    /// @param r: ECDSA sig parameter
    /// @param s: ECDSA sig parameter
    function createMetavestAndLockTokensWithPermit(
        MetaVesT.MetaVesTDetails calldata _metavestDetails,
        address _depositor,
        uint256 _deadline,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) external onlyAuthority {
        //prevent overwrite of existing MetaVesT
        if (
            imetavest.metavestDetails(_metavestDetails.grantee).grantee != address(0) ||
            _metavestDetails.grantee == authority ||
            _metavestDetails.grantee == address(this)
        ) revert MetaVesTController_MetaVesTAlreadyExists();
        if (_metavestDetails.grantee == address(0) || _metavestDetails.allocation.tokenContract == address(0))
            revert MetaVesTController_ZeroAddress();
        if (
            _deadline < block.timestamp || _metavestDetails.allocation.stopTime <= _metavestDetails.allocation.startTime
        ) revert MetaVesTController_TimeVariableError();
        if (
            (_metavestDetails.metavestType == MetaVesT.MetaVesTType.OPTION &&
                _metavestDetails.option.exercisePrice == 0) ||
            (_metavestDetails.metavestType == MetaVesT.MetaVesTType.RESTRICTED &&
                _metavestDetails.rta.repurchasePrice == 0)
        ) revert MetaVesTController_ZeroPrice();

        // limit array length and ensure the milestone arrays are equal in length
        if (
            _metavestDetails.milestones.length > ARRAY_LENGTH_LIMIT ||
            (_metavestDetails.milestones.length != _metavestDetails.milestoneAwards.length)
        ) revert MetaVesTController_LengthMismatch();

        uint256 _milestoneTotal;
        for (uint256 i; i < _metavestDetails.milestones.length; ++i) {
            _milestoneTotal += _metavestDetails.milestoneAwards[i];
        }
        uint256 _total = _metavestDetails.allocation.tokenStreamTotal +
            _metavestDetails.allocation.cliffCredit +
            _milestoneTotal;
        if (_total == 0) revert MetaVesTController_ZeroAmount();

        IERC20Permit(_metavestDetails.allocation.tokenContract).permit(
            _depositor,
            metavest,
            _total,
            _deadline,
            v,
            r,
            s
        );
        imetavest.createMetavestWithPermit(_metavestDetails, _total, _depositor);
    }

    /// @notice for 'authority' to create a MetaVesT for a grantee and lock the total token amount ('metavestDetails.allocation.tokenStreamTotal' + 'metavestDetails.allocation.cliffCredit' + 'metavestDetails.milestoneAwards')
    /// @dev msg.sender ('authority') must have approved 'metavest' for 'metavestDetails.allocation.tokenStreamTotal' + 'metavestDetails.allocation.cliffCredit' + 'metavestDetails.milestoneAwards' in '_metavestDetails.allocation.tokenContract' prior to calling this function;
    /// requires transfer of exact amount of 'metavestDetails.allocation.tokenStreamTotal' + 'metavestDetails.allocation.cliffCredit' + 'metavestDetails.milestoneAwards' along with MetaVesTDetails;
    /// @param _metavestDetails: MetaVesTDetails struct containing all applicable details for this '_metavestDetails.grantee'-- but MUST contain grantee, token contract, amount, and start and stop time
    function createMetavestAndLockTokens(MetaVesT.MetaVesTDetails calldata _metavestDetails) external onlyAuthority {
        //prevent overwrite of existing MetaVesT
        if (
            imetavest.metavestDetails(_metavestDetails.grantee).grantee != address(0) ||
            _metavestDetails.grantee == authority ||
            _metavestDetails.grantee == address(this)
        ) revert MetaVesTController_MetaVesTAlreadyExists();
        if (_metavestDetails.grantee == address(0) || _metavestDetails.allocation.tokenContract == address(0))
            revert MetaVesTController_ZeroAddress();
        if (_metavestDetails.allocation.stopTime <= _metavestDetails.allocation.startTime)
            revert MetaVesTController_TimeVariableError();
        if (
            (_metavestDetails.metavestType == MetaVesT.MetaVesTType.OPTION &&
                _metavestDetails.option.exercisePrice == 0) ||
            (_metavestDetails.metavestType == MetaVesT.MetaVesTType.RESTRICTED &&
                _metavestDetails.rta.repurchasePrice == 0)
        ) revert MetaVesTController_ZeroPrice();

        // limit array length and ensure the milestone arrays are equal in length
        if (
            _metavestDetails.milestones.length > ARRAY_LENGTH_LIMIT ||
            (_metavestDetails.milestones.length != _metavestDetails.milestoneAwards.length)
        ) revert MetaVesTController_LengthMismatch();

        uint256 _milestoneTotal;
        for (uint256 i; i < _metavestDetails.milestones.length; ++i) {
            _milestoneTotal += _metavestDetails.milestoneAwards[i];
        }
        uint256 _total = _metavestDetails.allocation.tokenStreamTotal +
            _metavestDetails.allocation.cliffCredit +
            _milestoneTotal;
        if (_total == 0) revert MetaVesTController_ZeroAmount();
        if (
            IERC20Permit(_metavestDetails.allocation.tokenContract).allowance(msg.sender, metavest) < _total ||
            IERC20Permit(_metavestDetails.allocation.tokenContract).balanceOf(msg.sender) < _total
        ) revert MetaVesTController_AmountNotApprovedForTransferFrom();
        imetavest.createMetavest(_metavestDetails, _total);
    }

    /// @notice for 'authority' to withdraw tokens from this controller (i.e. which it has withdrawn from 'metavest', typically 'paymentToken')
    /// @param _tokenContract contract address of the token which is being withdrawn
    function withdrawFromController(address _tokenContract) external onlyAuthority {
        uint256 _balance = IERC20(_tokenContract).balanceOf(address(this));
        if (_balance == 0) revert MetaVesTController_ZeroAmount();

        safeTransfer(_tokenContract, authority, _balance);
    }

    /// @notice for 'authority' to initiate a 'withdrawAll' from 'metavest' via this controller, to this controller. Typically for 'paymentToken'
    /// @dev 'withdrawAll' in MetaVesT will revert if 'controller' has an 'amountWithdrawable' of 0; for 'authority' to withdraw its own 'amountWithdrawable', it must call
    /// 'withdrawAll' directly in 'metavest'
    /// @param _tokenContract contract address of the token which is being withdrawn
    function withdrawAllFromMetavest(address _tokenContract) external onlyAuthority {
        uint256 _balance = IERC20(_tokenContract).balanceOf(metavest);
        if (_balance == 0) revert MetaVesTController_ZeroAmount();

        imetavest.withdrawAll(_tokenContract);
    }

    /// @notice for 'authority' to toggle whether '_grantee''s MetaVesT is transferable-- does not revoke previous transfers, but does cause such transferees' MetaVesTs transferability to be similarly updated
    /// @param _grantee address whose MetaVesT's (and whose transferees' MetaVesTs') transferability is being updated
    /// @param _isTransferable whether transferability is to be updated to transferable (true) or nontransferable (false)
    function updateMetavestTransferability(address _grantee, bool _isTransferable) external onlyAuthority {
        if (imetavest.metavestDetails(_grantee).grantee != _grantee) revert MetaVesTController_NoMetaVesT();
        imetavest.updateTransferability(_grantee, _isTransferable);
    }

    /// @notice for the controller to update either exercisePrice or repurchasePrice for a '_grantee' and their transferees, as applicable depending on the MetaVesTType
    /// @param _grantee address of grantee whose applicable price is being updated
    /// @param _newPrice new price (in 'paymentToken' per token)
    function updateExerciseOrRepurchasePrice(address _grantee, uint256 _newPrice) external onlyAuthority {
        if (imetavest.metavestDetails(_grantee).grantee != _grantee) revert MetaVesTController_NoMetaVesT();
        if (_newPrice == 0) revert MetaVesTController_ZeroPrice();
        imetavest.updatePrice(_grantee, _newPrice);
    }

    /// @notice for 'authority' to confirm grantee has completed the current milestone (or simple a milestone, if milestones are not chronological)
    /// also unlocking the the tokens for such milestone, including any transferees
    function confirmMetavestMilestone(address _grantee) external onlyAuthority {
        if (imetavest.metavestDetails(_grantee).grantee != _grantee) revert MetaVesTController_NoMetaVesT();
        imetavest.confirmMilestone(_grantee);
    }

    /// @notice allows 'authority' to remove a milestone from '_grantee''s MetaVesT if such milestone has not yet been confirmed, also making such tokens withdrawable by controller
    /// @dev removes array element by copying last element into to the place to remove, and also shortens the array length accordingly via 'pop()' in MetaVesT.sol
    /// @param _grantee address of grantee whose MetaVesT is being updated
    /// @param _milestoneIndex element of the 'milestones' and 'milestoneAwards' arrays to be removed
    function removeMetavestMilestone(address _grantee, uint8 _milestoneIndex) external onlyAuthority {
        MetaVesT.MetaVesTDetails memory _metavest = imetavest.metavestDetails(_grantee);
        if (_metavest.grantee != _grantee && _grantee != address(0)) revert MetaVesTController_NoMetaVesT();

        uint256 _maxIndex = _metavest.milestones.length - 1; // max index is the length of the array - 1, since the index counter starts at 0; will revert from underflow if milestones.length == 0
        // revert if the milestone corresponding to '_milestoneIndex' doesn't exist or has already been completed
        if (_milestoneIndex > _maxIndex || _milestoneIndex < _metavest.milestoneIndex)
            revert MetaVesTController_MilestoneIndexCompletedOrDoesNotExist();

        // to be passed via imetavest, to update controller's amountWithdrawable
        uint256 _deletedMilestoneAward = _metavest.milestoneAwards[_milestoneIndex];

        // remove '_milestoneIndex' element from each array by shifting each subsequent element, then deleting last one in MetaVesT.sol via 'pop()'
        for (uint256 i = _milestoneIndex; i < _maxIndex; i++) {
            _metavest.milestones[i] = _metavest.milestones[i + 1];
            _metavest.milestoneAwards[i] = _metavest.milestoneAwards[i + 1];
        }

        // pass the updated arrays to MetaVesT.sol to update state variables
        imetavest.removeMilestone(
            _milestoneIndex,
            _grantee,
            _metavest.allocation.tokenContract,
            _metavest.milestones,
            _metavest.milestoneAwards,
            _deletedMilestoneAward
        );
    }

    /// @notice for the applicable authority to add a milestone for a '_grantee' (and any transferees) and transfer the award amount of tokens
    /// @param _grantee address of grantee whose MetaVesT is being updated
    /// @param _milestoneAward amount of tokens corresponding to the newly added milestone, which must be transferred via this function
    function addMetavestMilestone(address _grantee, uint256 _milestoneAward) external onlyAuthority {
        MetaVesT.MetaVesTDetails memory _metavest = imetavest.metavestDetails(_grantee);
        if (_metavest.grantee != _grantee && _grantee != address(0)) revert MetaVesTController_NoMetaVesT();
        if (_milestoneAward == 0) revert MetaVesTController_ZeroAmount();
        if (
            IERC20(_metavest.allocation.tokenContract).allowance(msg.sender, metavest) < _milestoneAward ||
            IERC20(_metavest.allocation.tokenContract).balanceOf(msg.sender) < _milestoneAward
        ) revert MetaVesT.MetaVesT_AmountNotApprovedForTransferFrom();

        safeTransferFrom(_metavest.allocation.tokenContract, msg.sender, metavest, _milestoneAward);

        imetavest.addMilestone(_grantee, _milestoneAward);
    }

    /// @notice for the applicable authority to terminate and delete this '_grantee''s MetaVesT, withdrawing all withdrawable and unlocked tokens to '_grantee'
    /// @dev makes all unlockedTokens for such grantee withdrawable then sends them to grantee,
    /// so as to avoid a mapping overwrite if the grantee's terminateed MetaVesT is replaced with a new one before they can withdraw,
    /// and returns the remainder to 'authority'
    /// @param _grantee address of grantee whose MetaVesT is being terminated
    function terminateMetavestForGrantee(address _grantee) external onlyAuthority {
        MetaVesT.MetaVesTDetails memory _metavest = imetavest.metavestDetails(_grantee);
        if (_metavest.grantee != _grantee && _grantee != address(0)) revert MetaVesTController_NoMetaVesT();
        imetavest.terminate(_grantee);
    }

    /// @notice for 'authority' to repurchase tokens subject to a restricted token award
    /// @param _grantee address whose MetaVesT is subject to the repurchase
    /// @param _divisor: divisor corresponding to the fraction of _grantee's repurchasable tokens being repurchased by 'authority'; to repurchase the full available amount, submit '1'
    function repurchaseMetavestTokens(address _grantee, uint256 _divisor) external onlyAuthority {
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
            IERC20Permit(paymentToken).allowance(msg.sender, metavest) < _payment ||
            IERC20Permit(paymentToken).balanceOf(msg.sender) < _payment
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
    function acceptAuthorityRole() external {
        if (msg.sender != _pendingAuthority) revert MetaVesTController_OnlyPendingAuthority();

        delete _pendingAuthority;
        authority = msg.sender;
        imetavest.updateAuthority(msg.sender);

        emit MetaVesTController_AuthorityUpdated(msg.sender);
    }
}
