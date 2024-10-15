// SPDX-License-Identifier: AGPL-3.0-only
import "./BaseAllocation.sol";

pragma solidity 0.8.20;

contract TokenOptionAllocation is BaseAllocation {

    IERC20M internal immutable ipaymentToken;
    /// @notice address of payment token used for token option exercises or restricted token repurchases
    address public immutable paymentToken;
    uint256 public tokensExercised;
    uint256 public exercisePrice; 
    uint256 public shortStopDuration;
    uint256 public shortStopTime;
    uint256 public longStoptDate;

    error MetaVesT_InsufficientPaymentTokenBalance();
    event MetaVesT_TokenOptionExercised(address indexed _grantee, uint256 _tokensToExercise, uint256 _paymentAmount);

    /// @notice Constructor to create a TokenOptionAllocation
    /// @param _grantee - address of the grantee
    /// @param _controller - address of the controller
    /// @param _paymentToken - address of the payment token
    /// @param _exercisePrice - price of the token option exercise in vesting token decimals but only up to payment decimal precision
    /// @param _shortStopDuration - duration of the short stop
    /// @param _allocation - allocation details as an Allocation struct
    /// @param _milestones - milestones with conditions and awards
    constructor (
        address _grantee,
        address _controller,
        address _paymentToken,
        uint256 _exercisePrice,
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
        exercisePrice = _exercisePrice;
        shortStopDuration = _shortStopDuration;

        paymentToken = _paymentToken;
        ipaymentToken = IERC20M(_paymentToken);

        // manually copy milestones
        for (uint256 i; i < _milestones.length; ++i) {
            milestones.push(_milestones[i]);
        }
    }

    /// @notice returns the contract vesting type 2 for TokenOptionAllocation
    /// @return 2
    function getVestingType() external pure override returns (uint256) {
        return 2;
    }

    /// @notice returns the governing power of the TokenOptionAllocation
    /// @return governingPower - the governing power of the TokenOptionAllocation based on the governance setting
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
            governingPower = tokensExercised - tokensWithdrawn;
        else 
            governingPower = _min(tokensExercised, getUnlockedTokenAmount()) - tokensWithdrawn;
        
        return governingPower;
    }

    /// @notice updates the short stop time of the TokenOptionAllocation
    /// @dev onlyController -- must be called from the metavest controller
    /// @param _shortStopTime - the new short stop time
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
        exercisePrice = _newPrice;
        emit MetaVesT_PriceUpdated(grantee, _newPrice);
    }

    /// @notice gets the payment amount for a given amount of tokens
    /// @param _amount - the amount of tokens to calculate the payment amount  in the vesting token decimals
    /// @return paymentAmount - the payment amount for the given token amount in the payment token decimals
    function getPaymentAmount(uint256 _amount) public view returns (uint256) {
        uint8 paymentDecimals = IERC20M(paymentToken).decimals();
        uint8 exerciseTokenDecimals = IERC20M(allocation.tokenContract).decimals();
        
        // Calculate paymentAmount
        uint256 paymentAmount;
        paymentAmount = _amount * exercisePrice / (10**exerciseTokenDecimals);
        
        //scale paymentAmount to payment token decimals
        if(paymentDecimals<exerciseTokenDecimals) {
            paymentAmount = paymentAmount / (10**(exerciseTokenDecimals-paymentDecimals));
        }
        else {
            paymentAmount = paymentAmount * (10**(paymentDecimals-exerciseTokenDecimals));
        }
        
        return paymentAmount;
    }

    /// @notice exercises the token option
    /// @dev onlyGrantee -- must be called from the grantee
    /// @param _tokensToExercise - the number of tokens to exercise
    function exerciseTokenOption(uint256 _tokensToExercise) external nonReentrant onlyGrantee {
        if(block.timestamp>shortStopTime && terminated) revert MetaVest_ShortStopDatePassed();
        if (_tokensToExercise == 0) revert MetaVesT_ZeroAmount();
        if (_tokensToExercise > getAmountExercisable()) revert MetaVesT_MoreThanAvailable();

        // Calculate paymentAmount
        uint256 paymentAmount = getPaymentAmount(_tokensToExercise);
        if(paymentAmount == 0) revert MetaVesT_TooSmallAmount();
        
        if (IERC20M(paymentToken).balanceOf(msg.sender) < paymentAmount) revert MetaVesT_InsufficientPaymentTokenBalance();
        safeTransferFrom(paymentToken, msg.sender, getAuthority(), paymentAmount);
        tokensExercised += _tokensToExercise;
        emit MetaVesT_TokenOptionExercised(msg.sender, _tokensToExercise, paymentAmount);
    }

    /// @notice Allows the controller to terminate the TokenOptionAllocation
    /// @dev onlyController -- must be called from the metavest controller
    function terminate() external override onlyController nonReentrant {
        if(terminated) revert MetaVesT_AlreadyTerminated();
        
        uint256 milestonesAllocation = 0;
        for (uint256 i; i < milestones.length; ++i) {
                milestonesAllocation += milestones[i].milestoneAward;
        }
        uint256 tokensToRecover = allocation.tokenStreamTotal + milestonesAllocation - getAmountExercisable() - tokensExercised;
        terminationTime = block.timestamp;
        shortStopTime = block.timestamp + shortStopDuration;
        safeTransfer(allocation.tokenContract, getAuthority(), tokensToRecover);
        terminated = true;
        emit MetaVesT_Terminated(grantee, tokensToRecover);
    }

    /// @notice recovers any forfeited tokens after the short stop time
    /// @dev onlyAuthority -- must be called from the authority
    function recoverForfeitTokens() external onlyAuthority nonReentrant {
        if(block.timestamp<shortStopTime || shortStopTime==0 || terminated != true) revert MetaVesT_ShortStopTimeNotReached();
        uint256 tokensToRecover = IERC20M(allocation.tokenContract).balanceOf(address(this)) - tokensExercised;
        safeTransfer(allocation.tokenContract, getAuthority(), tokensToRecover);
    }

    /// @notice gets the amount of tokens available for a grantee to exercise
    /// @return uint256 amount of tokens available for the grantee to exercise
    function getAmountExercisable() public view returns (uint256) {
        if(block.timestamp<allocation.vestingStartTime || (block.timestamp>shortStopTime && shortStopTime>0))
            return 0;

        uint256 _timeElapsedSinceVest = block.timestamp - allocation.vestingStartTime;
        if(terminated)
            _timeElapsedSinceVest = terminationTime - allocation.vestingStartTime;

        uint256 _tokensVested = (_timeElapsedSinceVest * allocation.vestingRate) + allocation.vestingCliffCredit;

        if(_tokensVested>allocation.tokenStreamTotal) 
            _tokensVested = allocation.tokenStreamTotal;
    
        return _tokensVested + milestoneAwardTotal - tokensExercised;
    }

    /// @notice gets the amount of tokens unlocked for a grantee 
    /// @return uint256 amount of tokens unlocked for the grantee
    function getUnlockedTokenAmount() public view returns (uint256) {
        if(block.timestamp<allocation.unlockStartTime)
            return 0;
        uint256 _timeElapsedSinceUnlock = block.timestamp - allocation.unlockStartTime;
        uint256 _tokensUnlocked = (_timeElapsedSinceUnlock * allocation.unlockRate) + allocation.unlockingCliffCredit;
    
        if(_tokensUnlocked>allocation.tokenStreamTotal + milestoneAwardTotal) 
            _tokensUnlocked = allocation.tokenStreamTotal + milestoneAwardTotal;

        return _tokensUnlocked + milestoneUnlockedTotal;
    }

    /// @notice gets the amount of tokens available for a grantee to withdraw
    /// @return uint256 amount of tokens available for the grantee to withdraw
    function getAmountWithdrawable() public view override returns (uint256) {
        uint256 _tokensUnlocked = getUnlockedTokenAmount();
        return _min(tokensExercised, _tokensUnlocked) - tokensWithdrawn;
    }

}
