// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.20;

import "./RestrictedTokenAllocation.sol";
import "./interfaces/IAllocationFactory.sol";

contract RestrictedTokenFactory is IAllocationFactory {

    function createAllocation(
        AllocationType _allocationType,
        address _grantee,
        address _controller,
        RestrictedTokenAward.Allocation memory _allocation,
        RestrictedTokenAward.Milestone[] memory _milestones,
        address _paymentToken,
        uint256 _exercisePrice,
        uint256 _shortStopDuration
    ) external returns (address) {
       if (_allocationType == AllocationType.RestrictedToken) {
            return address(new RestrictedTokenAward(_grantee, _controller, _paymentToken, _exercisePrice, _shortStopDuration, _allocation, _milestones));
        } else {
            revert("AllocationFactory: invalid allocation type");
        }
    }
}
