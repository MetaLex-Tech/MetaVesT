// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.20;

/// @notice interface to a MetaLeX condition contract
/// @dev see https://github.com/MetaLex-Tech/BORG-CORE/tree/main/src/libs/conditions
interface IConditionM {
    function checkCondition(address _contract, bytes4 _functionSignature, bytes memory data) external view returns (bool);
}

interface IERC20M {
    function allowance(address owner, address spender) external view returns (uint256);
    function decimals() external view returns (uint8);
    function balanceOf(address account) external view returns (uint256);
}

interface IController { 
    function authority() external view returns (address);
}

/// @notice Solady's SafeTransferLib 'SafeTransfer()' and 'SafeTransferFrom()'; (https://github.com/Vectorized/solady/blob/main/src/utils/SafeTransferLib.sol)
abstract contract SafeTransferLib {
    error TransferFailed();
    error TransferFromFailed();

    /// @dev Sends `amount` of ERC20 `token` from the current contract to `to`. Reverts upon failure.
    function safeTransfer(address token, address to, uint256 amount) internal {
        assembly {
            mstore(0x14, to) // Store the `to` argument.
            mstore(0x34, amount) // Store the `amount` argument.
            mstore(0x00, 0xa9059cbb000000000000000000000000) // `transfer(address,uint256)`.
            // Perform the transfer, reverting upon failure.
            if iszero(
                and(
                    // The arguments of `and` are evaluated from right to left.
                    or(eq(mload(0x00), 1), iszero(returndatasize())), // Returned 1 or nothing.
                    call(gas(), token, 0, 0x10, 0x44, 0x00, 0x20)
                )
            ) {
                mstore(0x00, 0x90b8ec18) // `TransferFailed()`.
                revert(0x1c, 0x04)
            }
            mstore(0x34, 0) // Restore the part of the free memory pointer that was overwritten.
        }
    }

    /// @dev Sends `amount` of ERC20 `token` from `from` to `to`. Reverts upon failure.
    /// The `from` account must have at least `amount` approved for the current contract to manage.
    function safeTransferFrom(address token, address from, address to, uint256 amount) internal {
        assembly {
            let m := mload(0x40) // Cache the free memory pointer.
            mstore(0x60, amount) // Store the `amount` argument.
            mstore(0x40, to) // Store the `to` argument.
            mstore(0x2c, shl(96, from)) // Store the `from` argument.
            mstore(0x0c, 0x23b872dd000000000000000000000000) // `transferFrom(address,address,uint256)`.
            // Perform the transfer, reverting upon failure.
            if iszero(
                and(
                    // The arguments of `and` are evaluated from right to left.
                    or(eq(mload(0x00), 1), iszero(returndatasize())), // Returned 1 or nothing.
                    call(gas(), token, 0, 0x1c, 0x64, 0x00, 0x20)
                )
            ) {
                mstore(0x00, 0x7939f424) // `TransferFromFailed()`.
                revert(0x1c, 0x04)
            }
            mstore(0x60, 0) // Restore the zero slot to zero.
            mstore(0x40, m) // Restore the free memory pointer.
        }
    }
}

/// @notice gas-optimized reentrancy protection by Solady (https://github.com/Vectorized/solady/blob/main/src/utils/ReentrancyGuard.sol)
abstract contract ReentrancyGuard {
    /// @dev Equivalent to: `uint72(bytes9(keccak256("_REENTRANCY_GUARD_SLOT")))`. 9 bytes is large enough to avoid collisions with lower slots,
    /// but not too large to result in excessive bytecode bloat.
    uint256 private constant _REENTRANCY_GUARD_SLOT = 0x929eee149b4bd21268;
    error Reentrancy();

    /// @dev Guards a function from reentrancy.
    modifier nonReentrant() virtual {
        assembly {
            if eq(sload(_REENTRANCY_GUARD_SLOT), address()) {
                mstore(0x00, 0xab143c06) // `Reentrancy()`.
                revert(0x1c, 0x04)
            }
            sstore(_REENTRANCY_GUARD_SLOT, address())
        }
        _;
        assembly {
            sstore(_REENTRANCY_GUARD_SLOT, codesize())
        }
    }
}


abstract contract BaseAllocation is ReentrancyGuard, SafeTransferLib{

        /// @notice MetaVesTController contract address, immutably tied to this MetaVesT
        address public immutable controller;
        /// @notice authority address, may replace itself in 'controller'
        address public authority; // REVIEW: probably just have `getAuthority` which calls thru to `controller`? Saves having to worry about updating if it changes?
        struct Milestone {
            uint256 milestoneAward; // per-milestone indexed lump sums of tokens vested upon corresponding milestone completion
            bool unlockOnCompletion; // whether the 'milestoneAward' is to be unlocked upon completion
            bool complete; // whether the Milestone is satisfied and the 'milestoneAward' is to be released
            address[] conditionContracts; // array of contract addresses corresponding to condition(s) that must satisfied for this Milestone to be 'complete'
        }
        error MetaVesT_OnlyController();
        error MetaVesT_OnlyGrantee();
        error MetaVesT_OnlyAuthority();
        error MetaVesT_ZeroAddress();
        error MetaVesT_RateTooHigh();
        error MetaVesT_ZeroAmount();
        error MetaVesT_NotTerminated();
        error MetaVesT_MilestoneIndexCompletedOrDoesNotExist();
        error MetaVesT_ConditionNotSatisfied();
        error MetaVesT_AlreadyTerminated();
        error MetaVesT_MoreThanAvailable();
        error MetaVesT_VestNotTransferable();
        error MetaVesT_ShortStopTimeNotReached();

        event MetaVesT_MilestoneCompleted(address indexed grantee, uint256 indexed milestoneIndex);
        event MetaVesT_MilestoneAdded(address indexed grantee, Milestone milestone);
        event MetaVesT_MilestoneRemoved(address indexed grantee, uint256 indexed milestoneIndex);
        event MetaVesT_StopTimesUpdated(
            address indexed grant,
            uint48 shortStopTime
        );
        event MetaVesT_TransferabilityUpdated(address indexed grantee, bool isTransferable);
        event MetaVesT_TransferredRights(address indexed grantee, address transferee);
        event MetaVesT_UnlockRateUpdated(address indexed grantee, uint208 unlockRate);
        event MetaVesT_VestingRateUpdated(address indexed grantee, uint208 vestingRate);
        event MetaVesT_Withdrawn(address indexed grantee, address indexed tokenAddress, uint256 amount);
        event MetaVesT_PriceUpdated(address indexed grantee, uint256 exercisePrice);
        event MetaVesT_RepurchaseAndWithdrawal(address indexed grantee, address indexed tokenAddress, uint256 withdrawalAmount, uint256 repurchaseAmount);
        event MetaVesT_Terminated(address indexed grantee, uint256 tokensRecovered);
        event MetaVest_GovVariablesUpdated(GovType _govType);

        struct Allocation {
            uint256 tokenStreamTotal; // total number of tokens subject to linear vesting/restriction removal (includes cliff credits but not each 'milestoneAward')
            uint128 vestingCliffCredit; // lump sum of tokens which become vested at 'startTime' and will be added to '_linearVested'
            uint128 unlockingCliffCredit; // lump sum of tokens which become unlocked at 'startTime' and will be added to '_linearUnlocked'
            uint160 vestingRate; // tokens per second that become vested; if RESTRICTED this amount corresponds to 'lapse rate' for tokens that become non-repurchasable
            uint48 vestingStartTime; // if RESTRICTED this amount corresponds to 'lapse start time'
            uint160 unlockRate; // tokens per second that become unlocked;
            uint48 unlockStartTime; // start of the linear unlock
            address tokenContract; // contract address of the ERC20 token included in the MetaVesT
        }

        enum GovType {all, vested, unlocked}

        address public grantee; // grantee of the tokens
        bool transferable; // whether grantee can transfer their MetaVesT in whole
        Milestone[] public milestones; // array of Milestone structs
        Allocation public allocation; // struct containing vesting and unlocking details
        uint256 public milestoneAwardTotal; // total number of tokens awarded in milestones
        uint256 public milestoneUnlockedTotal; // total number of tokens unlocked in milestones
        uint256 public tokensWithdrawn; // total number of tokens withdrawn
        GovType public govType;
        bool public terminated;
        uint256 public terminationTime;
        address[] prevOwners;

        constructor(address _grantee, address _controller) {
            // Controller can be 0 for an immuatable version, but grantee cannot
            if ( _grantee == address(0)) revert MetaVesT_ZeroAddress();
            grantee = _grantee;
            controller = _controller;
            govType = GovType.vested;
        }

        function getVestingType() external view virtual returns (uint256);
        function getGoverningPower() external virtual returns (uint256);
        
        // REVIEW: implement here? Same for all variants? Possibly some of the other update functions, too?
        function updateTransferability(bool _transferable) external virtual;// onlyController;
        function updateVestingRate(uint160 _newVestingRate) external virtual;// onlyController;
        function updateUnlockRate(uint160 _newUnlockRate) external virtual;// onlyController;
        function updateStopTimes(uint48 _shortStopTime) external virtual;// onlyController;
        function confirmMilestone(uint256 _milestoneIndex) external virtual;// nonReentrant;
        function removeMilestone(uint256 _milestoneIndex) external virtual;// onlyController;
        function addMilestone(Milestone calldata _milestone) external virtual;// onlyController;
        function terminate() external virtual;// onlyController;
        function transferRights(address _newOwner) external virtual;
        function withdraw(uint256 _amount) external virtual;// nonReentrant;
        function getMetavestDetails() public view virtual returns (Allocation memory);
        function getAmountWithdrawable() external view virtual returns (uint256);

        function setGovVariables(GovType _govType) external onlyController {
            if(terminated) revert MetaVesT_AlreadyTerminated();
            govType = _govType;
            emit MetaVest_GovVariablesUpdated(govType);
        }

        function getAuthority() public view returns (address){
            return IController(controller).authority();
        }
        
        modifier onlyController() {
            if (msg.sender != controller) revert MetaVesT_OnlyController();
            _;
        }

        modifier onlyGrantee() {
            if (msg.sender != grantee) revert MetaVesT_OnlyGrantee();
            _;
        }

        modifier onlyAuthority() {
            if (msg.sender != getAuthority()) revert MetaVesT_OnlyAuthority();
            _;
        }

        /// @dev returns the minimum of `x` and `y`. See https://github.com/Vectorized/solady/blob/main/src/utils/FixedPointMathLib.sol
        function _min(uint256 x, uint256 y) internal pure returns (uint256 z) {
        /// @solidity memory-safe-assembly
        assembly {
            z := xor(x, mul(xor(x, y), lt(y, x)))
                }
        }


}
