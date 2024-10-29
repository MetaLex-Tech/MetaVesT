// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.20;

import "./TokenOptionAllocation.sol";
import "./interfaces/IAllocationFactory.sol";

/**
 * @title      Token Option Factory
 *
 * @author     MetaLeX Labs, Inc.
 *
 * @notice     Factory Contract for deploying Token Option Allocation MetaVesTs
 **/
contract TokenOptionFactory is IAllocationFactory {
    /// @notice creates a Token Option Allocation
    /// @param _allocationType AllocationType struct, which should be == AllocationType.TokenOption
    /// @param _grantee address of the grantee receiving the Token Option Allocation
    /// @param _controller contract address of the applicable MetaVesT Controller
    /// @param _allocation TokenOptionAllocation.Allocation struct details
    /// @param _milestones array of TokenOptionAllocation.Milestone[] structs for this allocation
    /// @param _paymentToken contract address of the payment token for repurchases
    /// @param _exercisePrice price of the token option exercise in vesting token decimals but only up to payment decimal precision
    /// @param _shortStopDuration duration of the short stop
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
