
// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.20;

import "./IBaseAllocation.sol";

interface IRestrictedTokenAward is IBaseAllocation {
    function getAmountRepurchasable() external view returns (uint256);
    function repurchaseTokens(uint256 _amount) external;
    function getRepurchasePrice() external view returns (uint256);
    function getShortStopDate() external view returns (uint256);
}
