// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.20;

import "./VestingAllocation.sol";
import "./interfaces/IAllocationFactory.sol";

/**
 * @title      Vesting Allocation Factory
 *
 * @author     MetaLeX Labs, Inc.
 *
 * @notice     Factory Contract for deploying Vesting Allocation MetaVesTs
 **/
contract VestingAllocationFactory is IAllocationFactory {
    /// @notice creates a Vesting Allocation
    /// @param _allocationType AllocationType struct, which should be == AllocationType.Vesting
    /// @param _grantee address of the grantee receiving the Vesting Allocation
    /// @param _controller contract address of the applicable MetaVesT Controller
    /// @param _allocation VestingAllocation.Allocation struct details
    /// @param _milestones array of VestingAllocation.Milestone[] structs for this allocation
    /// @param _paymentToken ignored param for this allocation type
    /// @param _exercisePrice ignored param for this allocation type
    /// @param _shortStopDuration ignored param for this allocation type
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
            return
                address(
                    new VestingAllocation(
                        _grantee,
                        _controller,
                        _allocation,
                        _milestones
                    )
                );
        } else {
            revert("AllocationFactory: invalid allocation type");
        }
    }
}
