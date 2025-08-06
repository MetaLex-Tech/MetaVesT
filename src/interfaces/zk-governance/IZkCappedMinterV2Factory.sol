// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

interface IZkCappedMinterV2Factory {
      function createCappedMinter(
            address _mintable,
            address _admin,
            uint256 _cap,
            uint48 _startTime,
            uint48 _expirationTime,
            uint256 _saltNonce
      ) external returns (address minterAddress);
}
