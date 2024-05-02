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

pragma solidity 0.8.20;

/// @notice interface to a MetaLeX condition contract
/// @dev see https://github.com/MetaLex-Tech/BORG-CORE/tree/main/src/libs/conditions
interface IConditionM {
    function checkCondition() external returns (bool);
}

interface IERC20M {
    function allowance(address owner, address spender) external view returns (uint256);

    function balanceOf(address account) external view returns (uint256);
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

/**
 * @title      MetaVesT
 *
 * @notice     BORG-compatible unlocking token allocations, vesting token options, and restricted token awards
 *             on a per-BORG (per-authority) basis, supporting multiple grantees and tokens and all
 *             MetaVesT types and details in one contract. Supports any combination of linear unlocks, lump sum grants, and conditional or milestone-based grants.
 *
 * @dev        'authority', via 'controller', has substantial controls over aspects of this contract by design, and many of the safety and
 *             design conditionals are housed in 'controller' as many of the functions are modified to be 'onlyController'. Whenever a new
 *             MetaVesT within this contract or a new milestone for a given MetaVesT is created by 'controller', the total number of corresponding
 *             tokens must be transferred with such transaction.
 **/
contract MetaVesT is ReentrancyGuard, SafeTransferLib {
    enum MetaVesTType {
        ALLOCATION, // simple unlocking token allocation
        OPTION, // token option
        RESTRICTED // restricted token award
    }

    struct MetaVesTDetails {
        address grantee; // grantee of the tokens
        bool transferable; // whether grantee can transfer their MetaVesT in whole or in part to other addresses
        MetaVesTType metavestType;
        Allocation allocation; // Allocation details are applicable for all three MetaVesTType options
        TokenOption option; // struct containing token option-specific details
        RestrictedTokenAward rta; // struct containing restricted token award-specific details
        GovEligibleTokens eligibleTokens; // struct containing bools of types of MetaVesTed tokens' governing power
        Milestone[] milestones; // array of Milestone structs
    }

    struct Allocation {
        uint256 tokenStreamTotal; // total number of tokens subject to linear vesting/restriction removal (includes cliff credits but not each 'milestoneAward')
        uint256 tokenGoverningPower; // number of tokens designated as usable in some manner in governance
        uint256 tokensVested; // vested but not withdrawn -- if RESTRICTED this amount corresponds to 'unrestricted';
        uint256 tokensUnlocked; // unlocked but not withdrawn
        uint256 vestedTokensWithdrawn; // number of tokens withdrawn that were previously 'tokensVested', for vesting calculations
        uint256 unlockedTokensWithdrawn; // number of tokens withdrawn that were previously 'tokensVested', for unlocking calculations
        uint128 vestingCliffCredit; // lump sum of tokens which become vested at 'startTime' and will be added to '_linearVested'
        uint128 unlockingCliffCredit; // lump sum of tokens which become unlocked at 'startTime' and will be added to '_linearUnlocked'
        uint160 vestingRate; // tokens per second that become vested; if RESTRICTED this amount corresponds to 'lapse rate' for tokens that become non-repurchasable
        uint48 vestingStartTime; // if RESTRICTED this amount corresponds to 'lapse start time'
        uint48 vestingStopTime; // long stop time
        uint160 unlockRate; // tokens per second that become unlocked;
        uint48 unlockStartTime; // start of the linear unlock
        uint48 unlockStopTime; // end of the linear unlock
        address tokenContract; // contract address of the ERC20 token included in the MetaVesT
    }

    struct TokenOption {
        uint256 exercisePrice; // amount of 'paymentToken' per token exercised
        uint208 tokensForfeited; // tokens able to be withdrawn by authority as no longer exercisable
        uint48 shortStopTime; // vesting stop time and exercise deadline, must be <= Allocation.stopTime, which is the long stop time at which time unexercised tokens become 'tokensForfeited'
    }

    struct RestrictedTokenAward {
        uint256 tokensRepurchasable; // amount of locked, repurchasable tokens
        uint208 repurchasePrice; // amount of 'paymentToken' per token repurchased
        uint48 shortStopTime; // lapse stop time and repurchase deadline, must be <= Allocation.stopTime, at which time 'tokensRepurchasable' == 0
    }

    struct GovEligibleTokens {
        bool nonwithdrawable; // whether 'nonwithdrawableAmount' counts towards 'tokenGoverningPower'
        bool vested; // whether 'tokensVested' counts towards 'tokenGoverningPower'
        bool unlocked; // whether 'tokensUnlocked' counts towards 'tokenGoverningPower'
    }

    struct Milestone {
        uint256 milestoneAward; // per-milestone indexed lump sums of tokens vested upon corresponding milestone completion
        bool complete; // whether the Milestone is satisfied and the 'milestoneAward' is to be released
        address[] conditionContracts; // array of contract addresses corresponding to condition(s) that must satisfied for this Milestone to be 'complete'
    }

    /// @dev limit arrays & loops for gas/size purposes
    uint256 internal constant ARRAY_LENGTH_LIMIT = 20;

    IERC20M internal immutable ipaymentToken;

    /// @notice MetaVesTController contract address, immutably tied to this MetaVesT
    address public immutable controller;

    /// @notice address of payment token used for token option exercises or restricted token repurchases
    address public immutable paymentToken;

    /// @notice authority address, may replace itself in 'controller'
    address public authority;

    /// @notice maps grantee address to their MetaVesTDetails struct
    mapping(address => MetaVesTDetails) public metavestDetails;

    /// @notice maps grantee to transferees of their MetaVesT
    mapping(address => address[]) public transferees;

    /// @notice maps grantee address to total amount of tokens in their MetaVesT which are non-withdrawable, including non-vested or locked, or unconfirmed 'milestoneAwards'
    /// @dev no need to specify token address because a grantee's paymentToken from any repurchase is always withdrawable, so this can only be their metavested token
    mapping(address => uint256) public nonwithdrawableAmount;

    /// @notice maps address to their total amount of tokens which are withdrawable from address(this)
    /// @dev address mapped to (token address -> amount able to be withdrawn)
    mapping(address => mapping(address => uint256)) public amountWithdrawable;

    /// @notice maps address to their amount of tokens exercised pursuant to a token option but not yet withdrawn
    /// @dev separate from option struct to prevent transfer and 'controller' interference
    mapping(address => uint256) internal _tokensExercised;

    /// @notice maps address to tokens unlocked via confirmed milestones, to ease unlocking calculations
    mapping(address => uint256) internal _milestoneUnlocked;

    /// @notice maps address to tokens vested via confirmed milestones, to ease vesting calculations
    mapping(address => uint256) internal _milestoneVested;

    /// @notice maps address to tokens unlocked via linear unlocking, to ease unlocking calculations. Includes 'unlockingCliffCredit' after 'unlockingStartTime'.
    mapping(address => uint256) internal _linearUnlocked;

    /// @notice maps address to tokens vested via linear vesting, to ease vesting calculations. Includes 'vestingCliffCredit' after 'vestingStartTime'.
    mapping(address => uint256) internal _linearVested;

    ///
    /// EVENTS
    ///

    event MetaVesT_Created(MetaVesTDetails metaVesTDetails);
    event MetaVesT_Deleted(address grantee);
    event MetaVesT_ExercisePriceUpdated(address grantee, uint256 newPrice);
    event MetaVesT_MilestoneAdded(address grantee, Milestone milestone);
    event MetaVesT_MilestoneCompleted(address grantee, uint256 index);
    event MetaVesT_MilestoneRemoved(address grantee, uint8 milestoneIndex);
    event MetaVesT_OptionExercised(address grantee, address tokenContract, uint256 amount);
    event MetaVesT_RepurchaseAndWithdrawal(address grantee, address tokenContract, uint256 amount);
    event MetaVesT_RepurchasePriceUpdated(address grantee, uint256 newPrice);
    event MetaVesT_StopTimesUpdated(
        address grantee,
        uint48 unlockingStopTime,
        uint48 vestingStopTime,
        uint48 shortStopTime
    );
    event MetaVesT_TransferabilityUpdated(address grantee, bool isTransferable);
    event MetaVesT_TransferredRights(address grantee, address transferee, uint128 divisor);
    event MetaVesT_UnlockRateUpdated(address grantee, uint208 unlockRate);
    event MetaVesT_VestingRateUpdated(address grantee, uint208 vestingRate);
    event MetaVesT_Withdrawal(address withdrawer, address tokenContract, uint256 amount);

    ///
    /// ERRORS
    ///

    error MetaVesT_AlreadyExists();
    error MetaVesT_AmountGreaterThanAvailable();
    error MetaVesT_AmountGreaterThanWithdrawable();
    error MetaVesT_AmountNotApprovedForTransferFrom();
    error MetaVesT_ConditionNotSatisfied(address conditionContract);
    error MetaVesT_MilestoneIndexCompletedOrDoesNotExist();
    error MetaVesT_NonTransferable();
    error MetaVesT_NoMetaVesT();
    error MetaVesT_NoTokenOption();
    error MetaVesT_OnlyController();
    error MetaVesT_OnlyGrantee();
    error MetaVesT_TransfereeLimit();
    error MetaVesT_ZeroAddress();
    error MetaVesT_ZeroAmount();
    error MetaVesT_ZeroPrice();

    ///
    /// FUNCTIONS
    ///

    modifier onlyController() {
        if (msg.sender != controller) revert MetaVesT_OnlyController();
        _;
    }

    /// @notice constructs a MetaVesT framework specifying authority address, MetaVesTController contract address, and payment token contract address
    /// each individual grantee's MetaVesT will be initiated in the 'controller' contract
    /** @dev ONLY ONE METAVEST PER ADDRESS;
     *** this contract supports multiple different ERC20s, but each grantee address (including transferees) may only correspond to one MetaVesT and therefore one token;
     *** for multiple metavests to a single recipient, use different/fresh addresses */
    /// @param _authority: address which initiates and may update each MetaVesT, such as a BORG or DAO, via the 'controller'
    /// 'authority' cannot initially be zero address, as no MetaVesTs could be initialized; however, may replace itself with zero address after creating MetaVesTs for immutability.
    /// @param _controller: MetaVesTController.sol contract address, permissioned to the 'authority' that parameterizes functionalities of each MetaVesT in this contract
    /// and may update details; contains many of the conditionals for the authority-permissioned functions
    /// @param _paymentToken contract address of the token used as payment/consideration for 'authority' to repurchase tokens according to a restricted token award, or for 'grantee' to exercise a token option
    constructor(address _authority, address _controller, address _paymentToken) {
        if (_authority == address(0) || _controller == address(0)) revert MetaVesT_ZeroAddress();
        authority = _authority;
        controller = _controller;
        paymentToken = _paymentToken;
        ipaymentToken = IERC20M(_paymentToken);
    }

    /// @notice creates a MetaVesT for a grantee and locks the total token amount ('metavestDetails.allocation.tokenStreamTotal' + all 'milestoneAward's)
    /// @dev see MetaVesTController for conditionals and additional comments
    /// @param _metavestDetails: MetaVesTDetails struct containing all applicable details for this '_metavestDetails.grantee'-- but MUST contain grantee, token contract, amount, and start and stop time
    /// @param _total: total amount of tokens being locked, including cliff and linear release, and total milestone awards
    function createMetavest(MetaVesTDetails calldata _metavestDetails, uint256 _total) external onlyController {
        address _grantee = _metavestDetails.grantee;
        MetaVesTDetails storage details = metavestDetails[_grantee];
        // manually copy milestones to avoid dynamic struct array -> storage error
        for (uint256 i; i < _metavestDetails.milestones.length; ++i) {
            details.milestones.push(_metavestDetails.milestones[i]);
        }

        // assign other details manually, avoiding milestones
        details.metavestType = _metavestDetails.metavestType;
        details.allocation = _metavestDetails.allocation;
        details.option = _metavestDetails.option;
        details.rta = _metavestDetails.rta;
        details.eligibleTokens = _metavestDetails.eligibleTokens;
        details.grantee = _grantee;
        details.transferable = _metavestDetails.transferable;

        nonwithdrawableAmount[_grantee] = _total;

        // ensure tokensRepurchasable is == _total, if RTA
        if (_metavestDetails.metavestType == MetaVesTType.RESTRICTED) details.rta.tokensRepurchasable = _total;

        safeTransferFrom(_metavestDetails.allocation.tokenContract, authority, address(this), _total);
        emit MetaVesT_Created(_metavestDetails);
    }

    /// @notice convenience function to get a grantee's updated 'tokenGoverningPower'
    /// @param _grantee address whose 'tokenGoverningPower' is being returned
    function getGoverningPower(address _grantee) external returns (uint256) {
        refreshMetavest(_grantee);
        return metavestDetails[_grantee].allocation.tokenGoverningPower;
    }

    /// @notice for controller to update 'authority' via its two-step functions
    /// @dev update event emitted in MetaVesTController
    /// @param _newAuthority new 'authority' address
    function updateAuthority(address _newAuthority) external onlyController {
        authority = _newAuthority;
    }

    /// @notice for 'authority', via 'controller', to toggle whether '_grantee''s MetaVesT is transferable-- does not revoke previous transfers, but does cause such transferees' MetaVesTs transferability to be similarly updated
    /// @param _grantee address whose MetaVesT's (and whose transferees' MetaVesTs') transferability is being updated
    /// @param _isTransferable whether transferability is to be updated to transferable (true) or nontransferable (false)
    function updateTransferability(address _grantee, bool _isTransferable) external onlyController {
        metavestDetails[_grantee].transferable = _isTransferable;

        // replicate for transferees
        if (transferees[_grantee].length != 0) {
            for (uint256 i; i < transferees[_grantee].length; ++i) {
                metavestDetails[transferees[_grantee][i]].transferable = _isTransferable;
            }
        }
        emit MetaVesT_TransferabilityUpdated(_grantee, _isTransferable);
    }

    /// @notice for 'controller' to update the 'unlockRate' for a '_grantee' and their transferees
    /// @dev an '_unlockRate' of 0 is permissible to enable temporary freezes of allocation unlocks by authority
    /// @param _grantee address whose MetaVesT's (and whose transferees' MetaVesTs') unlockRate is being updated
    /// @param _unlockRate token unlock rate for allocations in tokens per second
    function updateUnlockRate(address _grantee, uint160 _unlockRate) external onlyController {
        metavestDetails[_grantee].allocation.unlockRate = _unlockRate;

        // replicate for transferees
        if (transferees[_grantee].length != 0) {
            for (uint256 i; i < transferees[_grantee].length; ++i) {
                metavestDetails[transferees[_grantee][i]].allocation.unlockRate = _unlockRate;
            }
        }
        emit MetaVesT_UnlockRateUpdated(_grantee, _unlockRate);
    }

    /// @notice for 'controller' to update the 'vestingRate' for a '_grantee' and their transferees
    /// @dev a '_vestingRate' of 0 is permissible to enable temporary freezes of allocation unlocks by authority
    /// @param _grantee address whose MetaVesT's (and whose transferees' MetaVesTs') vestingRate is being updated
    /// @param _vestingRate token vesting rate, and 'lapse rate' for restricted token award
    function updateVestingRate(address _grantee, uint160 _vestingRate) external onlyController {
        metavestDetails[_grantee].allocation.vestingRate = _vestingRate;

        // replicate for transferees
        if (transferees[_grantee].length != 0) {
            for (uint256 i; i < transferees[_grantee].length; ++i) {
                metavestDetails[transferees[_grantee][i]].allocation.vestingRate = _vestingRate;
            }
        }
        emit MetaVesT_VestingRateUpdated(_grantee, _vestingRate);
    }

    /// @notice for authority to update a MetaVesT's stopTime and/or shortStopTime, as applicable (including any transferees)
    /// @dev 'controller' carries the conditional checks for '_stopTime', but note that if '_shortStopTime' has already occurred, it will be ignored rather than revert
    /// @param _grantee address of grantee whose MetaVesT is being updated
    /// @param _unlockStopTime the end of the linear unlock
    /// @param _vestingStopTime if allocation this is the end of the linear unlock; if token option or restricted token award this is the 'long stop time'
    /// @param _shortStopTime if token option, vesting stop time and exercise deadline; if restricted token award, lapse stop time and repurchase deadline -- must be <= stopTime
    function updateStopTimes(
        address _grantee,
        uint48 _unlockStopTime,
        uint48 _vestingStopTime,
        uint48 _shortStopTime
    ) external onlyController {
        MetaVesTDetails storage details = metavestDetails[_grantee];
        details.allocation.unlockStopTime = _unlockStopTime;
        details.allocation.vestingStopTime = _vestingStopTime;
        MetaVesTType _type = details.metavestType;
        uint256 _transfereesLen = transferees[_grantee].length;

        // ensure both the existing and new short stop times haven't been met, or ignore if MetaVesTType == ALLOCATION
        if (
            _type == MetaVesTType.OPTION &&
            details.option.shortStopTime > block.timestamp &&
            _shortStopTime > block.timestamp
        ) {
            details.option.shortStopTime = _shortStopTime;
            if (_transfereesLen != 0) {
                for (uint256 i; i < _transfereesLen; ++i) {
                    metavestDetails[transferees[_grantee][i]].allocation.unlockStopTime = _unlockStopTime;
                    metavestDetails[transferees[_grantee][i]].allocation.vestingStopTime = _vestingStopTime;
                    metavestDetails[transferees[_grantee][i]].option.shortStopTime = _shortStopTime;
                }
            }
        } else if (
            _type == MetaVesTType.RESTRICTED &&
            details.rta.shortStopTime > block.timestamp &&
            _shortStopTime > block.timestamp
        ) {
            details.rta.shortStopTime = _shortStopTime;
            if (_transfereesLen != 0) {
                for (uint256 i; i < _transfereesLen; ++i) {
                    metavestDetails[transferees[_grantee][i]].allocation.unlockStopTime = _unlockStopTime;
                    metavestDetails[transferees[_grantee][i]].allocation.vestingStopTime = _vestingStopTime;
                    metavestDetails[transferees[_grantee][i]].rta.shortStopTime = _shortStopTime;
                }
            }
        } else {
            if (_transfereesLen != 0) {
                for (uint256 i; i < _transfereesLen; ++i) {
                    metavestDetails[transferees[_grantee][i]].allocation.unlockStopTime = _unlockStopTime;
                    metavestDetails[transferees[_grantee][i]].allocation.vestingStopTime = _vestingStopTime;
                }
            }
        }
        emit MetaVesT_StopTimesUpdated(_grantee, _unlockStopTime, _vestingStopTime, _shortStopTime);
    }

    /// @notice for anyone to check whether grantee has completed a milestone, provided any condition contracts are satisfied,
    /// making the tokens for such milestone unlocked, including any transferees.
    /// @dev this function is not 'onlyController' permissioned because that functionality is possible via milestones.conditionContracts,
    /// by using a signatureCondition contract. This way, for milestones with objective conditions (such as a time or data condition), the grantee does not need to prompt
    /// the 'authority' to confirm their milestone
    /// @param _grantee address of grantee whose milestone is being confirmed
    /// @param _milestoneIndex element of 'milestones' array that is being confirmed
    function confirmMilestone(address _grantee, uint8 _milestoneIndex) external nonReentrant {
        refreshMetavest(_grantee);
        MetaVesTDetails storage details = metavestDetails[_grantee];
        Milestone[] memory _milestones = details.milestones;

        if (_milestoneIndex >= _milestones.length || _milestones[_milestoneIndex].complete)
            revert MetaVesT_MilestoneIndexCompletedOrDoesNotExist();

        // perform any applicable condition checks, including whether 'authority' has a signatureCondition
        for (uint256 i; i < _milestones[_milestoneIndex].conditionContracts.length; ++i) {
            if (!IConditionM(_milestones[_milestoneIndex].conditionContracts[i]).checkCondition())
                revert MetaVesT_ConditionNotSatisfied(_milestones[_milestoneIndex].conditionContracts[i]);
        }

        uint256 _milestoneAward = _milestones[_milestoneIndex].milestoneAward;
        unchecked {
            details.allocation.tokensVested += _milestoneAward;
            details.allocation.tokensUnlocked += _milestoneAward;
            _milestoneVested[_grantee] += _milestoneAward;
            _milestoneUnlocked[_grantee] += _milestoneAward;
        }

        //delete award and mark complete after adding to unlocked amount and deducting from amount locked
        delete details.milestones[_milestoneIndex].milestoneAward;
        details.milestones[_milestoneIndex].complete = true;

        // if claims were transferred, make similar updates (start and end time will be the same) for each transferee of this '_grantee'
        // condition contracts are the same, so no need to re-check in the same txn
        if (transferees[_grantee].length != 0) {
            for (uint256 i; i < transferees[_grantee].length; ++i) {
                address _transferee = transferees[_grantee][i];
                MetaVesTDetails storage transfereeDetails = metavestDetails[_transferee];
                uint256 _transfereeMilestoneAward = transfereeDetails.milestones[_milestoneIndex].milestoneAward;
                unchecked {
                    transfereeDetails.allocation.tokensVested += _transfereeMilestoneAward;
                    transfereeDetails.allocation.tokensUnlocked += _transfereeMilestoneAward;
                    _milestoneVested[_transferee] += _transfereeMilestoneAward;
                    _milestoneUnlocked[_transferee] += _transfereeMilestoneAward;
                }
                //delete award after adding to amount withdrawable and deducting from amount locked, and mark complete
                delete transfereeDetails.milestones[_milestoneIndex].milestoneAward;
                transfereeDetails.milestones[_milestoneIndex].complete = true;
            }
        }

        emit MetaVesT_MilestoneCompleted(_grantee, _milestoneIndex);
    }

    /// @notice for the applicable authority to remove a MetaVesT's milestone via the controller
    /// @dev conditionals and further comments for this function are in the 'controller'; since only an uncompleted milestone may be removed, 'milestoneIndex' doesn't need to be adjusted
    /// @param _milestoneIndex element of the 'milestones' array to be removed
    /// @param _grantee address of grantee whose MetaVesT is being updated
    /// @param _tokenContract token contract address of the applicable milestoneAward
    function removeMilestone(uint8 _milestoneIndex, address _grantee, address _tokenContract) external onlyController {
        MetaVesTDetails storage details = metavestDetails[_grantee];
        uint256 _removedMilestoneAmount = details.milestones[_milestoneIndex].milestoneAward;

        amountWithdrawable[controller][_tokenContract] += _removedMilestoneAmount;
        nonwithdrawableAmount[_grantee] -= _removedMilestoneAmount;

        delete details.milestones[_milestoneIndex];

        // replicate for transferees
        if (transferees[_grantee].length != 0) {
            for (uint256 i; i < transferees[_grantee].length; ++i) {
                address _transferee = transferees[_grantee][i];
                MetaVesTDetails storage transfereeDetails = metavestDetails[_transferee];
                uint256 _transfereeRemovedMilestoneAmount = transfereeDetails
                    .milestones[_milestoneIndex]
                    .milestoneAward;

                amountWithdrawable[controller][_tokenContract] += _transfereeRemovedMilestoneAmount;
                nonwithdrawableAmount[_transferee] -= _transfereeRemovedMilestoneAmount;

                delete transfereeDetails.milestones[_milestoneIndex];

                emit MetaVesT_MilestoneRemoved(_transferee, _milestoneIndex);
            }
        }
        emit MetaVesT_MilestoneRemoved(_grantee, _milestoneIndex);
    }

    /// @notice for the applicable authority to add a milestone to a MetaVesT's via the controller
    /// @dev conditionals and further comments for this function are in the 'controller
    /// @param _grantee address of grantee whose MetaVesT is being updated
    /// @param _milestone new Milestone struct added for '_grantee', to be added to their 'milestones' array
    function addMilestone(address _grantee, Milestone calldata _milestone) external onlyController {
        nonwithdrawableAmount[_grantee] += _milestone.milestoneAward;
        MetaVesTDetails storage details = metavestDetails[_grantee];

        details.milestones.push(_milestone);

        // add to milestone array length but not milestoneAward for current transferees as their relative divisor cannot be known, grantee receives the full benefit of the new award
        if (transferees[_grantee].length != 0) {
            for (uint256 i; i < transferees[_grantee].length; ++i) {
                address _transferee = transferees[_grantee][i];
                Milestone[] storage transfereeMilestones = metavestDetails[_transferee].milestones;
                transfereeMilestones.push(_milestone);
                delete transfereeMilestones[transfereeMilestones.length].milestoneAward;
            }
        }
        emit MetaVesT_MilestoneAdded(_grantee, _milestone);
    }

    /// @notice for the controller to update either exercisePrice or repurchasePrice for a '_grantee' and their transferees, as applicable depending on the MetaVesTType
    /// @param _grantee address of grantee whose applicable price is being updated
    /// @param _newPrice new price (in 'paymentToken' per token)
    function updatePrice(address _grantee, uint128 _newPrice) external onlyController {
        MetaVesTType _type = metavestDetails[_grantee].metavestType;
        uint256 _transfereesLen = transferees[_grantee].length;
        if (_type == MetaVesTType.OPTION) {
            metavestDetails[_grantee].option.exercisePrice = _newPrice;
            // update transferees' price
            if (_transfereesLen != 0) {
                for (uint256 i; i < _transfereesLen; ++i) {
                    metavestDetails[transferees[_grantee][i]].option.exercisePrice = _newPrice;
                }
            }
            emit MetaVesT_ExercisePriceUpdated(_grantee, _newPrice);
        } else if (_type == MetaVesTType.RESTRICTED) {
            metavestDetails[_grantee].rta.repurchasePrice = _newPrice;
            // update transferees' price
            if (_transfereesLen != 0) {
                for (uint256 i; i < _transfereesLen; ++i) {
                    metavestDetails[transferees[_grantee][i]].rta.repurchasePrice = _newPrice;
                }
            }
            emit MetaVesT_RepurchasePriceUpdated(_grantee, _newPrice);
        } else revert MetaVesT_ZeroPrice();
    }

    /// @notice for 'authority' (via 'controller') to repurchase tokens from this '_grantee''s restricted token award MetaVesT; '_amount' of 'paymentToken' will be transferred to this address and
    /// will be withdrawable by 'grantee'
    /// @dev conditionals for this function (including short stop time check and '_divisor' != 0) are in the 'controller'; repurchased tokens are sent to 'authority';
    /// note that 'refreshMetavest' is called in 'controller' so the purchase amount will be the same as calculated there and in this function, and that for transferees of transferees,
    /// 'authority' will need to initiate another repurchase from 'controller' (which is not subject to consent or condition checks)
    /// @param _grantee address of grantee whose tokens are being repurchased
    /// @param _divisor divisor corresponding to the fraction of _grantee's repurchasable tokens being repurchased by 'authority'; to repurchase the full available amount, submit '1'
    function repurchaseTokens(address _grantee, uint256 _divisor) external onlyController {
        MetaVesTDetails storage details = metavestDetails[_grantee];
        address _repurchasedToken = details.allocation.tokenContract;
        uint256 _amount = details.rta.tokensRepurchasable / _divisor;
        uint256 _repurchasePrice = details.rta.repurchasePrice; // same for '_grantee' and their transferees

        // to preserve linear calculations, repurchased tokens are deducted from the nonwithdrawableAmount as well as the tokenStreamTotal and tokensRepurchasable
        details.rta.tokensRepurchasable -= _amount;
        details.allocation.tokenStreamTotal -= _amount;
        nonwithdrawableAmount[_grantee] -= _amount;

        // make the payment to grantee withdrawable
        amountWithdrawable[_grantee][paymentToken] += _amount * _repurchasePrice;

        if (transferees[_grantee].length != 0) {
            for (uint256 i; i < transferees[_grantee].length; ++i) {
                address _transferee = transferees[_grantee][i];
                MetaVesTDetails storage transfereeDetails = metavestDetails[_transferee];
                uint256 _transfereeAmount = transfereeDetails.rta.tokensRepurchasable / _divisor;
                transfereeDetails.allocation.tokenStreamTotal -= _transfereeAmount;
                transfereeDetails.rta.tokensRepurchasable -= _transfereeAmount;
                nonwithdrawableAmount[_transferee] -= _transfereeAmount;
                _amount += _transfereeAmount;

                amountWithdrawable[_transferee][paymentToken] += _transfereeAmount * _repurchasePrice;
            }
        }

        // transfer all repurchased tokens to 'authority'
        safeTransfer(_repurchasedToken, authority, _amount);
        emit MetaVesT_RepurchaseAndWithdrawal(_grantee, _repurchasedToken, _amount);
    }

    /// @notice for the applicable authority to terminate and delete this '_grantee''s MetaVesT via the controller, retaining unvested tokens and accelerating the unlock of vested tokens
    /// @dev conditionals for this function are in the 'controller'; makes all unlockedTokens for such grantee withdrawable then sends them to grantee,
    /// so as to avoid a mapping overwrite if the grantee's terminated MetaVesT is replaced with a new one before they can withdraw.
    /// Returns remainder to 'authority'; call 'terminateVesting' to only terminate vesting and preserve the unlock schedule
    /// @param _grantee address of grantee whose MetaVesT is being terminated
    function terminate(address _grantee) external onlyController {
        MetaVesTDetails storage details = metavestDetails[_grantee];
        //'_grantee's' and all transferees' metavests are first refreshed in 'controller'
        address _tokenContract = details.allocation.tokenContract;
        uint256 _vested = details.allocation.tokensVested - details.allocation.vestedTokensWithdrawn; // '_vested' == vested but not withdrawn

        // calculate amount to send to '_grantee' starting with current amount withdrawable
        uint256 _amt = amountWithdrawable[_grantee][_tokenContract];

        // calculate nonwithdrawable and unvested remainder to be returned to 'authority' which includes unconfirmed milestoneAwards
        uint256 _remainder = nonwithdrawableAmount[_grantee] - _vested;

        // only include 'tokensVested' if the metavest type is not a token option, as that amount reflects vested but not exercised tokens, which is added to '_remainder'
        // if option, count the exercised tokens
        // since the metavest is being deleted, locked vested amounts are accelerated to unlocked
        if (details.metavestType != MetaVesTType.OPTION) _amt += _vested;
        else {
            _amt += _tokensExercised[_grantee];
            _remainder += _vested - _tokensExercised[_grantee];
        }

        // delete all mappings for '_grantee'
        delete metavestDetails[_grantee];
        delete amountWithdrawable[_grantee][_tokenContract];
        delete nonwithdrawableAmount[_grantee];
        delete _tokensExercised[_grantee];
        delete _linearUnlocked[_grantee];
        delete _linearVested[_grantee];
        delete _milestoneUnlocked[_grantee];
        delete _milestoneVested[_grantee];

        if (transferees[_grantee].length != 0) {
            for (uint256 x; x < transferees[_grantee].length; ++x) {
                address _transferee = transferees[_grantee][x];
                MetaVesTDetails storage transfereeDetails = metavestDetails[_transferee];
                uint256 _transfereeAmt = amountWithdrawable[_transferee][_tokenContract];
                uint256 _transfereeVested = transfereeDetails.allocation.tokensVested -
                    transfereeDetails.allocation.vestedTokensWithdrawn;

                // add each transferee's locked remainder to be returned to 'authority'
                _remainder += nonwithdrawableAmount[_transferee] - _transfereeVested;

                // see comment above re: options
                if (transfereeDetails.metavestType != MetaVesTType.OPTION) _transfereeAmt += _transfereeVested;
                else {
                    _transfereeAmt += _tokensExercised[_transferee];
                    _remainder += _transfereeVested;
                }

                // delete all mappings for '_transferee'
                delete metavestDetails[_transferee];
                delete _milestoneUnlocked[_transferee];
                delete _milestoneVested[_transferee];
                delete _tokensExercised[_transferee];
                delete _linearUnlocked[_transferee];
                delete _linearVested[_transferee];
                delete nonwithdrawableAmount[_transferee];
                delete amountWithdrawable[_transferee][_tokenContract];
                safeTransfer(_tokenContract, _transferee, _transfereeAmt);

                emit MetaVesT_Deleted(_transferee);
                emit MetaVesT_Withdrawal(_transferee, _tokenContract, _transfereeAmt);
            }
        }

        delete transferees[_grantee];

        safeTransfer(_tokenContract, _grantee, _amt);
        safeTransfer(_tokenContract, authority, _remainder);

        emit MetaVesT_Deleted(_grantee);
        emit MetaVesT_Withdrawal(_grantee, _tokenContract, _amt);
        emit MetaVesT_Withdrawal(authority, _tokenContract, _remainder);
    }

    /// @notice for the applicable authority to terminate (stop) this '_grantee''s vesting via the controller, but preserving the unlocking schedule for any already-vested tokens, so their MetaVesT is not deleted
    /// @dev conditionals for this function are in the 'controller'; returns unvested remainder to 'authority' but preserves MetaVesT for all vested tokens up until call;
    /// because 'refreshMetavest' uses transferor's 'vestingRate', this will also stop vesting for all levels of transferee
    /// @param _grantee address of grantee whose MetaVesT's vesting is being stopped
    function terminateVesting(address _grantee) external onlyController {
        MetaVesTDetails storage details = metavestDetails[_grantee];
        MetaVesTType _type = details.metavestType;
        uint256 _transfereesLen = transferees[_grantee].length;
        //'_grantee's' and all transferees' metavests are first refreshed in 'controller'
        address _tokenContract = details.allocation.tokenContract;
        address _authority = authority;

        // calculate locked unvested non-milestone remainder to be returned to 'authority'
        uint256 _remainder = details.allocation.tokenStreamTotal - _linearVested[_grantee];

        // deduct all unvested tokens from applicable mappings for '_grantee'
        nonwithdrawableAmount[_grantee] -= _remainder;
        if (details.rta.tokensRepurchasable >= _remainder && _type == MetaVesTType.RESTRICTED)
            details.rta.tokensRepurchasable -= _remainder;
        delete metavestDetails[_grantee].allocation.vestingCliffCredit;
        delete metavestDetails[_grantee].allocation.vestingRate;

        // for subsequent refreshMetavest calculation purposes, update these vesting tracking variables
        _linearVested[_grantee] = details.allocation.tokenStreamTotal; // no more linear vesting after this function
        details.allocation.vestedTokensWithdrawn += _remainder; // '_remainder' (before transferee remainders are added) is being "withdrawn" to authority

        // replicate for transferees
        if (_transfereesLen != 0) {
            for (uint256 x; x < _transfereesLen; ++x) {
                address _transferee = transferees[_grantee][x];
                MetaVesTDetails storage transfereeDetails = metavestDetails[_transferee];
                uint256 _transfereeRemainder = transfereeDetails.allocation.tokenStreamTotal -
                    _linearVested[_transferee];
                transfereeDetails.allocation.vestedTokensWithdrawn += _transfereeRemainder;
                _linearVested[_transferee] = transfereeDetails.allocation.tokenStreamTotal;
                _remainder += _transfereeRemainder;

                // deduct all unvested tokens from applicable mappings for '_transferee'
                nonwithdrawableAmount[_transferee] -= _transfereeRemainder;
                if (
                    transfereeDetails.rta.tokensRepurchasable >= _transfereeRemainder &&
                    _type == MetaVesTType.RESTRICTED
                ) transfereeDetails.rta.tokensRepurchasable -= _transfereeRemainder;
                delete metavestDetails[_transferee].allocation.vestingCliffCredit;
                delete metavestDetails[_transferee].allocation.vestingRate;
            }
        }

        // safeTransfer the total removed unvested tokens to 'authority'
        safeTransfer(_tokenContract, _authority, _remainder);
        emit MetaVesT_Withdrawal(_authority, _tokenContract, _remainder);
        emit MetaVesT_VestingRateUpdated(_grantee, 0);
    }

    /// @notice allows a grantee to transfer part or all of their MetaVesT to a '_transferee' if this MetaVest has transferability enabled
    /// @dev '_divisor' is uint128 to avoid arithmetic errors with cliff credit divisions, and would not reasonably exceed the uint128 max; note that resulting values from any divisor other than '1' may be round down
    /// @param _divisor divisor corresponding to the grantee's fraction of their claim transferred via this function; i.e. for a transfer of 25% of a claim, submit '4'; to transfer the entire MetaVesT, submit '1'
    /// @param _transferee address to which the claim is being transferred, that will have a new MetaVesT created
    function transferRights(uint128 _divisor, address _transferee) external {
        if (_divisor == 0) revert MetaVesT_ZeroAmount();
        if (_transferee == address(0)) revert MetaVesT_ZeroAddress();
        // prevent potential overwrite of existing MetaVesT
        MetaVesTDetails storage transfereeDetail = metavestDetails[_transferee];
        if (transfereeDetail.grantee != address(0) || _transferee == authority || _transferee == controller)
            revert MetaVesT_AlreadyExists();

        refreshMetavest(msg.sender);

        MetaVesTDetails storage details = metavestDetails[msg.sender];
        MetaVesTDetails memory _metavestDetails = details; // MLOADs for calculations
        Allocation memory _allocation = _metavestDetails.allocation;
        Milestone[] memory _milestones = _metavestDetails.milestones;

        // ensure MetaVesT exists and is transferable
        if (_metavestDetails.grantee == address(0) || msg.sender != _metavestDetails.grantee)
            revert MetaVesT_OnlyGrantee();
        if (!_metavestDetails.transferable) revert MetaVesT_NonTransferable();
        if (transferees[msg.sender].length == ARRAY_LENGTH_LIMIT) revert MetaVesT_TransfereeLimit();

        // update tracking values to calculate '_transferee' amount and subtract from grantee's
        _allocation.unlockedTokensWithdrawn = _allocation.unlockedTokensWithdrawn / _divisor;
        details.allocation.unlockedTokensWithdrawn -= _allocation.unlockedTokensWithdrawn;

        _allocation.vestedTokensWithdrawn = _allocation.vestedTokensWithdrawn / _divisor;
        details.allocation.vestedTokensWithdrawn -= _allocation.vestedTokensWithdrawn;

        _milestoneUnlocked[_transferee] = _milestoneUnlocked[msg.sender] / _divisor;
        _milestoneUnlocked[msg.sender] -= _milestoneUnlocked[_transferee];

        _milestoneVested[_transferee] = _milestoneVested[msg.sender] / _divisor;
        _milestoneVested[msg.sender] -= _milestoneVested[_transferee];

        _linearUnlocked[_transferee] = _linearUnlocked[msg.sender] / _divisor;
        _linearUnlocked[msg.sender] -= _linearUnlocked[_transferee];

        _linearVested[_transferee] = _linearVested[msg.sender] / _divisor;
        _linearVested[msg.sender] -= _linearVested[_transferee];

        nonwithdrawableAmount[_transferee] = nonwithdrawableAmount[msg.sender] / _divisor;
        nonwithdrawableAmount[msg.sender] -= nonwithdrawableAmount[_transferee];

        // transferee's MetaVesT should mirror the calling grantee's except for amounts and grantee address, so just update those necessary elements in the MLOAD
        _allocation.tokenStreamTotal /= _divisor;
        _allocation.vestingCliffCredit /= _divisor;
        _allocation.unlockingCliffCredit /= _divisor;
        _allocation.tokenGoverningPower /= _divisor;
        _allocation.tokensVested /= _divisor;
        _allocation.tokensUnlocked /= _divisor;
        if (_metavestDetails.rta.tokensRepurchasable != 0) _metavestDetails.rta.tokensRepurchasable /= _divisor;

        // update milestoneAwards; completed milestones will pass 0
        if (_milestones.length != 0) {
            // manually copy milestones to avoid dynamic struct array -> storage erro
            for (uint256 i; i < _milestones.length; ++i) {
                _milestones[i].milestoneAward /= _divisor;
                transfereeDetail.milestones.push(_milestones[i]); // we know transferee did not have a metavest before this, so we can simply push the memory milestones array to storage
                // update grantee's milestone array within same loop to remove each transferred milestoneAward for efficiency
                details.milestones[i].milestoneAward -= _milestones[i].milestoneAward;
            }
        }

        transferees[msg.sender].push(_transferee);

        // assign other transferee details manually using the updated '_metavestDetails'
        transfereeDetail.grantee = _transferee;
        transfereeDetail.metavestType = _metavestDetails.metavestType;
        transfereeDetail.allocation = _allocation;
        transfereeDetail.option = _metavestDetails.option;
        transfereeDetail.rta = _metavestDetails.rta;
        transfereeDetail.eligibleTokens = _metavestDetails.eligibleTokens;
        transfereeDetail.transferable = _metavestDetails.transferable;

        // subtract transferred amounts from grantee's metavestDetails
        details.allocation.tokenStreamTotal -= _allocation.tokenStreamTotal;
        details.allocation.vestingCliffCredit -= _allocation.vestingCliffCredit;
        details.allocation.unlockingCliffCredit -= _allocation.unlockingCliffCredit;
        details.allocation.tokenGoverningPower -= _allocation.tokenGoverningPower;
        details.allocation.tokensVested -= _allocation.tokensVested;
        details.allocation.tokensUnlocked -= _allocation.tokensUnlocked;
        if (details.rta.tokensRepurchasable > _metavestDetails.rta.tokensRepurchasable)
            details.rta.tokensRepurchasable -= _metavestDetails.rta.tokensRepurchasable;

        emit MetaVesT_Created(_metavestDetails);
        emit MetaVesT_TransferredRights(msg.sender, _transferee, _divisor);
    }

    /// @notice refresh the time-contingent details and amounts of '_grantee''s MetaVesT
    /// @dev this does not refresh the transferees’ transferees and so on, but ‘refreshMetavest’ is called anyway in each state-changing function
    /// that would be called by a transferee (which would then update their transferee’s values). Also, each transferee's unlock and vest calculations
    /// use their transferor's 'vestingRate', 'vestingStartTime', 'vestingStopTime', 'unlockRate', 'vestingStartTime', and 'vestingStopTime', so
    /// lower level updates will update a level of transferee above on each refresh, substantially mitigating any time-based temporary benefits or
    /// detriments to transferees-of-transferees and beyond. Further, such later transferees can have their metavests permissionlessly refreshed by any caller.
    /// @param _grantee address whose MetaVesT is being refreshed, along with any transferees of such MetaVesT
    function refreshMetavest(address _grantee) public {
        // check whether MetaVesT for this grantee exists
        MetaVesTDetails storage details = metavestDetails[_grantee];

        if (details.grantee != _grantee || _grantee == address(0)) revert MetaVesT_NoMetaVesT();

        Allocation memory _allocation = details.allocation;
        uint256 _streamTotal = _allocation.tokenStreamTotal;

        // separately calculate vesting and unlocking
        // vesting first
        uint256 _vestingStart = uint256(_allocation.vestingStartTime);
        uint256 _vestingEnd;
        uint256 _newlyVested;

        // if token option, '_end' == exercise deadline; if RTA, '_end' == repurchase deadline
        if (details.metavestType == MetaVesTType.OPTION) _vestingEnd = uint256(details.option.shortStopTime);
        else if (details.metavestType == MetaVesTType.RESTRICTED) _vestingEnd = uint256(details.rta.shortStopTime);
        else _vestingEnd = uint256(_allocation.vestingStopTime);

        ///
        /// calculate vest amounts, subtracting vested and withdrawn amounts
        ///
        if (block.timestamp < _vestingStart) {
            delete _linearVested[_grantee]; // linear vesting has not started, ensure it is 0
        } else if (block.timestamp >= _vestingEnd) {
            // after '_end', vested == tokenStreamTotal + milestone amounts vested up until now - vestedTokensWithdrawn
            // we know 'tokensVested' == _streamTotal + milestoneVested, and that 'vestedTokensWithdrawn' cannot exceed the total, so this will not over nor underflow
            unchecked {
                details.allocation.tokensVested =
                    _streamTotal +
                    _milestoneVested[_grantee] -
                    _allocation.vestedTokensWithdrawn;
                _linearVested[_grantee] = _streamTotal; // this includes vestingCliffCredit
            }
            // if token option, if long stop date reached, vested unexercised non-withdrawn tokens are forfeited (note 'tokensVested' already has 'vestedTokensWithdrawn' subtracted from line above)
            if (
                details.metavestType == MetaVesTType.OPTION &&
                block.timestamp >= _allocation.vestingStopTime &&
                details.allocation.tokensVested != 0
            ) {
                details.option.tokensForfeited += uint208(details.allocation.tokensVested - _tokensExercised[_grantee]);
                // make forfeited vested tokens withdrawable by 'authority'
                amountWithdrawable[authority][_allocation.tokenContract] += details.option.tokensForfeited;
                nonwithdrawableAmount[_grantee] -= details.option.tokensForfeited;
                delete details.allocation.tokensVested;
                delete _linearVested[_grantee];
            }
            // if RTA, if short stop date reached, unlocked tokens are not able to be repurchased by authority
            delete details.rta.tokensRepurchasable;
        } else {
            // new tokensVested = (vestRate * passed time since start) (+ the cliff, which == 0 after initial award by its deletion below) - preexisting '_linearVested' if the linear vest hasn't already been completed
            if (_linearVested[_grantee] != _streamTotal) {
                // we know from the 'else' conditional that block.timestamp > _vestingStart, so will not underflow
                uint256 _timeElapsedSinceStart;
                unchecked {
                    _timeElapsedSinceStart = block.timestamp - _vestingStart;
                }
                if (
                    _linearVested[_grantee] >
                    (_allocation.vestingRate * _timeElapsedSinceStart) + uint256(_allocation.vestingCliffCredit)
                )
                    // ensure '_linearVested' is not the greater value due to 'vestingCliffCredit' being larger than the linear vest update since the last refresh (and the cliff credit having been deleted), or this will revert
                    // if so, just add the linear update to '_newlyVested'
                    _newlyVested = ((_allocation.vestingRate * _timeElapsedSinceStart) +
                        uint256(_allocation.vestingCliffCredit));
                else
                    _newlyVested =
                        ((_allocation.vestingRate * _timeElapsedSinceStart) + uint256(_allocation.vestingCliffCredit)) -
                        _linearVested[_grantee];
            }
            // make sure linear vest calculation does not surpass the token stream total, such as with a high vestRate; if so, calculate accordingly
            if (_linearVested[_grantee] + _newlyVested <= _streamTotal) {
                details.allocation.tokensVested += _newlyVested; // add the newly vested amount rather than re-assigning variable entirely as pre-existing vested amount was already subtracted
                if (details.rta.tokensRepurchasable >= _newlyVested) details.rta.tokensRepurchasable -= _newlyVested;
            } else {
                delete _newlyVested; // linear already equals total, so this is 0
                details.allocation.tokensVested = _streamTotal + _milestoneVested[_grantee];
                _linearVested[_grantee] = _streamTotal;
            }
            // we know this will not overflow due to the preceding conditional
            unchecked {
                _linearVested[_grantee] += _newlyVested;
            }
            // delete cliff credit. After the cliff is added the first time, subsequent calls will simply pass 0 throughout this function
            delete details.allocation.vestingCliffCredit;
        }

        ///
        /// now calculating unlocked amounts
        ///
        uint256 _unlockingEnd = uint256(_allocation.unlockStopTime);
        uint256 _newlyUnlocked;

        // calculate unlock amounts, subtracting unlocked and withdrawn amounts
        if (block.timestamp < uint256(_allocation.unlockStartTime)) {
            delete _linearUnlocked[_grantee]; // linear unlocking has not started, ensure it is 0
        } else if (block.timestamp >= _unlockingEnd) {
            // after '_end', unlocked == tokenStreamTotal + milestone amounts unlocked up until now - unlockedTokensWithdrawn
            // we know 'tokensUnlocked' == _streamTotal + _milestoneUnlocked, and that 'unlockedTokensWithdrawn' cannot exceed the total, so this will not over nor underflow
            unchecked {
                details.allocation.tokensUnlocked =
                    _streamTotal +
                    _milestoneUnlocked[_grantee] -
                    _allocation.unlockedTokensWithdrawn;
                _linearUnlocked[_grantee] = _streamTotal;
            }
        } else {
            // new tokensUnlocked = (unlockRate * passed time since start) (+ the cliff, which == 0 after initial award by its deletion below) - preexisting '_linearUnlocked' if the linear unlock hasn't already been completed
            if (_linearUnlocked[_grantee] != _streamTotal)
                if (
                    _linearUnlocked[_grantee] >
                    (_allocation.unlockRate * (block.timestamp - uint256(_allocation.unlockStartTime))) +
                        uint256(_allocation.unlockingCliffCredit)
                )
                    // see above comment about '_linearVested' and cliff check
                    _newlyUnlocked = ((_allocation.unlockRate *
                        (block.timestamp - uint256(_allocation.unlockStartTime))) +
                        uint256(_allocation.unlockingCliffCredit));
                else
                    _newlyUnlocked =
                        ((_allocation.unlockRate * (block.timestamp - uint256(_allocation.unlockStartTime))) +
                            uint256(_allocation.unlockingCliffCredit)) -
                        _linearUnlocked[_grantee];
            // make sure linear unlocked calculation does not surpass the token stream total, such as with a high unlockRate; if so, calculate accordingly
            if (_linearUnlocked[_grantee] + _newlyUnlocked <= _streamTotal) {
                details.allocation.tokensUnlocked += _newlyUnlocked; // add the newly unlocked amount rather than re-assigning variable entirely as pre-existing unlocked amount was already subtracted
            } else {
                delete _newlyUnlocked; // linear already equals total, so this is 0
                details.allocation.tokensUnlocked = _streamTotal + _milestoneUnlocked[_grantee];
                _linearUnlocked[_grantee] = _streamTotal;
            }
            // we know this will not overflow due to the preceding conditional
            unchecked {
                _linearUnlocked[_grantee] += _newlyUnlocked;
            }
            // delete cliff credit. After the cliff is added the first time, subsequent calls will simply pass 0 throughout this function
            delete details.allocation.unlockingCliffCredit;
        }

        // the smaller of the updated vested & unlocked (the overlapping amount, which is withdrawable) is deducted from nonwithdrawableAmount
        nonwithdrawableAmount[_grantee] -= _min(_newlyVested, _newlyUnlocked);

        // recalculate governing power -- unlocked && vested is withdrawable, so those will not be counted together as grantee can simply withdraw and use in governance
        delete details.allocation.tokenGoverningPower;
        if (details.eligibleTokens.unlocked) details.allocation.tokenGoverningPower = details.allocation.tokensUnlocked;
        if (details.eligibleTokens.vested) details.allocation.tokenGoverningPower = details.allocation.tokensVested;
        if (details.eligibleTokens.nonwithdrawable)
            details.allocation.tokenGoverningPower = nonwithdrawableAmount[_grantee];

        // if claims were transferred, make similar updates (though note each start and end will be the same) for each transferee
        /// @dev this refreshes the "first level" of transferees; so a grantee's transferees will have their MetaVesTs refreshed, but
        /// for the second-level transferees of a transferee to have theirs' refreshed, the first-level transferee will have to refresh via this function
        if (transferees[_grantee].length != 0) {
            for (uint256 i; i < transferees[_grantee].length; ++i) {
                address _transferee = transferees[_grantee][i];
                MetaVesTDetails storage transfereeDetails = metavestDetails[_transferee];
                Allocation memory _transfereeAllocation = transfereeDetails.allocation;
                uint256 _transfereeNewlyVested;
                uint256 _transfereeNewlyUnlocked;

                // vesting first
                if (block.timestamp < _vestingStart) {
                    delete _linearVested[_transferee];
                } else if (block.timestamp >= _vestingEnd) {
                    transfereeDetails.allocation.tokensVested =
                        _transfereeAllocation.tokenStreamTotal +
                        _milestoneVested[_transferee] -
                        _transfereeAllocation.vestedTokensWithdrawn;
                    _linearVested[_transferee] = _transfereeAllocation.tokenStreamTotal;
                    // if token option, if long stop date reached, vested unexercised tokens are forfeited and may be reclaimed by 'authority'
                    if (
                        transfereeDetails.metavestType == MetaVesTType.OPTION &&
                        block.timestamp >= _allocation.vestingStopTime &&
                        transfereeDetails.allocation.tokensVested != 0
                    ) {
                        transfereeDetails.option.tokensForfeited += uint208(
                            transfereeDetails.allocation.tokensVested - _tokensExercised[_transferee]
                        );
                        // make forfeited vested tokens withdrawable by 'authority'
                        amountWithdrawable[authority][_transfereeAllocation.tokenContract] += transfereeDetails
                            .option
                            .tokensForfeited;
                        nonwithdrawableAmount[_transferee] -= transfereeDetails.option.tokensForfeited;
                        delete transfereeDetails.allocation.tokensVested;
                        delete _linearVested[_transferee];
                    }
                    // if RTA, if short stop date reached, vested tokens are not able to be repurchased by authority
                    delete transfereeDetails.rta.tokensRepurchasable;
                } else {
                    if (_linearVested[_transferee] != _transfereeAllocation.tokenStreamTotal) {
                        if (
                            _linearVested[_transferee] >
                            ((_allocation.vestingRate * (block.timestamp - _vestingStart)) +
                                uint256(transfereeDetails.allocation.vestingCliffCredit))
                        )
                            _transfereeNewlyVested = ((_allocation.vestingRate * (block.timestamp - _vestingStart)) +
                                uint256(transfereeDetails.allocation.vestingCliffCredit));
                        else
                            _transfereeNewlyVested =
                                ((_allocation.vestingRate * (block.timestamp - _vestingStart)) +
                                    uint256(transfereeDetails.allocation.vestingCliffCredit)) -
                                _linearVested[_transferee];
                    }
                    if (_linearVested[_transferee] + _transfereeNewlyVested <= _transfereeAllocation.tokenStreamTotal) {
                        transfereeDetails.allocation.tokensVested += _transfereeNewlyVested;
                        if (transfereeDetails.rta.tokensRepurchasable >= _transfereeNewlyVested)
                            transfereeDetails.rta.tokensRepurchasable -= _transfereeNewlyVested;
                    } else {
                        delete _transfereeNewlyVested;
                        transfereeDetails.allocation.tokensVested =
                            _transfereeAllocation.tokenStreamTotal +
                            _milestoneVested[_transferee];
                        _linearVested[_transferee] = _transfereeAllocation.tokenStreamTotal;
                    }
                    unchecked {
                        _linearVested[_transferee] += _transfereeNewlyVested;
                    }
                    delete transfereeDetails.allocation.vestingCliffCredit;
                }

                // now calculate unlocking
                if (block.timestamp < uint256(_allocation.unlockStartTime)) {
                    delete _linearUnlocked[_transferee];
                } else if (block.timestamp >= _unlockingEnd) {
                    transfereeDetails.allocation.tokensUnlocked =
                        _transfereeAllocation.tokenStreamTotal +
                        _milestoneUnlocked[_transferee] -
                        _transfereeAllocation.unlockedTokensWithdrawn;
                    _linearUnlocked[_transferee] = _transfereeAllocation.tokenStreamTotal;
                } else {
                    if (_linearUnlocked[_transferee] != _transfereeAllocation.tokenStreamTotal)
                        if (
                            _linearUnlocked[_transferee] >
                            ((_allocation.unlockRate * (block.timestamp - uint256(_allocation.unlockStartTime))) +
                                uint256(transfereeDetails.allocation.unlockingCliffCredit))
                        )
                            _transfereeNewlyUnlocked = ((_allocation.unlockRate *
                                (block.timestamp - uint256(_allocation.unlockStartTime))) +
                                uint256(transfereeDetails.allocation.unlockingCliffCredit));
                        else
                            _transfereeNewlyUnlocked =
                                ((_allocation.unlockRate * (block.timestamp - uint256(_allocation.unlockStartTime))) +
                                    uint256(transfereeDetails.allocation.unlockingCliffCredit)) -
                                _linearUnlocked[_transferee];
                    // make sure linear unlocked calculation does not surpass the token stream total
                    if (
                        _linearUnlocked[_transferee] + _transfereeNewlyUnlocked <=
                        _transfereeAllocation.tokenStreamTotal
                    ) {
                        transfereeDetails.allocation.tokensUnlocked += _transfereeNewlyUnlocked;
                    } else {
                        delete _transfereeNewlyUnlocked;
                        transfereeDetails.allocation.tokensUnlocked =
                            _transfereeAllocation.tokenStreamTotal +
                            _milestoneUnlocked[_transferee];
                        _linearUnlocked[_transferee] = _transfereeAllocation.tokenStreamTotal;
                    }
                    unchecked {
                        _linearUnlocked[_transferee] += _transfereeNewlyUnlocked;
                    }
                    // delete cliff credit. After the cliff is added the first time, later refreshes will simply pass 0
                    delete transfereeDetails.allocation.unlockingCliffCredit;
                }

                // the smaller of the updated vested & unlocked amount (the overlapping amount, which is withdrawable) is deducted from nonwithdrawableAmount
                nonwithdrawableAmount[_transferee] -= _min(_transfereeNewlyVested, _transfereeNewlyUnlocked);
                // recalculate governing power
                delete transfereeDetails.allocation.tokenGoverningPower;
                if (transfereeDetails.eligibleTokens.unlocked)
                    transfereeDetails.allocation.tokenGoverningPower = transfereeDetails.allocation.tokensUnlocked;
                if (transfereeDetails.eligibleTokens.vested)
                    transfereeDetails.allocation.tokenGoverningPower = transfereeDetails.allocation.tokensVested;
                if (transfereeDetails.eligibleTokens.nonwithdrawable)
                    transfereeDetails.allocation.tokenGoverningPower = nonwithdrawableAmount[_transferee];
            }
        }
    }

    /// @notice allows a grantee (or transferee) of a token option to exercise their option by paying the exercise price in 'paymentToken' for their amount of vested tokens, making such tokens withdrawable if unlocked
    /// @param _amount amount of tokens msg.sender seeks to exercise in their token option
    function exerciseOption(uint256 _amount) external {
        if (_amount == 0) revert MetaVesT_ZeroAmount();
        refreshMetavest(msg.sender);

        MetaVesTDetails storage details = metavestDetails[msg.sender];

        if (msg.sender != details.grantee) revert MetaVesT_OnlyGrantee();
        if (details.metavestType != MetaVesTType.OPTION) revert MetaVesT_NoTokenOption();

        address _tokenContract = details.allocation.tokenContract;
        // amount available to msg.sender to exercise and withdraw is the amount that is vested && not withdrawn && not from milestones && not already exercised
        uint256 _availableTokens = details.allocation.tokensVested -
            details.allocation.vestedTokensWithdrawn -
            _milestoneVested[msg.sender] -
            _tokensExercised[msg.sender];
        if (_availableTokens < _amount) revert MetaVesT_AmountGreaterThanAvailable();

        uint256 _payment = _amount * details.option.exercisePrice;
        if (
            ipaymentToken.allowance(msg.sender, address(this)) < _payment ||
            ipaymentToken.balanceOf(msg.sender) < _payment
        ) revert MetaVesT_AmountNotApprovedForTransferFrom();

        _tokensExercised[msg.sender] += _amount;
        nonwithdrawableAmount[msg.sender] -= _amount;

        safeTransferFrom(paymentToken, msg.sender, address(this), _payment);

        amountWithdrawable[controller][paymentToken] += _payment;

        emit MetaVesT_OptionExercised(msg.sender, _tokenContract, _amount);
    }

    /// @notice allows an address to withdraw their 'amountWithdrawable' of their corresponding token in their MetaVesT, or amount of 'paymentToken' as a result of a tokenRepurchase
    /// @dev notice withdrawing does not affect the 'tokensVested' nor 'tokensUnlocked' variables, as these are preserved for calculations until the metavest's long stop times
    /// @param _tokenAddress the ERC20 token address which msg.sender is withdrawing, which should be either the 'metavestDetails[msg.sender].allocation.tokenContract' or 'paymentToken'
    function withdrawAll(address _tokenAddress) external nonReentrant {
        if (_tokenAddress == address(0)) revert MetaVesT_ZeroAddress();
        uint256 _amt;
        MetaVesTDetails storage details = metavestDetails[msg.sender];
        Allocation storage detailsAllocation = metavestDetails[msg.sender].allocation;
        /// @dev if caller has a MetaVesT which is a Token Option, they must call 'exerciseOption' in order to exercise their option and make their 'tokensVested' (vested) exercised and then call this function, otherwise they would be withdrawing vested but not exercised tokens here
        uint256 _preAmtWithdrawable = amountWithdrawable[msg.sender][_tokenAddress];
        if (_tokenAddress == detailsAllocation.tokenContract && details.metavestType != MetaVesTType.OPTION) {
            if (msg.sender != details.grantee) revert MetaVesT_OnlyGrantee();
            refreshMetavest(msg.sender);

            // amountWithdrawable must be both vested and unlocked (and not already withdrawn), so we take the minimum of the two in order to determine the newly withdrawable amount, then add that to the withdrawn amounts
            unchecked {
                // we know each of vested and unlocked withdrawn cannot exceed the aggregate tokensVested and tokensUnlocked counters, and same with the withdrawable counters
                uint256 _newlyWithdrawable = _min(
                    detailsAllocation.tokensVested - detailsAllocation.vestedTokensWithdrawn,
                    detailsAllocation.tokensUnlocked - detailsAllocation.unlockedTokensWithdrawn
                );
                // add newly withdrawable tokens to amountWithdrawable, unlockedTokensWithdrawn, and vestedTokensWithdrawn, since all are being withdrawn now
                amountWithdrawable[msg.sender][_tokenAddress] = _preAmtWithdrawable + _newlyWithdrawable;
                detailsAllocation.unlockedTokensWithdrawn += _newlyWithdrawable;
                detailsAllocation.vestedTokensWithdrawn += _newlyWithdrawable;
            }
        } else if (_tokenAddress == detailsAllocation.tokenContract && details.metavestType == MetaVesTType.OPTION) {
            if (msg.sender != details.grantee) revert MetaVesT_OnlyGrantee();
            refreshMetavest(msg.sender);

            // amountWithdrawable for a token option must be both vested and exercised (and not already withdrawn), so we take the minimum of the two in order to determine the newly withdrawable amount, then add that to the withdrawn amounts
            uint256 _newlyWithdrawable = _min(
                _tokensExercised[msg.sender],
                detailsAllocation.tokensUnlocked - detailsAllocation.unlockedTokensWithdrawn
            );
            // add newly withdrawable tokens to amountWithdrawable, unlockedTokensWithdrawn, and vestedTokensWithdrawn, and deduct from _tokensExercised
            amountWithdrawable[msg.sender][_tokenAddress] = _preAmtWithdrawable + _newlyWithdrawable;
            detailsAllocation.unlockedTokensWithdrawn += _newlyWithdrawable;
            detailsAllocation.vestedTokensWithdrawn += _newlyWithdrawable;
            _tokensExercised[msg.sender] -= _newlyWithdrawable;
        }

        // delete the metavestDetails and mappings for this msg.sender if the token corresponds to a metavest and all their values are 0,
        // as now all tokens are withdrawn as well (so we know after this call, no locked, unlocked, vested, nor withdrawable tokens will remain)
        if (
            _tokenAddress == detailsAllocation.tokenContract &&
            nonwithdrawableAmount[msg.sender] == 0 &&
            detailsAllocation.tokensUnlocked == detailsAllocation.unlockedTokensWithdrawn &&
            detailsAllocation.tokensVested == detailsAllocation.vestedTokensWithdrawn
        ) {
            delete metavestDetails[msg.sender];
            delete _linearUnlocked[msg.sender];
            delete _linearVested[msg.sender];
            delete _milestoneUnlocked[msg.sender];
            delete _milestoneVested[msg.sender];
            emit MetaVesT_Deleted(msg.sender);
        }

        _amt = amountWithdrawable[msg.sender][_tokenAddress];
        if (_amt == 0) revert MetaVesT_ZeroAmount();

        // delete 'amountWithdrawable' for '_tokenAddress', as all tokens are being withdrawn now
        delete amountWithdrawable[msg.sender][_tokenAddress];

        safeTransfer(_tokenAddress, msg.sender, _amt);
        emit MetaVesT_Withdrawal(msg.sender, _tokenAddress, _amt);
    }

    /// @notice allows an address to withdraw '_amount' of the 'amountWithdrawable' of their corresponding token in their MetaVesT, or amount of 'paymentToken' as a result of a tokenRepurchase
    /// @dev best practice to call 'withdrawAll' rather than this function once a MetaVesT is completed, to delete it afterward
    /// @param _tokenAddress the ERC20 token address which msg.sender is withdrawing, which should be either the 'metavestDetails[msg.sender].allocation.tokenContract' or 'paymentToken'
    /// @param _amount amount of tokens msg.sender is withdrawing
    function withdraw(address _tokenAddress, uint256 _amount) external nonReentrant {
        if (_tokenAddress == address(0)) revert MetaVesT_ZeroAddress();

        MetaVesTDetails storage details = metavestDetails[msg.sender];
        Allocation storage detailsAllocation = details.allocation;
        /// @dev if caller has a MetaVesT which is a Token Option, they must call 'exerciseOption' in order to exercise their option and make their 'tokensVested' (vested) exercised and then call this function, otherwise they would be withdrawing vested but not exercised tokens here
        if (_tokenAddress == detailsAllocation.tokenContract && details.metavestType != MetaVesTType.OPTION) {
            uint256 _preAmtWithdrawable = amountWithdrawable[msg.sender][_tokenAddress];
            refreshMetavest(msg.sender);

            if (msg.sender != details.grantee) revert MetaVesT_OnlyGrantee();
            unchecked {
                // we know each of vested and unlocked withdrawn cannot exceed the aggregate tokensVested and tokensUnlocked counters, and same with the withdrawable counters
                uint256 _newlyWithdrawable = _min(
                    detailsAllocation.tokensVested - detailsAllocation.vestedTokensWithdrawn,
                    detailsAllocation.tokensUnlocked - detailsAllocation.unlockedTokensWithdrawn
                );

                amountWithdrawable[msg.sender][_tokenAddress] = _preAmtWithdrawable + _newlyWithdrawable;
                detailsAllocation.unlockedTokensWithdrawn += _newlyWithdrawable;
                detailsAllocation.vestedTokensWithdrawn += _newlyWithdrawable;
            }
        } else if (_tokenAddress == detailsAllocation.tokenContract && details.metavestType == MetaVesTType.OPTION) {
            uint256 _preAmtWithdrawable = amountWithdrawable[msg.sender][_tokenAddress];
            refreshMetavest(msg.sender);

            if (msg.sender != details.grantee) revert MetaVesT_OnlyGrantee();

            // amountWithdrawable for a token option must be both vested and exercised (and not already withdrawn), so we take the minimum of the two in order to determine the newly withdrawable amount, then add that to the withdrawn amounts
            uint256 _newlyWithdrawable = _min(
                _tokensExercised[msg.sender],
                detailsAllocation.tokensUnlocked - detailsAllocation.unlockedTokensWithdrawn
            );
            // add newly withdrawable tokens to amountWithdrawable, unlockedTokensWithdrawn, and vestedTokensWithdrawn, and deduct from _tokensExercised
            amountWithdrawable[msg.sender][_tokenAddress] = _preAmtWithdrawable + _newlyWithdrawable;
            detailsAllocation.unlockedTokensWithdrawn += _newlyWithdrawable;
            detailsAllocation.vestedTokensWithdrawn += _newlyWithdrawable;
            _tokensExercised[msg.sender] -= _newlyWithdrawable;
        }
        if (_amount > amountWithdrawable[msg.sender][_tokenAddress]) revert MetaVesT_AmountGreaterThanWithdrawable();

        // subtract '_amount' from 'amountWithdrawable' for '_tokenAddress'
        amountWithdrawable[msg.sender][_tokenAddress] -= _amount;

        safeTransfer(_tokenAddress, msg.sender, _amount);
        emit MetaVesT_Withdrawal(msg.sender, _tokenAddress, _amount);
    }

    /// @notice retrieve the MetaVesT details for a grantee
    /// @param _grantee address whose MetaVest details are being retrieved
    function getMetavestDetails(address _grantee) external view returns (MetaVesTDetails memory) {
        return metavestDetails[_grantee];
    }

    /// @notice retrieve the current amountWithdrawable for an address and a token contract
    /// @dev for an updated amountWithdrawable for a grantee with a metavest, call 'refreshMetavest' supplying '_address' first
    /// @param _address address whose amountWithdrawable for '_tokenContract' is being retrieved
    /// @param _tokenContract contract address of the applicable ERC20 token
    function getAmountWithdrawable(address _address, address _tokenContract) external view returns (uint256) {
        return amountWithdrawable[_address][_tokenContract];
    }

    /// @dev returns the minimum of `x` and `y`. See https://github.com/Vectorized/solady/blob/main/src/utils/FixedPointMathLib.sol
    function _min(uint256 x, uint256 y) internal pure returns (uint256 z) {
        /// @solidity memory-safe-assembly
        assembly {
            z := xor(x, mul(xor(x, y), lt(y, x)))
        }
    }
}
