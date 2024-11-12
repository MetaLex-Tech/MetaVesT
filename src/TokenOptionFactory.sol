// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.24;

import "./TokenOptionAllocation.sol";
import "./interfaces/IAllocationFactory.sol";

contract TokenOptionFactory is IAllocationFactory {

    function createAllocation(
        AllocationType _allocationType,
        address _grantee,
        address _controller,
        TokenOptionAllocation.Allocation memory _allocation,
        TokenOptionAllocation.Milestone[] memory _milestones,
        address _paymentToken,
        uint256 _exercisePrice,
        uint256 _shortStopDuration
    ) external returns (address) {
         if (_allocationType == AllocationType.TokenOption) {
            return address(new TokenOptionAllocation(_grantee, _controller, _paymentToken, _exercisePrice, _shortStopDuration, _allocation, _milestones));
        } else {
            revert("AllocationFactory: invalid allocation type");
        }
    }
}
