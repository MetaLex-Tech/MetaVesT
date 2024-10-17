// SPDX-License-Identifier: AGPL-3.0-only
import "./BaseAllocation.sol";

pragma solidity 0.8.20;

contract RestrictedTokenAward is BaseAllocation {

    /// @notice address of payment token used for token option exercises or restricted token repurchases
    address public immutable paymentToken;
    uint256 public shortStopDuration;
    uint256 public shortStopDate;
    uint256 public repurchasePrice;
    uint256 public tokensRepurchased;
    uint256 public tokensRepurchasedWithdrawn;

    /// @notice Constructor to deploy a new RestrictedTokenAward
    /// @param _grantee - address of the grantee
    /// @param _controller - address of the controller
    /// @param _paymentToken - address of the payment token
    /// @param _repurchasePrice - price at which the restricted tokens can be repurchased in vesting token decimals but only up to payment decimal precision
    /// @param _shortStopDuration - duration after termination during which restricted tokens can be repurchased
    /// @param _allocation - allocation details as an Allocation struct
    /// @param _milestones - milestones with their conditions and awards
    constructor (
        address _grantee,
        address _controller,
        address _paymentToken,
        uint256 _repurchasePrice,
        uint256 _shortStopDuration,
        Allocation memory _allocation,
        Milestone[] memory _milestones
    ) BaseAllocation(
         _grantee,
         _controller
    ) {
        //perform input validation
        if (_allocation.tokenContract == address(0)) revert MetaVesT_ZeroAddress();
        if (_allocation.tokenStreamTotal == 0) revert MetaVesT_ZeroAmount();
        if (_allocation.vestingRate >  1000*1e18 || _allocation.unlockRate > 1000*1e18) revert MetaVesT_RateTooHigh();

        //set vesting allocation variables
        allocation.tokenContract = _allocation.tokenContract;
        allocation.tokenStreamTotal = _allocation.tokenStreamTotal;
        allocation.vestingCliffCredit = _allocation.vestingCliffCredit;
        allocation.unlockingCliffCredit = _allocation.unlockingCliffCredit;
        allocation.vestingRate = _allocation.vestingRate;
        allocation.vestingStartTime = _allocation.vestingStartTime;
        allocation.unlockRate = _allocation.unlockRate;
        allocation.unlockStartTime = _allocation.unlockStartTime;

        // set token option variables
        repurchasePrice = _repurchasePrice;
        shortStopDuration = _shortStopDuration;

        paymentToken = _paymentToken;

        // manually copy milestones
        for (uint256 i; i < _milestones.length; ++i) {
            milestones.push(_milestones[i]);
        }
    }

    /// @notice returns the vesting type for RestrictedTokenAward
    /// @return uint256 type 3
    function getVestingType() external pure override returns (uint256) {
        return 3;
    }

    /// @notice returns the governing power for RestrictedTokenAward based on the govType
    /// @return uint256 governingPower for this RestrictedTokenAward contract
    function getGoverningPower() external view override returns (uint256) {
        uint256 governingPower;
      if(govType==GovType.all)
        {
            uint256 totalMilestoneAward = 0;
            for(uint256 i; i < milestones.length; ++i)
            { 
                    totalMilestoneAward += milestones[i].milestoneAward;
            }
            governingPower = (allocation.tokenStreamTotal + totalMilestoneAward) - tokensWithdrawn;
        }
        else if(govType==GovType.vested)
             governingPower = getVestedTokenAmount() - tokensWithdrawn;
        else 
            governingPower = _min(getVestedTokenAmount(), getUnlockedTokenAmount()) - tokensWithdrawn;
        
        return governingPower;
    }

    /// @notice updates the short stop time of the vesting contract
    /// @dev onlyController -- must be called from the metavest controller
    /// @param _shortStopTime - new short stop time to be set in seconds
    function updateStopTimes(uint48 _shortStopTime) external override onlyController {
        if(terminated) revert MetaVesT_AlreadyTerminated();
        shortStopDuration = _shortStopTime;
        emit MetaVesT_StopTimesUpdated(grantee, _shortStopTime);
    }

    /// @notice updates the exercise price
    /// @dev onlyController -- must be called from the metavest controller
    /// @param _newPrice - the new exercise price in vesting token decimals but only up to payment decimal precision
    function updatePrice(uint256 _newPrice) external onlyController {
        if(terminated) revert MetaVesT_AlreadyTerminated();
        repurchasePrice = _newPrice;
        emit MetaVesT_PriceUpdated(grantee, _newPrice);
    }

    /// @notice gets the payment amount for a given amount of tokens
    /// @param _amount - the amount of tokens to calculate the payment amount  in the vesting token decimals
    /// @return paymentAmount - the payment amount for the given token amount in the payment token decimals
    function getPaymentAmount(uint256 _amount) public view returns (uint256) {
        uint8 paymentDecimals = IERC20M(paymentToken).decimals();
        uint8 repurchaseTokenDecimals = IERC20M(allocation.tokenContract).decimals();
        
        // Calculate paymentAmount
        uint256 paymentAmount;
        paymentAmount = _amount * repurchasePrice / (10**repurchaseTokenDecimals);
        
        //scale paymentAmount to payment token decimals
        if(paymentDecimals<repurchaseTokenDecimals) {
            paymentAmount = paymentAmount / (10**(repurchaseTokenDecimals-paymentDecimals));
        }
        else {
            paymentAmount = paymentAmount * (10**(paymentDecimals-repurchaseTokenDecimals));
        }
        
        return paymentAmount;
    }

    /// @notice allows the authority to repurchase tokens after termination
    /// @dev onlyAuthority -- must be called by the authority
    /// @param _amount - the amount of tokens to repurchase in the vesting token decimals
    function repurchaseTokens(uint256 _amount) external onlyAuthority nonReentrant {
        if(!terminated) revert MetaVesT_NotTerminated();
        if (_amount == 0) revert MetaVesT_ZeroAmount();
        if (_amount > getAmountRepurchasable()) revert MetaVesT_MoreThanAvailable();
        if(block.timestamp<shortStopDate) revert MetaVesT_ShortStopTimeNotReached();

        // Calculate repurchaseAmount
        uint256 repurchaseAmount = getPaymentAmount(_amount);
        if(repurchaseAmount == 0) revert MetaVesT_TooSmallAmount();

        safeTransferFrom(paymentToken, getAuthority(), address(this), repurchaseAmount);
        // transfer all repurchased tokens to 'authority'
        safeTransfer(allocation.tokenContract, getAuthority(), _amount);
        tokensRepurchased += _amount;
        emit MetaVesT_RepurchaseAndWithdrawal(grantee, allocation.tokenContract, _amount, repurchaseAmount);
    }

    /// @notice allows the grantee to claim the amount paid for repurchased tokens
    /// @dev onlyGrantee -- must be called by the grantee
    function claimRepurchasedTokens() external onlyGrantee nonReentrant {
        if(IERC20M(paymentToken).balanceOf(address(this)) == 0) revert MetaVesT_MoreThanAvailable();
        uint256 _amount = IERC20M(paymentToken).balanceOf(address(this));
        safeTransfer(paymentToken, msg.sender, _amount);
        tokensRepurchasedWithdrawn += _amount;
        emit MetaVesT_Withdrawn(msg.sender, paymentToken, _amount);
    }

    /// @notice Allows the controller to terminate the RestrictedTokenAward
    /// @dev onlyController -- must be called from the metavest controller
    function terminate() external override onlyController nonReentrant {
         if(terminated) revert MetaVesT_AlreadyTerminated();

        terminationTime = block.timestamp;
        // remaining tokens must be repurchased by 'authority'
        shortStopDate = block.timestamp + shortStopDuration;
        terminated = true;
        emit MetaVesT_Terminated(grantee, 0);
    }

    /// @notice returns the amount of tokens that can be repurchased
    /// @return uint256 amount of tokens that can be repurchased
    function getAmountRepurchasable() public view returns (uint256) {
        if(!terminated) return 0;
       
         uint256 milestonesAllocation = 0;
        for (uint256 i; i < milestones.length; ++i) {
                milestonesAllocation += milestones[i].milestoneAward;
        }
        uint256 repurchaseAmount = allocation.tokenStreamTotal + milestonesAllocation - getVestedTokenAmount() - tokensRepurchased;
        if(repurchaseAmount>IERC20M(allocation.tokenContract).balanceOf(address(this)))
           repurchaseAmount = IERC20M(allocation.tokenContract).balanceOf(address(this));
        return repurchaseAmount;
    }

    /// @notice returns the amount of tokens that are vested
    /// @return uint256 amount of tokens that are vested
     function getVestedTokenAmount() public view returns (uint256) {
        if(block.timestamp<allocation.vestingStartTime || (terminated && terminationTime<allocation.vestingStartTime))
            return 0;
        uint256 _timeElapsedSinceVest = block.timestamp - allocation.vestingStartTime;

        if(terminated)
            _timeElapsedSinceVest = terminationTime - allocation.vestingStartTime;

           uint256 _tokensVested = (_timeElapsedSinceVest * allocation.vestingRate) + allocation.vestingCliffCredit;

            if(_tokensVested>allocation.tokenStreamTotal) 
                _tokensVested = allocation.tokenStreamTotal;
        return _tokensVested += milestoneAwardTotal;
    }

    /// @notice returns the amount of tokens that are unlocked
    /// @return uint256 amount of tokens that are unlocked
    function getUnlockedTokenAmount() public view returns (uint256) {
        if(block.timestamp<allocation.unlockStartTime)
            return 0;
        uint256 _timeElapsedSinceUnlock = block.timestamp - allocation.unlockStartTime;

        uint256 _tokensUnlocked = (_timeElapsedSinceUnlock * allocation.unlockRate) + allocation.unlockingCliffCredit;

        if(_tokensUnlocked>allocation.tokenStreamTotal + milestoneAwardTotal) 
            _tokensUnlocked = allocation.tokenStreamTotal + milestoneAwardTotal;

        return _tokensUnlocked += milestoneUnlockedTotal;
    }

    /// @notice returns the amount of tokens that can be withdrawn
    /// @return uint256 amount of tokens that can be withdrawn
    function getAmountWithdrawable() public view override returns (uint256) {
        uint256 _tokensVested = getVestedTokenAmount();
        uint256 _tokensUnlocked = getUnlockedTokenAmount();
        uint256 withdrawableAmount = _min(_tokensVested, _tokensUnlocked);
        if(withdrawableAmount>tokensWithdrawn)
            return withdrawableAmount - tokensWithdrawn;
        else
            return 0;
    }

}
