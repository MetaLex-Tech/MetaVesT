// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.20;

import "./RestrictedTokenAllocation.sol";
import "./interfaces/IAllocationFactory.sol";

/**
 * @title      Restricted Token Factory
 *
 * @author     MetaLeX Labs, Inc.
 *
 * @notice     Factory Contract for deploying Restricted Token Allocation MetaVesTs
 **/
contract RestrictedTokenFactory is IAllocationFactory {
    /// @notice creates a Restricted Token Allocation
    /// @param _allocationType AllocationType struct, which should be == AllocationType.RestrictedToken
    /// @param _grantee address of the grantee receiving the Restricted Token Allocation
    /// @param _controller contract address of the applicable MetaVesT Controller
    /// @param _allocation RestrictedTokenAward.Allocation struct details
    /// @param _milestones array of RestrictedTokenAward.Milestone[] structs for this allocation
    /// @param _paymentToken contract address of the payment token for repurchases
    /// @param _exercisePrice price at which the restricted tokens can be repurchased in vesting token decimals but only up to payment decimal precision
    /// @param _shortStopDuration duration after termination during which restricted tokens can be repurchased
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
            return
                address(
                    new RestrictedTokenAward(
                        _grantee,
                        _controller,
                        _paymentToken,
                        _exercisePrice,
                        _shortStopDuration,
                        _allocation,
                        _milestones
                    )
                );
        } else {
            revert("AllocationFactory: invalid allocation type");
        }
    }
}
