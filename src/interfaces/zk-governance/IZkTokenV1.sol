// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IERC20} from "forge-std/interfaces/IERC20.sol";

interface IZkTokenV1 is IERC20 {
    function MINTER_ROLE() external returns (bytes32);

    function grantRole(bytes32 role, address account) external;
}
