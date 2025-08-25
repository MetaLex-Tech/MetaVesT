// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

interface IZkCappedMinterV2 {
      error ZkCappedMinterV2__CapExceeded(address minter, uint256 amount);

      function MINTABLE() external returns (address);

      function DEFAULT_ADMIN_ROLE() external returns (bytes32);
      function MINTER_ROLE() external returns (bytes32);
      function PAUSER_ROLE() external returns (bytes32);
      function START_TIME() external returns (uint48);

      function grantRole(bytes32 role, address account) external;
      function hasRole(bytes32 role, address account) external view returns (bool);

      function mint(address _to, uint256 _amount) external;

      function pause() external;
      function unpause() external;
      function paused() external view returns (bool);

      function close() external;
      function closed() external view returns (bool);
}
