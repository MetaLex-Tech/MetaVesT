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

/// @notice interface to a MetaLeX condition contract
/// @dev see https://github.com/MetaLex-Tech/BORG-CORE/tree/main/src/libs/conditions
interface ICondition {
    function checkCondition() external returns (bool);
}

interface IERC20 {
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
 *             on a per-BORG or per-DAO (including per-authority) basis, supporting multiple grantees and tokens and all
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
        MetaVesTType metavestType;
        Allocation allocation; // Allocation details are applicable for all three MetaVesTType options
        TokenOption option; // struct containing token option-specific details
        RestrictedTokenAward rta; // struct containing restricted token award-specific details
        GovEligibleTokens eligibleTokens; // struct containing bools of types of MetaVesTed tokens' governing power
        Milestone[] milestones; // array of Milestone structs
        address grantee; // grantee of the tokens
        bool transferable; // whether grantee can transfer their MetaVesT in whole or in part to other addresses
    }

    struct Allocation {
        uint256 tokenStreamTotal; // total number of tokens subject to linear vesting/restriction removal (does NOT include 'cliffCredit' nor each 'milestoneAward')
        uint256 tokenGoverningPower; // number of tokens able to be staked/voted/otherwise used in 'dao' governance
        uint256 tokensVested; // vested but not withdrawn -- if RESTRICTED this amount corresponds to 'unrestricted';
        uint256 tokensUnlocked; // unlocked but not withdrawn
        uint256 vestedTokensWithdrawn; // number of tokens withdrawn that were previously 'tokensVested', for vesting calculations
        uint256 unlockedTokensWithdrawn; // number of tokens withdrawn that were previously 'tokensVested', for unlocking calculations
        uint128 vestingCliffCredit; // lump sum of tokens which become vested (note: not added to 'tokensVested' so as not to disrupt calculations) at 'startTime'
        uint128 unlockingCliffCredit; // lump sum of tokens which become withdrawable (note: not added to 'tokensUnlocked' so as not to disrupt calculations) at 'startTime'
        uint160 vestingRate; // tokens per second that become vested; if RESTRICTED this amount corresponds to 'lapse rate' for tokens that become non-repurchasable
        uint48 vestingStartTime; // if RESTRICTED this amount corresponds to 'lapse start time'
        uint48 vestingStopTime; // long stop time
        uint160 unlockRate; // tokens per second that become unlocked;
        uint48 unlockStartTime; // start of the linear unlock
        uint48 unlockStopTime; // end of the linear unlock
        address tokenContract; // contract address of the ERC20 token including in the given MetaVesT
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
        bool locked; // whether 'amountLocked' counts towards 'tokenGoverningPower'
        bool vested; // whether 'tokensVested' counts towards 'tokenGoverningPower'
        bool unlocked; // whether 'tokensUnlocked' counts towards 'tokenGoverningPower'
    }

    struct Milestone {
        bool complete; // whether the Milestone is satisfied and the 'milestoneAward' is to be released
        uint256 milestoneAward; // per-milestone indexed lump sums of tokens unlocked upon corresponding milestone completion
        address[] conditionContracts; // array of contract addresses corresponding to condition(s) that must satisfied for this Milestone to be 'complete'
    }

    /// @dev limit arrays & loops for gas/size purposes
    uint256 internal constant ARRAY_LENGTH_LIMIT = 20;

    /// @notice MetaVesTController contract address, immutably tied to this MetaVesT
    address public immutable controller;

    /// @notice address of payment token used for token option exercises or restricted token repurchases
    address public immutable paymentToken;

    /// @notice authority address, may replace itself in 'controller'
    address public authority;

    /// @notice contract address for use of 'tokenGoverningPower', typically a DAO pool, governor, staking address, if any (otherwise address(0))
    address public dao;

    /// @notice maps grantee to transferees of their MetaVesT
    mapping(address => address[]) public transferees;

    /// @notice maps address to total amount of tokens currently locked for their MetaVesT
    /// initially == 'metavestDetails.allocation.tokenStreamTotal' + 'metavestDetails.allocation.cliffCredit' + each 'metavestDetails.milestones.milestoneAward'
    mapping(address => uint256) public amountLocked;

    /// @notice maps address to tokens unlocked via cliff and confirmed milestones, to ease unlocking calculations
    mapping(address => uint256) internal cliffAndMilestoneUnlocked;

    /// @notice maps address to tokens vested via cliff and confirmed milestones, to ease vesting calculations
    mapping(address => uint256) internal cliffAndMilestoneVested;

    /// @notice maps address to tokens unlocked via linear unlocking, to ease unlocking calculations
    mapping(address => uint256) internal linearUnlocked;

    /// @notice maps address to tokens unlocked via linear unlocking, to ease unlocking calculations
    mapping(address => uint256) internal linearVested;

    /// @notice maps address to their total amount of tokens which are withdrawable from address(this)
    /// @dev address mapped to (token address -> amount able to be withdrawn)
    mapping(address => mapping(address => uint256)) public amountWithdrawable;

    /// @notice maps grantee address to their MetaVesTDetails struct
    mapping(address => MetaVesTDetails) public metavestDetails;

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
    event MetaVesT_TransferredRights(address grantee, address transferee, uint256 divisor);
    event MetaVesT_UnlockRateUpdated(address grantee, uint208 unlockRate);
    event MetaVesT_VestingRateUpdated(address grantee, uint208 vestingRate);
    event MetaVesT_Withdrawal(address withdrawer, address tokenContract, uint256 amount);

    ///
    /// ERRORS
    ///

    error MetaVesT_AlreadyExists();
    error MetaVesT_AmountGreaterThanVested();
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

    /// @notice constructs a MetaVesT framework specifying authority address, MetaVesTController contract address, and DAO staking/voting contract address
    /// each individual grantee's MetaVesT will be initiated in the 'controller' contract
    /** @dev ONLY ONE METAVEST PER ADDRESS;
     *** this contract supports multiple different ERC20s, but each grantee address (including transferees) may only correspond to one MetaVesT and therefore one token*/
    /// @param _authority: address which initiates and may update each MetaVesT, such as a BORG or DAO, via the 'controller'
    /// 'authority' cannot initially be zero address, as no MetaVesTs could be initialized; however, may replace itself with zero address after creating MetaVesTs for immutability.
    /// @param _controller: MetaVesTController.sol contract address, permissioned to the 'authority' that parameterizes functionalities of each MetaVesT in this contract
    /// and may update details; contains many of the conditionals for the authority-permissioned functions
    /// @param _dao: contract address which token may be staked and used for voting, typically a DAO pool, governor, staking address. Submit address(0) for no such functionality.
    /// @param _paymentToken contract address of the token used as payment/consideration for 'authority' to repurchase tokens according to a restricted token award, or for 'grantee' to exercise a token option
    constructor(address _authority, address _controller, address _dao, address _paymentToken) {
        if (_authority == address(0) || _controller == address(0)) revert MetaVesT_ZeroAddress();
        authority = _authority;
        controller = _controller;
        dao = _dao;
        paymentToken = _paymentToken;
    }

    /// @notice creates a MetaVesT for a grantee and locks the total token amount ('metavestDetails.allocation.tokenStreamTotal' + 'metavestDetails.allocation.vestingCliffCredit' + each 'metavestDetails.milestones.milestoneAward')
    /// @dev see MetaVesTController for conditionals and additional comments
    /// @param _metavestDetails: MetaVesTDetails struct containing all applicable details for this '_metavestDetails.grantee'-- but MUST contain grantee, token contract, amount, and start and stop time
    /// @param _total: total amount of tokens being locked, including linear release, milestone awards, and vestingCliffCredit
    function createMetavest(MetaVesTDetails calldata _metavestDetails, uint256 _total) external onlyController {
        address _grantee = _metavestDetails.grantee;
        MetaVesTDetails storage details = metavestDetails[_grantee];
        // manually copy milestones to avoid dynamic struct array -> storage error
        for (uint256 i = 0; i < _metavestDetails.milestones.length; ++i) {
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

        amountLocked[_grantee] = _total;

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

    /// @notice for controller to update 'dao' via its two-step functions
    /// @dev update event emitted in MetaVesTController
    /// @param _newDao new 'dao' address
    function updateDao(address _newDao) external onlyController {
        dao = _newDao;
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
    /// @dev an '_vestingRate' of 0 is permissible to enable temporary freezes of allocation unlocks by authority
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
    function confirmMilestone(address _grantee, uint8 _milestoneIndex) external {
        refreshMetavest(_grantee);
        MetaVesTDetails storage details = metavestDetails[_grantee];
        Milestone[] memory _milestones = details.milestones;

        if (_milestoneIndex >= _milestones.length || _milestones[_milestoneIndex].complete)
            revert MetaVesT_MilestoneIndexCompletedOrDoesNotExist();

        // perform any applicable condition checks, including whether 'authority' has a signatureCondition
        for (uint256 i; i < _milestones[_milestoneIndex].conditionContracts.length; ++i) {
            if (!ICondition(_milestones[_milestoneIndex].conditionContracts[i]).checkCondition())
                revert MetaVesT_ConditionNotSatisfied(_milestones[_milestoneIndex].conditionContracts[i]);
        }

        uint256 _milestoneAward = _milestones[_milestoneIndex].milestoneAward;
        unchecked {
            details.allocation.tokensVested += _milestoneAward; // cannot overflow as milestoneAwards cannot cumulatively be greater that tokenStreamTotal
            cliffAndMilestoneVested[_grantee] += _milestoneAward;
            amountLocked[_grantee] -= _milestoneAward; // cannot underflow as milestoneAwards cannot be cumulatively be greater than the amountLocked
            if (details.metavestType == MetaVesTType.RESTRICTED) details.rta.tokensRepurchasable -= _milestoneAward;
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
                uint256 _award = transfereeDetails.milestones[_milestoneIndex].milestoneAward;
                unchecked {
                    transfereeDetails.allocation.tokensVested += _award;
                    cliffAndMilestoneVested[_transferee] += _award;
                    amountLocked[_transferee] -= _award;
                    if (details.metavestType == MetaVesTType.RESTRICTED)
                        transfereeDetails.rta.tokensRepurchasable -= _award;
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
        amountLocked[_grantee] -= _removedMilestoneAmount;

        delete details.milestones[_milestoneIndex];

        bool _rta;
        // ensure tokensRepurchasable subtracts deleted amount, if RTA
        if (details.rta.tokensRepurchasable != 0) {
            details.rta.tokensRepurchasable -= _removedMilestoneAmount;
            _rta = true;
        }

        // replicate for transferees
        if (transferees[_grantee].length != 0) {
            for (uint256 i; i < transferees[_grantee].length; ++i) {
                address _transferee = transferees[_grantee][i];
                MetaVesTDetails storage transfereeDetails = metavestDetails[_transferee];
                uint256 _transfereeRemovedMilestoneAmount = transfereeDetails
                    .milestones[_milestoneIndex]
                    .milestoneAward;

                amountWithdrawable[controller][_tokenContract] += _transfereeRemovedMilestoneAmount;
                amountLocked[_transferee] -= _transfereeRemovedMilestoneAmount;
                if (_rta) transfereeDetails.rta.tokensRepurchasable -= _transfereeRemovedMilestoneAmount;

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
        amountLocked[_grantee] += _milestone.milestoneAward;
        MetaVesTDetails storage details = metavestDetails[_grantee];
        // ensure tokensRepurchasable is == _total, if RTA
        if (details.metavestType == MetaVesTType.RESTRICTED)
            details.rta.tokensRepurchasable += _milestone.milestoneAward;

        details.milestones.push(_milestone);

        // add to milestone array length but not amount for current transferees
        if (transferees[_grantee].length != 0) {
            for (uint256 i; i < transferees[_grantee].length; ++i) {
                address _transferee = transferees[_grantee][i];
                Milestone[] storage transfereeMilestones = metavestDetails[_transferee].milestones;
                transfereeMilestones.push(_milestone);
                transfereeMilestones[transfereeMilestones.length].milestoneAward = 0;
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
    /// @dev conditionals for this function (including short stop time check and '_divisor' != 0) are in the 'controller'; repurchased tokens are sent to 'authority'
    /// @param _grantee address of grantee whose tokens are being repurchased
    /// @param _divisor divisor corresponding to the fraction of _grantee's repurchasable tokens being repurchased by 'authority'; to repurchase the full available amount, submit '1'
    function repurchaseTokens(address _grantee, uint256 _divisor) external onlyController {
        MetaVesTDetails storage details = metavestDetails[_grantee];
        address _repurchasedToken = details.allocation.tokenContract;
        uint256 _amount = details.rta.tokensRepurchasable / _divisor;
        uint256 _repurchasePrice = details.rta.repurchasePrice; // same for '_grantee' and their transferees

        // to preserve linear calculations, repurchased tokens are deducted from the amountLocked as well as the tokenStreamTotal and tokensRepurchasable
        details.rta.tokensRepurchasable -= _amount;
        details.allocation.tokenStreamTotal -= _amount;
        amountLocked[_grantee] -= _amount;

        // make the payment to grantee withdrawable
        amountWithdrawable[_grantee][paymentToken] += _amount * _repurchasePrice;

        if (transferees[_grantee].length != 0) {
            for (uint256 i; i < transferees[_grantee].length; ++i) {
                address _transferee = transferees[_grantee][i];
                MetaVesTDetails storage transfereeDetails = metavestDetails[_transferee];
                uint256 _transfereeAmount = transfereeDetails.rta.tokensRepurchasable / _divisor;
                transfereeDetails.allocation.tokenStreamTotal -= _transfereeAmount;
                transfereeDetails.rta.tokensRepurchasable -= _transfereeAmount;
                amountLocked[_transferee] -= _transfereeAmount;
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
    /// so as to avoid a mapping overwrite if the grantee's terminatedd MetaVesT is replaced with a new one before they can withdraw.
    /// Returns remainder to 'authority'
    /// @param _grantee: address of grantee whose MetaVesT is being terminated
    function terminate(address _grantee) external onlyController {
        MetaVesTDetails storage details = metavestDetails[_grantee];
        //'_grantee's' and all transferees' metavests are first refreshed in 'controller'
        address _tokenContract = details.allocation.tokenContract;
        uint256 _vested = details.allocation.tokensVested;

        // calculate amount to send to '_grantee'
        uint256 _amt = amountWithdrawable[_grantee][_tokenContract];

        // calculate locked unvested remainder to be returned to 'authority'
        uint256 _remainder = amountLocked[_grantee] - _vested - details.allocation.vestedTokensWithdrawn;

        // only include 'tokensVested' if the metavest type is not a token option, as that amount reflects vested but not exercised tokens, which is added to '_remainder'
        // since the metavest is being deleted, locked vested amounts are accelerated to unlocked
        if (details.metavestType != MetaVesTType.OPTION) _amt += _vested;
        else _remainder += _vested;

        // delete all mappings for '_grantee'
        delete metavestDetails[_grantee];
        delete amountWithdrawable[_grantee][_tokenContract];
        delete amountLocked[_grantee];
        delete linearUnlocked[_grantee];
        delete linearVested[_grantee];
        delete cliffAndMilestoneUnlocked[_grantee];
        delete cliffAndMilestoneVested[_grantee];

        if (transferees[_grantee].length != 0) {
            for (uint256 x; x < transferees[_grantee].length; ++x) {
                address _transferee = transferees[_grantee][x];
                MetaVesTDetails storage transfereeDetails = metavestDetails[_transferee];
                uint256 _transfereeAmt = amountWithdrawable[_transferee][_tokenContract];

                // add each transferee's locked remainder to be returned to 'authority'
                _remainder +=
                    amountLocked[_transferee] -
                    transfereeDetails.allocation.tokensVested -
                    transfereeDetails.allocation.unlockedTokensWithdrawn;

                // only include 'tokensVested' if the metavest type is not a token option, as that amount reflects vested but not exercised tokens, which is added to '_remainder'
                if (transfereeDetails.metavestType != MetaVesTType.OPTION)
                    _transfereeAmt += transfereeDetails.allocation.tokensVested;
                else _remainder += _vested;

                // delete all mappings for '_transferee'
                delete metavestDetails[_transferee];
                delete cliffAndMilestoneUnlocked[_transferee];
                delete cliffAndMilestoneVested[_transferee];
                delete linearUnlocked[_transferee];
                delete linearVested[_transferee];
                delete amountLocked[_transferee];
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

    /// @notice allows a grantee to transfer part or all of their MetaVesT to a '_transferee' if this MetaVest has transferability enabled
    /// @param _divisor: divisor corresponding to the grantee's fraction of their claim transferred via this function; i.e. for a transfer of 25% of a claim, submit '4'; to transfer the entire MetaVesT, submit '1'
    /// @param _transferee: address to which the claim is being transferred, that will have a new MetaVesT created
    function transferRights(uint256 _divisor, address _transferee) external {
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
        address _tokenContract = _allocation.tokenContract;

        // ensure MetaVesT exists and is transferable
        if (_metavestDetails.grantee == address(0) || msg.sender != _metavestDetails.grantee)
            revert MetaVesT_OnlyGrantee();
        if (!_metavestDetails.transferable) revert MetaVesT_NonTransferable();
        if (transferees[msg.sender].length == ARRAY_LENGTH_LIMIT) revert MetaVesT_TransfereeLimit();

        // update the current amountWithdrawable, if the msg.sender chooses to include it in the transfer by not first calling 'withdrawAll'
        uint256 _withdrawableTransferred = amountWithdrawable[msg.sender][_tokenContract] / _divisor;
        amountWithdrawable[_transferee][_tokenContract] = _withdrawableTransferred;
        amountWithdrawable[msg.sender][_tokenContract] -= _withdrawableTransferred;

        // update unlockedTokensWithdrawn, vestedTokensWithdrawn, cliffAndMilestoneUnlocked, linearUnlocked, and amountLocked similarly
        _allocation.unlockedTokensWithdrawn = _allocation.unlockedTokensWithdrawn / _divisor;
        details.allocation.unlockedTokensWithdrawn -= _allocation.unlockedTokensWithdrawn / _divisor;

        _allocation.vestedTokensWithdrawn = _allocation.vestedTokensWithdrawn / _divisor;
        details.allocation.vestedTokensWithdrawn -= _allocation.vestedTokensWithdrawn / _divisor;

        cliffAndMilestoneUnlocked[_transferee] = cliffAndMilestoneUnlocked[msg.sender] / _divisor;
        cliffAndMilestoneUnlocked[msg.sender] -= cliffAndMilestoneUnlocked[msg.sender] / _divisor;

        cliffAndMilestoneVested[_transferee] = cliffAndMilestoneVested[msg.sender] / _divisor;
        cliffAndMilestoneVested[msg.sender] -= cliffAndMilestoneVested[msg.sender] / _divisor;

        linearUnlocked[_transferee] = linearUnlocked[msg.sender] / _divisor;
        linearUnlocked[msg.sender] -= linearUnlocked[msg.sender] / _divisor;

        amountLocked[_transferee] = amountLocked[msg.sender] / _divisor;
        amountLocked[msg.sender] -= amountLocked[msg.sender] / _divisor;

        // transferee's MetaVesT should mirror the calling grantee's except for amounts and grantee address, so just update necessary elements in the MLOAD
        _allocation.tokenStreamTotal = _allocation.tokenStreamTotal / _divisor;
        _allocation.vestingCliffCredit = uint128(_allocation.vestingCliffCredit / _divisor);
        _allocation.unlockingCliffCredit = uint128(_allocation.unlockingCliffCredit / _divisor);
        _allocation.tokenGoverningPower = _allocation.tokenGoverningPower / _divisor;
        _allocation.tokensVested = _allocation.tokensVested / _divisor;
        _allocation.tokensUnlocked = _allocation.tokensUnlocked / _divisor;
        if (_metavestDetails.rta.tokensRepurchasable != 0)
            _metavestDetails.rta.tokensRepurchasable = _metavestDetails.rta.tokensRepurchasable / _divisor;

        // update milestoneAwards; completed milestones will pass 0
        if (_milestones.length != 0) {
            // manually copy milestones to avoid dynamic struct array -> storage erro
            for (uint256 i = 0; i < _milestones.length; ++i) {
                _milestones[i].milestoneAward = _milestones[i].milestoneAward / _divisor;
                transfereeDetail.milestones.push(_milestones[i]);
                // update grantee's array within same loop
                details.milestones[i].milestoneAward /= _milestones[i].milestoneAward;
            }
        }

        transferees[msg.sender].push(_transferee);

        // assign other transferee details manually using the updated '_metavestDetails', avoiding milestones
        transfereeDetail.grantee = _transferee;
        transfereeDetail.metavestType = _metavestDetails.metavestType;
        transfereeDetail.allocation = _allocation;
        transfereeDetail.option = _metavestDetails.option;
        transfereeDetail.rta = _metavestDetails.rta;
        transfereeDetail.eligibleTokens = _metavestDetails.eligibleTokens;
        transfereeDetail.transferable = _metavestDetails.transferable;

        for (uint256 i = 0; i < _milestones.length; ++i) {
            transfereeDetail.milestones.push(_milestones[i]);
        }

        details.allocation.tokenStreamTotal -= _allocation.tokenStreamTotal;
        details.allocation.vestingCliffCredit -= _allocation.vestingCliffCredit;
        details.allocation.unlockingCliffCredit -= _allocation.unlockingCliffCredit;
        details.allocation.tokenGoverningPower -= _allocation.tokenGoverningPower;
        details.allocation.tokensVested -= _allocation.tokensVested;
        details.allocation.tokensUnlocked -= _allocation.tokensUnlocked;
        details.allocation.tokenStreamTotal -= _allocation.tokenStreamTotal;
        if (_metavestDetails.rta.tokensRepurchasable != 0)
            details.rta.tokensRepurchasable -= _metavestDetails.rta.tokensRepurchasable;

        emit MetaVesT_Created(_metavestDetails);
        emit MetaVesT_TransferredRights(msg.sender, _transferee, _divisor);
    }

    /// @notice refresh the time-contingent details and amounts of '_grantee''s MetaVesT; if any tokens remain locked past the stopTime
    /// @dev updates the grantee's (and any transferees') 'tokensVested'
    /// @param _grantee: address whose MetaVesT is being refreshed, along with any transferees of such MetaVesT
    function refreshMetavest(address _grantee) public {
        // check whether MetaVesT for this grantee exists
        MetaVesTDetails storage details = metavestDetails[_grantee];

        if (details.grantee != _grantee || _grantee == address(0)) revert MetaVesT_NoMetaVesT();

        Allocation memory _allocation = details.allocation;
        uint256 _allocationTotal = _allocation.tokenStreamTotal;
        address _tokenContract = _allocation.tokenContract;
        MetaVesTType _type = details.metavestType;

        // separately calculate vesting and unlocking
        // vesting first
        uint256 _vestingStart = uint256(_allocation.vestingStartTime);
        uint256 _vestingEnd;

        // if token option, '_end' == exercise deadline; if RTA, '_end' == repurchase deadline
        if (_type == MetaVesTType.OPTION) _vestingEnd = uint256(details.option.shortStopTime);
        else if (_type == MetaVesTType.RESTRICTED) _vestingEnd = uint256(details.rta.shortStopTime);
        else _vestingEnd = uint256(_allocation.vestingStopTime);

        // calculate vest amounts, subtracting vested and withdrawn amounts
        if (block.timestamp < _vestingStart) {
            linearVested[_grantee] = 0;
        } else if (block.timestamp >= _vestingEnd) {
            // after '_end', vested == tokenStreamTotal + cliff and milestone amounts vested up until now - vestedTokensWithdrawn
            details.allocation.tokensVested =
                cliffAndMilestoneVested[_grantee] +
                _allocation.vestingCliffCredit +
                _allocationTotal -
                _allocation.vestedTokensWithdrawn;
            linearVested[_grantee] = _allocationTotal;
            // if token option, if long stop date reached, vested unexercised tokens are forfeited
            if (_type == MetaVesTType.OPTION && block.timestamp >= _allocation.vestingStopTime) {
                details.option.tokensForfeited += uint208(details.allocation.tokensVested);
                // make forfeited vested tokens withdrawable by 'authority'
                amountWithdrawable[authority][_tokenContract] += details.allocation.tokensVested;
                delete details.allocation.tokensVested;
                delete linearVested[_grantee];
            }
            // if RTA, if short stop date reached, unlocked tokens are not able to be repurchased by authority
            delete details.rta.tokensRepurchasable;
        } else {
            // new tokensVested = (vestRate * passed time since start) - preexisting 'linearVested' if the linear vest hasn't already been completed
            uint256 _newlyVested;
            if (linearVested[_grantee] != _allocationTotal)
                _newlyVested = (_allocation.vestingRate * (block.timestamp - _vestingStart)) - linearVested[_grantee];
            // make sure linear vest calculation does not surpass the token stream total, such as with a high vestRate; if so, calculate accordingly
            if (linearVested[_grantee] + _newlyVested <= _allocationTotal) {
                details.allocation.tokensVested += _newlyVested + _allocation.vestingCliffCredit; // add the newly vested amount (and the cliff, which == 0 after initial award by its deletion below) rather than re-assigning variable entirely as pre-existing vested amount was already subtracted
                if (details.rta.tokensRepurchasable >= _newlyVested) details.rta.tokensRepurchasable -= _newlyVested;
            } else {
                _newlyVested = 0;
                details.allocation.tokensVested =
                    _allocationTotal +
                    cliffAndMilestoneVested[_grantee] +
                    _allocation.vestingCliffCredit;
                linearVested[_grantee] = _allocationTotal;
            }
            // delete cliff credit. After the cliff is added the first time, subsequent calls will simply pass 0 throughout this function
            linearVested[_grantee] += _newlyVested;
            cliffAndMilestoneVested[_grantee] += _allocation.vestingCliffCredit;
            delete details.allocation.vestingCliffCredit;
        }

        // now calculating unlocking
        uint256 _unlockingStart = uint256(_allocation.unlockStartTime);
        uint256 _unlockingEnd = uint256(_allocation.unlockStopTime);

        // calculate unlock amounts, subtracting unlocked and withdrawn amounts
        if (block.timestamp < _unlockingStart) {
            linearUnlocked[_grantee] = 0;
        } else if (block.timestamp >= _unlockingEnd) {
            // after '_end', unlocked == tokenStreamTotal + cliff and milestone amounts unlocked up until now - unlockedTokensWithdrawn
            details.allocation.tokensUnlocked =
                cliffAndMilestoneUnlocked[_grantee] +
                _allocation.unlockingCliffCredit +
                _allocationTotal -
                _allocation.unlockedTokensWithdrawn;
            linearUnlocked[_grantee] = _allocationTotal;
        } else {
            // new tokensUnlocked = (unlockRate * passed time since start) - preexisting 'linearUnlocked' if the linear unlock hasn't already been completed
            uint256 _newlyUnlocked;
            if (linearUnlocked[_grantee] != _allocationTotal)
                _newlyUnlocked =
                    (_allocation.unlockRate * (block.timestamp - _unlockingStart)) -
                    linearUnlocked[_grantee];
            // make sure linear unlocked calculation does not surpass the token stream total, such as with a high unlockRate; if so, calculate accordingly
            if (linearUnlocked[_grantee] + _newlyUnlocked <= _allocationTotal) {
                details.allocation.tokensUnlocked += _newlyUnlocked + _allocation.unlockingCliffCredit; // add the newly unlocked amount (and the cliff, which == 0 after initial award by its deletion below) rather than re-assigning variable entirely as pre-existing unlocked amount was already subtracted
            } else {
                _newlyUnlocked = 0;
                details.allocation.tokensUnlocked =
                    _allocationTotal +
                    cliffAndMilestoneUnlocked[_grantee] +
                    _allocation.unlockingCliffCredit;
                linearUnlocked[_grantee] = _allocationTotal;
            }
            // delete cliff credit and remove the new unlocked amount from amountLocked mapping. After the cliff is added the first time, subsequent calls will simply pass 0 throughout this function
            linearUnlocked[_grantee] += _newlyUnlocked;
            cliffAndMilestoneUnlocked[_grantee] += _allocation.unlockingCliffCredit;
            delete details.allocation.unlockingCliffCredit;
        }

        // the smaller of the updated vested & unlocked (the overlapping amount, which is withdrawable) is deducted from amountLocked
        amountLocked[_grantee] -= _min(details.allocation.tokensVested, details.allocation.tokensUnlocked);

        // recalculate governing power
        delete details.allocation.tokenGoverningPower;
        if (details.eligibleTokens.locked) details.allocation.tokenGoverningPower += amountLocked[_grantee];
        if (details.eligibleTokens.unlocked)
            details.allocation.tokenGoverningPower += details.allocation.tokensUnlocked;
        if (details.eligibleTokens.vested) details.allocation.tokenGoverningPower += _allocation.tokensVested;

        // if claims were transferred, make similar updates (though note each start and end will be the same) for each transferee
        /// @dev this refreshes the "first level" of transferees; so a grantee's transferees will have their MetaVesTs refreshed, but
        /// for the second-level transferees of a transferee to have theirs' refreshed, the first-level transferee will have to refresh via this function
        if (transferees[_grantee].length != 0) {
            for (uint256 i; i < transferees[_grantee].length; ++i) {
                address _transferee = transferees[_grantee][i];
                MetaVesTDetails storage transfereeDetails = metavestDetails[_transferee];
                Allocation memory _transfereeAllocation = transfereeDetails.allocation;
                uint256 _totalStream = _transfereeAllocation.tokenStreamTotal;

                // vesting first
                if (block.timestamp < _vestingStart) {
                    linearVested[_transferee] = 0;
                } else if (block.timestamp >= _vestingEnd) {
                    // after '_end', vested == tokenStreamTotal + cliff and milestone amounts vested up until now - vestedTokensWithdrawn
                    transfereeDetails.allocation.tokensVested =
                        cliffAndMilestoneVested[_transferee] +
                        _transfereeAllocation.vestingCliffCredit +
                        _totalStream -
                        _transfereeAllocation.vestedTokensWithdrawn;
                    linearVested[_transferee] = _totalStream;
                    // if token option, if long stop date reached, vested unexercised tokens are forfeited and may be reclaimed by 'authority'
                    if (
                        transfereeDetails.metavestType == MetaVesTType.OPTION &&
                        block.timestamp >= _allocation.vestingStopTime
                    ) {
                        transfereeDetails.option.tokensForfeited += uint208(transfereeDetails.allocation.tokensVested);
                        // make forfeited vested tokens withdrawable by 'authority'
                        amountWithdrawable[authority][_tokenContract] += transfereeDetails.allocation.tokensVested;
                        delete transfereeDetails.allocation.tokensVested;
                        delete linearVested[_transferee];
                    }
                    // if RTA, if short stop date reached, vested tokens are not able to be repurchased by authority
                    delete transfereeDetails.rta.tokensRepurchasable;
                } else {
                    // new tokensVested = (vestingRate * passed time since start) - preexisting 'linearVested' if the linear vest hasn't already been completed
                    uint256 _newlyVested;
                    if (linearVested[_transferee] != _transfereeAllocation.tokenStreamTotal)
                        _newlyVested =
                            (_allocation.vestingRate * (block.timestamp - _vestingStart)) -
                            linearVested[_transferee];
                    // make sure linear vest calculation does not surpass the token stream total
                    if (linearVested[_transferee] + _newlyVested <= _totalStream) {
                        transfereeDetails.allocation.tokensVested +=
                            _newlyVested +
                            transfereeDetails.allocation.vestingCliffCredit;
                        if (transfereeDetails.rta.tokensRepurchasable >= _newlyVested)
                            transfereeDetails.rta.tokensRepurchasable -= _newlyVested;
                    } else {
                        _newlyVested = 0;
                        transfereeDetails.allocation.tokensVested =
                            _transfereeAllocation.tokenStreamTotal +
                            cliffAndMilestoneVested[_transferee] +
                            _transfereeAllocation.vestingCliffCredit;
                        linearVested[_transferee] = _transfereeAllocation.tokenStreamTotal;
                    }
                    // delete cliff credit. After the cliff is added the first time, later refreshes will simply pass 0
                    linearVested[_transferee] += _newlyVested;
                    cliffAndMilestoneVested[_transferee] += _transfereeAllocation.vestingCliffCredit;
                    delete transfereeDetails.allocation.vestingCliffCredit;
                }

                // now unlocking
                if (block.timestamp < _unlockingStart) {
                    linearUnlocked[_transferee] = 0;
                } else if (block.timestamp >= _unlockingEnd) {
                    // after '_end', unlocked == tokenStreamTotal + cliff and milestone amounts unlocked up until now - unlockedTokensWithdrawn
                    transfereeDetails.allocation.tokensUnlocked =
                        cliffAndMilestoneUnlocked[_transferee] +
                        _transfereeAllocation.unlockingCliffCredit +
                        _totalStream -
                        _transfereeAllocation.unlockedTokensWithdrawn;
                    linearUnlocked[_transferee] = _totalStream;
                } else {
                    // new tokensUnlocked = (unlockRate * passed time since start) - preexisting 'linearUnlocked' if the linear unlock hasn't already been completed
                    uint256 _newlyUnlocked;
                    if (linearUnlocked[_transferee] != _transfereeAllocation.tokenStreamTotal)
                        _newlyUnlocked =
                            (_allocation.unlockRate * (block.timestamp - _unlockingStart)) -
                            linearUnlocked[_transferee];
                    // make sure linear unlocked calculation does not surpass the token stream total
                    if (linearUnlocked[_transferee] + _newlyUnlocked <= _totalStream) {
                        transfereeDetails.allocation.tokensUnlocked +=
                            _newlyUnlocked +
                            transfereeDetails.allocation.unlockingCliffCredit;
                    } else {
                        _newlyUnlocked = 0;
                        transfereeDetails.allocation.tokensUnlocked =
                            _transfereeAllocation.tokenStreamTotal +
                            cliffAndMilestoneUnlocked[_transferee] +
                            _transfereeAllocation.unlockingCliffCredit;
                        linearUnlocked[_transferee] = _transfereeAllocation.tokenStreamTotal;
                    }
                    // delete cliff credit. After the cliff is added the first time, later refreshes will simply pass 0
                    linearUnlocked[_transferee] += _newlyUnlocked;
                    cliffAndMilestoneUnlocked[_transferee] += _transfereeAllocation.unlockingCliffCredit;
                    delete transfereeDetails.allocation.unlockingCliffCredit;
                }

                // the smaller of the updated vested & unlocked amount (the overlapping amount, which is withdrawable) is deducted from amountLocked
                amountLocked[_transferee] -= _min(
                    transfereeDetails.allocation.tokensVested,
                    transfereeDetails.allocation.tokensUnlocked
                );
                // recalculate governing power
                delete transfereeDetails.allocation.tokenGoverningPower;
                if (transfereeDetails.eligibleTokens.locked)
                    transfereeDetails.allocation.tokenGoverningPower += amountLocked[_transferee];
                if (transfereeDetails.eligibleTokens.unlocked)
                    transfereeDetails.allocation.tokenGoverningPower += _transfereeAllocation.tokensUnlocked;
                if (transfereeDetails.eligibleTokens.vested)
                    transfereeDetails.allocation.tokenGoverningPower += _transfereeAllocation.tokensVested;
            }
        }
    }

    /// @notice allows a grantee (or transferee) of a token option to exercise their option by paying the exercise price in 'paymentToken' for their amount of unlocked tokens, making such tokens withdrawable
    /// @param _amount amount of tokens msg.sender seeks to exercise in their token option
    function exerciseOption(uint256 _amount) external nonReentrant {
        refreshMetavest(msg.sender);

        MetaVesTDetails storage details = metavestDetails[msg.sender];
        Allocation storage detailsAllocation = details.allocation;
        address _tokenContract = detailsAllocation.tokenContract;
        if (msg.sender != details.grantee) revert MetaVesT_OnlyGrantee();
        if (details.metavestType != MetaVesTType.OPTION) revert MetaVesT_NoTokenOption();
        if (detailsAllocation.tokensVested < _amount) revert MetaVesT_AmountGreaterThanVested();

        uint256 _payment = _amount * details.option.exercisePrice;
        if (
            IERC20(paymentToken).allowance(msg.sender, address(this)) < _payment ||
            IERC20(paymentToken).balanceOf(msg.sender) < _payment
        ) revert MetaVesT_AmountNotApprovedForTransferFrom();

        safeTransferFrom(paymentToken, msg.sender, address(this), _payment);

        amountWithdrawable[controller][paymentToken] += _payment;

        // amount withdrawable to msg.sender is the amount that is both exercised and unlocked
        uint256 _amountWithdrawable = _min(_amount, detailsAllocation.tokensUnlocked);
        amountWithdrawable[msg.sender][_tokenContract] += _amountWithdrawable;
        detailsAllocation.unlockedTokensWithdrawn += _amountWithdrawable;
        detailsAllocation.vestedTokensWithdrawn += _amountWithdrawable;

        emit MetaVesT_OptionExercised(msg.sender, _tokenContract, _amount);
    }

    /// @notice allows an address to withdraw their 'amountWithdrawable' of their corresponding token in their MetaVesT, or amount of 'paymentToken' as a result of a tokenRepurchase
    /// @dev notice withdrawing does not affect the 'tokensVested' nor 'tokensUnlocked' variables, as these are preserved for calculations until the metavest's long stop times
    /// @param _tokenAddress the ERC20 token address which msg.sender is withdrawing, which should be either the 'metavestDetails[msg.sender].allocation.tokenContract' or 'paymentToken'
    function withdrawAll(address _tokenAddress) external nonReentrant {
        if (_tokenAddress == address(0)) revert MetaVesT_ZeroAddress();
        uint256 _amt;
        MetaVesTDetails storage details = metavestDetails[msg.sender];
        Allocation storage detailsAllocation = details.allocation;
        /// @dev if caller has a MetaVesT which is a Token Option, they must call 'exerciseOption' in order to exercise their option and make their 'tokensVested' (vested) withdrawable (up until the amount which is already unlocked) and then call this function, otherwise they would be withdrawing vested but not exercised tokens here
        if (
            msg.sender != authority &&
            msg.sender != controller &&
            _tokenAddress == detailsAllocation.tokenContract &&
            details.metavestType != MetaVesTType.OPTION
        ) {
            uint256 _preAmtWithdrawable = amountWithdrawable[msg.sender][_tokenAddress];
            refreshMetavest(msg.sender);

            if (msg.sender != details.grantee) revert MetaVesT_OnlyGrantee();

            uint256 _newlyWithdrawable = _min(
                detailsAllocation.tokensVested - detailsAllocation.vestedTokensWithdrawn,
                detailsAllocation.tokensUnlocked - detailsAllocation.unlockedTokensWithdrawn
            );
            // add newly withdrawable tokens to amountWithdrawable, unlockedTokensWithdrawn, and vestedTokensWithdrawn, since all are being withdrawn now
            amountWithdrawable[msg.sender][_tokenAddress] = _preAmtWithdrawable + _newlyWithdrawable;
            detailsAllocation.unlockedTokensWithdrawn += _newlyWithdrawable;
            detailsAllocation.vestedTokensWithdrawn += _newlyWithdrawable;
        }

        // delete the metavestDetails for this msg.sender if the token corresponds to a metavest and all their values are 0, as now all tokens are withdrawn as well (so we know after this call, no locked, unlocked, vested, nor withdrawable tokens will remain)
        if (
            _tokenAddress == detailsAllocation.tokenContract &&
            amountLocked[msg.sender] == 0 &&
            detailsAllocation.tokensUnlocked == detailsAllocation.unlockedTokensWithdrawn &&
            detailsAllocation.tokensVested == detailsAllocation.vestedTokensWithdrawn
        ) delete metavestDetails[msg.sender];
        emit MetaVesT_Deleted(msg.sender);

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
        /// @dev if caller has a MetaVesT which is a Token Option, they must call 'exerciseOption' in order to exercise their option and make their 'tokensVested' (vested) withdrawable and then call this function, otherwise they would be withdrawing vested but not exercised tokens here
        if (
            msg.sender != authority &&
            msg.sender != controller &&
            _tokenAddress == detailsAllocation.tokenContract &&
            details.metavestType != MetaVesTType.OPTION
        ) {
            uint256 _preAmtWithdrawable = amountWithdrawable[msg.sender][_tokenAddress];
            refreshMetavest(msg.sender);

            if (msg.sender != details.grantee) revert MetaVesT_OnlyGrantee();

            uint256 _newlyWithdrawable = _min(
                detailsAllocation.tokensVested - detailsAllocation.vestedTokensWithdrawn,
                detailsAllocation.tokensUnlocked - detailsAllocation.unlockedTokensWithdrawn
            );

            amountWithdrawable[msg.sender][_tokenAddress] = _preAmtWithdrawable + _newlyWithdrawable;
            detailsAllocation.unlockedTokensWithdrawn += _newlyWithdrawable;
            detailsAllocation.vestedTokensWithdrawn += _newlyWithdrawable;
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
