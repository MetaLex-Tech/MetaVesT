//SPDX-License-Identifier: AGPL-3.0-only

/*
**************************************
███╗   ███╗███████╗████████╗  █████╗ ██╗   ██╗███████╗ ███████╗████████╗
████╗ ████║██╔════╝╚══██╔══╝ ██╔══██╗██║   ██║██╔════╝ ██╔════╝╚══██╔══╝
██╔████╔██║█████╗     ██║    ███████║██║   ██║█████╗   ███████╗   ██║   
██║╚██╔╝██║██╔══╝     ██║    ██╔══██║ ██╗ ██╔╝██╔══╝   ╚════██║   ██║   
██║ ╚═╝ ██║███████╗   ██║    ██║  ██║  ╚██╔═╝ ███████╗ ███████║   ██║   
╚═╝     ╚═╝╚══════╝   ╚═╝    ╚═╝  ╚═╝   ╚═╝   ╚══════╝ ╚══════╝   ╚═╝   
                                     *************************************
                                                                        */

pragma solidity ^0.8.18;

interface IConditionManager {
    function checkConditions() external returns (bool);
}

/// @notice interface for ERC-20 standard token contract, including EIP2612 permit
interface IERC20Permit {
    function allowance(
        address owner,
        address spender
    ) external view returns (uint256);

    function balanceOf(address account) external view returns (uint256);

    function permit(
        address owner,
        address spender,
        uint256 value,
        uint256 deadline,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) external;
}

/// @notice Solady's SafeTransferLib 'SafeTransfer()' and 'SafeTransferFrom()'
/// @author Solady (https://github.com/Vectorized/solady/blob/main/src/utils/SafeTransferLib.sol), license copied below
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
    function safeTransferFrom(
        address token,
        address from,
        address to,
        uint256 amount
    ) internal {
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

/// @notice Gas-optimized reentrancy protection for smart contracts.
/// @author Solady
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

/**
 * @title      MetaVesT
 *
 * @notice     BORG-compatible unlocking token allocations, vesting token options and restricted token awards
 *             on a per-BORG or per-DAO (including per-authority) basis, supporting multiple grantees and all
 *             MetaVesT types and details in one contract
 **/
contract MetaVesT is ReentrancyGuard, SafeTransferLib {
    enum MetaVesTType {
        ALLOCATION, // simple unlocking token allocation
        OPTION, // token option
        RESTRICTED // restricted token award
    }

    struct MetaVesTDetails {
        MetaVesTType metavestType;
        Allocation allocation; // Allocation details are applicable for all three MetaVesTType options
        TokenOption option;
        RestrictedTokenAward rta;
        address grantee;
        address conditionManager; // manages price conditions (option exercise or restricted token repurchase)
        bool transferable; // whether grantee can transfer their MetaVesT in whole or in part to another address
        uint8 milestoneIndex;
        bool[] milestones;
        uint256[] milestoneAwards; // per-milestone indexed lump sums of tokens available for withdrawal upon corresponding milestone completion
    }

    struct Allocation {
        uint256 tokenStreamTotal; // total number of tokens subject to linear unlocking/vesting (does NOT include 'cliffCredit' nor 'milestoneAwards')
        uint256 cliffCredit; // lump sum of tokens which become withdrawable (note: not added to 'tokensUnlocked' so as not to disrupt calculations) at 'startTime'
        uint256 tokensVotable;
        uint256 tokensStakeable;
        uint256 tokensUnlocked; // available but not withdrawn -- if OPTION this amount corresponds to 'vested'; if RESTRICTED this amount corresponds to 'unrestricted';
        uint208 unlockRate; // if OPTION this amount corresponds to 'vesting rate'; if RESTRICTED this amount corresponds to 'lapse rate'; up to 4.11 x 10^42 tokens per sec
        uint48 lastUpdate;
        address tokenContract;
        uint48 startTime; // if OPTION this amount corresponds to 'vesting start time'; if RESTRICTED this amount corresponds to 'lapse start time'
        uint48 stopTime;
    }

    struct TokenOption {
        uint256 exercisePrice;
        uint256 tokensExercised; // note: unexercised tokens == 'tokenStreamTotal' - 'tokensExercised'
        uint208 tokensForfeited;
        uint48 shortStopTime; // must be < Allocation.stopTime
        address reclaimer; // if vesting stopTime occurs before all tokens are vested, and/or long-stop date occurs and there are still vested tokens that have not been purchased, allows some authority (could be DAO or a BORG) to reclaim those tokens
    }

    struct RestrictedTokenAward {
        uint256 repurchasePrice; // denominated in _____________
        uint256 tokensRepurchasable;
        uint208 tokensRepurchased;
        uint48 shortStopTime; // repurchase deadline, must be < Allocation.stopTime
        address reclaimer; // if lapse stopTime occurs before all tokens are unrestricted, allows some authority (could be DAO or a BORG) to reclaim those tokens by paying the repurchase price
    }

    uint256 internal constant ARRAY_LENGTH_LIMIT = 20; // limit arrays & loops

    /// @notice MetaVesTController contract address, immutably tied to this MetaVesT
    address public immutable controller;

    /// @notice has permission for MetaVesTDetails parameter updates, perhaps a BORG or DAO; alternative: Auth auth or address GlobalACL. May replace itself in 'controller'
    address public authority;
    /// @notice contract address which token may be staked and used for voting, typically a DAO pool, governor, staking address, if any (otherwise address(0))
    address public dao;

    /// @notice maps grantee to transferees of their MetaVesT
    mapping(address => address[]) public transferees;

    /// @notice maps address to total amount of tokens currently locked for their ultimate benefit,
    /// initially == 'metavestDetails.allocation.tokenStreamTotal' + 'metavestDetails.allocation.cliffCredit' + 'metavestDetails.milestoneAwards'
    /// for balance calculations of grantees with respect to their MetaVesT.
    /// reduced via unlocking, cliff award, milestone awards, and transfers
    mapping(address => uint256) public amountLocked;

    /// @notice maps address to total amount of tokens
    /// @dev address mapped to (token address -> amount able to be withdrawn)
    mapping(address => mapping(address => uint256)) public amountWithdrawable;

    /// @notice address mapped to (token address -> amount of tokenUnlocked withdrawn) for unlocking calculations
    mapping(address => mapping(address => uint256))
        public unlockedAmountWithdrawn;

    /// @notice maps grantee address to their MetaVesTDetails struct
    mapping(address => MetaVesTDetails) public metavestDetails;

    ///
    /// EVENTS
    ///

    event MetaVesT_Created(MetaVesTDetails metaVesTDetails);
    event MetaVesT_Deleted(address grantee);
    event MetaVesT_MilestoneCompleted(address grantee, uint256 index);
    event MetaVesT_RepurchaseAndWithdrawal(
        address grantee,
        address tokenContract,
        uint256 amount
    );
    event MetaVesT_TransferredRights(
        address grantee,
        address transferee,
        uint256 divisor
    );
    event MetaVesT_Withdrawal(
        address withdrawer,
        address tokenContract,
        uint256 amount
    );

    ///
    /// ERRORS
    ///

    error MetaVesT_AllMilestonesComplete();
    error MetaVesT_AlreadyExists();
    error MetaVesT_AmountNotApprovedForTransferFrom();
    error MetaVesT_LengthMismatch();
    error MetaVesT_MilestoneAwardsGreaterThanTotal();
    error MetaVesT_MustLockTotalAmount();
    error MetaVesT_NonTransferable();
    error MetaVesT_OnlyAuthority();
    error MetaVesT_OnlyController();
    error MetaVesT_OnlyGrantee();
    error MetaVesT_TimeVariableError();
    error MetaVesT_TransfereeLimit();
    error MetaVesT_ZeroAddress();
    error MetaVesT_ZeroAmount();

    ///
    /// FUNCTIONS
    ///

    modifier onlyAuthority() {
        if (msg.sender != authority) revert MetaVesT_OnlyAuthority();
        _;
    }

    modifier onlyController() {
        if (msg.sender != controller) revert MetaVesT_OnlyController();
        _;
    }

    /// @notice constructs a MetaVesT framework specifying authority address, MetaVesTController contract address, and DAO staking/voting contract address (which may be the same)
    /// each individual grantee's MetaVesT will be initiated in the newly deployed MetaVesT contract, and all details in the deployed MetaVesT are amendable by 'authority'
    /** @dev ONLY ONE METAVEST PER ADDRESS; note that a conditionManager will need to be deployed for Token Option or Restricted Token Award price conditions
     *** this contract supports multiple different ERC20s, but each grantee address (including transferees) may only correspond to one MetaVesT and therefore one token*/
    /// @param _authority: address which initiates and may update each MetaVesT, such as a BORG or DAO
    /// 'authority' cannot initially be zero address, as no MetaVesTs could be initialized; however, may replace itself with zero address after creating MetaVesTs for immutability.
    /// @param _controller: MetaVesTController.sol contract address, permissioned to the 'authority' that parameterizes functionalities of each MetaVesT in this contract
    /// and may update details; contains many of the conditionals for the authority-permissioned functions
    /// @param _dao: contract address which token may be staked and used for voting, typically a DAO pool, governor, staking address. Submit address(0) for no such functionality.
    constructor(address _authority, address _controller, address _dao) {
        if (_authority == address(0) || _controller == address(0))
            revert MetaVesT_ZeroAddress();
        authority = _authority;
        controller = _controller;
        dao = _dao;
    }

    /// @notice create a MetaVesT for a grantee and lock the total token amount ('metavestDetails.allocation.tokenStreamTotal' + 'metavestDetails.allocation.cliffCredit' + 'metavestDetails.milestoneAwards') via permit()
    /// @dev requires transfer of exact amount of 'metavestDetails.allocation.tokenStreamTotal' + 'metavestDetails.allocation.cliffCredit' + 'metavestDetails.milestoneAwards' along with MetaVesTDetails;
    /// while '_depositor' need not be the 'authority' (to allow tokens to come from anywhere), only 'authority' should be able
    /// to set a grantee's 'MetaVesTDetails' by calling this function.
    /// @param _metavestDetails: MetaVesTDetails struct containing all applicable details for this '_metavestDetails.grantee'-- but MUST contain grantee, token contract, some locked amount, and start and stop time
    /// @param _depositor: depositor of the tokens, often msg.sender/originating EOA
    /// @param _deadline: deadline for usage of the permit approval signature
    /// @param v: ECDSA sig parameter
    /// @param r: ECDSA sig parameter
    /// @param s: ECDSA sig parameter
    function createMetavestAndLockTokensWithPermit(
        MetaVesTDetails calldata _metavestDetails,
        address _depositor,
        uint256 _deadline,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) external onlyAuthority nonReentrant {
        //prevent overwrite of existing MetaVesT
        if (metavestDetails[_metavestDetails.grantee].grantee != address(0))
            revert MetaVesT_AlreadyExists();
        if (_metavestDetails.grantee == address(0))
            revert MetaVesT_ZeroAddress();
        if (_deadline < block.timestamp) revert MetaVesT_TimeVariableError();
        if (
            _metavestDetails.allocation.stopTime <=
            _metavestDetails.allocation.startTime
        ) revert MetaVesT_TimeVariableError();

        // limit array length and ensure the milestone arrays are equal in length
        if (
            _metavestDetails.milestones.length > ARRAY_LENGTH_LIMIT ||
            (_metavestDetails.milestones.length !=
                _metavestDetails.milestoneAwards.length)
        ) revert MetaVesT_LengthMismatch();

        uint256 _milestoneTotal;
        for (uint256 i; i < _metavestDetails.milestones.length; ++i) {
            _milestoneTotal += _metavestDetails.milestoneAwards[i];
        }
        uint256 _total = _metavestDetails.allocation.tokenStreamTotal +
            _metavestDetails.allocation.cliffCredit +
            _milestoneTotal;
        if (_total == 0) revert MetaVesT_ZeroAmount();

        address _tokenAddr = _metavestDetails.allocation.tokenContract;
        if (_tokenAddr == address(0)) revert MetaVesT_ZeroAddress();

        metavestDetails[_metavestDetails.grantee] = _metavestDetails;
        amountLocked[_metavestDetails.grantee] += _total;

        IERC20Permit(_tokenAddr).permit(
            _depositor,
            address(this),
            _total,
            _deadline,
            v,
            r,
            s
        );
        safeTransferFrom(_tokenAddr, _depositor, address(this), _total);
        emit MetaVesT_Created(_metavestDetails);
    }

    /// @notice for 'authority' to create a MetaVesT for a grantee and lock the total token amount ('metavestDetails.allocation.tokenStreamTotal' + 'metavestDetails.allocation.cliffCredit' + 'metavestDetails.milestoneAwards')
    /// @dev msg.sender ('authority') must have approved address(this) for 'metavestDetails.allocation.tokenStreamTotal' + 'metavestDetails.allocation.cliffCredit' + 'metavestDetails.milestoneAwards' in '_metavestDetails.allocation.tokenContract' prior to calling this function;
    /// requires transfer of exact amount of 'metavestDetails.allocation.tokenStreamTotal' + 'metavestDetails.allocation.cliffCredit' + 'metavestDetails.milestoneAwards' along with MetaVesTDetails;
    /// @param _metavestDetails: MetaVesTDetails struct containing all applicable details for this '_metavestDetails.grantee'-- but MUST contain grantee, token contract, amount, and start and stop time
    function createMetavestAndLockTokens(
        MetaVesTDetails calldata _metavestDetails
    ) external onlyAuthority {
        //prevent overwrite of existing MetaVesT
        if (metavestDetails[_metavestDetails.grantee].grantee != address(0))
            revert MetaVesT_AlreadyExists();
        if (_metavestDetails.grantee == address(0))
            revert MetaVesT_ZeroAddress();
        if (
            _metavestDetails.allocation.stopTime <=
            _metavestDetails.allocation.startTime
        ) revert MetaVesT_TimeVariableError();
        // limit array length and ensure the milestone arrays are equal in length
        if (
            _metavestDetails.milestones.length > ARRAY_LENGTH_LIMIT ||
            (_metavestDetails.milestones.length !=
                _metavestDetails.milestoneAwards.length)
        ) revert MetaVesT_LengthMismatch();

        uint256 _milestoneTotal;
        for (uint256 i; i < _metavestDetails.milestones.length; ++i) {
            _milestoneTotal += _metavestDetails.milestoneAwards[i];
        }
        uint256 _total = _metavestDetails.allocation.tokenStreamTotal +
            _metavestDetails.allocation.cliffCredit +
            _milestoneTotal;
        if (_total == 0) revert MetaVesT_ZeroAmount();

        address _tokenAddr = _metavestDetails.allocation.tokenContract;
        if (_tokenAddr == address(0)) revert MetaVesT_ZeroAddress();
        if (
            IERC20Permit(_tokenAddr).allowance(msg.sender, address(this)) <
            _total ||
            IERC20Permit(_tokenAddr).balanceOf(msg.sender) < _total
        ) revert MetaVesT_AmountNotApprovedForTransferFrom();

        metavestDetails[_metavestDetails.grantee] = _metavestDetails;
        amountLocked[_metavestDetails.grantee] += _total;

        safeTransferFrom(_tokenAddr, msg.sender, address(this), _total);
        emit MetaVesT_Created(_metavestDetails);
    }

    /// @notice for the applicable authority to update this MetaVesT's details via the controller
    /// @dev conditionals for this function are in the 'controller'
    /// @param _grantee: address of grantee whose MetaVesT is being updated
    /// @param _metavestDetails: MetaVesTDetails struct
    function updateMetavestDetails(
        address _grantee,
        MetaVesTDetails calldata _metavestDetails
    ) external onlyController {
        metavestDetails[_grantee] = _metavestDetails;
    }

    /// @notice for the applicable authority to repurchase tokens from this '_grantee''s restricted token award MetaVesT
    /// @dev conditionals for this function are in the 'controller'; repurchased tokens are sent to 'authority'
    /// @param _grantee: address of grantee whose tokens are being repurchased
    function repurchaseTokens(
        address _grantee
    ) external onlyController nonReentrant {
        uint256 _amount = metavestDetails[_grantee].rta.tokensRepurchasable;
        delete metavestDetails[_grantee].rta.tokensRepurchasable;
        metavestDetails[_grantee].allocation.tokenStreamTotal -= _amount;
        metavestDetails[_grantee].rta.tokensRepurchased += uint208(_amount);
        amountLocked[_grantee] -= _amount;

        if (transferees[_grantee].length != 0) {
            for (uint256 i; i < transferees[_grantee].length; ++i) {
                address _addr = transferees[_grantee][i];
                uint256 _transfereeAmount = metavestDetails[_addr]
                    .rta
                    .tokensRepurchasable;
                delete metavestDetails[_addr].rta.tokensRepurchasable;
                metavestDetails[_addr]
                    .allocation
                    .tokenStreamTotal -= _transfereeAmount;
                metavestDetails[_addr].rta.tokensRepurchased += uint208(
                    _transfereeAmount
                );
                amountLocked[_grantee] -= _transfereeAmount;
                _amount += _transfereeAmount;
            }
            safeTransfer(
                metavestDetails[_grantee].allocation.tokenContract,
                authority,
                _amount
            );
            emit MetaVesT_RepurchaseAndWithdrawal(
                _grantee,
                metavestDetails[_grantee].allocation.tokenContract,
                _amount
            );
        }
    }

    /// @notice for the applicable authority to revoke this '_grantee''s MetaVesT via the controller
    /// @dev conditionals for this function are in the 'controller'; makes all unlockedTokens for such grantee withdrawable then sends them to grantee,
    /// so as to avoid a mapping overwrite if the grantee's revoked MetaVesT is replaced with a new one before they can withdraw.
    /// Returns remainder to 'authority'
    /// @param _grantee: address of grantee whose MetaVesT is being revoked
    function revokeMetavest(
        address _grantee
    ) external onlyController nonReentrant {
        // refresh '_grantee's' and all transferees' metavests first
        refreshMetavest(_grantee);
        MetaVesTDetails memory _metavestDetails = metavestDetails[_grantee];

        // calculate amount to send to '_grantee'
        uint256 _amt = _metavestDetails.allocation.tokensUnlocked +
            amountWithdrawable[_grantee][
                _metavestDetails.allocation.tokenContract
            ];

        // calculate remainder to be returned to 'authority'
        // add remaining unsatisfied milestone awards to the remainder
        // iterating through entire milestones array is okay as already withdrawn amounts were deleted
        uint256 _milestoneTotal;
        if (_metavestDetails.milestones.length != 0)
            for (uint256 i; i < _metavestDetails.milestones.length; ++i) {
                _milestoneTotal += _metavestDetails.milestoneAwards[i];
            }
        uint256 _remainder = (_metavestDetails.allocation.tokenStreamTotal -
            _metavestDetails.allocation.tokensUnlocked) + _milestoneTotal;

        // delete all mappings for '_grantee'
        delete metavestDetails[_grantee];
        delete amountWithdrawable[_grantee][
            _metavestDetails.allocation.tokenContract
        ];
        delete unlockedAmountWithdrawn[_grantee][
            _metavestDetails.allocation.tokenContract
        ];

        if (transferees[_grantee].length != 0) {
            for (uint256 x; x < transferees[_grantee].length; ++x) {
                address _addr = transferees[_grantee][x];
                uint256 _transfereeAmt = metavestDetails[_addr]
                    .allocation
                    .tokensUnlocked +
                    amountWithdrawable[_addr][
                        _metavestDetails.allocation.tokenContract
                    ];
                if (_metavestDetails.milestones.length != 0)
                    // milestone length will be the same for a transferee
                    for (
                        uint256 i;
                        i < _metavestDetails.milestones.length;
                        ++i
                    ) {
                        _remainder += metavestDetails[_addr].milestoneAwards[i];
                    }
                _remainder +=
                    metavestDetails[_addr].allocation.tokenStreamTotal -
                    metavestDetails[_addr].allocation.tokensUnlocked;

                // delete all mappings for '_addr'
                delete metavestDetails[_addr];
                delete amountWithdrawable[_addr][
                    _metavestDetails.allocation.tokenContract
                ];
                delete unlockedAmountWithdrawn[_addr][
                    _metavestDetails.allocation.tokenContract
                ];
                safeTransfer(
                    _metavestDetails.allocation.tokenContract,
                    _addr,
                    _transfereeAmt
                );

                emit MetaVesT_Deleted(_addr);
                emit MetaVesT_Withdrawal(
                    _addr,
                    _metavestDetails.allocation.tokenContract,
                    _transfereeAmt
                );
            }
        }

        delete transferees[_grantee];

        safeTransfer(_metavestDetails.allocation.tokenContract, _grantee, _amt);
        safeTransfer(
            _metavestDetails.allocation.tokenContract,
            authority,
            _remainder
        );

        emit MetaVesT_Deleted(_grantee);
        emit MetaVesT_Withdrawal(
            _grantee,
            _metavestDetails.allocation.tokenContract,
            _amt
        );
        emit MetaVesT_Withdrawal(
            authority,
            _metavestDetails.allocation.tokenContract,
            _remainder
        );
    }

    /// @notice for 'controller' to confirm grantee has completed the current milestone (or simple a milestone, if milestones are not chronological)
    /// also unlocking the the tokens for such milestone, including any transferees
    function confirmMilestone(address _grantee) external onlyController {
        MetaVesTDetails memory _metavestDetails = metavestDetails[_grantee];
        uint256 _index = _metavestDetails.milestoneIndex;
        if (_index == metavestDetails[_grantee].milestones.length)
            revert MetaVesT_AllMilestonesComplete();

        unchecked {
            amountWithdrawable[_grantee][
                _metavestDetails.allocation.tokenContract
            ] += _metavestDetails.milestoneAwards[_index]; // cannot overflow as milestoneAwards cannot cumulatively be greater that tokenStreamTotal
            amountLocked[_metavestDetails.grantee] -= _metavestDetails
                .milestoneAwards[_index]; // cannot underflow as milestoneAwards cannot be cumulatively be greater than the amountLocked
            ++metavestDetails[_grantee].milestoneIndex; // will not overflow on human timelines/milestone array length is limited
        }
        //delete award after adding to amount withdrawable and deducting from amount locked
        delete metavestDetails[_grantee].milestoneAwards[_index];

        // if claims were transferred, make similar updates (start and end time will be the same) for each transferee of this '_grantee'
        if (transferees[_grantee].length != 0) {
            for (uint256 i; i < transferees[_grantee].length; ++i) {
                address _addr = transferees[_grantee][i];
                amountWithdrawable[_addr][
                    _metavestDetails.allocation.tokenContract
                ] += metavestDetails[_addr].milestoneAwards[_index];
                amountLocked[_addr] -= metavestDetails[_addr].milestoneAwards[
                    _index
                ];

                //delete award after adding to amount withdrawable and deducting from amount locked
                delete metavestDetails[_addr].milestoneAwards[_index];
            }
        }

        emit MetaVesT_MilestoneCompleted(_grantee, _index);
    }

    /////////////////
    //// NEED MORE GRANULAR TRANSFER AMOUNT ABILITY
    ////////////////
    /// @notice allows a grantee to transfer part or all of their MetaVesT to a '_transferee' if this MetaVest has transferability enabled
    /// @param _divisor: divisor corresponding to the grantee's fraction of their claim transferred via this function; i.e. for a transfer of 25% of a claim, submit '4'; to transfer the entire MetaVesT, submit '1'
    /// @param _transferee: address to which the claim is being transferred, that will have a new MetaVesT created
    function transferRights(uint256 _divisor, address _transferee) external {
        //prevent overwrite of existing MetaVesT
        if (metavestDetails[_transferee].grantee != address(0))
            revert MetaVesT_AlreadyExists();
        MetaVesTDetails memory _metavestDetails = metavestDetails[msg.sender];
        if (
            _metavestDetails.grantee == address(0) ||
            msg.sender != _metavestDetails.grantee
        ) revert MetaVesT_OnlyGrantee();
        if (!_metavestDetails.transferable) revert MetaVesT_NonTransferable();
        if (_transferee == address(0)) revert MetaVesT_ZeroAddress();
        if (transferees[msg.sender].length > ARRAY_LENGTH_LIMIT)
            revert MetaVesT_TransfereeLimit();

        // update the current amountWithdrawable, if the msg.sender chooses to include it in the transfer by not first calling 'withdrawAll'
        uint256 _withdrawableTransferred = amountWithdrawable[msg.sender][
            _metavestDetails.allocation.tokenContract
        ] / _divisor;

        amountWithdrawable[_transferee][
            _metavestDetails.allocation.tokenContract
        ] = _withdrawableTransferred;
        amountWithdrawable[msg.sender][
            _metavestDetails.allocation.tokenContract
        ] -= _withdrawableTransferred;

        // update unlockedAmountWithdrawn and amountLocked similarly
        uint256 _unlockedWithdrawnTransferred = unlockedAmountWithdrawn[
            msg.sender
        ][_metavestDetails.allocation.tokenContract] / _divisor;

        unlockedAmountWithdrawn[_transferee][
            _metavestDetails.allocation.tokenContract
        ] = _unlockedWithdrawnTransferred;
        unlockedAmountWithdrawn[msg.sender][
            _metavestDetails.allocation.tokenContract
        ] -= _unlockedWithdrawnTransferred;

        uint256 _lockedAmtTransferred = amountLocked[msg.sender] / _divisor;
        amountLocked[_transferee] = _lockedAmtTransferred;
        amountLocked[msg.sender] -= _lockedAmtTransferred;

        // transferee's MetaVesT should mirror the calling grantee's except for amounts and grantee address
        _metavestDetails.grantee = _transferee;
        _metavestDetails.allocation.tokenStreamTotal =
            _metavestDetails.allocation.tokenStreamTotal /
            _divisor;
        _metavestDetails.allocation.cliffCredit =
            _metavestDetails.allocation.cliffCredit /
            _divisor;
        _metavestDetails.allocation.tokensVotable =
            _metavestDetails.allocation.tokensVotable /
            _divisor;
        _metavestDetails.allocation.tokensStakeable =
            _metavestDetails.allocation.tokensStakeable /
            _divisor;
        _metavestDetails.allocation.tokensUnlocked =
            _metavestDetails.allocation.tokensUnlocked /
            _divisor;
        if (_metavestDetails.rta.tokensRepurchasable != 0)
            _metavestDetails.rta.tokensRepurchasable =
                _metavestDetails.rta.tokensRepurchasable /
                _divisor;
        if (_metavestDetails.milestones.length != 0) {
            for (uint256 i; i < _metavestDetails.milestones.length; ++i) {
                _metavestDetails.milestoneAwards[i] =
                    _metavestDetails.milestoneAwards[i] /
                    _divisor;
                // update grantee's array within same loop
                metavestDetails[msg.sender].milestoneAwards[
                    i
                ] -= _metavestDetails.milestoneAwards[i];
            }
        }

        //update caller's MetaVesT by subtracting the amounts in transferee's MetaVesT
        metavestDetails[msg.sender]
            .allocation
            .tokenStreamTotal -= _metavestDetails.allocation.tokenStreamTotal;
        metavestDetails[msg.sender].allocation.cliffCredit -= _metavestDetails
            .allocation
            .cliffCredit;
        metavestDetails[msg.sender].allocation.tokensVotable -= _metavestDetails
            .allocation
            .tokensVotable;
        metavestDetails[msg.sender]
            .allocation
            .tokensStakeable -= _metavestDetails.allocation.tokensStakeable;
        metavestDetails[msg.sender]
            .allocation
            .tokensUnlocked -= _metavestDetails.allocation.tokensUnlocked;
        metavestDetails[msg.sender]
            .allocation
            .tokenStreamTotal -= _metavestDetails.allocation.tokenStreamTotal;
        if (_metavestDetails.rta.tokensRepurchasable != 0)
            metavestDetails[msg.sender]
                .rta
                .tokensRepurchasable -= _metavestDetails
                .rta
                .tokensRepurchasable;

        transferees[msg.sender].push(_transferee);

        //create '_transferee''s MetaVesT
        _createMetavestViaTransfer(_metavestDetails);

        emit MetaVesT_TransferredRights(msg.sender, _transferee, _divisor);
    }

    ////////////////
    // short stop dates
    ////////////////
    /// @notice refresh the time-contingent details and amounts of '_grantee''s MetaVesT
    /// @dev updates the grantee's (and any transferees') 'tokensUnlocked', and whether 'cliffCredit' is added to 'amountWithdrawable'
    /// @param _grantee: address whose MetaVesT is being refreshed
    function refreshMetavest(address _grantee) public {
        MetaVesTDetails memory _metavestDetails = metavestDetails[_grantee];

        // check short stop times

        uint256 _start = uint256(_metavestDetails.allocation.startTime);
        uint256 _end = uint256(_metavestDetails.allocation.stopTime);

        // calculate unlock amounts, subtracting unlocked and withdrawn amounts
        if (block.timestamp <= _start) {
            metavestDetails[_grantee].allocation.tokensUnlocked = 0;
        } else if (block.timestamp >= _end) {
            metavestDetails[_grantee].allocation.tokensUnlocked =
                _metavestDetails.allocation.tokenStreamTotal -
                unlockedAmountWithdrawn[_grantee][
                    _metavestDetails.allocation.tokenContract
                ];
        } else {
            // new tokensUnlocked = (unlockRate * passed time since start) - (pre-existing unlocked amount + unlocked amount already withdrawn)
            uint256 _newlyUnlocked = (_metavestDetails.allocation.unlockRate *
                (block.timestamp - _start)) -
                (_metavestDetails.allocation.tokensUnlocked +
                    unlockedAmountWithdrawn[_grantee][
                        _metavestDetails.allocation.tokenContract
                    ]);
            // make sure unlocked calculation does not surpass the token stream total
            if (_newlyUnlocked > _metavestDetails.allocation.tokenStreamTotal)
                metavestDetails[_grantee]
                    .allocation
                    .tokensUnlocked = _metavestDetails
                    .allocation
                    .tokenStreamTotal;
            else
                metavestDetails[_grantee]
                    .allocation
                    .tokensUnlocked += _newlyUnlocked; // add the newly unlocked amount rather than re-assigning variable entirely as pre-existing unlocked amount was already subtracted

            amountWithdrawable[_grantee][
                _metavestDetails.allocation.tokenContract
            ] += _metavestDetails.allocation.cliffCredit;
            // delete cliff credit and remove it (and the new unlocked amount) from amountLocked mapping. After the cliff is added the first time, later refreshes will simply pass 0
            amountLocked[_grantee] -=
                _metavestDetails.allocation.cliffCredit +
                metavestDetails[_grantee].allocation.tokensUnlocked;
            delete metavestDetails[_grantee].allocation.cliffCredit;
        }

        // if claims were transferred, make similar updates (start and end time will be the same) for each transferee
        if (transferees[_grantee].length != 0) {
            for (uint256 i; i < transferees[_grantee].length; ++i) {
                address _addr = transferees[_grantee][i];
                uint256 _totalStream = metavestDetails[_addr]
                    .allocation
                    .tokenStreamTotal;
                if (block.timestamp <= _start) {
                    metavestDetails[_addr].allocation.tokensUnlocked = 0;
                } else if (block.timestamp >= _end) {
                    metavestDetails[_addr].allocation.tokensUnlocked =
                        _totalStream -
                        unlockedAmountWithdrawn[_addr][
                            _metavestDetails.allocation.tokenContract
                        ];
                } else {
                    // tokensUnlocked = (unlockRate * passed time since start) - (pre-existing unlocked amount + unlocked amount already withdrawn)
                    uint256 _newlyUnlocked = (_metavestDetails
                        .allocation
                        .unlockRate * (block.timestamp - _start)) -
                        (metavestDetails[_addr].allocation.tokensUnlocked +
                            unlockedAmountWithdrawn[_addr][
                                _metavestDetails.allocation.tokenContract
                            ]);
                    // make sure unlocked calculation does not surpass the token stream total
                    if (_newlyUnlocked > _totalStream)
                        metavestDetails[_addr]
                            .allocation
                            .tokensUnlocked = _totalStream;
                    else
                        metavestDetails[_addr]
                            .allocation
                            .tokensUnlocked += _newlyUnlocked;

                    amountWithdrawable[_addr][
                        _metavestDetails.allocation.tokenContract
                    ] += metavestDetails[_addr].allocation.cliffCredit;
                    // delete cliff credit and remove it (and the new unlocked amount) from amountLocked mapping. After the cliff is added the first time, later refreshes will simply pass 0
                    amountLocked[_addr] -=
                        metavestDetails[_addr].allocation.cliffCredit +
                        metavestDetails[_addr].allocation.tokensUnlocked;
                    delete metavestDetails[_addr].allocation.cliffCredit;
                }
            }
        }
    }

    ///
    /// IN PROCESS
    ///
    /// function exerciseOption() external (remember price call via conditionManager), only grantee, check transferees, update mappings (becomes amountWithdrawable)
    ///
    /// in controller: function repurchase() external (remember price call via conditionManager), only authority, check transferees, update mappings
    ///

    /// @notice allows an address to withdraw their 'amountWithdrawable' of their corresponding token in their MetaVesT
    /// @dev because each address can only have one MetaVesT, the amountWithdrawable corresponds to the 'metavestDetails[msg.sender].allocation.tokenContract'
    function withdrawAll() external nonReentrant {
        refreshMetavest(msg.sender);
        MetaVesTDetails memory _metavest = metavestDetails[msg.sender];
        if (msg.sender != _metavest.grantee) revert MetaVesT_OnlyGrantee();

        // add newly unlocked tokens to amountWithdrawable and unlockedAmountWithdrawn
        amountWithdrawable[msg.sender][
            _metavest.allocation.tokenContract
        ] += _metavest.allocation.tokensUnlocked;
        unlockedAmountWithdrawn[msg.sender][
            _metavest.allocation.tokenContract
        ] += _metavest.allocation.tokensUnlocked;

        uint256 _amt = amountWithdrawable[msg.sender][
            _metavest.allocation.tokenContract
        ];
        if (_amt == 0) revert MetaVesT_ZeroAmount();

        // delete 'tokensUnlocked' and 'amountWithdrawable' as all are being withdrawn now
        delete metavestDetails[msg.sender].allocation.tokensUnlocked;
        delete amountWithdrawable[msg.sender][
            _metavest.allocation.tokenContract
        ];

        // if no amountLocked remains, delete the metavestDetails for this msg.sender as now all tokens are withdrawn as well (so we know amountWithdrawable == 0)
        if (amountLocked[msg.sender] == 0) delete metavestDetails[msg.sender];
        emit MetaVesT_Deleted(msg.sender);

        safeTransfer(_metavest.allocation.tokenContract, msg.sender, _amt);
        emit MetaVesT_Withdrawal(
            msg.sender,
            _metavest.allocation.tokenContract,
            _amt
        );
    }

    /// @notice creates a MetaVesT via 'transferRights()' by a current grantee
    /// @dev no need to transfer tokens to this address nor update lockedTokens mapping as this MetaVest is created from tokens already in address(this)
    /// @param _metavestDetails: MetaVesTDetails struct containing all applicable details for this '_metavestDetails.grantee'-- but MUST contain grantee, token contract, amount, and start and stop time
    function _createMetavestViaTransfer(
        MetaVesTDetails memory _metavestDetails
    ) internal {
        if (_metavestDetails.grantee == address(0))
            revert MetaVesT_ZeroAddress();
        if (
            _metavestDetails.allocation.stopTime <=
            _metavestDetails.allocation.startTime
        ) revert MetaVesT_TimeVariableError();
        // limit array length and ensure the milestone arrays are equal in length
        if (
            _metavestDetails.milestones.length > ARRAY_LENGTH_LIMIT ||
            (_metavestDetails.milestones.length !=
                _metavestDetails.milestoneAwards.length)
        ) revert MetaVesT_LengthMismatch();

        uint256 _milestoneTotal;
        for (uint256 i; i < _metavestDetails.milestones.length; ++i) {
            _milestoneTotal += _metavestDetails.milestoneAwards[i];
        }
        uint256 _total = _metavestDetails.allocation.tokenStreamTotal +
            _metavestDetails.allocation.cliffCredit +
            _milestoneTotal;
        if (_total == 0) revert MetaVesT_ZeroAmount();

        address _tokenAddr = _metavestDetails.allocation.tokenContract;
        if (_tokenAddr == address(0)) revert MetaVesT_ZeroAddress();

        metavestDetails[_metavestDetails.grantee] = _metavestDetails;

        emit MetaVesT_Created(_metavestDetails);
    }
}
