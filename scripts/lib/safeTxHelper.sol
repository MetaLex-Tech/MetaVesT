// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.28;

import {CommonBase} from "forge-std/Base.sol";
import {ISafeProxyFactory, IGnosisSafe} from "../../test/lib/safe.sol";

contract SafeTxHelper is CommonBase {
    function _signAndExecSafeTransaction(uint256 privateKey, address safe, address to, uint256 value, bytes memory data) internal {
        uint8 operation = 0; // Call
        uint256 safeTxGas = 0;
        uint256 baseGas = 0;
        uint256 gasPrice = 0;
        address gasToken = address(0);
        address refundReceiver = address(0);
        uint256 nonce = IGnosisSafe(safe).nonce();

        IGnosisSafe(safe).execTransaction(
            to,
            value,
            data,
            operation,
            safeTxGas,
            baseGas,
            gasPrice,
            gasToken,
            refundReceiver,
            _getSafeTxSignature(
                privateKey,
                safe,
                to,
                value,
                data,
                operation,
                safeTxGas,
                baseGas,
                gasPrice,
                gasToken,
                refundReceiver,
                nonce
            )
        );
    }

    function _getSafeTxSignature(
        uint256 privateKey,
        address safe,
        address to,
        uint256 value,
        bytes memory data,
        uint8 operation,
        uint256 safeTxGas,
        uint256 baseGas,
        uint256 gasPrice,
        address gasToken,
        address refundReceiver,
        uint256 nonce
    ) internal view returns (bytes memory) {
        bytes memory txHashData = IGnosisSafe(safe).encodeTransactionData(
            to,
            value,
            data,
            operation,
            safeTxGas,
            baseGas,
            gasPrice,
            gasToken,
            refundReceiver,
            nonce
        );

        (uint8 v, bytes32 r, bytes32 s) = vm.sign(privateKey, keccak256(txHashData));
        bytes memory signature = abi.encodePacked(r, s, v);
        return signature;
    }
}
