// SPDX-License-Identifier: AGPL-3.0-only
import "./BaseAllocation.sol";

pragma solidity 0.8.20;

contract RestrictedTokenAward is BaseAllocation {

    IERC20M internal immutable ipaymentToken;
    /// @notice address of payment token used for token option exercises or restricted token repurchases
    address public immutable paymentToken;
    uint256 public shortStopDuration;
    uint256 public shortStopDate;
    uint256 public repurchasePrice;
    uint256 public tokensRepurchased;
    uint256 public tokensRepurchasedWithdrawn;


    error MetaVesT_InsufficientPaymentTokenBalance();
    event MetaVesT_TokenOptionExercised(address indexed _grantee, uint256 _tokensToExercise, uint256 _paymentAmount);

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
        ipaymentToken = IERC20M(_paymentToken);

        // manually copy milestones
        for (uint256 i; i < _milestones.length; ++i) {
            milestones.push(_milestones[i]);
        }
    }

    function getVestingType() external pure override returns (uint256) {
        return 3;
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
             governingPower = getVestedTokenAmount() - tokensWithdrawn;
        else 
            governingPower = _min(getVestedTokenAmount(), getUnlockedTokenAmount()) - tokensWithdrawn;
        
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
        repurchasePrice = _newPrice;
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
        uint8 repurchaseTokenDecimals = IERC20M(allocation.tokenContract).decimals();
        
        // Calculate paymentAmount
        uint256 paymentAmount;
        if (paymentDecimals >= repurchaseTokenDecimals) {
            paymentAmount = _amount * repurchasePrice / (10**repurchaseTokenDecimals);
        } else {
            paymentAmount = _amount * repurchasePrice / (10**repurchaseTokenDecimals);
            paymentAmount = paymentAmount / (10**(repurchaseTokenDecimals - paymentDecimals));
        }
        return paymentAmount;
    }

    function repurchaseTokens(uint256 _amount) external onlyAuthority nonReentrant {
        if(!terminated) revert MetaVesT_NotTerminated();
        if (_amount == 0) revert MetaVesT_ZeroAmount();
        if (_amount > getAmountRepurchasable()) revert MetaVesT_MoreThanAvailable();
        
        // Calculate repurchaseAmount
        uint256 repurchaseAmount = getPaymentAmount(_amount);

        safeTransferFrom(paymentToken, getAuthority(), address(this), repurchaseAmount);
        // transfer all repurchased tokens to 'authority'
        safeTransfer(allocation.tokenContract, getAuthority(), _amount);
        tokensRepurchased += _amount;
        emit MetaVesT_RepurchaseAndWithdrawal(grantee, allocation.tokenContract, _amount, repurchaseAmount);
    }

    function claimRepurchasedTokens() external onlyGrantee nonReentrant {
        if(IERC20M(paymentToken).balanceOf(address(this)) == 0) revert MetaVesT_MoreThanAvailable();
        uint256 _amount = IERC20M(paymentToken).balanceOf(address(this));
        safeTransfer(paymentToken, msg.sender, _amount);
        tokensRepurchasedWithdrawn += _amount;
        emit MetaVesT_Withdrawn(msg.sender, paymentToken, _amount);
    }

    function terminate() external override onlyController nonReentrant {
         if(terminated) revert MetaVesT_AlreadyTerminated();
        uint256 tokensToRecover = 0;
        uint256 milestonesAllocation = 0;
        for (uint256 i; i < milestones.length; ++i) {
                milestonesAllocation += milestones[i].milestoneAward;
        }
        terminationTime = block.timestamp;
        // remaining tokens must be repruchased by 'authority'
        // REVIEW: unused.
        shortStopDate = block.timestamp + shortStopDuration;
        terminated = true;
        emit MetaVesT_Terminated(grantee, tokensToRecover);
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

    function getAmountRepurchasable() public view returns (uint256) {
        if(!terminated) return 0;
       
         uint256 milestonesAllocation = 0;
        for (uint256 i; i < milestones.length; ++i) {
                milestonesAllocation += milestones[i].milestoneAward;
        }
        return allocation.tokenStreamTotal + milestonesAllocation - getVestedTokenAmount();
    }

     function getVestedTokenAmount() public view returns (uint256) {
        if(block.timestamp<allocation.vestingStartTime)
            return 0;
        uint256 _timeElapsedSinceVest = block.timestamp - allocation.vestingStartTime;

        if(terminated)
            _timeElapsedSinceVest = terminationTime - allocation.vestingStartTime;

           uint256 _tokensVested = (_timeElapsedSinceVest * allocation.vestingRate) + allocation.vestingCliffCredit;

            if(_tokensVested>allocation.tokenStreamTotal) 
                _tokensVested = allocation.tokenStreamTotal;
        return _tokensVested += milestoneAwardTotal;
    }

    function getUnlockedTokenAmount() public view returns (uint256) {
        if(block.timestamp<allocation.unlockStartTime)
            return 0;
        uint256 _timeElapsedSinceUnlock = block.timestamp - allocation.unlockStartTime;

        uint256 _tokensUnlocked = (_timeElapsedSinceUnlock * allocation.unlockRate) + allocation.unlockingCliffCredit;

        if(_tokensUnlocked>allocation.tokenStreamTotal) 
            _tokensUnlocked = allocation.tokenStreamTotal;

        return _tokensUnlocked += milestoneUnlockedTotal;
    }


    function getAmountWithdrawable() public view override returns (uint256) {
        uint256 _tokensVested = getVestedTokenAmount();
        uint256 _tokensUnlocked = getUnlockedTokenAmount();
        return _min(_tokensVested, _tokensUnlocked) - tokensWithdrawn;
    }

    function getMetavestDetails() public view override returns (Allocation memory) {
        return allocation;
    }

}
