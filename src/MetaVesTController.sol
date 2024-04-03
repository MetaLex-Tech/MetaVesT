//SPDX-License-Identifier: AGPL-3.0-only

/*
**************************************
                            MetaVesT Controller
                                     *************************************
                                                                        */

pragma solidity ^0.8.18;

import "./MetaVesT.sol";

interface IERC20 {
    function balanceOf(address account) external view returns (uint256);
}

interface IMetaVesT {
    function confirmMilestone(address grantee) external;
    function refreshMetavest(address grantee) external;
    function repurchaseTokens(address grantee, uint256 divisor) external;
    function revokeMetavest(address grantee) external;
    function metavestDetails(address grantee) external view returns (MetaVesT.MetaVesTDetails memory details);
    function transferees(address grantee) external view returns (address[] memory);
    function updateMetavestDetails(address grantee, MetaVesT.MetaVesTDetails calldata details) external;
    function withdrawAll(address tokenAddress) external;
}

/**
 * @title      MetaVesT Controller
 *
 * @notice     Contract for a MetaVesT's authority to configure parameters, confirm milestones, and
 *             other permissioned functions
 **/
contract MetaVesTController is SafeTransferLib {
    //supported DAO/voting/staking contract types
    //enum GovernorType {}

    address public immutable metavest;
    address public immutable paymentToken;
    IMetaVesT internal immutable imetavest;

    address public authority;
    address internal _pendingAuthority;

    event MetaVesTController_AuthorityUpdated(address newAuthority);

    error MetaVesTController_CannotAlterTokenContract();
    error MetaVesTController_IncorrectAddress();
    error MetaVesTController_IncorrectMetaVesTType();
    error MetaVesTController_MustRevokeCurrentMetaVesTAndCreateNew();
    error MetaVesTController_NoMetaVesT();
    error MetaVesTController_OnlyAuthority();
    error MetaVesTController_OnlyPendingAuthority();
    error MetaVesTController_RepurchaseExpired();
    error MetaVesTController_TimeVariableError();
    error MetaVesTController_ZeroAmount();

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

    /// @notice for 'authority' to confirm grantee has completed the current milestone (or simple a milestone, if milestones are not chronological)
    /// also unlocking the the tokens for such milestone, including any transferees
    function confirmMilestone(address _grantee) external onlyAuthority {
        if (imetavest.metavestDetails(_grantee).grantee != _grantee) revert MetaVesTController_NoMetaVesT();
        imetavest.confirmMilestone(_grantee);
    }

    /// @notice for the applicable authority to update this MetaVesT's details. If a MetaVesT is being altered to
    /// reduce token amount, use 'revokeMetavest()' then create a new MetaVesT in MetaVesT.sol for such grantee
    /// @dev cannot use this to create a new MetaVesT, call function in MetaVesT.sol directly as tokens must be transferred
    /// @param _grantee address of grantee whose MetaVesT is being updated
    /// @param _newMetavestDetails MetaVesTDetails struct to be updated for '_grantee'
    function updateMetavestDetails(
        address _grantee,
        MetaVesT.MetaVesTDetails calldata _newMetavestDetails
    ) external onlyAuthority {
        MetaVesT.MetaVesTDetails memory _metavest = imetavest.metavestDetails(_grantee);
        if (_metavest.grantee != _grantee) revert MetaVesTController_NoMetaVesT();
        if (_metavest.allocation.tokenContract != _newMetavestDetails.allocation.tokenContract)
            revert MetaVesTController_CannotAlterTokenContract();
        if (_newMetavestDetails.allocation.tokenStreamTotal == 0) revert MetaVesTController_ZeroAmount();
        if (
            _newMetavestDetails.allocation.startTime <= block.timestamp ||
            _newMetavestDetails.allocation.stopTime <= _newMetavestDetails.allocation.startTime
        ) revert MetaVesTController_TimeVariableError();

        imetavest.updateMetavestDetails(_grantee, _newMetavestDetails);
    }

    /// @notice for the applicable authority to revoke this '_grantee''s MetaVesT, withdrawing all withdrawable and unlocked tokens to '_grantee'
    /// @dev makes all unlockedTokens for such grantee withdrawable then sends them to grantee,
    /// so as to avoid a mapping overwrite if the grantee's revoked MetaVesT is replaced with a new one before they can withdraw,
    /// and returns the remainder to 'authority'
    /// @param _grantee address of grantee whose MetaVesT is being revoked
    function revokeMetavest(address _grantee) external onlyAuthority {
        MetaVesT.MetaVesTDetails memory _metavest = imetavest.metavestDetails(_grantee);
        if (_metavest.grantee != _grantee) revert MetaVesTController_NoMetaVesT();
        imetavest.revokeMetavest(_grantee);
    }

    /// @notice for 'authority' to repurchase tokens subject to a restricted token award
    /// @param _grantee address whose MetaVesT is subject to the repurchase
    /// @param _divisor: divisor corresponding to the fraction of _grantee's repurchasable tokens being repurchased by 'authority'; to repurchase the full available amount, submit '1'
    function repurchaseTokens(address _grantee, uint256 _divisor) external onlyAuthority {
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
    function updateAuthority(address _newAuthority) external onlyAuthority {
        _pendingAuthority = _newAuthority;
    }

    /// @notice allows the pending new authority to accept the role transfer
    /// @dev access restricted to the address stored as '_pendingauthority' to accept the two-step change. Transfers 'authority' role to the caller and deletes '_pendingauthority' to reset.
    function acceptAuthorityRole() external {
        if (msg.sender != _pendingAuthority) revert MetaVesTController_OnlyPendingAuthority();
        delete _pendingAuthority;
        authority = msg.sender;
        emit MetaVesTController_AuthorityUpdated(msg.sender);
    }
}
