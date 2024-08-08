// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.20;

interface IBaseAllocation {
    function getVestingType() external view returns (uint256);
    function getGoverningPower() external view returns (uint256);
    function updateAuthority(address _newAuthority) external;
    function updateTransferability(bool _transferable) external;
    function updateVestingRate(uint160 _newVestingRate) external;
    function updateUnlockRate(uint160 _newUnlockRate) external;
    function updateStopTimes(uint48 _newVestingStopTime, uint48 _newUnlockStopTime, uint48 _shortStopTime) external;
    function confirmMilestone(uint256 _milestoneIndex) external;
    function removeMilestone(uint256 _milestoneIndex) external;
    function addMilestone(IBaseAllocation.Milestone calldata _milestone) external;
    function terminate() external;
    function transferRights(address _newOwner) external;
    function withdraw(uint256 _amount) external;
    function getMetavestDetails() external view returns (IBaseAllocation.Allocation memory);
    function getAmountWithdrawable() external view returns (uint256);
    function updatePrice(uint256 _newPrice) external;
    struct Milestone {
        uint256 milestoneAward;
        bool unlockOnCompletion;
        bool complete;
        address[] conditionContracts;
    }
    struct Allocation {
        uint256 tokenStreamTotal;
        uint128 vestingCliffCredit;
        uint128 unlockingCliffCredit;
        uint160 vestingRate;
        uint48 vestingStartTime;
        uint160 unlockRate;
        uint48 unlockStartTime;
        address tokenContract;
    }

}