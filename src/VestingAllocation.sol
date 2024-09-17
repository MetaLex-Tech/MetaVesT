// SPDX-License-Identifier: AGPL-3.0-only
import "./BaseAllocation.sol";

pragma solidity 0.8.20;

contract VestingAllocation is BaseAllocation {

    /// @notice constructor for VestingAllocation
    /// @param _grantee address of the grantee
    /// @param _controller address of the controller
    /// @param _allocation Allocation struct containing token contract
    /// @param _milestones array of Milestone structs with conditions and awards
    constructor (
        address _grantee,
        address _controller,
        Allocation memory _allocation,
        Milestone[] memory _milestones
    ) BaseAllocation(
         _grantee,
         _controller
    ) {
        //perform input validation
        if (_allocation.tokenContract == address(0)) revert MetaVesT_ZeroAddress();
        if (_allocation.tokenStreamTotal == 0) revert MetaVesT_ZeroAmount();
        if (_grantee == address(0)) revert MetaVesT_ZeroAddress();
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
        // manually copy milestones
        for (uint256 i; i < _milestones.length; ++i) {
            milestones.push(_milestones[i]);
        }
    }

    /// @notice returns the contract vesting type 1 for VestingAllocation
    /// @return 1 for VestingAllocation
    function getVestingType() external pure override returns (uint256) {
        return 1;
    }

    /// @notice returns the governing power of the VestingAllocation
    /// @return governingPower - the governing power of the VestingAllocation based on the governance setting
    function getGoverningPower() external view override returns (uint256 governingPower) {
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

    /// @notice unused for VestingAllocation
    /// @dev onlyController -- must be called from the metavest controller
    /// @param _shortStopTime - the new short stop time
    function updateStopTimes(uint48 _shortStopTime) external override onlyController {
        if(terminated) revert MetaVesT_AlreadyTerminated();
        revert MetaVesT_ConditionNotSatisfied();
    }

    /// @notice terminates the VestingAllocation and transfers any remaining tokens to the authority
    /// @dev onlyController -- must be called from the metavest controller
    function terminate() external override onlyController nonReentrant {
        if(terminated) revert MetaVesT_AlreadyTerminated();
        uint256 tokensToRecover = 0;
        uint256 milestonesAllocation = 0;
        for (uint256 i; i < milestones.length; ++i) {
                milestonesAllocation += milestones[i].milestoneAward;
        }
        tokensToRecover = allocation.tokenStreamTotal + milestonesAllocation - getVestedTokenAmount();
        terminationTime = block.timestamp;
        safeTransfer(allocation.tokenContract, getAuthority(), tokensToRecover);
        terminated = true;
        emit MetaVesT_Terminated(grantee, tokensToRecover);
    }

    /// @notice returns the amount of tokens that are vested
    /// @return _tokensVested - the amount of tokens that are vested in decimals of the vesting token
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

    /// @notice returns the amount of tokens that are unlocked
    /// @return _tokensUnlocked - the amount of tokens that are unlocked in decimals of the vesting token
    function getUnlockedTokenAmount() public view returns (uint256) {
        if(block.timestamp<allocation.unlockStartTime)
            return 0;
        uint256 _timeElapsedSinceUnlock = block.timestamp - allocation.unlockStartTime;
        uint256 _tokensUnlocked = (_timeElapsedSinceUnlock * allocation.unlockRate) + allocation.unlockingCliffCredit;

        if(_tokensUnlocked>allocation.tokenStreamTotal) 
            _tokensUnlocked = allocation.tokenStreamTotal;

        return _tokensUnlocked += milestoneUnlockedTotal;
    }

    /// @notice returns the amount of tokens that are withdrawable
    /// @return _tokensWithdrawable - the amount of tokens that are withdrawable in decimals of the vesting token
    function getAmountWithdrawable() public view override returns (uint256) {
        uint256 _tokensVested = getVestedTokenAmount();
        uint256 _tokensUnlocked = getUnlockedTokenAmount();
        return _min(_tokensVested, _tokensUnlocked) - tokensWithdrawn;
    }

}
