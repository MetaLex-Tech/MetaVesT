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
    //emit MetaVesT_TokenOptionExercised(msg.sender, _tokensToExercise, _tokensToExercise * tokenOption.exercisePrice);
    event MetaVesT_TokenOptionExercised(address indexed _grantee, uint256 _tokensToExercise, uint256 _paymentAmount);

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

    function getVestingType() external pure override returns (uint256) {
        return 2;
    }

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


    function updateTransferability(bool _transferable) external override onlyController {
        transferable = _transferable;
        emit MetaVesT_TransferabilityUpdated(grantee, _transferable);
    }

    function updateVestingRate(uint160 _newVestingRate) external override onlyController {
        if(terminated) revert MetaVesT_AlreadyTerminated();
        allocation.vestingRate = _newVestingRate;
          emit MetaVesT_VestingRateUpdated(grantee, _newVestingRate);
    }

    function updateUnlockRate(uint160 _newUnlockRate) external override onlyController {
        if(terminated) revert MetaVesT_AlreadyTerminated();
        allocation.unlockRate = _newUnlockRate;
        emit MetaVesT_UnlockRateUpdated(grantee, _newUnlockRate);
    }

    function updateStopTimes(uint48 _shortStopTime) external override onlyController {
        if(terminated) revert MetaVesT_AlreadyTerminated();
        shortStopDuration = _shortStopTime;
        emit MetaVesT_StopTimesUpdated(grantee, _shortStopTime);
    }

    function updatePrice(uint256 _newPrice) external onlyController {
        if(terminated) revert MetaVesT_AlreadyTerminated();
        exercisePrice = _newPrice;
        emit MetaVesT_PriceUpdated(grantee, _newPrice);
    }

    function confirmMilestone(uint256 _milestoneIndex) external override nonReentrant {
        if(terminated) revert MetaVesT_AlreadyTerminated();
        if (_milestoneIndex >= milestones.length || milestones[_milestoneIndex].complete)
            revert MetaVesT_MilestoneIndexCompletedOrDoesNotExist();

        //encode the milestone index to bytes for signature verification
        bytes memory _data = abi.encodePacked(_milestoneIndex);
        // perform any applicable condition checks, including whether 'authority' has a signatureCondition
        for (uint256 i; i < milestones[_milestoneIndex].conditionContracts.length; ++i) {
            if (!IConditionM(milestones[_milestoneIndex].conditionContracts[i]).checkCondition(address(this), msg.sig, _data))
                revert MetaVesT_ConditionNotSatisfied();
        }

        milestones[_milestoneIndex].complete = true;
        milestoneAwardTotal += milestones[_milestoneIndex].milestoneAward;
          if(milestones[_milestoneIndex].unlockOnCompletion)
            milestoneUnlockedTotal += milestones[_milestoneIndex].milestoneAward;

        emit MetaVesT_MilestoneCompleted(grantee, _milestoneIndex);
    }

    function removeMilestone(uint256 _milestoneIndex) external override onlyController {
        if(terminated) revert MetaVesT_AlreadyTerminated();
        if (_milestoneIndex >= milestones.length) revert MetaVesT_ZeroAmount();
        delete milestones[_milestoneIndex];
    }

    function addMilestone(Milestone calldata _milestone) external override onlyController {
        if(terminated) revert MetaVesT_AlreadyTerminated();
        milestones.push(_milestone);
        emit MetaVesT_MilestoneAdded(grantee, _milestone);
    }

    function getPaymentAmount(uint256 _amount) public view returns (uint256) {
        uint8 paymentDecimals = IERC20M(paymentToken).decimals();
        uint8 exerciseTokenDecimals = IERC20M(allocation.tokenContract).decimals();
        
        // Calculate paymentAmount
        uint256 paymentAmount;
        if (paymentDecimals >= exerciseTokenDecimals) {
            paymentAmount = _amount * exercisePrice / (10**exerciseTokenDecimals);
        } else {
            paymentAmount = _amount * exercisePrice / (10**exerciseTokenDecimals);
            paymentAmount = paymentAmount / (10**(exerciseTokenDecimals - paymentDecimals));
        }
        return paymentAmount;
    }

    function exerciseTokenOption(uint256 _tokensToExercise) external nonReentrant onlyGrantee {
        if(block.timestamp>shortStopTime && terminated) revert MetaVesT_ShortStopTimeNotReached();
        if (_tokensToExercise == 0) revert MetaVesT_ZeroAmount();
        if (_tokensToExercise > getAmountExercisable()) revert MetaVesT_MoreThanAvailable();
        // Calculate paymentAmount
        uint256 paymentAmount = getPaymentAmount(_tokensToExercise);
        
        if (IERC20M(paymentToken).balanceOf(msg.sender) < paymentAmount) revert MetaVesT_InsufficientPaymentTokenBalance();
        safeTransferFrom(paymentToken, msg.sender, getAuthority(), paymentAmount);
        tokensExercised += _tokensToExercise;
        emit MetaVesT_TokenOptionExercised(msg.sender, _tokensToExercise, paymentAmount);
    }

    function terminate() external override onlyController nonReentrant {
        if(terminated) revert MetaVesT_AlreadyTerminated();
        
        uint256 milestonesAllocation = 0;
        for (uint256 i; i < milestones.length; ++i) {
                milestonesAllocation += milestones[i].milestoneAward;
        }
        uint256 tokensToRecover = allocation.tokenStreamTotal + milestonesAllocation - getAmountExercisable() - tokensExercised + tokensWithdrawn;
        terminationTime = block.timestamp;
        shortStopTime = block.timestamp + shortStopDuration;
        safeTransfer(allocation.tokenContract, getAuthority(), tokensToRecover);
        terminated = true;
        emit MetaVesT_Terminated(grantee, tokensToRecover);
    }

    function recoverForfeitTokens() external onlyController nonReentrant {
        if(block.timestamp<shortStopTime || shortStopTime==0 || terminated != true) revert MetaVesT_ShortStopTimeNotReached();
        uint256 tokensToRecover = IERC20M(allocation.tokenContract).balanceOf(address(this)) - getAmountWithdrawable();
        safeTransfer(allocation.tokenContract, getAuthority(), tokensToRecover);
    }

    function transferRights(address _newOwner) external override onlyGrantee {
        if(_newOwner == address(0)) revert MetaVesT_ZeroAddress();
        if(!transferable) revert MetaVesT_VestNotTransferable();
        emit MetaVesT_TransferredRights(grantee, _newOwner);
        prevOwners.push(grantee);
        grantee = _newOwner;
    }

    function withdraw(uint256 _amount) external override nonReentrant onlyGrantee {
        if (_amount == 0) revert MetaVesT_ZeroAmount();
        if (_amount > getAmountWithdrawable() || _amount > IERC20M(allocation.tokenContract).balanceOf(address(this))) revert MetaVesT_MoreThanAvailable();
        tokensWithdrawn += _amount;
        safeTransfer(allocation.tokenContract, msg.sender, _amount);
        emit MetaVesT_Withdrawn(msg.sender, allocation.tokenContract, _amount);
    }

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

    function getUnlockedTokenAmount() public view returns (uint256) {
        if(block.timestamp<allocation.unlockStartTime)
            return 0;
        uint256 _timeElapsedSinceUnlock = block.timestamp - allocation.unlockStartTime;
        uint256 _tokensUnlocked = (_timeElapsedSinceUnlock * allocation.unlockRate) + allocation.unlockingCliffCredit;
    
        if(_tokensUnlocked>allocation.tokenStreamTotal) 
            _tokensUnlocked = allocation.tokenStreamTotal;

        return _tokensUnlocked + milestoneUnlockedTotal;
    }

    function getAmountWithdrawable() public view override returns (uint256) {
        uint256 _tokensUnlocked = getUnlockedTokenAmount();
        return _min(tokensExercised, _tokensUnlocked) - tokensWithdrawn;
    }

    function getMetavestDetails() public view override returns (Allocation memory) {
        return allocation;
    }

}
