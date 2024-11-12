// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.24;

import "./VestingAllocation.sol";
import "./interfaces/IAllocationFactory.sol";

contract VestingAllocationFactory is IAllocationFactory {

    function createAllocation(
        AllocationType _allocationType,
        address _grantee,
        address _controller,
        VestingAllocation.Allocation memory _allocation,
        VestingAllocation.Milestone[] memory _milestones,
        address _paymentToken,
        uint256 _exercisePrice,
        uint256 _shortStopDuration
    ) external returns (address) {
        if (_allocationType == AllocationType.Vesting) {
            return address(new VestingAllocation(_grantee, _controller, _allocation, _milestones));
        } else {
            revert("AllocationFactory: invalid allocation type");
        }
    }
}
