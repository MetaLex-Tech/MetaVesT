// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.20;

interface IPriceAllocation {
    function getVestingType() external view returns (uint256);
    function updatePrice(uint256 _newPrice) external;
}