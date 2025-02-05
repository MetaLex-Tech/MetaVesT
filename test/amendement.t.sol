// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "../src/metavestController.sol";
import "../src/BaseAllocation.sol";
import "../src/RestrictedTokenAllocation.sol";
import "../src/interfaces/IAllocationFactory.sol";
import "../src/VestingAllocationFactory.sol";
import "../src/TokenOptionFactory.sol";
import "../src/RestrictedTokenFactory.sol";

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

contract MetaVestControllerTest is Test {
    metavestController public controller;
    MockERC20 public token;
    MockERC20 public paymentToken;
    address public authority;
    address public dao;
    address public vestingFactory;
    address public tokenOptionFactory;
    address public restrictedTokenFactory;
    address public grantee;
    address public mockAllocation;

    function setUp() public {
        authority = address(this);
        dao = address(2);
        VestingAllocationFactory factory = new VestingAllocationFactory();
        TokenOptionFactory tokenFactory = new TokenOptionFactory();
        RestrictedTokenFactory restrictedTokenFactory = new RestrictedTokenFactory();
        grantee = address(6);

        token = new MockERC20("Test Token", "TT");
        paymentToken = new MockERC20("Payment Token", "PT");

        controller = new metavestController(
            authority,
            dao,
            address(factory),
            address(tokenFactory),
            address(restrictedTokenFactory)
        );

        token.mint(authority, 1000000e58);
        paymentToken.mint(authority, 1000000e58);

        paymentToken.transfer(address(grantee), 1000e25);
        mockAllocation = createDummyVestingAllocation();

        vm.prank(authority);
        controller.createSet("testSet");
    }
    

    function testProposeMetavestAmendment() public {
        bytes4 msgSig = bytes4(keccak256("updateMetavestTransferability(address,bool)"));
        bytes memory callData = abi.encodeWithSelector(msgSig, address(mockAllocation), true);

        vm.prank(authority);
        controller.proposeMetavestAmendment(address(mockAllocation), msgSig, callData);

        (bool isPending, bytes32 dataHash, bool inFavor) = controller.functionToGranteeToAmendmentPending(msgSig, address(mockAllocation));
        
        assertTrue(isPending);
        assertEq(dataHash, keccak256(callData));
        assertFalse(inFavor);
    }

     function testFailProposeMajorityMetavestAmendment() public {
        address mockAllocation2 = createDummyVestingAllocation();
        address mockAllocation3 = createDummyVestingAllocation();
        address mockAllocation4 = createDummyVestingAllocation();
        bytes4 msgSig = bytes4(keccak256("updateMetavestTransferability(address,bool)"));
        bytes memory callData = abi.encodeWithSelector(msgSig, mockAllocation2, true);

        vm.prank(authority);
        controller.addMetaVestToSet("testSet", mockAllocation2);
        controller.addMetaVestToSet("testSet", mockAllocation3);
        controller.addMetaVestToSet("testSet", mockAllocation4);
        vm.warp(block.timestamp + 1 days);
        vm.prank(authority);
        controller.proposeMajorityMetavestAmendment("testSet", msgSig, callData);
        
        vm.prank(grantee);
        //log the current withdrawable
        console.log(TokenOptionAllocation(mockAllocation2).getAmountWithdrawable());

        controller.voteOnMetavestAmendment(mockAllocation2, "testSet", msgSig, true);

        vm.prank(authority);
        controller.updateMetavestTransferability(mockAllocation2, true);
    }

    function testQuickProposeMajorityMetavestAmendment() public {
        address mockAllocation2 = createDummyVestingAllocation();
        address mockAllocation3 = createDummyVestingAllocation();
        address mockAllocation4 = createDummyVestingAllocation();
        bytes4 msgSig = bytes4(keccak256("updateMetavestTransferability(address,bool)"));
        bytes memory callData = abi.encodeWithSelector(msgSig, mockAllocation2, true);

        vm.prank(authority);
        controller.addMetaVestToSet("testSet", mockAllocation2);
        controller.addMetaVestToSet("testSet", mockAllocation3);
        controller.addMetaVestToSet("testSet", mockAllocation4);
        vm.warp(block.timestamp + 15 seconds);
        vm.prank(authority);
        controller.proposeMajorityMetavestAmendment("testSet", msgSig, callData);
        
        vm.startPrank(grantee);
        //log the current withdrawable
        console.log(TokenOptionAllocation(mockAllocation2).getAmountWithdrawable());

        controller.voteOnMetavestAmendment(mockAllocation2, "testSet", msgSig, true);
        
        controller.voteOnMetavestAmendment(mockAllocation3, "testSet", msgSig, true);
        vm.stopPrank();
        vm.prank(authority);
        controller.updateMetavestTransferability(mockAllocation2, true);
    }


    function testMajorityPowerMetavestAmendment() public {
        address mockAllocation2 = createDummyTokenOptionAllocation();
        address mockAllocation3 = createDummyTokenOptionAllocation();
        address mockAllocation4 = createDummyTokenOptionAllocation();
        bytes4 msgSig = bytes4(keccak256("updateMetavestTransferability(address,bool)"));
        bytes memory callData = abi.encodeWithSelector(msgSig, mockAllocation2, true);

        vm.prank(authority);
        controller.addMetaVestToSet("testSet", mockAllocation2);
        controller.addMetaVestToSet("testSet", mockAllocation3);
        controller.addMetaVestToSet("testSet", mockAllocation4);
        vm.warp(block.timestamp + 1 days);
        vm.startPrank(grantee);
         ERC20(paymentToken).approve(address(mockAllocation2), 2000e18);
         TokenOptionAllocation(mockAllocation2).exerciseTokenOption(TokenOptionAllocation(mockAllocation2).getAmountExercisable());
        vm.stopPrank();
        vm.prank(authority);
        controller.proposeMajorityMetavestAmendment("testSet", msgSig, callData);

        vm.prank(grantee);
        controller.voteOnMetavestAmendment(mockAllocation3, "testSet", msgSig, true);
        vm.prank(grantee);
        controller.voteOnMetavestAmendment(mockAllocation4, "testSet", msgSig, true);

        vm.prank(authority);
        controller.updateMetavestTransferability(mockAllocation2, true);
    }

    function testFailMajorityPowerMetavestAmendment() public {
        address mockAllocation2 = createDummyTokenOptionAllocation();
        address mockAllocation3 = createDummyTokenOptionAllocation();
        address mockAllocation4 = createDummyTokenOptionAllocation();
        bytes4 msgSig = bytes4(keccak256("updateMetavestTransferability(address,bool)"));
        bytes memory callData = abi.encodeWithSelector(msgSig, mockAllocation2, true);

        vm.prank(authority);
        controller.addMetaVestToSet("testSet", mockAllocation2);
        controller.addMetaVestToSet("testSet", mockAllocation3);
        controller.addMetaVestToSet("testSet", mockAllocation4);
        vm.warp(block.timestamp + 1 days);
        vm.startPrank(grantee);
         ERC20(paymentToken).approve(address(mockAllocation2), 2000e18);
         TokenOptionAllocation(mockAllocation2).exerciseTokenOption(TokenOptionAllocation(mockAllocation2).getAmountExercisable());
        vm.stopPrank();
        vm.prank(authority);
        controller.proposeMajorityMetavestAmendment("testSet", msgSig, callData);

        vm.prank(grantee);
        controller.voteOnMetavestAmendment(mockAllocation3, "testSet", msgSig, true);
        vm.prank(grantee);
        controller.voteOnMetavestAmendment(mockAllocation4, "testSet", msgSig, true);

        vm.prank(authority);
        controller.updateMetavestTransferability(mockAllocation2, true);
        vm.prank(authority);
        controller.updateMetavestTransferability(mockAllocation2, true);
    }

    function testProposeMajorityMetavestAmendment() public {
        address mockAllocation2 = createDummyVestingAllocation();
        address mockAllocation3 = createDummyVestingAllocation();
        bytes4 msgSig = bytes4(keccak256("updateMetavestTransferability(address,bool)"));
        bytes memory callData = abi.encodeWithSelector(msgSig, mockAllocation2, true);

        vm.prank(authority);
        controller.addMetaVestToSet("testSet", mockAllocation2);
        controller.addMetaVestToSet("testSet", mockAllocation3);
        vm.warp(block.timestamp + 1 days);
        vm.prank(authority);
        controller.proposeMajorityMetavestAmendment("testSet", msgSig, callData);

        vm.prank(grantee);
        controller.voteOnMetavestAmendment(mockAllocation2, "testSet", msgSig, true);

        vm.prank(authority);
        controller.updateMetavestTransferability(mockAllocation2, true);

        vm.prank(authority);
        controller.updateMetavestTransferability(mockAllocation3, true);
    }

    function testProposeMajorityMetavestAmendmentReAdd() public {
        address mockAllocation2 = createDummyVestingAllocation();
        address mockAllocation3 = createDummyVestingAllocation();
        bytes4 msgSig = bytes4(keccak256("updateMetavestTransferability(address,bool)"));
        bytes memory callData = abi.encodeWithSelector(msgSig, mockAllocation2, true);

        vm.prank(authority);
        controller.addMetaVestToSet("testSet", mockAllocation2);
        controller.addMetaVestToSet("testSet", mockAllocation3);
        vm.warp(block.timestamp + 1 days);
        vm.prank(authority);
        controller.proposeMajorityMetavestAmendment("testSet", msgSig, callData);

        vm.prank(grantee);
        controller.voteOnMetavestAmendment(mockAllocation2, "testSet", msgSig, true);

        vm.prank(authority);
        controller.updateMetavestTransferability(mockAllocation3, true);

        vm.prank(authority);
        controller.removeMetaVestFromSet("testSet", mockAllocation3);
      //  vm.prank(authority);
      //  controller.updateMetavestTransferability(mockAllocation3, true);
        vm.warp(block.timestamp + 90 days);
        vm.prank(authority);
        controller.proposeMajorityMetavestAmendment("testSet", msgSig, callData);

        vm.prank(grantee);
        controller.voteOnMetavestAmendment(mockAllocation2, "testSet", msgSig, true);

        vm.prank(authority);
        controller.updateMetavestTransferability(mockAllocation2, true);

        vm.prank(authority);
        controller.addMetaVestToSet("testSet", mockAllocation3);

        vm.prank(authority);
        controller.updateMetavestTransferability(mockAllocation3, true);
    }

        function testFailNoPassProposeMajorityMetavestAmendment() public {
        address mockAllocation2 = createDummyVestingAllocation();
        address mockAllocation3 = createDummyVestingAllocation();
        bytes4 msgSig = bytes4(keccak256("updateMetavestTransferability(address,bool)"));
        bytes memory callData = abi.encodeWithSelector(msgSig, mockAllocation2, true);

        vm.prank(authority);
        controller.addMetaVestToSet("testSet", mockAllocation2);
        controller.addMetaVestToSet("testSet", mockAllocation3);
        vm.warp(block.timestamp + 1 days);
        vm.prank(authority);
        controller.proposeMajorityMetavestAmendment("testSet", msgSig, callData);

        vm.prank(authority);
        controller.updateMetavestTransferability(mockAllocation2, true);
        
        vm.prank(authority);
        controller.updateMetavestTransferability(mockAllocation3, true);
    }

    function testVoteOnMetavestAmendment() public {
        bytes4 msgSig = bytes4(keccak256("updateMetavestTransferability(address,bool)"));
        bytes memory callData = abi.encodeWithSelector(msgSig, address(mockAllocation), true);

        vm.prank(authority);
        controller.addMetaVestToSet("testSet", address(mockAllocation));

        vm.prank(authority);
        controller.proposeMajorityMetavestAmendment("testSet", msgSig, callData);

        vm.prank(grantee);
        controller.voteOnMetavestAmendment(address(mockAllocation), "testSet", msgSig, true);

        (uint256 totalVotingPower, uint256 currentVotingPower, , ,  ) = controller.functionToSetMajorityProposal(msgSig, "testSet");

    }

    function testFailVoteOnMetavestAmendmentTwice() public {
        bytes4 msgSig = bytes4(keccak256("updateMetavestTransferability(address,bool)"));
        bytes memory callData = abi.encodeWithSelector(msgSig, address(mockAllocation), true);

        vm.prank(authority);
        controller.addMetaVestToSet("testSet", address(mockAllocation));

        vm.prank(authority);
        controller.proposeMajorityMetavestAmendment("testSet", msgSig, callData);

        vm.startPrank(grantee);
        controller.voteOnMetavestAmendment(address(mockAllocation), "testSet", msgSig, true);
        controller.voteOnMetavestAmendment(address(mockAllocation), "testSet", msgSig, true);
        vm.stopPrank();
    }

    function testSetManagement() public {
        vm.startPrank(authority);
        
        // Test creating a new set
        controller.createSet("newSet");

        // Test adding a MetaVest to a set
        controller.addMetaVestToSet("newSet", address(mockAllocation));


        // Test removing a MetaVest from a set
        controller.removeMetaVestFromSet("newSet", address(mockAllocation));


        // Test removing a set
        controller.removeSet("newSet");


        vm.stopPrank();
    }

    function testFailCreateDuplicateSet() public {
        vm.startPrank(authority);
        controller.createSet("duplicateSet");
        controller.createSet("duplicateSet");
        vm.stopPrank();
    }

    function testFailNonAuthorityCreateSet() public {
        vm.prank(grantee);
        controller.createSet("unauthorizedSet");
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
            milestoneAward: 100e18,
            unlockOnCompletion: true,
            complete: false,
            conditionContracts: new address[](0)
        });

        token.approve(address(controller), 1100e18);

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
            milestoneAward: 100e18,
            unlockOnCompletion: true,
            complete: false,
            conditionContracts: new address[](0)
        });

        token.approve(address(controller), 1100e18);

        return controller.createMetavest(
            metavestController.metavestType.TokenOption,
            grantee,
            allocation,
            milestones,
            1e18,
            address(paymentToken),
            365 days,
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
            milestoneAward: 100e18,
            unlockOnCompletion: true,
            complete: false,
            conditionContracts: new address[](0)
        });

        token.approve(address(controller), 1100e18);

        return controller.createMetavest(
            metavestController.metavestType.RestrictedTokenAward,
            grantee,
            allocation,
            milestones,
            1e18,
            address(paymentToken),
            365 days,
            0
            
        );
    }

    //write a test for every consentcheck function in metavest controller
    function testConsentCheck() public {
        address allocation = createDummyVestingAllocation();
        bytes4 msgSig = bytes4(keccak256("updateMetavestTransferability(address,bool)"));
        bytes memory callData = abi.encodeWithSelector(msgSig, allocation, true);

        vm.prank(authority);
        controller.proposeMetavestAmendment(allocation, msgSig, callData);

        vm.prank(grantee);
        controller.consentToMetavestAmendment(allocation, msgSig, true);

        vm.prank(authority);
        controller.updateMetavestTransferability(allocation, true);
    }

    function testFailConsentCheck() public {
        address allocation = createDummyVestingAllocation();
        bytes4 msgSig = bytes4(keccak256("updateMetavestTransferability(address,bool)"));
        bytes memory callData = abi.encodeWithSelector(msgSig, allocation, true);

        vm.prank(authority);
        controller.proposeMetavestAmendment(allocation, msgSig, callData);

        vm.prank(grantee);
        controller.voteOnMetavestAmendment(allocation, "testSet", msgSig, false);

        vm.prank(authority);
        controller.updateMetavestTransferability(allocation, true);
    }

    function testFailConsentCheckNoProposal() public {
        address allocation = createDummyVestingAllocation();
        bytes4 msgSig = bytes4(keccak256("updateMetavestTransferability(address,bool)"));

        vm.prank(grantee);
        controller.voteOnMetavestAmendment(allocation, "testSet", msgSig, true);
    }

    function testFailConsentCheckNoVote() public {
        address allocation = createDummyVestingAllocation();
        bytes4 msgSig = bytes4(keccak256("updateMetavestTransferability(address,bool)"));
        bytes memory callData = abi.encodeWithSelector(msgSig, allocation, true);

        vm.prank(authority);
        controller.proposeMetavestAmendment(allocation, msgSig, callData);

        vm.prank(authority);
        controller.updateMetavestTransferability(allocation, true);
    }

    function testFailConsentCheckNoUpdate() public {
        address allocation = createDummyVestingAllocation();
        bytes4 msgSig = bytes4(keccak256("updateMetavestTransferability(address,bool)"));
        bytes memory callData = abi.encodeWithSelector(msgSig, allocation, true);

        vm.prank(authority);
        controller.proposeMetavestAmendment(allocation, msgSig, callData);

        vm.prank(grantee);
        controller.voteOnMetavestAmendment(allocation, "testSet", msgSig, true);
    }

    function testFailConsentCheckNoVoteUpdate() public {
        address allocation = createDummyVestingAllocation();
        bytes4 msgSig = bytes4(keccak256("updateMetavestTransferability(address,bool)"));
        bytes memory callData = abi.encodeWithSelector(msgSig, allocation, true);

        vm.prank(authority);
        controller.proposeMetavestAmendment(allocation, msgSig, callData);

        vm.prank(grantee);
        controller.voteOnMetavestAmendment(allocation, "testSet", msgSig, true);
    }

    function testCreateSetWithThreeTokenOptionsAndChangeExercisePrice() public {
        address allocation1 = createDummyTokenOptionAllocation();
        address allocation2 = createDummyTokenOptionAllocation();
        address allocation3 = createDummyTokenOptionAllocation();

        vm.prank(authority);
        controller.addMetaVestToSet("testSet", allocation1);
        controller.addMetaVestToSet("testSet", allocation2);
        controller.addMetaVestToSet("testSet", allocation3);
         assertTrue(TokenOptionAllocation(allocation1).exercisePrice() == 1e18);
         vm.warp(block.timestamp + 25 seconds);

        
        vm.startPrank(grantee);
        ERC20(paymentToken).approve(address(allocation1), 2000e18);
        ERC20(paymentToken).approve(address(allocation2), 2000e18);
 
         TokenOptionAllocation(allocation1).exerciseTokenOption(TokenOptionAllocation(allocation1).getAmountExercisable());
         
         TokenOptionAllocation(allocation2).exerciseTokenOption(TokenOptionAllocation(allocation2).getAmountExercisable());
         vm.stopPrank();
        bytes4 msgSig = bytes4(keccak256("updateExerciseOrRepurchasePrice(address,uint256)"));
        bytes memory callData = abi.encodeWithSelector(msgSig, allocation1, 2e18);

        vm.prank(authority);
        controller.proposeMajorityMetavestAmendment("testSet", msgSig, callData);

        vm.prank(grantee);
        controller.voteOnMetavestAmendment(allocation1, "testSet", msgSig, true);

        vm.prank(grantee);
        controller.voteOnMetavestAmendment(allocation2, "testSet", msgSig, true);

        vm.prank(authority);
        controller.updateExerciseOrRepurchasePrice(allocation1, 2e18);

        vm.prank(authority);
        controller.updateExerciseOrRepurchasePrice(allocation2, 2e18);

        vm.prank(authority);
        controller.updateExerciseOrRepurchasePrice(allocation3, 2e18);

        // Check that the exercise price was updated
        assertTrue(TokenOptionAllocation(allocation1).exercisePrice() == 2e18);
    }

    function testFailCreateSetWithThreeTokenOptionsAndChangeExercisePrice() public {
        address allocation1 = createDummyTokenOptionAllocation();
        address allocation2 = createDummyTokenOptionAllocation();
        address allocation3 = createDummyTokenOptionAllocation();

        vm.prank(authority);
        controller.addMetaVestToSet("testSet", allocation1);
        controller.addMetaVestToSet("testSet", allocation2);
        controller.addMetaVestToSet("testSet", allocation3);
         assertTrue(TokenOptionAllocation(allocation1).exercisePrice() == 1e18);
         vm.warp(block.timestamp + 25 seconds);


        vm.startPrank(grantee);
        ERC20(paymentToken).approve(address(allocation1), 2000e18);
        ERC20(paymentToken).approve(address(allocation2), 2000e18);
 
         TokenOptionAllocation(allocation1).exerciseTokenOption(TokenOptionAllocation(allocation1).getAmountExercisable());
         
         TokenOptionAllocation(allocation2).exerciseTokenOption(TokenOptionAllocation(allocation2).getAmountExercisable());
         vm.stopPrank();
        bytes4 msgSig = bytes4(keccak256("updateExerciseOrRepurchasePrice(address,uint256)"));
        bytes memory callData = abi.encodeWithSelector(msgSig, allocation1, 2e18);

        vm.prank(authority);
        controller.proposeMajorityMetavestAmendment("testSet", msgSig, callData);

        //vm.prank(grantee);
       // controller.voteOnMetavestAmendment(allocation1, "testSet", msgSig, true);

       // vm.prank(grantee);
       // controller.voteOnMetavestAmendment(allocation2, "testSet", msgSig, true);

        vm.prank(authority);
        controller.updateExerciseOrRepurchasePrice(allocation1, 2e18);

        vm.prank(authority);
        controller.updateExerciseOrRepurchasePrice(allocation2, 2e18);

        vm.prank(authority);
        controller.updateExerciseOrRepurchasePrice(allocation3, 2e18);

        // Check that the exercise price was updated
        assertTrue(TokenOptionAllocation(allocation1).exercisePrice() == 2e18);
    }

    function testFailconsentToNoPendingAmendment() public {
        address allocation = createDummyVestingAllocation();
        bytes4 msgSig = bytes4(keccak256("updateMetavestTransferability(address,bool)"));
        bytes memory callData = abi.encodeWithSelector(msgSig, allocation, true);

        vm.prank(grantee);
        controller.consentToMetavestAmendment(allocation, msgSig, true);
    }

    function testEveryUpdateAmendmentFunction() public {
        address allocation = createDummyTokenOptionAllocation();
        bytes4 msgSig = bytes4(keccak256("updateMetavestTransferability(address,bool)"));
        bytes memory callData = abi.encodeWithSelector(msgSig, allocation, true);

        vm.prank(authority);
        controller.proposeMetavestAmendment(allocation, msgSig, callData);

        vm.prank(grantee);
        controller.consentToMetavestAmendment(allocation, msgSig, true);

        vm.prank(authority);
        controller.updateMetavestTransferability(allocation, true);

        msgSig = bytes4(keccak256("updateExerciseOrRepurchasePrice(address,uint256)"));
        callData = abi.encodeWithSelector(msgSig, allocation, 2e18);

        vm.prank(authority);
        controller.proposeMetavestAmendment(allocation, msgSig, callData);

        vm.prank(grantee);
        controller.consentToMetavestAmendment(allocation, msgSig, true);

        vm.prank(authority);
        controller.updateExerciseOrRepurchasePrice(allocation, 2e18);

        msgSig = bytes4(keccak256("removeMetavestMilestone(address,uint256)"));
        callData = abi.encodeWithSelector(msgSig, allocation, 0);

        vm.prank(authority);
        controller.proposeMetavestAmendment(allocation, msgSig, callData);

        vm.prank(grantee);
        controller.consentToMetavestAmendment(allocation, msgSig, true);

        vm.prank(authority);
        controller.removeMetavestMilestone(allocation, 0);

        msgSig = bytes4(keccak256("updateMetavestUnlockRate(address,uint160)"));
        callData = abi.encodeWithSelector(msgSig, allocation, 20e18);

        vm.prank(authority);
        controller.proposeMetavestAmendment(allocation, msgSig, callData);

        vm.prank(grantee);
        controller.consentToMetavestAmendment(allocation, msgSig, true);

        vm.prank(authority);
        controller.updateMetavestUnlockRate(allocation, 20e18);

        msgSig = bytes4(keccak256("updateMetavestVestingRate(address,uint160)"));
        callData = abi.encodeWithSelector(msgSig, allocation, 20e18);

        vm.prank(authority);
        controller.proposeMetavestAmendment(allocation, msgSig, callData);

        vm.prank(grantee);
        controller.consentToMetavestAmendment(allocation, msgSig, true);

        vm.prank(authority);
        controller.updateMetavestVestingRate(allocation, 20e18);

        msgSig = bytes4(keccak256("setMetaVestGovVariables(address,uint8)"));
        callData = abi.encodeWithSelector(msgSig, allocation, BaseAllocation.GovType.vested);

        vm.prank(authority);
        controller.proposeMetavestAmendment(allocation, msgSig, callData);

        vm.prank(grantee);
        controller.consentToMetavestAmendment(allocation, msgSig, true);

        vm.prank(authority);
        controller.setMetaVestGovVariables(allocation, BaseAllocation.GovType.vested);
    }

    function testEveryUpdateAmendmentFunctionRestricted() public {
        address allocation = createDummyRestrictedTokenAward();
        bytes4 msgSig = bytes4(keccak256("updateMetavestTransferability(address,bool)"));
        bytes memory callData = abi.encodeWithSelector(msgSig, allocation, true);

        vm.prank(authority);
        controller.proposeMetavestAmendment(allocation, msgSig, callData);

        vm.prank(grantee);
        controller.consentToMetavestAmendment(allocation, msgSig, true);

        vm.prank(authority);
        controller.updateMetavestTransferability(allocation, true);

        msgSig = bytes4(keccak256("updateExerciseOrRepurchasePrice(address,uint256)"));
        callData = abi.encodeWithSelector(msgSig, allocation, 2e18);

        vm.prank(authority);
        controller.proposeMetavestAmendment(allocation, msgSig, callData);

        vm.prank(grantee);
        controller.consentToMetavestAmendment(allocation, msgSig, true);

        vm.prank(authority);
        controller.updateExerciseOrRepurchasePrice(allocation, 2e18);

        msgSig = bytes4(keccak256("removeMetavestMilestone(address,uint256)"));
        callData = abi.encodeWithSelector(msgSig, allocation, 0);

        vm.prank(authority);
        controller.proposeMetavestAmendment(allocation, msgSig, callData);

        vm.prank(grantee);
        controller.consentToMetavestAmendment(allocation, msgSig, true);

        vm.prank(authority);
        controller.removeMetavestMilestone(allocation, 0);

        msgSig = bytes4(keccak256("updateMetavestUnlockRate(address,uint160)"));
        callData = abi.encodeWithSelector(msgSig, allocation, 20e18);

        vm.prank(authority);
        controller.proposeMetavestAmendment(allocation, msgSig, callData);

        vm.prank(grantee);
        controller.consentToMetavestAmendment(allocation, msgSig, true);

        vm.prank(authority);
        controller.updateMetavestUnlockRate(allocation, 20e18);

        msgSig = bytes4(keccak256("updateMetavestVestingRate(address,uint160)"));
        callData = abi.encodeWithSelector(msgSig, allocation, 20e18);

        vm.prank(authority);
        controller.proposeMetavestAmendment(allocation, msgSig, callData);

        vm.prank(grantee);
        controller.consentToMetavestAmendment(allocation, msgSig, true);

        vm.prank(authority);
        controller.updateMetavestVestingRate(allocation, 20e18);

        msgSig = bytes4(keccak256("setMetaVestGovVariables(address,uint8)"));
        callData = abi.encodeWithSelector(msgSig, allocation, BaseAllocation.GovType.vested);

        vm.prank(authority);
        controller.proposeMetavestAmendment(allocation, msgSig, callData);

        vm.prank(grantee);
        controller.consentToMetavestAmendment(allocation, msgSig, true);

        vm.prank(authority);
        controller.setMetaVestGovVariables(allocation, BaseAllocation.GovType.vested);
    }

    function testEveryUpdateAmendmentFunctionVesting() public {
        address allocation = createDummyVestingAllocation();
        bytes4 msgSig = bytes4(keccak256("updateMetavestTransferability(address,bool)"));
        bytes memory callData = abi.encodeWithSelector(msgSig, allocation, true);

        vm.prank(authority);
        controller.proposeMetavestAmendment(allocation, msgSig, callData);

        vm.prank(grantee);
        controller.consentToMetavestAmendment(allocation, msgSig, true);

        vm.prank(authority);
        controller.updateMetavestTransferability(allocation, true);

        msgSig = bytes4(keccak256("removeMetavestMilestone(address,uint256)"));
        callData = abi.encodeWithSelector(msgSig, allocation, 0);

        vm.prank(authority);
        controller.proposeMetavestAmendment(allocation, msgSig, callData);

        vm.prank(grantee);
        controller.consentToMetavestAmendment(allocation, msgSig, true);

        vm.prank(authority);
        controller.removeMetavestMilestone(allocation, 0);

        msgSig = bytes4(keccak256("updateMetavestUnlockRate(address,uint160)"));
        callData = abi.encodeWithSelector(msgSig, allocation, 20e18);

        vm.prank(authority);
        controller.proposeMetavestAmendment(allocation, msgSig, callData);

        vm.prank(grantee);
        controller.consentToMetavestAmendment(allocation, msgSig, true);

        vm.prank(authority);
        controller.updateMetavestUnlockRate(allocation, 20e18);

        msgSig = bytes4(keccak256("updateMetavestVestingRate(address,uint160)"));
        callData = abi.encodeWithSelector(msgSig, allocation, 20e18);

        vm.prank(authority);
        controller.proposeMetavestAmendment(allocation, msgSig, callData);

        vm.prank(grantee);
        controller.consentToMetavestAmendment(allocation, msgSig, true);

        vm.prank(authority);
        controller.updateMetavestVestingRate(allocation, 20e18);

        msgSig = bytes4(keccak256("setMetaVestGovVariables(address,uint8)"));
        callData = abi.encodeWithSelector(msgSig, allocation, BaseAllocation.GovType.vested);

        vm.prank(authority);
        controller.proposeMetavestAmendment(allocation, msgSig, callData);

        vm.prank(grantee);
        controller.consentToMetavestAmendment(allocation, msgSig, true);

        vm.prank(authority);
        controller.setMetaVestGovVariables(allocation, BaseAllocation.GovType.vested);
    }

    function testFailEveryUpdateAmendmentFunctionVesting() public {
        address allocation = createDummyVestingAllocation();
        bytes4 msgSig = bytes4(keccak256("updateMetavestTransferability(address,bool)"));
        bytes memory callData = abi.encodeWithSelector(msgSig, allocation, true);

        vm.prank(authority);
        controller.proposeMetavestAmendment(allocation, msgSig, callData);

        vm.prank(grantee);
        controller.consentToMetavestAmendment(allocation, msgSig, true);

        vm.prank(authority);
        controller.updateMetavestTransferability(allocation, true);

        msgSig = bytes4(keccak256("removeMetavestMilestone(address,uint256)"));
        callData = abi.encodeWithSelector(msgSig, allocation, 0);

        vm.prank(authority);
        controller.proposeMetavestAmendment(allocation, msgSig, callData);

        vm.prank(grantee);
        controller.consentToMetavestAmendment(allocation, msgSig, true);

        vm.prank(authority);
        controller.removeMetavestMilestone(allocation, 0);

        msgSig = bytes4(keccak256("updateMetavestUnlockRate(address,uint160)"));
        callData = abi.encodeWithSelector(msgSig, allocation, 20e18);

        vm.prank(authority);
        controller.proposeMetavestAmendment(allocation, msgSig, callData);

        vm.prank(grantee);
        controller.consentToMetavestAmendment(allocation, msgSig, true);

        vm.prank(authority);
        controller.updateMetavestUnlockRate(allocation, 20e18);

        msgSig = bytes4(keccak256("updateMetavestVestingRate(address,uint160)"));
        callData = abi.encodeWithSelector(msgSig, allocation, 20e18);

        vm.prank(authority);
        controller.proposeMetavestAmendment(allocation, msgSig, callData);

        vm.prank(grantee);
        controller.consentToMetavestAmendment(allocation, msgSig, true);

        vm.prank(authority);
        controller.updateMetavestVestingRate(allocation, 20e18);

        msgSig = bytes4(keccak256("setMetaVestGovVariables(address,uint8)"));
        callData = abi.encodeWithSelector(msgSig, allocation, BaseAllocation.GovType.vested);

        vm.prank(authority);
        controller.proposeMetavestAmendment(allocation, msgSig, callData);

        vm.prank(authority);
        controller.setMetaVestGovVariables(allocation, BaseAllocation.GovType.vested);
    }
}