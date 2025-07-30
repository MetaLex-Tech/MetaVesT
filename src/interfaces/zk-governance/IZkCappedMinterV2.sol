// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

interface IZkCappedMinterV2 {
      function MINTER_ROLE() external returns (bytes32);

      function grantRole(bytes32 role, address account) external;

      function mint(address _to, uint256 _amount) external;
}
