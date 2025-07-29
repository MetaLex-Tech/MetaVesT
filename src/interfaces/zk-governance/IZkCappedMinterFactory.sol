// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

interface IZkCappedMinterFactory {
      function createCappedMinter(address _token, address _admin, uint256 _cap, uint256 _saltNonce) external returns (address minterAddress);
}
