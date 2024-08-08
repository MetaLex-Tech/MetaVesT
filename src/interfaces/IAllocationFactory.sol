// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.20;

import "../VestingAllocation.sol";

interface IAllocationFactory {

    enum AllocationType {
        Vesting,
        RestrictedToken,
        TokenOption
    }

    function createAllocation(
        AllocationType _allocationType,
        address _grantee,
        address _controller,
        VestingAllocation.Allocation memory _allocation,
        VestingAllocation.Milestone[] memory _milestones,
        address _paymentToken,
        uint256 _exercisePrice,
        uint256 _shortStopDuration,
        uint256 _longStopDate
    ) external returns (address);
}