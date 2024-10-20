// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "../src/metavestController.sol";
import "../src/VestingAllocation.sol";
import "../src/TokenOptionAllocation.sol";
import "../src/RestrictedTokenAllocation.sol";
import "../src/interfaces/IAllocationFactory.sol";
import "../src/VestingAllocationFactory.sol";
import "../src/TokenOptionFactory.sol";
import "../src/RestrictedTokenFactory.sol";
import "./mocks/MockCondition.sol";

abstract contract ERC20 {


    /// @dev The total supply has overflowed.
    error TotalSupplyOverflow();

    /// @dev The allowance has overflowed.
    error AllowanceOverflow();

    /// @dev The allowance has underflowed.
    error AllowanceUnderflow();

    /// @dev Insufficient balance.
    error InsufficientBalance();

    /// @dev Insufficient allowance.
    error InsufficientAllowance();

    /// @dev The permit is invalid.
    error InvalidPermit();

    /// @dev The permit has expired.
    error PermitExpired();


    /// @dev Emitted when `amount` tokens is transferred from `from` to `to`.
    event Transfer(address indexed from, address indexed to, uint256 amount);

    /// @dev Emitted when `amount` tokens is approved by `owner` to be used by `spender`.
    event Approval(address indexed owner, address indexed spender, uint256 amount);

    /// @dev `keccak256(bytes("Transfer(address,address,uint256)"))`.
    uint256 private constant _TRANSFER_EVENT_SIGNATURE =
        0xddf252ad1be2c89b69c2b068fc378daa952ba7f163c4a11628f55a4df523b3ef;

    /// @dev `keccak256(bytes("Approval(address,address,uint256)"))`.
    uint256 private constant _APPROVAL_EVENT_SIGNATURE =
        0x8c5be1e5ebec7d5bd14f71427d1e84f3dd0314c0f7b2291e5b200ac8c7c3b925;


    /// @dev The storage slot for the total supply.
    uint256 private constant _TOTAL_SUPPLY_SLOT = 0x05345cdf77eb68f44c;

    /// @dev The balance slot of `owner` is given by:
    /// ```
    ///     mstore(0x0c, _BALANCE_SLOT_SEED)
    ///     mstore(0x00, owner)
    ///     let balanceSlot := keccak256(0x0c, 0x20)
    /// ```
    uint256 private constant _BALANCE_SLOT_SEED = 0x87a211a2;

    /// @dev The allowance slot of (`owner`, `spender`) is given by:
    /// ```
    ///     mstore(0x20, spender)
    ///     mstore(0x0c, _ALLOWANCE_SLOT_SEED)
    ///     mstore(0x00, owner)
    ///     let allowanceSlot := keccak256(0x0c, 0x34)
    /// ```
    uint256 private constant _ALLOWANCE_SLOT_SEED = 0x7f5e9f20;

    /// @dev The nonce slot of `owner` is given by:
    /// ```
    ///     mstore(0x0c, _NONCES_SLOT_SEED)
    ///     mstore(0x00, owner)
    ///     let nonceSlot := keccak256(0x0c, 0x20)
    /// ```
    uint256 private constant _NONCES_SLOT_SEED = 0x38377508;


    /// @dev Returns the name of the token.
    function name() public view virtual returns (string memory);

    /// @dev Returns the symbol of the token.
    function symbol() public view virtual returns (string memory);

    /// @dev Returns the decimals places of the token.
    function decimals() public view virtual returns (uint8) {
        return 18;
    }


    /// @dev Returns the amount of tokens in existence.
    function totalSupply() public view virtual returns (uint256 result) {
        /// @solidity memory-safe-assembly
        assembly {
            result := sload(_TOTAL_SUPPLY_SLOT)
        }
    }

    /// @dev Returns the amount of tokens owned by `owner`.
    function balanceOf(address owner) public view virtual returns (uint256 result) {
        /// @solidity memory-safe-assembly
        assembly {
            mstore(0x0c, _BALANCE_SLOT_SEED)
            mstore(0x00, owner)
            result := sload(keccak256(0x0c, 0x20))
        }
    }

    /// @dev Returns the amount of tokens that `spender` can spend on behalf of `owner`.
    function allowance(address owner, address spender)
        public
        view
        virtual
        returns (uint256 result)
    {
        /// @solidity memory-safe-assembly
        assembly {
            mstore(0x20, spender)
            mstore(0x0c, _ALLOWANCE_SLOT_SEED)
            mstore(0x00, owner)
            result := sload(keccak256(0x0c, 0x34))
        }
    }

    /// @dev Sets `amount` as the allowance of `spender` over the caller's tokens.
    ///
    /// Emits a {Approval} event.
    function approve(address spender, uint256 amount) public virtual returns (bool) {
        /// @solidity memory-safe-assembly
        assembly {
            // Compute the allowance slot and store the amount.
            mstore(0x20, spender)
            mstore(0x0c, _ALLOWANCE_SLOT_SEED)
            mstore(0x00, caller())
            sstore(keccak256(0x0c, 0x34), amount)
            // Emit the {Approval} event.
            mstore(0x00, amount)
            log3(0x00, 0x20, _APPROVAL_EVENT_SIGNATURE, caller(), shr(96, mload(0x2c)))
        }
        return true;
    }

    /// @dev Atomically increases the allowance granted to `spender` by the caller.
    ///
    /// Emits a {Approval} event.
    function increaseAllowance(address spender, uint256 difference) public virtual returns (bool) {
        /// @solidity memory-safe-assembly
        assembly {
            // Compute the allowance slot and load its value.
            mstore(0x20, spender)
            mstore(0x0c, _ALLOWANCE_SLOT_SEED)
            mstore(0x00, caller())
            let allowanceSlot := keccak256(0x0c, 0x34)
            let allowanceBefore := sload(allowanceSlot)
            // Add to the allowance.
            let allowanceAfter := add(allowanceBefore, difference)
            // Revert upon overflow.
            if lt(allowanceAfter, allowanceBefore) {
                mstore(0x00, 0xf9067066) // `AllowanceOverflow()`.
                revert(0x1c, 0x04)
            }
            // Store the updated allowance.
            sstore(allowanceSlot, allowanceAfter)
            // Emit the {Approval} event.
            mstore(0x00, allowanceAfter)
            log3(0x00, 0x20, _APPROVAL_EVENT_SIGNATURE, caller(), shr(96, mload(0x2c)))
        }
        return true;
    }

    /// @dev Atomically decreases the allowance granted to `spender` by the caller.
    ///
    /// Emits a {Approval} event.
    function decreaseAllowance(address spender, uint256 difference) public virtual returns (bool) {
        /// @solidity memory-safe-assembly
        assembly {
            // Compute the allowance slot and load its value.
            mstore(0x20, spender)
            mstore(0x0c, _ALLOWANCE_SLOT_SEED)
            mstore(0x00, caller())
            let allowanceSlot := keccak256(0x0c, 0x34)
            let allowanceBefore := sload(allowanceSlot)
            // Revert if will underflow.
            if lt(allowanceBefore, difference) {
                mstore(0x00, 0x8301ab38) // `AllowanceUnderflow()`.
                revert(0x1c, 0x04)
            }
            // Subtract and store the updated allowance.
            let allowanceAfter := sub(allowanceBefore, difference)
            sstore(allowanceSlot, allowanceAfter)
            // Emit the {Approval} event.
            mstore(0x00, allowanceAfter)
            log3(0x00, 0x20, _APPROVAL_EVENT_SIGNATURE, caller(), shr(96, mload(0x2c)))
        }
        return true;
    }

    /// @dev Transfer `amount` tokens from the caller to `to`.
    ///
    /// Requirements:
    /// - `from` must at least have `amount`.
    ///
    /// Emits a {Transfer} event.
    function transfer(address to, uint256 amount) public virtual returns (bool) {
        _beforeTokenTransfer(msg.sender, to, amount);
        /// @solidity memory-safe-assembly
        assembly {
            // Compute the balance slot and load its value.
            mstore(0x0c, _BALANCE_SLOT_SEED)
            mstore(0x00, caller())
            let fromBalanceSlot := keccak256(0x0c, 0x20)
            let fromBalance := sload(fromBalanceSlot)
            // Revert if insufficient balance.
            if gt(amount, fromBalance) {
                mstore(0x00, 0xf4d678b8) // `InsufficientBalance()`.
                revert(0x1c, 0x04)
            }
            // Subtract and store the updated balance.
            sstore(fromBalanceSlot, sub(fromBalance, amount))
            // Compute the balance slot of `to`.
            mstore(0x00, to)
            let toBalanceSlot := keccak256(0x0c, 0x20)
            // Add and store the updated balance of `to`.
            // Will not overflow because the sum of all user balances
            // cannot exceed the maximum uint256 value.
            sstore(toBalanceSlot, add(sload(toBalanceSlot), amount))
            // Emit the {Transfer} event.
            mstore(0x20, amount)
            log3(0x20, 0x20, _TRANSFER_EVENT_SIGNATURE, caller(), shr(96, mload(0x0c)))
        }
        _afterTokenTransfer(msg.sender, to, amount);
        return true;
    }

    /// @dev Transfers `amount` tokens from `from` to `to`.
    ///
    /// Note: Does not update the allowance if it is the maximum uint256 value.
    ///
    /// Requirements:
    /// - `from` must at least have `amount`.
    /// - The caller must have at least `amount` of allowance to transfer the tokens of `from`.
    ///
    /// Emits a {Transfer} event.
    function transferFrom(address from, address to, uint256 amount) public virtual returns (bool) {
        _beforeTokenTransfer(from, to, amount);
        /// @solidity memory-safe-assembly
        assembly {
            let from_ := shl(96, from)
            // Compute the allowance slot and load its value.
            mstore(0x20, caller())
            mstore(0x0c, or(from_, _ALLOWANCE_SLOT_SEED))
            let allowanceSlot := keccak256(0x0c, 0x34)
            let allowance_ := sload(allowanceSlot)
            // If the allowance is not the maximum uint256 value.
            if iszero(eq(allowance_, not(0))) {
                // Revert if the amount to be transferred exceeds the allowance.
                if gt(amount, allowance_) {
                    mstore(0x00, 0x13be252b) // `InsufficientAllowance()`.
                    revert(0x1c, 0x04)
                }
                // Subtract and store the updated allowance.
                sstore(allowanceSlot, sub(allowance_, amount))
            }
            // Compute the balance slot and load its value.
            mstore(0x0c, or(from_, _BALANCE_SLOT_SEED))
            let fromBalanceSlot := keccak256(0x0c, 0x20)
            let fromBalance := sload(fromBalanceSlot)
            // Revert if insufficient balance.
            if gt(amount, fromBalance) {
                mstore(0x00, 0xf4d678b8) // `InsufficientBalance()`.
                revert(0x1c, 0x04)
            }
            // Subtract and store the updated balance.
            sstore(fromBalanceSlot, sub(fromBalance, amount))
            // Compute the balance slot of `to`.
            mstore(0x00, to)
            let toBalanceSlot := keccak256(0x0c, 0x20)
            // Add and store the updated balance of `to`.
            // Will not overflow because the sum of all user balances
            // cannot exceed the maximum uint256 value.
            sstore(toBalanceSlot, add(sload(toBalanceSlot), amount))
            // Emit the {Transfer} event.
            mstore(0x20, amount)
            log3(0x20, 0x20, _TRANSFER_EVENT_SIGNATURE, shr(96, from_), shr(96, mload(0x0c)))
        }
        _afterTokenTransfer(from, to, amount);
        return true;
    }


    /// @dev Returns the current nonce for `owner`.
    /// This value is used to compute the signature for EIP-2612 permit.
    function nonces(address owner) public view virtual returns (uint256 result) {
        /// @solidity memory-safe-assembly
        assembly {
            // Compute the nonce slot and load its value.
            mstore(0x0c, _NONCES_SLOT_SEED)
            mstore(0x00, owner)
            result := sload(keccak256(0x0c, 0x20))
        }
    }

    /// @dev Sets `value` as the allowance of `spender` over the tokens of `owner`,
    /// authorized by a signed approval by `owner`.
    ///
    /// Emits a {Approval} event.
    function permit(
        address owner,
        address spender,
        uint256 value,
        uint256 deadline,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) public virtual {
        bytes32 domainSeparator = DOMAIN_SEPARATOR();
        /// @solidity memory-safe-assembly
        assembly {
            // Grab the free memory pointer.
            let m := mload(0x40)
            // Revert if the block timestamp greater than `deadline`.
            if gt(timestamp(), deadline) {
                mstore(0x00, 0x1a15a3cc) // `PermitExpired()`.
                revert(0x1c, 0x04)
            }
            // Clean the upper 96 bits.
            owner := shr(96, shl(96, owner))
            spender := shr(96, shl(96, spender))
            // Compute the nonce slot and load its value.
            mstore(0x0c, _NONCES_SLOT_SEED)
            mstore(0x00, owner)
            let nonceSlot := keccak256(0x0c, 0x20)
            let nonceValue := sload(nonceSlot)
            // Increment and store the updated nonce.
            sstore(nonceSlot, add(nonceValue, 1))
            // Prepare the inner hash.
            // `keccak256("Permit(address owner,address spender,uint256 value,uint256 nonce,uint256 deadline)")`.
            // forgefmt: disable-next-item
            mstore(m, 0x6e71edae12b1b97f4d1f60370fef10105fa2faae0126114a169c64845d6126c9)
            mstore(add(m, 0x20), owner)
            mstore(add(m, 0x40), spender)
            mstore(add(m, 0x60), value)
            mstore(add(m, 0x80), nonceValue)
            mstore(add(m, 0xa0), deadline)
            // Prepare the outer hash.
            mstore(0, 0x1901)
            mstore(0x20, domainSeparator)
            mstore(0x40, keccak256(m, 0xc0))
            // Prepare the ecrecover calldata.
            mstore(0, keccak256(0x1e, 0x42))
            mstore(0x20, and(0xff, v))
            mstore(0x40, r)
            mstore(0x60, s)
            pop(staticcall(gas(), 1, 0, 0x80, 0x20, 0x20))
            // If the ecrecover fails, the returndatasize will be 0x00,
            // `owner` will be be checked if it equals the hash at 0x00,
            // which evaluates to false (i.e. 0), and we will revert.
            // If the ecrecover succeeds, the returndatasize will be 0x20,
            // `owner` will be compared against the returned address at 0x20.
            if iszero(eq(mload(returndatasize()), owner)) {
                mstore(0x00, 0xddafbaef) // `InvalidPermit()`.
                revert(0x1c, 0x04)
            }
            // Compute the allowance slot and store the value.
            // The `owner` is already at slot 0x20.
            mstore(0x40, or(shl(160, _ALLOWANCE_SLOT_SEED), spender))
            sstore(keccak256(0x2c, 0x34), value)
            // Emit the {Approval} event.
            log3(add(m, 0x60), 0x20, _APPROVAL_EVENT_SIGNATURE, owner, spender)
            mstore(0x40, m) // Restore the free memory pointer.
            mstore(0x60, 0) // Restore the zero pointer.
        }
    }

    /// @dev Returns the EIP-2612 domains separator.
    function DOMAIN_SEPARATOR() public view virtual returns (bytes32 result) {
        /// @solidity memory-safe-assembly
        assembly {
            result := mload(0x40) // Grab the free memory pointer.
        }
        //  We simply calculate it on-the-fly to allow for cases where the `name` may change.
        bytes32 nameHash = keccak256(bytes(name()));
        /// @solidity memory-safe-assembly
        assembly {
            let m := result
            // `keccak256("EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)")`.
            // forgefmt: disable-next-item
            mstore(m, 0x8b73c3c69bb8fe3d512ecc4cf759cc79239f7b179b0ffacaa9a75d522b39400f)
            mstore(add(m, 0x20), nameHash)
            // `keccak256("1")`.
            // forgefmt: disable-next-item
            mstore(add(m, 0x40), 0xc89efdaa54c0f20c7adf612882df0950f5a951637e0307cdcb4c672f298b8bc6)
            mstore(add(m, 0x60), chainid())
            mstore(add(m, 0x80), address())
            result := keccak256(m, 0xa0)
        }
    }


    /// @dev Mints `amount` tokens to `to`, increasing the total supply.
    ///
    /// Emits a {Transfer} event.
    function _mint(address to, uint256 amount) internal virtual {
        _beforeTokenTransfer(address(0), to, amount);
        /// @solidity memory-safe-assembly
        assembly {
            let totalSupplyBefore := sload(_TOTAL_SUPPLY_SLOT)
            let totalSupplyAfter := add(totalSupplyBefore, amount)
            // Revert if the total supply overflows.
            if lt(totalSupplyAfter, totalSupplyBefore) {
                mstore(0x00, 0xe5cfe957) // `TotalSupplyOverflow()`.
                revert(0x1c, 0x04)
            }
            // Store the updated total supply.
            sstore(_TOTAL_SUPPLY_SLOT, totalSupplyAfter)
            // Compute the balance slot and load its value.
            mstore(0x0c, _BALANCE_SLOT_SEED)
            mstore(0x00, to)
            let toBalanceSlot := keccak256(0x0c, 0x20)
            // Add and store the updated balance.
            sstore(toBalanceSlot, add(sload(toBalanceSlot), amount))
            // Emit the {Transfer} event.
            mstore(0x20, amount)
            log3(0x20, 0x20, _TRANSFER_EVENT_SIGNATURE, 0, shr(96, mload(0x0c)))
        }
        _afterTokenTransfer(address(0), to, amount);
    }

    /// @dev Burns `amount` tokens from `from`, reducing the total supply.
    ///
    /// Emits a {Transfer} event.
    function _burn(address from, uint256 amount) internal virtual {
        _beforeTokenTransfer(from, address(0), amount);
        /// @solidity memory-safe-assembly
        assembly {
            // Compute the balance slot and load its value.
            mstore(0x0c, _BALANCE_SLOT_SEED)
            mstore(0x00, from)
            let fromBalanceSlot := keccak256(0x0c, 0x20)
            let fromBalance := sload(fromBalanceSlot)
            // Revert if insufficient balance.
            if gt(amount, fromBalance) {
                mstore(0x00, 0xf4d678b8) // `InsufficientBalance()`.
                revert(0x1c, 0x04)
            }
            // Subtract and store the updated balance.
            sstore(fromBalanceSlot, sub(fromBalance, amount))
            // Subtract and store the updated total supply.
            sstore(_TOTAL_SUPPLY_SLOT, sub(sload(_TOTAL_SUPPLY_SLOT), amount))
            // Emit the {Transfer} event.
            mstore(0x00, amount)
            log3(0x00, 0x20, _TRANSFER_EVENT_SIGNATURE, shr(96, shl(96, from)), 0)
        }
        _afterTokenTransfer(from, address(0), amount);
    }

    /// @dev Moves `amount` of tokens from `from` to `to`.
    function _transfer(address from, address to, uint256 amount) internal virtual {
        _beforeTokenTransfer(from, to, amount);
        /// @solidity memory-safe-assembly
        assembly {
            let from_ := shl(96, from)
            // Compute the balance slot and load its value.
            mstore(0x0c, or(from_, _BALANCE_SLOT_SEED))
            let fromBalanceSlot := keccak256(0x0c, 0x20)
            let fromBalance := sload(fromBalanceSlot)
            // Revert if insufficient balance.
            if gt(amount, fromBalance) {
                mstore(0x00, 0xf4d678b8) // `InsufficientBalance()`.
                revert(0x1c, 0x04)
            }
            // Subtract and store the updated balance.
            sstore(fromBalanceSlot, sub(fromBalance, amount))
            // Compute the balance slot of `to`.
            mstore(0x00, to)
            let toBalanceSlot := keccak256(0x0c, 0x20)
            // Add and store the updated balance of `to`.
            // Will not overflow because the sum of all user balances
            // cannot exceed the maximum uint256 value.
            sstore(toBalanceSlot, add(sload(toBalanceSlot), amount))
            // Emit the {Transfer} event.
            mstore(0x20, amount)
            log3(0x20, 0x20, _TRANSFER_EVENT_SIGNATURE, shr(96, from_), shr(96, mload(0x0c)))
        }
        _afterTokenTransfer(from, to, amount);
    }


    /// @dev Updates the allowance of `owner` for `spender` based on spent `amount`.
    function _spendAllowance(address owner, address spender, uint256 amount) internal virtual {
        /// @solidity memory-safe-assembly
        assembly {
            // Compute the allowance slot and load its value.
            mstore(0x20, spender)
            mstore(0x0c, _ALLOWANCE_SLOT_SEED)
            mstore(0x00, owner)
            let allowanceSlot := keccak256(0x0c, 0x34)
            let allowance_ := sload(allowanceSlot)
            // If the allowance is not the maximum uint256 value.
            if iszero(eq(allowance_, not(0))) {
                // Revert if the amount to be transferred exceeds the allowance.
                if gt(amount, allowance_) {
                    mstore(0x00, 0x13be252b) // `InsufficientAllowance()`.
                    revert(0x1c, 0x04)
                }
                // Subtract and store the updated allowance.
                sstore(allowanceSlot, sub(allowance_, amount))
            }
        }
    }

    /// @dev Sets `amount` as the allowance of `spender` over the tokens of `owner`.
    ///
    /// Emits a {Approval} event.
    function _approve(address owner, address spender, uint256 amount) internal virtual {
        /// @solidity memory-safe-assembly
        assembly {
            let owner_ := shl(96, owner)
            // Compute the allowance slot and store the amount.
            mstore(0x20, spender)
            mstore(0x0c, or(owner_, _ALLOWANCE_SLOT_SEED))
            sstore(keccak256(0x0c, 0x34), amount)
            // Emit the {Approval} event.
            mstore(0x00, amount)
            log3(0x00, 0x20, _APPROVAL_EVENT_SIGNATURE, shr(96, owner_), shr(96, mload(0x2c)))
        }
    }


    /// @dev Hook that is called before any transfer of tokens.
    /// This includes minting and burning.
    function _beforeTokenTransfer(address from, address to, uint256 amount) internal virtual {}

    /// @dev Hook that is called after any transfer of tokens.
    /// This includes minting and burning.
    function _afterTokenTransfer(address from, address to, uint256 amount) internal virtual {}
}

abstract contract ERC20Stable {

    /// @dev The total supply has overflowed.
    error TotalSupplyOverflow();

    /// @dev The allowance has overflowed.
    error AllowanceOverflow();

    /// @dev The allowance has underflowed.
    error AllowanceUnderflow();

    /// @dev Insufficient balance.
    error InsufficientBalance();

    /// @dev Insufficient allowance.
    error InsufficientAllowance();

    /// @dev The permit is invalid.
    error InvalidPermit();

    /// @dev The permit has expired.
    error PermitExpired();


    /// @dev Emitted when `amount` tokens is transferred from `from` to `to`.
    event Transfer(address indexed from, address indexed to, uint256 amount);

    /// @dev Emitted when `amount` tokens is approved by `owner` to be used by `spender`.
    event Approval(address indexed owner, address indexed spender, uint256 amount);

    /// @dev `keccak256(bytes("Transfer(address,address,uint256)"))`.
    uint256 private constant _TRANSFER_EVENT_SIGNATURE =
        0xddf252ad1be2c89b69c2b068fc378daa952ba7f163c4a11628f55a4df523b3ef;

    /// @dev `keccak256(bytes("Approval(address,address,uint256)"))`.
    uint256 private constant _APPROVAL_EVENT_SIGNATURE =
        0x8c5be1e5ebec7d5bd14f71427d1e84f3dd0314c0f7b2291e5b200ac8c7c3b925;

    /// @dev The storage slot for the total supply.
    uint256 private constant _TOTAL_SUPPLY_SLOT = 0x05345cdf77eb68f44c;

    /// @dev The balance slot of `owner` is given by:
    /// ```
    ///     mstore(0x0c, _BALANCE_SLOT_SEED)
    ///     mstore(0x00, owner)
    ///     let balanceSlot := keccak256(0x0c, 0x20)
    /// ```
    uint256 private constant _BALANCE_SLOT_SEED = 0x87a211a2;

    /// @dev The allowance slot of (`owner`, `spender`) is given by:
    /// ```
    ///     mstore(0x20, spender)
    ///     mstore(0x0c, _ALLOWANCE_SLOT_SEED)
    ///     mstore(0x00, owner)
    ///     let allowanceSlot := keccak256(0x0c, 0x34)
    /// ```
    uint256 private constant _ALLOWANCE_SLOT_SEED = 0x7f5e9f20;

    /// @dev The nonce slot of `owner` is given by:
    /// ```
    ///     mstore(0x0c, _NONCES_SLOT_SEED)
    ///     mstore(0x00, owner)
    ///     let nonceSlot := keccak256(0x0c, 0x20)
    /// ```
    uint256 private constant _NONCES_SLOT_SEED = 0x38377508;

    /// @dev Returns the name of the token.
    function name() public view virtual returns (string memory);

    /// @dev Returns the symbol of the token.
    function symbol() public view virtual returns (string memory);

    /// @dev Returns the decimals places of the token.
    function decimals() public view virtual returns (uint8) {
        return 6;
    }

    /// @dev Returns the amount of tokens in existence.
    function totalSupply() public view virtual returns (uint256 result) {
        /// @solidity memory-safe-assembly
        assembly {
            result := sload(_TOTAL_SUPPLY_SLOT)
        }
    }

    /// @dev Returns the amount of tokens owned by `owner`.
    function balanceOf(address owner) public view virtual returns (uint256 result) {
        /// @solidity memory-safe-assembly
        assembly {
            mstore(0x0c, _BALANCE_SLOT_SEED)
            mstore(0x00, owner)
            result := sload(keccak256(0x0c, 0x20))
        }
    }

    /// @dev Returns the amount of tokens that `spender` can spend on behalf of `owner`.
    function allowance(address owner, address spender)
        public
        view
        virtual
        returns (uint256 result)
    {
        /// @solidity memory-safe-assembly
        assembly {
            mstore(0x20, spender)
            mstore(0x0c, _ALLOWANCE_SLOT_SEED)
            mstore(0x00, owner)
            result := sload(keccak256(0x0c, 0x34))
        }
    }

    /// @dev Sets `amount` as the allowance of `spender` over the caller's tokens.
    ///
    /// Emits a {Approval} event.
    function approve(address spender, uint256 amount) public virtual returns (bool) {
        /// @solidity memory-safe-assembly
        assembly {
            // Compute the allowance slot and store the amount.
            mstore(0x20, spender)
            mstore(0x0c, _ALLOWANCE_SLOT_SEED)
            mstore(0x00, caller())
            sstore(keccak256(0x0c, 0x34), amount)
            // Emit the {Approval} event.
            mstore(0x00, amount)
            log3(0x00, 0x20, _APPROVAL_EVENT_SIGNATURE, caller(), shr(96, mload(0x2c)))
        }
        return true;
    }

    /// @dev Atomically increases the allowance granted to `spender` by the caller.
    ///
    /// Emits a {Approval} event.
    function increaseAllowance(address spender, uint256 difference) public virtual returns (bool) {
        /// @solidity memory-safe-assembly
        assembly {
            // Compute the allowance slot and load its value.
            mstore(0x20, spender)
            mstore(0x0c, _ALLOWANCE_SLOT_SEED)
            mstore(0x00, caller())
            let allowanceSlot := keccak256(0x0c, 0x34)
            let allowanceBefore := sload(allowanceSlot)
            // Add to the allowance.
            let allowanceAfter := add(allowanceBefore, difference)
            // Revert upon overflow.
            if lt(allowanceAfter, allowanceBefore) {
                mstore(0x00, 0xf9067066) // `AllowanceOverflow()`.
                revert(0x1c, 0x04)
            }
            // Store the updated allowance.
            sstore(allowanceSlot, allowanceAfter)
            // Emit the {Approval} event.
            mstore(0x00, allowanceAfter)
            log3(0x00, 0x20, _APPROVAL_EVENT_SIGNATURE, caller(), shr(96, mload(0x2c)))
        }
        return true;
    }

    /// @dev Atomically decreases the allowance granted to `spender` by the caller.
    ///
    /// Emits a {Approval} event.
    function decreaseAllowance(address spender, uint256 difference) public virtual returns (bool) {
        /// @solidity memory-safe-assembly
        assembly {
            // Compute the allowance slot and load its value.
            mstore(0x20, spender)
            mstore(0x0c, _ALLOWANCE_SLOT_SEED)
            mstore(0x00, caller())
            let allowanceSlot := keccak256(0x0c, 0x34)
            let allowanceBefore := sload(allowanceSlot)
            // Revert if will underflow.
            if lt(allowanceBefore, difference) {
                mstore(0x00, 0x8301ab38) // `AllowanceUnderflow()`.
                revert(0x1c, 0x04)
            }
            // Subtract and store the updated allowance.
            let allowanceAfter := sub(allowanceBefore, difference)
            sstore(allowanceSlot, allowanceAfter)
            // Emit the {Approval} event.
            mstore(0x00, allowanceAfter)
            log3(0x00, 0x20, _APPROVAL_EVENT_SIGNATURE, caller(), shr(96, mload(0x2c)))
        }
        return true;
    }

    /// @dev Transfer `amount` tokens from the caller to `to`.
    ///
    /// Requirements:
    /// - `from` must at least have `amount`.
    ///
    /// Emits a {Transfer} event.
    function transfer(address to, uint256 amount) public virtual returns (bool) {
        _beforeTokenTransfer(msg.sender, to, amount);
        /// @solidity memory-safe-assembly
        assembly {
            // Compute the balance slot and load its value.
            mstore(0x0c, _BALANCE_SLOT_SEED)
            mstore(0x00, caller())
            let fromBalanceSlot := keccak256(0x0c, 0x20)
            let fromBalance := sload(fromBalanceSlot)
            // Revert if insufficient balance.
            if gt(amount, fromBalance) {
                mstore(0x00, 0xf4d678b8) // `InsufficientBalance()`.
                revert(0x1c, 0x04)
            }
            // Subtract and store the updated balance.
            sstore(fromBalanceSlot, sub(fromBalance, amount))
            // Compute the balance slot of `to`.
            mstore(0x00, to)
            let toBalanceSlot := keccak256(0x0c, 0x20)
            // Add and store the updated balance of `to`.
            // Will not overflow because the sum of all user balances
            // cannot exceed the maximum uint256 value.
            sstore(toBalanceSlot, add(sload(toBalanceSlot), amount))
            // Emit the {Transfer} event.
            mstore(0x20, amount)
            log3(0x20, 0x20, _TRANSFER_EVENT_SIGNATURE, caller(), shr(96, mload(0x0c)))
        }
        _afterTokenTransfer(msg.sender, to, amount);
        return true;
    }

    /// @dev Transfers `amount` tokens from `from` to `to`.
    ///
    /// Note: Does not update the allowance if it is the maximum uint256 value.
    ///
    /// Requirements:
    /// - `from` must at least have `amount`.
    /// - The caller must have at least `amount` of allowance to transfer the tokens of `from`.
    ///
    /// Emits a {Transfer} event.
    function transferFrom(address from, address to, uint256 amount) public virtual returns (bool) {
        _beforeTokenTransfer(from, to, amount);
        /// @solidity memory-safe-assembly
        assembly {
            let from_ := shl(96, from)
            // Compute the allowance slot and load its value.
            mstore(0x20, caller())
            mstore(0x0c, or(from_, _ALLOWANCE_SLOT_SEED))
            let allowanceSlot := keccak256(0x0c, 0x34)
            let allowance_ := sload(allowanceSlot)
            // If the allowance is not the maximum uint256 value.
            if iszero(eq(allowance_, not(0))) {
                // Revert if the amount to be transferred exceeds the allowance.
                if gt(amount, allowance_) {
                    mstore(0x00, 0x13be252b) // `InsufficientAllowance()`.
                    revert(0x1c, 0x04)
                }
                // Subtract and store the updated allowance.
                sstore(allowanceSlot, sub(allowance_, amount))
            }
            // Compute the balance slot and load its value.
            mstore(0x0c, or(from_, _BALANCE_SLOT_SEED))
            let fromBalanceSlot := keccak256(0x0c, 0x20)
            let fromBalance := sload(fromBalanceSlot)
            // Revert if insufficient balance.
            if gt(amount, fromBalance) {
                mstore(0x00, 0xf4d678b8) // `InsufficientBalance()`.
                revert(0x1c, 0x04)
            }
            // Subtract and store the updated balance.
            sstore(fromBalanceSlot, sub(fromBalance, amount))
            // Compute the balance slot of `to`.
            mstore(0x00, to)
            let toBalanceSlot := keccak256(0x0c, 0x20)
            // Add and store the updated balance of `to`.
            // Will not overflow because the sum of all user balances
            // cannot exceed the maximum uint256 value.
            sstore(toBalanceSlot, add(sload(toBalanceSlot), amount))
            // Emit the {Transfer} event.
            mstore(0x20, amount)
            log3(0x20, 0x20, _TRANSFER_EVENT_SIGNATURE, shr(96, from_), shr(96, mload(0x0c)))
        }
        _afterTokenTransfer(from, to, amount);
        return true;
    }


    /// @dev Returns the current nonce for `owner`.
    /// This value is used to compute the signature for EIP-2612 permit.
    function nonces(address owner) public view virtual returns (uint256 result) {
        /// @solidity memory-safe-assembly
        assembly {
            // Compute the nonce slot and load its value.
            mstore(0x0c, _NONCES_SLOT_SEED)
            mstore(0x00, owner)
            result := sload(keccak256(0x0c, 0x20))
        }
    }

    /// @dev Sets `value` as the allowance of `spender` over the tokens of `owner`,
    /// authorized by a signed approval by `owner`.
    ///
    /// Emits a {Approval} event.
    function permit(
        address owner,
        address spender,
        uint256 value,
        uint256 deadline,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) public virtual {
        bytes32 domainSeparator = DOMAIN_SEPARATOR();
        /// @solidity memory-safe-assembly
        assembly {
            // Grab the free memory pointer.
            let m := mload(0x40)
            // Revert if the block timestamp greater than `deadline`.
            if gt(timestamp(), deadline) {
                mstore(0x00, 0x1a15a3cc) // `PermitExpired()`.
                revert(0x1c, 0x04)
            }
            // Clean the upper 96 bits.
            owner := shr(96, shl(96, owner))
            spender := shr(96, shl(96, spender))
            // Compute the nonce slot and load its value.
            mstore(0x0c, _NONCES_SLOT_SEED)
            mstore(0x00, owner)
            let nonceSlot := keccak256(0x0c, 0x20)
            let nonceValue := sload(nonceSlot)
            // Increment and store the updated nonce.
            sstore(nonceSlot, add(nonceValue, 1))
            // Prepare the inner hash.
            // `keccak256("Permit(address owner,address spender,uint256 value,uint256 nonce,uint256 deadline)")`.
            // forgefmt: disable-next-item
            mstore(m, 0x6e71edae12b1b97f4d1f60370fef10105fa2faae0126114a169c64845d6126c9)
            mstore(add(m, 0x20), owner)
            mstore(add(m, 0x40), spender)
            mstore(add(m, 0x60), value)
            mstore(add(m, 0x80), nonceValue)
            mstore(add(m, 0xa0), deadline)
            // Prepare the outer hash.
            mstore(0, 0x1901)
            mstore(0x20, domainSeparator)
            mstore(0x40, keccak256(m, 0xc0))
            // Prepare the ecrecover calldata.
            mstore(0, keccak256(0x1e, 0x42))
            mstore(0x20, and(0xff, v))
            mstore(0x40, r)
            mstore(0x60, s)
            pop(staticcall(gas(), 1, 0, 0x80, 0x20, 0x20))
            // If the ecrecover fails, the returndatasize will be 0x00,
            // `owner` will be be checked if it equals the hash at 0x00,
            // which evaluates to false (i.e. 0), and we will revert.
            // If the ecrecover succeeds, the returndatasize will be 0x20,
            // `owner` will be compared against the returned address at 0x20.
            if iszero(eq(mload(returndatasize()), owner)) {
                mstore(0x00, 0xddafbaef) // `InvalidPermit()`.
                revert(0x1c, 0x04)
            }
            // Compute the allowance slot and store the value.
            // The `owner` is already at slot 0x20.
            mstore(0x40, or(shl(160, _ALLOWANCE_SLOT_SEED), spender))
            sstore(keccak256(0x2c, 0x34), value)
            // Emit the {Approval} event.
            log3(add(m, 0x60), 0x20, _APPROVAL_EVENT_SIGNATURE, owner, spender)
            mstore(0x40, m) // Restore the free memory pointer.
            mstore(0x60, 0) // Restore the zero pointer.
        }
    }

    /// @dev Returns the EIP-2612 domains separator.
    function DOMAIN_SEPARATOR() public view virtual returns (bytes32 result) {
        /// @solidity memory-safe-assembly
        assembly {
            result := mload(0x40) // Grab the free memory pointer.
        }
        //  We simply calculate it on-the-fly to allow for cases where the `name` may change.
        bytes32 nameHash = keccak256(bytes(name()));
        /// @solidity memory-safe-assembly
        assembly {
            let m := result
            // `keccak256("EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)")`.
            // forgefmt: disable-next-item
            mstore(m, 0x8b73c3c69bb8fe3d512ecc4cf759cc79239f7b179b0ffacaa9a75d522b39400f)
            mstore(add(m, 0x20), nameHash)
            // `keccak256("1")`.
            // forgefmt: disable-next-item
            mstore(add(m, 0x40), 0xc89efdaa54c0f20c7adf612882df0950f5a951637e0307cdcb4c672f298b8bc6)
            mstore(add(m, 0x60), chainid())
            mstore(add(m, 0x80), address())
            result := keccak256(m, 0xa0)
        }
    }

    /// @dev Mints `amount` tokens to `to`, increasing the total supply.
    ///
    /// Emits a {Transfer} event.
    function _mint(address to, uint256 amount) internal virtual {
        _beforeTokenTransfer(address(0), to, amount);
        /// @solidity memory-safe-assembly
        assembly {
            let totalSupplyBefore := sload(_TOTAL_SUPPLY_SLOT)
            let totalSupplyAfter := add(totalSupplyBefore, amount)
            // Revert if the total supply overflows.
            if lt(totalSupplyAfter, totalSupplyBefore) {
                mstore(0x00, 0xe5cfe957) // `TotalSupplyOverflow()`.
                revert(0x1c, 0x04)
            }
            // Store the updated total supply.
            sstore(_TOTAL_SUPPLY_SLOT, totalSupplyAfter)
            // Compute the balance slot and load its value.
            mstore(0x0c, _BALANCE_SLOT_SEED)
            mstore(0x00, to)
            let toBalanceSlot := keccak256(0x0c, 0x20)
            // Add and store the updated balance.
            sstore(toBalanceSlot, add(sload(toBalanceSlot), amount))
            // Emit the {Transfer} event.
            mstore(0x20, amount)
            log3(0x20, 0x20, _TRANSFER_EVENT_SIGNATURE, 0, shr(96, mload(0x0c)))
        }
        _afterTokenTransfer(address(0), to, amount);
    }

    /// @dev Burns `amount` tokens from `from`, reducing the total supply.
    ///
    /// Emits a {Transfer} event.
    function _burn(address from, uint256 amount) internal virtual {
        _beforeTokenTransfer(from, address(0), amount);
        /// @solidity memory-safe-assembly
        assembly {
            // Compute the balance slot and load its value.
            mstore(0x0c, _BALANCE_SLOT_SEED)
            mstore(0x00, from)
            let fromBalanceSlot := keccak256(0x0c, 0x20)
            let fromBalance := sload(fromBalanceSlot)
            // Revert if insufficient balance.
            if gt(amount, fromBalance) {
                mstore(0x00, 0xf4d678b8) // `InsufficientBalance()`.
                revert(0x1c, 0x04)
            }
            // Subtract and store the updated balance.
            sstore(fromBalanceSlot, sub(fromBalance, amount))
            // Subtract and store the updated total supply.
            sstore(_TOTAL_SUPPLY_SLOT, sub(sload(_TOTAL_SUPPLY_SLOT), amount))
            // Emit the {Transfer} event.
            mstore(0x00, amount)
            log3(0x00, 0x20, _TRANSFER_EVENT_SIGNATURE, shr(96, shl(96, from)), 0)
        }
        _afterTokenTransfer(from, address(0), amount);
    }


    /// @dev Moves `amount` of tokens from `from` to `to`.
    function _transfer(address from, address to, uint256 amount) internal virtual {
        _beforeTokenTransfer(from, to, amount);
        /// @solidity memory-safe-assembly
        assembly {
            let from_ := shl(96, from)
            // Compute the balance slot and load its value.
            mstore(0x0c, or(from_, _BALANCE_SLOT_SEED))
            let fromBalanceSlot := keccak256(0x0c, 0x20)
            let fromBalance := sload(fromBalanceSlot)
            // Revert if insufficient balance.
            if gt(amount, fromBalance) {
                mstore(0x00, 0xf4d678b8) // `InsufficientBalance()`.
                revert(0x1c, 0x04)
            }
            // Subtract and store the updated balance.
            sstore(fromBalanceSlot, sub(fromBalance, amount))
            // Compute the balance slot of `to`.
            mstore(0x00, to)
            let toBalanceSlot := keccak256(0x0c, 0x20)
            // Add and store the updated balance of `to`.
            // Will not overflow because the sum of all user balances
            // cannot exceed the maximum uint256 value.
            sstore(toBalanceSlot, add(sload(toBalanceSlot), amount))
            // Emit the {Transfer} event.
            mstore(0x20, amount)
            log3(0x20, 0x20, _TRANSFER_EVENT_SIGNATURE, shr(96, from_), shr(96, mload(0x0c)))
        }
        _afterTokenTransfer(from, to, amount);
    }


    /// @dev Updates the allowance of `owner` for `spender` based on spent `amount`.
    function _spendAllowance(address owner, address spender, uint256 amount) internal virtual {
        /// @solidity memory-safe-assembly
        assembly {
            // Compute the allowance slot and load its value.
            mstore(0x20, spender)
            mstore(0x0c, _ALLOWANCE_SLOT_SEED)
            mstore(0x00, owner)
            let allowanceSlot := keccak256(0x0c, 0x34)
            let allowance_ := sload(allowanceSlot)
            // If the allowance is not the maximum uint256 value.
            if iszero(eq(allowance_, not(0))) {
                // Revert if the amount to be transferred exceeds the allowance.
                if gt(amount, allowance_) {
                    mstore(0x00, 0x13be252b) // `InsufficientAllowance()`.
                    revert(0x1c, 0x04)
                }
                // Subtract and store the updated allowance.
                sstore(allowanceSlot, sub(allowance_, amount))
            }
        }
    }

    /// @dev Sets `amount` as the allowance of `spender` over the tokens of `owner`.
    ///
    /// Emits a {Approval} event.
    function _approve(address owner, address spender, uint256 amount) internal virtual {
        /// @solidity memory-safe-assembly
        assembly {
            let owner_ := shl(96, owner)
            // Compute the allowance slot and store the amount.
            mstore(0x20, spender)
            mstore(0x0c, or(owner_, _ALLOWANCE_SLOT_SEED))
            sstore(keccak256(0x0c, 0x34), amount)
            // Emit the {Approval} event.
            mstore(0x00, amount)
            log3(0x00, 0x20, _APPROVAL_EVENT_SIGNATURE, shr(96, owner_), shr(96, mload(0x2c)))
        }
    }

    /// @dev Hook that is called before any transfer of tokens.
    /// This includes minting and burning.
    function _beforeTokenTransfer(address from, address to, uint256 amount) internal virtual {}

    /// @dev Hook that is called after any transfer of tokens.
    /// This includes minting and burning.
    function _afterTokenTransfer(address from, address to, uint256 amount) internal virtual {}
}

contract MockERC20 is ERC20 {
    constructor(string memory name, string memory symbol) ERC20() {}
    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }
    function name() public view override returns (string memory) {
        return "Test Token";
    }
    function symbol() public view override returns (string memory) {
        return "TT";
    }
}

contract MockERC20Stable is ERC20Stable {
    constructor(string memory name, string memory symbol) ERC20Stable() {}
    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }
    function name() public view override returns (string memory) {
        return "Test Token";
    }
    function symbol() public view override returns (string memory) {
        return "TT";
    }
}

contract MetaVestControllerTest is Test {
    metavestController public controller;
    MockERC20 public token;
    MockERC20Stable public paymentToken;

    address public authority;
    address public dao;
    address public grantee;
    address public transferee;

    function setUp() public {
        authority = address(this);
        dao = address(0x2);
        grantee = address(0x3);
        transferee = address(0x4);
        
        token = new MockERC20("Test Token", "TT");
        paymentToken = new MockERC20Stable("Payment Token", "PT");

        VestingAllocationFactory factory = new VestingAllocationFactory();
        TokenOptionFactory tokenFactory = new TokenOptionFactory();
        RestrictedTokenFactory restrictedTokenFactory = new RestrictedTokenFactory();
        
        controller = new metavestController(
            authority,
            dao,
            address(factory),
            address(tokenFactory),
            address(restrictedTokenFactory)
        );

        token.mint(authority, 1000000e58);
        paymentToken.mint(authority, 1000000e58);
        paymentToken.transfer(grantee, 1e25);

        vm.prank(authority);
        controller.createSet("testSet");
    }

    function testCreateVestingAllocation() public {
        BaseAllocation.Allocation memory allocation = BaseAllocation.Allocation({
            tokenContract: address(token),
            tokenStreamTotal: 1000e18,
            vestingCliffCredit: 100e18,
            unlockingCliffCredit: 100e18,
            vestingRate: 10e18,
            vestingStartTime: uint48(block.timestamp),
            unlockRate: 10e18,
            unlockStartTime: uint48(block.timestamp)
        });

        BaseAllocation.Milestone[] memory milestones = new BaseAllocation.Milestone[](1);
        milestones[0] = BaseAllocation.Milestone({
            milestoneAward: 100e18,
            unlockOnCompletion: true,
            complete: false,
            conditionContracts: new address[](0)
        });

        token.approve(address(controller), 1100e18);

        address vestingAllocation = controller.createMetavest(
            metavestController.metavestType.Vesting,
            grantee,
            allocation,
            milestones,
            0,
            address(0),
            0,
            0
            
        );

        assertEq(token.balanceOf(vestingAllocation), 1100e18);
        assertEq(controller.vestingAllocations(grantee, 0), vestingAllocation);
    }

    function testCreateTokenOptionAllocation() public {
        BaseAllocation.Allocation memory allocation = BaseAllocation.Allocation({
            tokenContract: address(token),
            tokenStreamTotal: 1000e18,
            vestingCliffCredit: 100e18,
            unlockingCliffCredit: 100e18,
            vestingRate: 10e18,
            vestingStartTime: uint48(block.timestamp),
            unlockRate: 10e18,
            unlockStartTime: uint48(block.timestamp)
        });

        BaseAllocation.Milestone[] memory milestones = new BaseAllocation.Milestone[](1);
        milestones[0] = BaseAllocation.Milestone({
            milestoneAward: 100e18,
            unlockOnCompletion: true,
            complete: false,
            conditionContracts: new address[](0)
        });

        token.approve(address(controller), 1100e18);

        address tokenOptionAllocation = controller.createMetavest(
            metavestController.metavestType.TokenOption,
            grantee,
            allocation,
            milestones,
            1e18,
            address(paymentToken),
            365 days,
            0
        );

        assertEq(token.balanceOf(tokenOptionAllocation), 1100e18);
        assertEq(controller.tokenOptionAllocations(grantee, 0), tokenOptionAllocation);
    }

    function testCreateRestrictedTokenAward() public {
        BaseAllocation.Allocation memory allocation = BaseAllocation.Allocation({
            tokenContract: address(token),
            tokenStreamTotal: 1000e18,
            vestingCliffCredit: 100e18,
            unlockingCliffCredit: 100e18,
            vestingRate: 10e18,
            vestingStartTime: uint48(block.timestamp),
            unlockRate: 10e18,
            unlockStartTime: uint48(block.timestamp)
        });

        BaseAllocation.Milestone[] memory milestones = new BaseAllocation.Milestone[](1);
        milestones[0] = BaseAllocation.Milestone({
            milestoneAward: 100e18,
            unlockOnCompletion: true,
            complete: false,
            conditionContracts: new address[](0)
        });

        token.approve(address(controller), 1100e18);

        address restrictedTokenAward = controller.createMetavest(
            metavestController.metavestType.RestrictedTokenAward,
            grantee,
            allocation,
            milestones,
            1e18,
            address(paymentToken),
            365 days,
            0
            
        );

        assertEq(token.balanceOf(restrictedTokenAward), 1100e18);
        assertEq(controller.restrictedTokenAllocations(grantee, 0), restrictedTokenAward);
    }

    function testUpdateTransferability() public {
        uint256 startTimestamp = block.timestamp;
        address vestingAllocation = createDummyVestingAllocation();
        address[] memory addresses = new address[](1);
        addresses[0] = vestingAllocation;
        //compute msg.data for updateMetavestTransferability(vestingAllocation, true)
        bytes4 selector = controller.updateMetavestTransferability.selector;
        bytes memory msgData = abi.encodeWithSelector(selector, vestingAllocation, true);
        controller.proposeMetavestAmendment(vestingAllocation, controller.updateMetavestTransferability.selector, msgData);
        vm.prank(grantee);
        controller.consentToMetavestAmendment(vestingAllocation, controller.updateMetavestTransferability.selector, true);
        
        controller.updateMetavestTransferability(vestingAllocation, true);
        vm.prank(grantee);
        RestrictedTokenAward(vestingAllocation).transferRights(transferee);
         uint256 newTimestamp = startTimestamp + 100; // 101
        vm.warp(newTimestamp);
        skip(10);
        vm.prank(transferee);
        uint256 balance = RestrictedTokenAward(vestingAllocation).getAmountWithdrawable();
 

    //warp ahead 100 blocks
       
        vm.prank(transferee);
        RestrictedTokenAward(vestingAllocation).withdraw(balance);
        
       // assertTrue(BaseAllocation(vestingAllocation).transferable());
    }

    function testGetGovPower() public {
       address vestingAllocation = createDummyVestingAllocation();
       BaseAllocation(vestingAllocation).getGoverningPower();
    }

     function testProposeMajorityMetavestAmendment() public {
        address mockAllocation2 = createDummyVestingAllocation();
        bytes4 msgSig = bytes4(keccak256("updateMetavestTransferability(address,bool)"));
        bytes memory callData = abi.encodeWithSelector(msgSig, mockAllocation2, true);

        vm.prank(authority);
        controller.addMetaVestToSet("testSet", mockAllocation2);
        vm.warp(block.timestamp + 1 days);
        vm.prank(authority);
        controller.proposeMajorityMetavestAmendment("testSet", msgSig, callData);

        vm.prank(grantee);
        controller.voteOnMetavestAmendment(mockAllocation2, "testSet", msgSig, true);

        vm.prank(authority);
        controller.updateMetavestTransferability(mockAllocation2, true);
    }

    
     function testFailReProposeMajorityMetavestAmendment() public {
        address mockAllocation2 = createDummyVestingAllocation();
        bytes4 msgSig = bytes4(keccak256("updateMetavestTransferability(address,bool)"));
        bytes memory callData = abi.encodeWithSelector(msgSig, mockAllocation2, true);

        vm.prank(authority);
        controller.addMetaVestToSet("testSet", mockAllocation2);
        vm.warp(block.timestamp + 1 days);
        vm.prank(authority);
        controller.proposeMajorityMetavestAmendment("testSet", msgSig, callData);
        vm.warp(block.timestamp + 30 days);
        /*
        vm.prank(grantee);
        controller.voteOnMetavestAmendment(mockAllocation2, "testSet", msgSig, true);

        vm.prank(authority);
        controller.updateMetavestTransferability(mockAllocation2, true);*/
        controller.proposeMajorityMetavestAmendment("testSet", msgSig, callData);
        
    }

    function testReProposeMajorityMetavestAmendment() public {
        address mockAllocation2 = createDummyVestingAllocation();
        bytes4 msgSig = bytes4(keccak256("updateMetavestTransferability(address,bool)"));
        bytes memory callData = abi.encodeWithSelector(msgSig, mockAllocation2, true);

        vm.prank(authority);
        controller.addMetaVestToSet("testSet", mockAllocation2);
        vm.warp(block.timestamp + 1 days);
        vm.prank(authority);
        controller.proposeMajorityMetavestAmendment("testSet", msgSig, callData);
        vm.warp(block.timestamp + 30 days);

        vm.prank(authority);
        controller.cancelExpiredMajorityMetavestAmendment("testSet", msgSig);

        vm.prank(authority);
        controller.proposeMajorityMetavestAmendment("testSet", msgSig, callData);
        
    }

    function testFailRemoveNonExistantMetaVestFromSet() public {
        address mockAllocation2 = createDummyVestingAllocation();
        vm.startPrank(authority);
      //  controller.createSet("testSet");
        controller.removeMetaVestFromSet("testSet", mockAllocation2);
    }


    function testUpdateExercisePrice() public {
        address tokenOptionAllocation = createDummyTokenOptionAllocation();

        //compute msg.data for updateExerciseOrRepurchasePrice(tokenOptionAllocation, 2e18)
        bytes4 selector = controller.updateExerciseOrRepurchasePrice.selector;
        bytes memory msgData = abi.encodeWithSelector(selector, tokenOptionAllocation, 2e18);
       
        controller.proposeMetavestAmendment(tokenOptionAllocation, controller.updateExerciseOrRepurchasePrice.selector, msgData);
        
        vm.prank(grantee);
        controller.consentToMetavestAmendment(tokenOptionAllocation, controller.updateExerciseOrRepurchasePrice.selector, true);

        controller.updateExerciseOrRepurchasePrice(tokenOptionAllocation, 2e18);

        assertEq(TokenOptionAllocation(tokenOptionAllocation).exercisePrice(), 2e18);
    }

    function testRemoveMilestone() public {
        address vestingAllocation = createDummyVestingAllocation();
        //create array of addresses and include vestingAllocation address
        address[] memory addresses = new address[](1);
        addresses[0] = vestingAllocation;
        bytes4 selector = bytes4(keccak256("removeMetavestMilestone(address,uint256)"));
        bytes memory msgData = abi.encodeWithSelector(selector, vestingAllocation, 0);
        controller.proposeMetavestAmendment(vestingAllocation, controller.removeMetavestMilestone.selector, msgData);
        vm.prank(grantee);
        //consent to amendment for the removemetavestmilestone method sig function consentToMetavestAmendment(address _metavest, bytes4 _msgSig, bool _inFavor) external {
        controller.consentToMetavestAmendment(vestingAllocation, controller.removeMetavestMilestone.selector, true);
        controller.removeMetavestMilestone(vestingAllocation, 0);
        
        //BaseAllocation.Milestone memory milestone = BaseAllocation(vestingAllocation).milestones(0);
        //assertEq(milestone.milestoneAward, 0);
    }

    function testAddMilestone() public {
        address vestingAllocation = createDummyVestingAllocation();
        
        BaseAllocation.Milestone memory newMilestone = BaseAllocation.Milestone({
            milestoneAward: 50e18,
            unlockOnCompletion: true,
            complete: false,
            conditionContracts: new address[](0)
        });
        
        token.approve(address(controller), 50e18);
        controller.addMetavestMilestone(vestingAllocation, newMilestone);
        
       // BaseAllocation.Milestone memory addedMilestone = BaseAllocation(vestingAllocation).milestones[0];
      //  assertEq(addedMilestone.milestoneAward, 50e18);
    }

    function testUpdateUnlockRate() public {
        address vestingAllocation = createDummyVestingAllocation();
        address[] memory addresses = new address[](1);
        addresses[0] = vestingAllocation;
        bytes4 selector = controller.updateMetavestUnlockRate.selector;
        bytes memory msgData = abi.encodeWithSelector(selector, vestingAllocation, 20e18);
        controller.proposeMetavestAmendment(vestingAllocation, controller.updateMetavestUnlockRate.selector, msgData);
        vm.prank(grantee);
        controller.consentToMetavestAmendment(vestingAllocation, controller.updateMetavestUnlockRate.selector, true);
        
        controller.updateMetavestUnlockRate(vestingAllocation, 20e18);
        
        BaseAllocation.Allocation memory updatedAllocation = BaseAllocation(vestingAllocation).getMetavestDetails();
        assertEq(updatedAllocation.unlockRate, 20e18);
    }

    function testUpdateVestingRate() public {
        address vestingAllocation = createDummyVestingAllocation();
        address[] memory addresses = new address[](1);
        addresses[0] = vestingAllocation;
        bytes4 selector = controller.updateMetavestVestingRate.selector;
        bytes memory msgData = abi.encodeWithSelector(selector, vestingAllocation, 20e18);
        controller.proposeMetavestAmendment(vestingAllocation, controller.updateMetavestVestingRate.selector, msgData);
        vm.prank(grantee);
        controller.consentToMetavestAmendment(vestingAllocation, controller.updateMetavestVestingRate.selector, true);
        
        controller.updateMetavestVestingRate(vestingAllocation, 20e18);
        
        BaseAllocation.Allocation memory updatedAllocation = BaseAllocation(vestingAllocation).getMetavestDetails();
        assertEq(updatedAllocation.vestingRate, 20e18);
    }

    function testUpdateStopTimes() public {
        
        address vestingAllocation = createDummyRestrictedTokenAward();
         address[] memory addresses = new address[](1);
        addresses[0] = vestingAllocation;
        bytes4 selector = bytes4(keccak256("updateMetavestStopTimes(address,uint48)"));
        bytes memory msgData = abi.encodeWithSelector(selector, vestingAllocation, uint48(block.timestamp + 500 days));
        controller.proposeMetavestAmendment(vestingAllocation, controller.updateMetavestStopTimes.selector, msgData);
        vm.prank(grantee);
        controller.consentToMetavestAmendment(vestingAllocation, controller.updateMetavestStopTimes.selector, true);
        uint48 newShortStopTime = uint48(block.timestamp + 500 days);
        
        controller.updateMetavestStopTimes(vestingAllocation, newShortStopTime);
    }

    function testTerminateVesting() public {
        address vestingAllocation = createDummyVestingAllocation();
        
        controller.terminateMetavestVesting(vestingAllocation);
        
        assertTrue(BaseAllocation(vestingAllocation).terminated());
    }

    function testRepurchaseTokens() public {
        uint256 startingBalance = paymentToken.balanceOf(grantee);
        address restrictedTokenAward = createDummyRestrictedTokenAward();
        uint256 repurchaseAmount = 5e18;
        uint256 snapshot = token.balanceOf(authority);
        uint256 payment = RestrictedTokenAward(restrictedTokenAward).getPaymentAmount(repurchaseAmount);
        controller.terminateMetavestVesting(restrictedTokenAward);
        paymentToken.approve(address(restrictedTokenAward), payment);
        vm.warp(block.timestamp + 20 days);
        vm.prank(authority);
        RestrictedTokenAward(restrictedTokenAward).repurchaseTokens(repurchaseAmount);

        assertEq(token.balanceOf(authority), snapshot+repurchaseAmount);

        vm.prank(grantee);
        RestrictedTokenAward(restrictedTokenAward).claimRepurchasedTokens();
        assertEq(paymentToken.balanceOf(grantee), startingBalance + payment);
    }

    function testRepurchaseTokensFuture() public {
        uint256 startingBalance = paymentToken.balanceOf(grantee);
        address restrictedTokenAward = createDummyRestrictedTokenAwardFuture();

        uint256 snapshot = token.balanceOf(authority);

        controller.terminateMetavestVesting(restrictedTokenAward);
        uint256 repurchaseAmount = RestrictedTokenAward(restrictedTokenAward).getAmountRepurchasable();
        uint256 payment = RestrictedTokenAward(restrictedTokenAward).getPaymentAmount(repurchaseAmount);
        paymentToken.approve(address(restrictedTokenAward), payment);
        vm.warp(block.timestamp + 20 days);
        vm.prank(authority);
        RestrictedTokenAward(restrictedTokenAward).repurchaseTokens(repurchaseAmount);

        assertEq(token.balanceOf(authority), snapshot+repurchaseAmount);

        vm.prank(grantee);
        RestrictedTokenAward(restrictedTokenAward).claimRepurchasedTokens();
        console.log(token.balanceOf(restrictedTokenAward));
        assertEq(paymentToken.balanceOf(grantee), startingBalance + payment);
        
    }

    function testTerminateTokensFuture() public {
        uint256 startingBalance = paymentToken.balanceOf(grantee);
        address restrictedTokenAward = createDummyVestingAllocationLargeFuture();

        controller.terminateMetavestVesting(restrictedTokenAward);
       
        console.log(token.balanceOf(restrictedTokenAward));
    }

    function testUpdateAuthority() public {
        address newAuthority = address(0x4);
        
        controller.initiateAuthorityUpdate(newAuthority);
        
        vm.prank(newAuthority);
        controller.acceptAuthorityRole();
        
        assertEq(controller.authority(), newAuthority);
    }

    function testUpdateDao() public {
        address newDao = address(0x5);
        
        vm.prank(dao);
        controller.initiateDaoUpdate(newDao);
        
        vm.prank(newDao);
        controller.acceptDaoRole();
        
        assertEq(controller.dao(), newDao);
    }

    // Helper functions to create dummy allocations for testing
    function createDummyVestingAllocation() internal returns (address) {
        BaseAllocation.Allocation memory allocation = BaseAllocation.Allocation({
            tokenContract: address(token),
            tokenStreamTotal: 1000e18,
            vestingCliffCredit: 100e18,
            unlockingCliffCredit: 100e18,
            vestingRate: 10e18,
            vestingStartTime: uint48(block.timestamp),
            unlockRate: 10e18,
            unlockStartTime: uint48(block.timestamp)
        });

        BaseAllocation.Milestone[] memory milestones = new BaseAllocation.Milestone[](1);
        milestones[0] = BaseAllocation.Milestone({
            milestoneAward: 1000e18,
            unlockOnCompletion: true,
            complete: false,
            conditionContracts: new address[](0)
        });

        token.approve(address(controller), 2100e18);

        return controller.createMetavest(
            metavestController.metavestType.Vesting,
            grantee,
            allocation,
            milestones,
            0,
            address(0),
            0,
            0
            
        );
    }

        // Helper functions to create dummy allocations for testing
    function createDummyVestingAllocationNoUnlock() internal returns (address) {
        BaseAllocation.Allocation memory allocation = BaseAllocation.Allocation({
            tokenContract: address(token),
            tokenStreamTotal: 1000e18,
            vestingCliffCredit: 100e18,
            unlockingCliffCredit: 100e18,
            vestingRate: 10e18,
            vestingStartTime: uint48(block.timestamp),
            unlockRate: 10e18,
            unlockStartTime: uint48(block.timestamp)
        });

        BaseAllocation.Milestone[] memory milestones = new BaseAllocation.Milestone[](1);
        milestones[0] = BaseAllocation.Milestone({
            milestoneAward: 1000e18,
            unlockOnCompletion: false,
            complete: false,
            conditionContracts: new address[](0)
        });

        token.approve(address(controller), 2100e18);

        return controller.createMetavest(
            metavestController.metavestType.Vesting,
            grantee,
            allocation,
            milestones,
            0,
            address(0),
            0,
            0
            
        );
    }

        // Helper functions to create dummy allocations for testing
    function createDummyVestingAllocationSlowUnlock() internal returns (address) {
        BaseAllocation.Allocation memory allocation = BaseAllocation.Allocation({
            tokenContract: address(token),
            tokenStreamTotal: 1000e18,
            vestingCliffCredit: 100e18,
            unlockingCliffCredit: 100e18,
            vestingRate: 10e18,
            vestingStartTime: uint48(block.timestamp),
            unlockRate: 5e18,
            unlockStartTime: uint48(block.timestamp)
        });

        BaseAllocation.Milestone[] memory milestones = new BaseAllocation.Milestone[](1);
        milestones[0] = BaseAllocation.Milestone({
            milestoneAward: 1000e18,
            unlockOnCompletion: true,
            complete: false,
            conditionContracts: new address[](0)
        });

        token.approve(address(controller), 2100e18);

        return controller.createMetavest(
            metavestController.metavestType.Vesting,
            grantee,
            allocation,
            milestones,
            0,
            address(0),
            0,
            0
            
        );
    }

        // Helper functions to create dummy allocations for testing
    function createDummyVestingAllocationLarge() internal returns (address) {
        BaseAllocation.Allocation memory allocation = BaseAllocation.Allocation({
            tokenContract: address(token),
            tokenStreamTotal: 1000e18,
            vestingCliffCredit: 0,
            unlockingCliffCredit: 0,
            vestingRate: 10e18,
            vestingStartTime: uint48(block.timestamp),
            unlockRate: 10e18,
            unlockStartTime: uint48(block.timestamp)
        });

        BaseAllocation.Milestone[] memory milestones = new BaseAllocation.Milestone[](0);


        token.approve(address(controller), 2100e18);

        return controller.createMetavest(
            metavestController.metavestType.Vesting,
            grantee,
            allocation,
            milestones,
            0,
            address(0),
            0,
            0
            
        );
    }

            // Helper functions to create dummy allocations for testing
    function createDummyVestingAllocationLargeFuture() internal returns (address) {
        BaseAllocation.Allocation memory allocation = BaseAllocation.Allocation({
            tokenContract: address(token),
            tokenStreamTotal: 1000e18,
            vestingCliffCredit: 0,
            unlockingCliffCredit: 0,
            vestingRate: 10e18,
            vestingStartTime: uint48(block.timestamp+2000),
            unlockRate: 10e18,
            unlockStartTime: uint48(block.timestamp+2000)
        });

        BaseAllocation.Milestone[] memory milestones = new BaseAllocation.Milestone[](0);


        token.approve(address(controller), 2100e18);

        return controller.createMetavest(
            metavestController.metavestType.Vesting,
            grantee,
            allocation,
            milestones,
            0,
            address(0),
            0,
            0
            
        );
    }

    function createDummyTokenOptionAllocation() internal returns (address) {
        BaseAllocation.Allocation memory allocation = BaseAllocation.Allocation({
            tokenContract: address(token),
            tokenStreamTotal: 1000e18,
            vestingCliffCredit: 100e18,
            unlockingCliffCredit: 100e18,
            vestingRate: 10e18,
            vestingStartTime: uint48(block.timestamp),
            unlockRate: 10e18,
            unlockStartTime: uint48(block.timestamp)
        });

        BaseAllocation.Milestone[] memory milestones = new BaseAllocation.Milestone[](1);
        milestones[0] = BaseAllocation.Milestone({
            milestoneAward: 1000e18,
            unlockOnCompletion: true,
            complete: false,
            conditionContracts: new address[](0)
        });

        token.approve(address(controller), 2000e18);

        return controller.createMetavest(
            metavestController.metavestType.TokenOption,
            grantee,
            allocation,
            milestones,
            5e17,
            address(paymentToken),
            1 days,
            0
        );
    }


   function createDummyRestrictedTokenAward() internal returns (address) {
        BaseAllocation.Allocation memory allocation = BaseAllocation.Allocation({
            tokenContract: address(token),
            tokenStreamTotal: 1000e18,
            vestingCliffCredit: 100e18,
            unlockingCliffCredit: 100e18,
            vestingRate: 10e18,
            vestingStartTime: uint48(block.timestamp),
            unlockRate: 10e18,
            unlockStartTime: uint48(block.timestamp)
        });

        BaseAllocation.Milestone[] memory milestones = new BaseAllocation.Milestone[](1);
        milestones[0] = BaseAllocation.Milestone({
            milestoneAward: 1000e18,
            unlockOnCompletion: true,
            complete: false,
            conditionContracts: new address[](0)
        });

        token.approve(address(controller), 2100e18);

        return controller.createMetavest(
            metavestController.metavestType.RestrictedTokenAward,
            grantee,
            allocation,
            milestones,
            1e18,
            address(paymentToken),
            1 days,
            0
            
        );
    }

    function createDummyRestrictedTokenAwardFuture() internal returns (address) {
        BaseAllocation.Allocation memory allocation = BaseAllocation.Allocation({
            tokenContract: address(token),
            tokenStreamTotal: 1000e18,
            vestingCliffCredit: 100e18,
            unlockingCliffCredit: 100e18,
            vestingRate: 10e18,
            vestingStartTime: uint48(block.timestamp+1000),
            unlockRate: 10e18,
            unlockStartTime: uint48(block.timestamp+1000)
        });

        BaseAllocation.Milestone[] memory milestones = new BaseAllocation.Milestone[](1);
        milestones[0] = BaseAllocation.Milestone({
            milestoneAward: 1000e18,
            unlockOnCompletion: true,
            complete: false,
            conditionContracts: new address[](0)
        });

        token.approve(address(controller), 2100e18);

        return controller.createMetavest(
            metavestController.metavestType.RestrictedTokenAward,
            grantee,
            allocation,
            milestones,
            1e18,
            address(paymentToken),
            1 days,
            0
            
        );
    }


    function testGetMetaVestType() public {
        address vestingAllocation = createDummyVestingAllocation();
        address tokenOptionAllocation = createDummyTokenOptionAllocation();
        address restrictedTokenAward = createDummyRestrictedTokenAward();

        assertEq(controller.getMetaVestType(vestingAllocation), 1);
        assertEq(controller.getMetaVestType(tokenOptionAllocation), 2);
        assertEq(controller.getMetaVestType(restrictedTokenAward), 3);
    }

    function testWithdrawFromController() public {
        uint256 amount = 100e18;
        token.transfer(address(controller), amount);

        uint256 initialBalance = token.balanceOf(authority);
        controller.withdrawFromController(address(token));
        uint256 finalBalance = token.balanceOf(authority);

        assertEq(finalBalance - initialBalance, amount);
        assertEq(token.balanceOf(address(controller)), 0);
    }

    function testFailWithdrawFromControllerNonAuthority() public {
        vm.prank(address(0x1234));
        controller.withdrawFromController(address(token));
    }

    function testFailCreateMetavestWithZeroAddress() public {
        BaseAllocation.Allocation memory allocation = BaseAllocation.Allocation({
            tokenContract: address(0),
            tokenStreamTotal: 1000e18,
            vestingCliffCredit: 100e18,
            unlockingCliffCredit: 100e18,
            vestingRate: 10e18,
            vestingStartTime: uint48(block.timestamp),
            unlockRate: 10e18,
            unlockStartTime: uint48(block.timestamp)
        });

        BaseAllocation.Milestone[] memory milestones = new BaseAllocation.Milestone[](0);

        controller.createMetavest(
            metavestController.metavestType.Vesting,
            address(0),
            allocation,
            milestones,
            0,
            address(0),
            0,
            0
            
        );
    }

    function testFailCreateMetavestWithInsufficientApproval() public {
        BaseAllocation.Allocation memory allocation = BaseAllocation.Allocation({
            tokenContract: address(token),
            tokenStreamTotal: 1000e18,
            vestingCliffCredit: 100e18,
            unlockingCliffCredit: 100e18,
            vestingRate: 10e18,
            vestingStartTime: uint48(block.timestamp),
            unlockRate: 10e18,
            unlockStartTime: uint48(block.timestamp)
        });

        BaseAllocation.Milestone[] memory milestones = new BaseAllocation.Milestone[](0);

        // Not approving any tokens
        controller.createMetavest(
            metavestController.metavestType.Vesting,
            grantee,
            allocation,
            milestones,
            0,
            address(0),
            0,
            0
            
        );
    }

    function testTerminateVestAndRecovers() public {
        address vestingAllocation = createDummyVestingAllocation();
        uint256 snapshot = token.balanceOf(authority);
        VestingAllocation(vestingAllocation).confirmMilestone(0);
        vm.warp(block.timestamp + 50 seconds);
        controller.terminateMetavestVesting(vestingAllocation);
        vm.startPrank(grantee);
        VestingAllocation(vestingAllocation).withdraw(VestingAllocation(vestingAllocation).getAmountWithdrawable());
        vm.stopPrank();
        assertEq(token.balanceOf(vestingAllocation), 0);
    }

    function testTerminateVestAndRecoverSlowUnlock() public {
        address vestingAllocation = createDummyVestingAllocationSlowUnlock();
        uint256 snapshot = token.balanceOf(authority);
        VestingAllocation(vestingAllocation).confirmMilestone(0);
        vm.warp(block.timestamp + 25 seconds);
        controller.terminateMetavestVesting(vestingAllocation);
        vm.startPrank(grantee);
        VestingAllocation(vestingAllocation).withdraw(VestingAllocation(vestingAllocation).getAmountWithdrawable());
        vm.warp(block.timestamp + 25 seconds);
        VestingAllocation(vestingAllocation).withdraw(VestingAllocation(vestingAllocation).getAmountWithdrawable());
        vm.stopPrank();
        assertEq(token.balanceOf(vestingAllocation), 0);
    }

    function testTerminateRecoverAll() public {
        address vestingAllocation = createDummyVestingAllocationLarge();
        uint256 snapshot = token.balanceOf(authority);
         vm.warp(block.timestamp + 25 seconds);
        controller.terminateMetavestVesting(vestingAllocation);
        vm.startPrank(grantee);
        VestingAllocation(vestingAllocation).withdraw(VestingAllocation(vestingAllocation).getAmountWithdrawable());
        vm.stopPrank();
        assertEq(token.balanceOf(vestingAllocation), 0);
    }

        function testTerminateRecoverChunksBefore() public {
        address vestingAllocation = createDummyVestingAllocationLarge();
        uint256 snapshot = token.balanceOf(authority);
         vm.warp(block.timestamp + 25 seconds);
        vm.startPrank(grantee);
        VestingAllocation(vestingAllocation).withdraw(VestingAllocation(vestingAllocation).getAmountWithdrawable());
        vm.stopPrank();
         vm.warp(block.timestamp + 25 seconds);

        controller.terminateMetavestVesting(vestingAllocation);
        vm.startPrank(grantee);
        VestingAllocation(vestingAllocation).withdraw(VestingAllocation(vestingAllocation).getAmountWithdrawable());
        vm.stopPrank();
        assertEq(token.balanceOf(vestingAllocation), 0);
    }

    function testConfirmingMilestoneRestrictedTokenAllocation() public {
        address vestingAllocation = createDummyRestrictedTokenAward();
        uint256 snapshot = token.balanceOf(authority);
        RestrictedTokenAward(vestingAllocation).confirmMilestone(0);
        vm.warp(block.timestamp + 50 seconds);
        vm.startPrank(grantee);
        RestrictedTokenAward(vestingAllocation).withdraw(VestingAllocation(vestingAllocation).getAmountWithdrawable());
        vm.stopPrank();
    }

        function testConfirmingMilestoneTokenOption() public {
        address vestingAllocation = createDummyTokenOptionAllocation();
        uint256 snapshot = token.balanceOf(authority);
        TokenOptionAllocation(vestingAllocation).confirmMilestone(0);
        vm.warp(block.timestamp + 50 seconds);
        vm.startPrank(grantee);
        //exercise max available
        ERC20Stable(paymentToken).approve(vestingAllocation, TokenOptionAllocation(vestingAllocation).getPaymentAmount(TokenOptionAllocation(vestingAllocation).getAmountExercisable()));
        TokenOptionAllocation(vestingAllocation).exerciseTokenOption(TokenOptionAllocation(vestingAllocation).getAmountExercisable());
        TokenOptionAllocation(vestingAllocation).withdraw(VestingAllocation(vestingAllocation).getAmountWithdrawable());
        vm.stopPrank();
    }

    function testUnlockMilestoneNotUnlocked() public {
        address vestingAllocation = createDummyVestingAllocationNoUnlock();
        uint256 snapshot = token.balanceOf(authority);
        VestingAllocation(vestingAllocation).confirmMilestone(0);
        vm.warp(block.timestamp + 50 seconds);
        vm.startPrank(grantee);
        VestingAllocation(vestingAllocation).withdraw(VestingAllocation(vestingAllocation).getAmountWithdrawable());
        console.log(token.balanceOf(vestingAllocation));
        vm.warp(block.timestamp + 1050 seconds);
        VestingAllocation(vestingAllocation).withdraw(VestingAllocation(vestingAllocation).getAmountWithdrawable());
        console.log(token.balanceOf(vestingAllocation));
        vm.stopPrank();
    }

    function testTerminateTokenOptionAndRecover() public {
        address tokenOptionAllocation = createDummyTokenOptionAllocation();
        uint256 snapshot = token.balanceOf(authority);
        vm.warp(block.timestamp + 25 seconds);
        vm.prank(grantee);
        ERC20Stable(paymentToken).approve(tokenOptionAllocation, 350e18);
        vm.prank(grantee);
        TokenOptionAllocation(tokenOptionAllocation).exerciseTokenOption(350e18);
        controller.terminateMetavestVesting(tokenOptionAllocation);
        vm.startPrank(grantee);
        vm.warp(block.timestamp + 1 days + 25 seconds);
        assertEq(TokenOptionAllocation(tokenOptionAllocation).getAmountExercisable(), 0);
        TokenOptionAllocation(tokenOptionAllocation).withdraw(TokenOptionAllocation(tokenOptionAllocation).getAmountWithdrawable());
        vm.stopPrank();
        assertEq(token.balanceOf(tokenOptionAllocation), 0);
        vm.warp(block.timestamp + 365 days);
        vm.prank(authority);
        TokenOptionAllocation(tokenOptionAllocation).recoverForfeitTokens();
    }

    function testTerminateEarlyTokenOptionAndRecover() public {
        address tokenOptionAllocation = createDummyTokenOptionAllocation();
        uint256 snapshot = token.balanceOf(authority);
        vm.warp(block.timestamp + 5 seconds);
       // vm.prank(grantee);
       /* ERC20Stable(paymentToken).approve(tokenOptionAllocation, 350e18);
        vm.prank(grantee);
        TokenOptionAllocation(tokenOptionAllocation).exerciseTokenOption(350e18);*/
        controller.terminateMetavestVesting(tokenOptionAllocation);
        vm.warp(block.timestamp + 365 days);
        vm.prank(authority);
        TokenOptionAllocation(tokenOptionAllocation).recoverForfeitTokens();
    }


    function testTerminateRestrictedTokenAwardAndRecover() public {
        address restrictedTokenAward = createDummyRestrictedTokenAward();
        uint256 snapshot = token.balanceOf(authority);
        vm.warp(block.timestamp + 25 seconds);
        controller.terminateMetavestVesting(restrictedTokenAward);
        vm.startPrank(grantee);
        RestrictedTokenAward(restrictedTokenAward).withdraw(RestrictedTokenAward(restrictedTokenAward).getAmountWithdrawable());
        vm.stopPrank();
        uint256 amt = RestrictedTokenAward(restrictedTokenAward).getAmountRepurchasable();
        uint256 payamt = RestrictedTokenAward(restrictedTokenAward).getPaymentAmount(amt);
        vm.warp(block.timestamp + 20 days);
        paymentToken.approve(address(restrictedTokenAward), payamt);
        RestrictedTokenAward(restrictedTokenAward).repurchaseTokens(amt);

        vm.startPrank(grantee);
        RestrictedTokenAward(restrictedTokenAward).claimRepurchasedTokens();
        assertEq(token.balanceOf(restrictedTokenAward), 0);
        assertEq(paymentToken.balanceOf(restrictedTokenAward), 0);
    }

        function testChangeVestingAndUnlockingRate() public {
        address restrictedTokenAward = createDummyRestrictedTokenAward();
        uint256 snapshot = token.balanceOf(authority);
        vm.warp(block.timestamp + 25 seconds);
       
        bytes4 msgSig = bytes4(keccak256("updateMetavestUnlockRate(address,uint160)"));
        bytes memory callData = abi.encodeWithSelector(msgSig, restrictedTokenAward, 50e18);

        vm.prank(authority);
        controller.proposeMetavestAmendment(restrictedTokenAward, msgSig, callData);

        vm.prank(grantee);
        controller.consentToMetavestAmendment(restrictedTokenAward, msgSig, true);

        vm.prank(authority);
        controller.updateMetavestUnlockRate(restrictedTokenAward, 50e18);

        msgSig = bytes4(keccak256("updateMetavestVestingRate(address,uint160)"));
        callData = abi.encodeWithSelector(msgSig, restrictedTokenAward, 50e18);

        vm.prank(authority);
        controller.proposeMetavestAmendment(restrictedTokenAward, msgSig, callData);

        vm.prank(grantee);
        controller.consentToMetavestAmendment(restrictedTokenAward, msgSig, true);

        vm.prank(authority);
        controller.updateMetavestVestingRate(restrictedTokenAward, 50e18);

        vm.startPrank(grantee);
        RestrictedTokenAward(restrictedTokenAward).withdraw(RestrictedTokenAward(restrictedTokenAward).getAmountWithdrawable());
        vm.stopPrank();
       
    }

    function testZeroReclaim() public {
        address restrictedTokenAward = createDummyRestrictedTokenAward();
        vm.warp(block.timestamp + 15 seconds);
        vm.startPrank(grantee);
        RestrictedTokenAward(restrictedTokenAward).withdraw(RestrictedTokenAward(restrictedTokenAward).getAmountWithdrawable());
        vm.stopPrank();
        //create call data to propose setting vesting to 0
        bytes4 msgSig = bytes4(keccak256("updateMetavestVestingRate(address,uint160)"));
        bytes memory callData = abi.encodeWithSelector(msgSig, restrictedTokenAward, 0);

        vm.prank(authority);
        controller.proposeMetavestAmendment(restrictedTokenAward, msgSig, callData);

        vm.prank(grantee);
        controller.consentToMetavestAmendment(restrictedTokenAward, msgSig, true);

        vm.prank(authority);
        controller.updateMetavestVestingRate(restrictedTokenAward, 0);

        vm.startPrank(authority);
        controller.terminateMetavestVesting(restrictedTokenAward);
        vm.warp(block.timestamp + 155 days);
        uint256 amt = RestrictedTokenAward(restrictedTokenAward).getAmountRepurchasable();
        uint256 payamt = RestrictedTokenAward(restrictedTokenAward).getPaymentAmount(amt);
        paymentToken.approve(address(restrictedTokenAward), payamt);
        RestrictedTokenAward(restrictedTokenAward).repurchaseTokens(amt);
                 vm.stopPrank();
        vm.prank(grantee);
        RestrictedTokenAward(restrictedTokenAward).claimRepurchasedTokens();
        console.log(token.balanceOf(restrictedTokenAward));
    }

    function testZeroReclaimVesting() public {
        address restrictedTokenAward = createDummyVestingAllocation();
        vm.warp(block.timestamp + 15 seconds);
        vm.startPrank(grantee);
        RestrictedTokenAward(restrictedTokenAward).withdraw(RestrictedTokenAward(restrictedTokenAward).getAmountWithdrawable());
        vm.stopPrank();
        //create call data to propose setting vesting to 0
        bytes4 msgSig = bytes4(keccak256("updateMetavestVestingRate(address,uint160)"));
        bytes memory callData = abi.encodeWithSelector(msgSig, restrictedTokenAward, 0);

        vm.prank(authority);
        controller.proposeMetavestAmendment(restrictedTokenAward, msgSig, callData);

        vm.prank(grantee);
        controller.consentToMetavestAmendment(restrictedTokenAward, msgSig, true);

        vm.prank(authority);
        controller.updateMetavestVestingRate(restrictedTokenAward, 0);

        vm.startPrank(authority);
        controller.terminateMetavestVesting(restrictedTokenAward);
        vm.stopPrank();
        console.log(token.balanceOf(restrictedTokenAward));
    }

    function testSlightReduc() public {
        address restrictedTokenAward = createDummyVestingAllocation();
        vm.warp(block.timestamp + 5 seconds);
        vm.startPrank(grantee);
        RestrictedTokenAward(restrictedTokenAward).withdraw(RestrictedTokenAward(restrictedTokenAward).getAmountWithdrawable());
        vm.stopPrank();
        //create call data to propose setting vesting to 0
        bytes4 msgSig = bytes4(keccak256("updateMetavestVestingRate(address,uint160)"));
        bytes memory callData = abi.encodeWithSelector(msgSig, restrictedTokenAward, 80e18);

        vm.prank(authority);
        controller.proposeMetavestAmendment(restrictedTokenAward, msgSig, callData);

        vm.prank(grantee);
        controller.consentToMetavestAmendment(restrictedTokenAward, msgSig, true);

        vm.prank(authority);
        controller.updateMetavestVestingRate(restrictedTokenAward, 80e18);
        vm.warp(block.timestamp + 5 seconds);
        vm.startPrank(authority);
        controller.terminateMetavestVesting(restrictedTokenAward);
        vm.stopPrank();
        vm.warp(block.timestamp + 155 seconds);
        vm.startPrank(grantee);
        RestrictedTokenAward(restrictedTokenAward).withdraw(RestrictedTokenAward(restrictedTokenAward).getAmountWithdrawable());
        vm.stopPrank();
        console.log(token.balanceOf(restrictedTokenAward));
    }

    function testLargeReduc() public {
        address restrictedTokenAward = createDummyVestingAllocation();
        vm.warp(block.timestamp + 5 seconds);
        vm.startPrank(grantee);
        RestrictedTokenAward(restrictedTokenAward).withdraw(RestrictedTokenAward(restrictedTokenAward).getAmountWithdrawable());
        vm.stopPrank();
        //create call data to propose setting vesting to 0
        bytes4 msgSig = bytes4(keccak256("updateMetavestVestingRate(address,uint160)"));
        bytes memory callData = abi.encodeWithSelector(msgSig, restrictedTokenAward, 10e18);

        vm.prank(authority);
        controller.proposeMetavestAmendment(restrictedTokenAward, msgSig, callData);

        vm.prank(grantee);
        controller.consentToMetavestAmendment(restrictedTokenAward, msgSig, true);

        vm.prank(authority);
        controller.updateMetavestVestingRate(restrictedTokenAward, 10e18);
        vm.warp(block.timestamp + 5 seconds);
        vm.startPrank(authority);
        controller.terminateMetavestVesting(restrictedTokenAward);
        vm.stopPrank();
        vm.warp(block.timestamp + 155 seconds);
        vm.startPrank(grantee);
        RestrictedTokenAward(restrictedTokenAward).withdraw(RestrictedTokenAward(restrictedTokenAward).getAmountWithdrawable());
        vm.stopPrank();
        console.log(token.balanceOf(restrictedTokenAward));
    }

    function testLargeReducOption() public {
        address restrictedTokenAward = createDummyTokenOptionAllocation();
        vm.warp(block.timestamp + 5 seconds);
        vm.startPrank(grantee);
        //approve amount to exercise by getting amount to exercise and price
        ERC20Stable(paymentToken).approve(restrictedTokenAward, TokenOptionAllocation(restrictedTokenAward).getPaymentAmount(TokenOptionAllocation(restrictedTokenAward).getAmountExercisable()));
        TokenOptionAllocation(restrictedTokenAward).exerciseTokenOption(TokenOptionAllocation(restrictedTokenAward).getAmountExercisable());
        RestrictedTokenAward(restrictedTokenAward).withdraw(RestrictedTokenAward(restrictedTokenAward).getAmountWithdrawable());
        vm.stopPrank();
        //create call data to propose setting vesting to 0
        bytes4 msgSig = bytes4(keccak256("updateMetavestVestingRate(address,uint160)"));
        bytes memory callData = abi.encodeWithSelector(msgSig, restrictedTokenAward, 10e18);

        vm.prank(authority);
        controller.proposeMetavestAmendment(restrictedTokenAward, msgSig, callData);

        vm.prank(grantee);
        controller.consentToMetavestAmendment(restrictedTokenAward, msgSig, true);

        vm.prank(authority);
        controller.updateMetavestVestingRate(restrictedTokenAward, 10e18);
        vm.warp(block.timestamp + 5 seconds);
        vm.startPrank(authority);
        controller.terminateMetavestVesting(restrictedTokenAward);
        vm.stopPrank();
        vm.warp(block.timestamp + 155 seconds);
        vm.startPrank(grantee);
         ERC20Stable(paymentToken).approve(restrictedTokenAward, TokenOptionAllocation(restrictedTokenAward).getPaymentAmount(TokenOptionAllocation(restrictedTokenAward).getAmountExercisable()));
        TokenOptionAllocation(restrictedTokenAward).exerciseTokenOption(TokenOptionAllocation(restrictedTokenAward).getAmountExercisable());
        RestrictedTokenAward(restrictedTokenAward).withdraw(RestrictedTokenAward(restrictedTokenAward).getAmountWithdrawable());
        vm.stopPrank();
        console.log(token.balanceOf(restrictedTokenAward));
    }



    function testReclaim() public {
        address restrictedTokenAward = createDummyRestrictedTokenAward();
        vm.warp(block.timestamp + 15 seconds);
        vm.startPrank(grantee);
        RestrictedTokenAward(restrictedTokenAward).withdraw(RestrictedTokenAward(restrictedTokenAward).getAmountWithdrawable());
        vm.stopPrank();

        vm.startPrank(authority);
        controller.terminateMetavestVesting(restrictedTokenAward);
        vm.warp(block.timestamp + 155 days);
        uint256 amt = RestrictedTokenAward(restrictedTokenAward).getAmountRepurchasable();
        uint256 payamt = RestrictedTokenAward(restrictedTokenAward).getPaymentAmount(amt);
        paymentToken.approve(address(restrictedTokenAward), payamt);
        RestrictedTokenAward(restrictedTokenAward).repurchaseTokens(amt);
         vm.stopPrank();
        vm.prank(grantee);
        RestrictedTokenAward(restrictedTokenAward).claimRepurchasedTokens();
        console.log(token.balanceOf(restrictedTokenAward));
    }



    function testFailUpdateExercisePriceForVesting() public {
        address vestingAllocation = createDummyVestingAllocation();
        controller.updateExerciseOrRepurchasePrice(vestingAllocation, 2e18);
    }

    function testFailRepurchaseTokensAfterExpiry() public {
        address restrictedTokenAward = createDummyRestrictedTokenAward();
        
        // Fast forward time to after the short stop date
        vm.warp(block.timestamp + 366 days);
        
        RestrictedTokenAward(restrictedTokenAward).repurchaseTokens(500e18);
    }

    function testFailRepurchaseTokensInsufficientAllowance() public {
        address restrictedTokenAward = createDummyRestrictedTokenAward();
        
        // Not approving any tokens
       RestrictedTokenAward(restrictedTokenAward).repurchaseTokens(500e18);
    }

    function testFailInitiateAuthorityUpdateNonAuthority() public {
        vm.prank(address(0x1234));
        controller.initiateAuthorityUpdate(address(0x5678));
    }

    function testFailAcceptAuthorityRoleNonPendingAuthority() public {
        controller.initiateAuthorityUpdate(address(0x5678));
        
        vm.prank(address(0x1234));
        controller.acceptAuthorityRole();
    }

    function testFailInitiateDaoUpdateNonDao() public {
        vm.prank(address(0x1234));
        controller.initiateDaoUpdate(address(0x5678));
    }

    function testFailAcceptDaoRoleNonPendingDao() public {
        vm.prank(dao);
        controller.initiateDaoUpdate(address(0x5678));
        
        vm.prank(address(0x1234));
        controller.acceptDaoRole();
    }

    function testUpdateFunctionCondition() public {
        bytes4 functionSig = bytes4(keccak256("testFunction()"));
      /*      constructor(
        address[] memory _signers,
        uint256 _threshold,
        Logic _logic
    ) */
        address[] memory signers = new address[](2);
        signers[0] = address(0x1);
        signers[1] = address(0x2);
        SignatureCondition condition = new SignatureCondition(signers, 1, SignatureCondition.Logic.AND);
        
        vm.prank(dao);
        controller.updateFunctionCondition(address(condition), functionSig);
        
        assertEq(controller.functionToConditions(functionSig, 0), address(condition));
    }

    function testFailUpdateFunctionConditionNonDao() public {
        bytes4 functionSig = bytes4(keccak256("updateMetavestStopTimes(address,uint48)"));
        address condition = address(0x1234);
        
        controller.updateFunctionCondition(condition, functionSig);
    }


    function testRemoveFunctionCondition() public {
        bytes4 functionSig = bytes4(keccak256("updateMetavestStopTimes(address,uint48)"));
      /*      constructor(
        address[] memory _signers,
        uint256 _threshold,
        Logic _logic
    ) */
        address[] memory signers = new address[](2);
        signers[0] = address(0x1);
        signers[1] = address(0x2);
        SignatureCondition condition = new SignatureCondition(signers, 1, SignatureCondition.Logic.AND);
        
        vm.prank(dao);
        controller.updateFunctionCondition(address(condition), functionSig);
        assert(controller.functionToConditions(functionSig, 0) == address(condition));
        vm.prank(dao);
        controller.removeFunctionCondition(address(condition), functionSig);
    }

    function testFailCheckFunctionCondition() public {
        bytes4 functionSig = bytes4(keccak256("createMetavest(uint8,address,(uint256,uint128,uint128,uint160,uint48,uint160,uint48,address),(uint256,bool,bool,address[])[],uint256,address,uint256,uint256)"));
      /*      constructor(
        address[] memory _signers,
        uint256 _threshold,
        Logic _logic
    ) */
        address[] memory signers = new address[](2);
        signers[0] = address(0x1);
        signers[1] = address(0x2);
        SignatureCondition condition = new SignatureCondition(signers, 1, SignatureCondition.Logic.AND);
        
        vm.prank(dao);
        controller.updateFunctionCondition(address(condition), functionSig);
        assert(controller.functionToConditions(functionSig, 0) == address(condition));
        //create a dummy metavest
        address vestingAllocation = createDummyVestingAllocation();
    }
}