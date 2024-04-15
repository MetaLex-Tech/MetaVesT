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

/// @notice interface to a BORG-Core condition contract
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

/// @notice gas-optimized reentrancy protection for smart contracts by Solady (https://github.com/Vectorized/solady/blob/main/src/utils/ReentrancyGuard.sol)
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
 *             on a per-BORG or per-DAO (including per-authority) basis, supporting multiple grantees and tokens and all
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
        TokenOption option; // struct containing token option-specific details
        RestrictedTokenAward rta; // struct containing restricted token award-specific details
        GovEligibleTokens eligibleTokens;
        Milestone[] milestones;
        address grantee;
        bool transferable; // whether grantee can transfer their MetaVesT in whole or in part to other addresses
    }

    struct Allocation {
        uint256 tokenStreamTotal; // total number of tokens subject to linear unlocking/vesting/restriction removal (does NOT include 'cliffCredit' nor each 'milestoneAward')
        uint256 cliffCredit; // lump sum of tokens which become withdrawable (note: not added to 'tokensUnlocked' so as not to disrupt calculations) at 'startTime'
        uint256 tokenGoverningPower; // number of tokens able to be staked/voted/otherwise used in 'dao' governance
        uint256 tokensUnlocked; // available but not withdrawn -- if OPTION this amount corresponds to 'vested'; if RESTRICTED this amount corresponds to 'unrestricted';
        uint256 unlockedTokensWithdrawn; // number of tokens withdrawn that were previously 'tokensUnlocked', for unlocking calculations
        uint208 unlockRate; // if OPTION this amount corresponds to 'vesting rate'; if RESTRICTED this amount corresponds to 'lapse rate'; up to 4.11 x 10^42 tokens per sec
        address tokenContract;
        uint48 startTime; // if OPTION this amount corresponds to 'vesting start time'; if RESTRICTED this amount corresponds to 'lapse start time'
        uint48 stopTime; // if ALLOCATION this is the end of the linear unlock; if OPTION or RESTRICTED this is the 'long stop time'
    }

    struct TokenOption {
        uint256 exercisePrice; // amount of 'paymentToken' per token exercised
        uint208 tokensForfeited; // tokens able to be withdrawn by authority as no longer exercisable
        uint48 shortStopTime; // vesting stop time and exercise deadline, must be <= Allocation.stopTime, which is the long stop time at which time unexercised tokens become 'tokensForfeited'
    }

    struct RestrictedTokenAward {
        uint256 repurchasePrice; // amount of 'paymentToken' per token repurchased
        uint256 tokensRepurchasable; // amount of locked, repurchasable tokens
        uint48 shortStopTime; // lapse stop time and repurchase deadline, must be <= Allocation.stopTime, at which time 'tokensRepurchasable' == 0
    }

    struct GovEligibleTokens {
        bool locked; // whether 'amountLocked' counts towards 'tokenGoverningPower'
        bool unlocked; // whether 'tokensUnlocked' counts towards 'tokenGoverningPower'
        bool withdrawable; // whether 'amountWithdrawable' counts towards 'tokenGoverningPower'
    }

    struct Milestone {
        bool complete;
        uint256 milestoneAward; // per-milestone indexed lump sums of tokens unlocked upon corresponding milestone completion
        address[] conditionContracts;
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

    /// @notice maps address to tokens unlocked via linear unlocking, to ease unlocking calculations
    mapping(address => uint256) internal linearUnlocked;

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
    event MetaVesT_StopTimesUpdated(address grantee, uint48 stopTime, uint48 shortStopTime);
    event MetaVesT_TransferabilityUpdated(address grantee, bool isTransferable);
    event MetaVesT_TransferredRights(address grantee, address transferee, uint256 divisor);
    event MetaVesT_UnlockRateUpdated(address grantee, uint208 unlockRate);
    event MetaVesT_Withdrawal(address withdrawer, address tokenContract, uint256 amount);

    ///
    /// ERRORS
    ///

    error MetaVesT_AlreadyExists();
    error MetaVesT_AmountGreaterThanUnlocked();
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

    /// @notice creates a MetaVesT for a grantee and locks the total token amount ('metavestDetails.allocation.tokenStreamTotal' + 'metavestDetails.allocation.cliffCredit' + each 'metavestDetails.milestones.milestoneAward')
    /// @dev see MetaVesTController for conditionals and additional comments
    /// @param _metavestDetails: MetaVesTDetails struct containing all applicable details for this '_metavestDetails.grantee'-- but MUST contain grantee, token contract, amount, and start and stop time
    /// @param _total: total amount of tokens being locked
    function createMetavest(
        MetaVesTDetails calldata _metavestDetails,
        uint256 _total
    ) external onlyController nonReentrant {
        // delete and manually copy milestones to avoid dynamic struct array -> storage error
        delete metavestDetails[_metavestDetails.grantee].milestones;
        for (uint256 i = 0; i < _metavestDetails.milestones.length; ++i) {
            metavestDetails[_metavestDetails.grantee].milestones.push(_metavestDetails.milestones[i]);
        }

        // assign other details manually, avoiding milestones
        MetaVesTDetails storage detail = metavestDetails[_metavestDetails.grantee];
        detail.metavestType = _metavestDetails.metavestType;
        detail.allocation = _metavestDetails.allocation;
        detail.option = _metavestDetails.option;
        detail.rta = _metavestDetails.rta;
        detail.eligibleTokens = _metavestDetails.eligibleTokens;
        detail.grantee = _metavestDetails.grantee;
        detail.transferable = _metavestDetails.transferable;

        amountLocked[_metavestDetails.grantee] += _total;
        // ensure tokensRepurchasable is == _total, if RTA
        if (_metavestDetails.metavestType == MetaVesTType.RESTRICTED)
            metavestDetails[_metavestDetails.grantee].rta.tokensRepurchasable = _total;

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
    /// @param _unlockRate token unlock rate for allocations, 'vesting rate' for options, and 'lapse rate' for restricted token award; up to 4.11 x 10^42 tokens per sec
    function updateUnlockRate(address _grantee, uint208 _unlockRate) external onlyController {
        metavestDetails[_grantee].allocation.unlockRate = _unlockRate;

        // replicate for transferees
        if (transferees[_grantee].length != 0) {
            for (uint256 i; i < transferees[_grantee].length; ++i) {
                metavestDetails[transferees[_grantee][i]].allocation.unlockRate = _unlockRate;
            }
        }
        emit MetaVesT_UnlockRateUpdated(_grantee, _unlockRate);
    }

    /// @notice for authority to update a MetaVesT's stopTime and/or shortStopTime, as applicable (including any transferees)
    /// @dev 'controller' carries the conditional checks for '_stopTime', but note that if '_shortStopTime' has already occurred, it will be ignored rather than revert
    /// @param _grantee address of grantee whose MetaVesT is being updated
    /// @param _stopTime if allocation this is the end of the linear unlock; if token option or restricted token award this is the 'long stop time'
    /// @param _shortStopTime if token option, vesting stop time and exercise deadline; if restricted token award, lapse stop time and repurchase deadline -- must be <= stopTime
    function updateStopTimes(address _grantee, uint48 _stopTime, uint48 _shortStopTime) external onlyController {
        metavestDetails[_grantee].allocation.stopTime = _stopTime;
        MetaVesTType _type = metavestDetails[_grantee].metavestType;

        // ensure both the existing and new short stop times haven't been met, or ignore if MetaVesTType == ALLOCATION
        if (
            _type == MetaVesTType.OPTION &&
            metavestDetails[_grantee].option.shortStopTime > block.timestamp &&
            _shortStopTime > block.timestamp
        ) {
            metavestDetails[_grantee].option.shortStopTime = _shortStopTime;
            if (transferees[_grantee].length != 0) {
                for (uint256 i; i < transferees[_grantee].length; ++i) {
                    metavestDetails[transferees[_grantee][i]].allocation.stopTime = _stopTime;
                    metavestDetails[transferees[_grantee][i]].option.shortStopTime = _shortStopTime;
                }
            }
        } else if (
            _type == MetaVesTType.RESTRICTED &&
            metavestDetails[_grantee].rta.shortStopTime > block.timestamp &&
            _shortStopTime > block.timestamp
        ) {
            metavestDetails[_grantee].rta.shortStopTime = _shortStopTime;
            if (transferees[_grantee].length != 0) {
                for (uint256 i; i < transferees[_grantee].length; ++i) {
                    metavestDetails[transferees[_grantee][i]].allocation.stopTime = _stopTime;
                    metavestDetails[transferees[_grantee][i]].rta.shortStopTime = _shortStopTime;
                }
            }
        } else {
            if (transferees[_grantee].length != 0) {
                for (uint256 i; i < transferees[_grantee].length; ++i) {
                    metavestDetails[transferees[_grantee][i]].allocation.stopTime = _stopTime;
                }
            }
        }
        emit MetaVesT_StopTimesUpdated(_grantee, _stopTime, _shortStopTime);
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
        MetaVesTDetails memory _metavestDetails = metavestDetails[_grantee];

        if (
            _milestoneIndex > _metavestDetails.milestones.length ||
            _metavestDetails.milestones[_milestoneIndex].complete
        ) revert MetaVesT_MilestoneIndexCompletedOrDoesNotExist();

        // perform any applicable condition checks, including whether 'authority' has a signatureCondition
        for (uint256 i; i < _metavestDetails.milestones[_milestoneIndex].conditionContracts.length; ++i) {
            if (!ICondition(_metavestDetails.milestones[_milestoneIndex].conditionContracts[i]).checkCondition())
                revert MetaVesT_ConditionNotSatisfied(
                    _metavestDetails.milestones[_milestoneIndex].conditionContracts[i]
                );
        }

        unchecked {
            metavestDetails[_grantee].allocation.tokensUnlocked += _metavestDetails
                .milestones[_milestoneIndex]
                .milestoneAward; // cannot overflow as milestoneAwards cannot cumulatively be greater that tokenStreamTotal
            cliffAndMilestoneUnlocked[_grantee] += _metavestDetails.milestones[_milestoneIndex].milestoneAward;
            amountLocked[_metavestDetails.grantee] -= _metavestDetails.milestones[_milestoneIndex].milestoneAward; // cannot underflow as milestoneAwards cannot be cumulatively be greater than the amountLocked
            if (_metavestDetails.metavestType == MetaVesTType.RESTRICTED)
                metavestDetails[_grantee].rta.tokensRepurchasable -= _metavestDetails
                    .milestones[_milestoneIndex]
                    .milestoneAward;
        }

        //delete award and mark complete after adding to unlocked amount and deducting from amount locked
        delete metavestDetails[_grantee].milestones[_milestoneIndex].milestoneAward;
        metavestDetails[_grantee].milestones[_milestoneIndex].complete = true;

        // if claims were transferred, make similar updates (start and end time will be the same) for each transferee of this '_grantee'
        // condition contracts are the same, so no need to re-check in the same txn
        if (transferees[_grantee].length != 0) {
            for (uint256 i; i < transferees[_grantee].length; ++i) {
                address _addr = transferees[_grantee][i];
                uint256 _award = metavestDetails[_addr].milestones[_milestoneIndex].milestoneAward;
                unchecked {
                    metavestDetails[_addr].allocation.tokensUnlocked += _award;
                    cliffAndMilestoneUnlocked[_addr] += _award;
                    amountLocked[_addr] -= _award;
                    if (_metavestDetails.metavestType == MetaVesTType.RESTRICTED)
                        metavestDetails[_addr].rta.tokensRepurchasable -= _award;
                }
                //delete award after adding to amount withdrawable and deducting from amount locked, and mark complete
                delete metavestDetails[_addr].milestones[_milestoneIndex].milestoneAward;
                metavestDetails[_addr].milestones[_milestoneIndex].complete = true;
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
        uint256 _removedMilestoneAmount = metavestDetails[_grantee].milestones[_milestoneIndex].milestoneAward;

        amountWithdrawable[controller][_tokenContract] += _removedMilestoneAmount;
        amountLocked[_grantee] -= _removedMilestoneAmount;

        delete metavestDetails[_grantee].milestones[_milestoneIndex];

        bool _rta;
        // ensure tokensRepurchasable subtracts deleted amount, if RTA
        if (metavestDetails[_grantee].rta.tokensRepurchasable != 0) {
            metavestDetails[_grantee].rta.tokensRepurchasable -= _removedMilestoneAmount;
            _rta = true;
        }

        // replicate for transferees
        if (transferees[_grantee].length != 0) {
            for (uint256 i; i < transferees[_grantee].length; ++i) {
                address _transferee = transferees[_grantee][i];
                uint256 _transfereeRemovedMilestoneAmount = metavestDetails[_transferee]
                    .milestones[_milestoneIndex]
                    .milestoneAward;

                amountWithdrawable[controller][_tokenContract] += _transfereeRemovedMilestoneAmount;
                amountLocked[_transferee] -= _transfereeRemovedMilestoneAmount;
                if (_rta) metavestDetails[_transferee].rta.tokensRepurchasable -= _transfereeRemovedMilestoneAmount;

                delete metavestDetails[_transferee].milestones[_milestoneIndex];

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
        // ensure tokensRepurchasable is == _total, if RTA
        if (metavestDetails[_grantee].metavestType == MetaVesTType.RESTRICTED)
            metavestDetails[_grantee].rta.tokensRepurchasable += _milestone.milestoneAward;

        metavestDetails[_grantee].milestones.push(_milestone);

        // add to milestone array length but not amount for current transferees
        if (transferees[_grantee].length != 0) {
            for (uint256 i; i < transferees[_grantee].length; ++i) {
                metavestDetails[transferees[_grantee][i]].milestones.push(_milestone);
                metavestDetails[transferees[_grantee][i]]
                    .milestones[metavestDetails[transferees[_grantee][i]].milestones.length]
                    .milestoneAward = 0;
            }
        }
        emit MetaVesT_MilestoneAdded(_grantee, _milestone);
    }

    /// @notice for the controller to update either exercisePrice or repurchasePrice for a '_grantee' and their transferees, as applicable depending on the MetaVesTType
    /// @param _grantee address of grantee whose applicable price is being updated
    /// @param _newPrice new price (in 'paymentToken' per token)
    function updatePrice(address _grantee, uint256 _newPrice) external onlyController {
        MetaVesTType _type = metavestDetails[_grantee].metavestType;
        if (_type == MetaVesTType.OPTION) {
            metavestDetails[_grantee].option.exercisePrice = _newPrice;
            // update transferees' price
            if (transferees[_grantee].length != 0) {
                for (uint256 i; i < transferees[_grantee].length; ++i) {
                    metavestDetails[transferees[_grantee][i]].option.exercisePrice = _newPrice;
                }
            }
            emit MetaVesT_ExercisePriceUpdated(_grantee, _newPrice);
        } else if (_type == MetaVesTType.RESTRICTED) {
            metavestDetails[_grantee].rta.repurchasePrice = _newPrice;
            // update transferees' price
            if (transferees[_grantee].length != 0) {
                for (uint256 i; i < transferees[_grantee].length; ++i) {
                    metavestDetails[transferees[_grantee][i]].option.exercisePrice = _newPrice;
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
    function repurchaseTokens(address _grantee, uint256 _divisor) external onlyController nonReentrant {
        address _repurchasedToken = metavestDetails[_grantee].allocation.tokenContract;
        uint256 _amount = metavestDetails[_grantee].rta.tokensRepurchasable / _divisor;

        metavestDetails[_grantee].allocation.unlockedTokensWithdrawn += _amount;
        metavestDetails[_grantee].rta.tokensRepurchasable -= _amount;
        metavestDetails[_grantee].allocation.tokenStreamTotal -= _amount;
        amountWithdrawable[_grantee][paymentToken] += _amount * metavestDetails[_grantee].rta.repurchasePrice;
        amountLocked[_grantee] -= _amount;

        if (transferees[_grantee].length != 0) {
            for (uint256 i; i < transferees[_grantee].length; ++i) {
                address _transferee = transferees[_grantee][i];
                uint256 _transfereeAmount = metavestDetails[_transferee].rta.tokensRepurchasable / _divisor;
                metavestDetails[_transferee].allocation.unlockedTokensWithdrawn += _transfereeAmount;
                metavestDetails[_transferee].allocation.tokenStreamTotal -= _transfereeAmount;
                metavestDetails[_transferee].rta.tokensRepurchasable -= _transfereeAmount;
                amountWithdrawable[_transferee][paymentToken] +=
                    _transfereeAmount *
                    metavestDetails[_transferee].rta.repurchasePrice;
                amountLocked[_transferee] -= _transfereeAmount;
                _amount += _transfereeAmount;
            }
        }

        // transfer all repurchased tokens to 'authority'
        safeTransfer(_repurchasedToken, authority, _amount);
        emit MetaVesT_RepurchaseAndWithdrawal(_grantee, _repurchasedToken, _amount);
    }

    /// @notice for the applicable authority to terminate and delete this '_grantee''s MetaVesT via the controller
    /// @dev conditionals for this function are in the 'controller'; makes all unlockedTokens for such grantee withdrawable then sends them to grantee,
    /// so as to avoid a mapping overwrite if the grantee's terminatedd MetaVesT is replaced with a new one before they can withdraw.
    /// Returns remainder to 'authority'
    /// @param _grantee: address of grantee whose MetaVesT is being terminated
    function terminate(address _grantee) external onlyController nonReentrant {
        //'_grantee's' and all transferees' metavests are first refreshed in 'controller'
        MetaVesTDetails memory _metavestDetails = metavestDetails[_grantee];

        // calculate amount to send to '_grantee'
        uint256 _amt = amountWithdrawable[_grantee][_metavestDetails.allocation.tokenContract];

        // calculate locked remainder to be returned to 'authority'
        uint256 _remainder = amountLocked[_grantee] -
            _metavestDetails.allocation.tokensUnlocked -
            _metavestDetails.allocation.unlockedTokensWithdrawn;

        // only include 'tokensUnlocked' if the metavest type is not a token option, as that amount reflects vested but not exercised tokens, which is added to '_remainder'
        if (_metavestDetails.metavestType != MetaVesTType.OPTION) _amt += _metavestDetails.allocation.tokensUnlocked;
        else _remainder += _metavestDetails.allocation.tokensUnlocked;

        // delete all mappings for '_grantee'
        delete metavestDetails[_grantee];
        delete amountWithdrawable[_grantee][_metavestDetails.allocation.tokenContract];
        delete amountLocked[_grantee];
        delete linearUnlocked[_grantee];
        delete cliffAndMilestoneUnlocked[_grantee];

        if (transferees[_grantee].length != 0) {
            for (uint256 x; x < transferees[_grantee].length; ++x) {
                address _addr = transferees[_grantee][x];
                uint256 _transfereeAmt = amountWithdrawable[_addr][_metavestDetails.allocation.tokenContract];

                // add each transferee's locked remainder to be returned to 'authority'
                _remainder +=
                    amountLocked[_addr] -
                    metavestDetails[_addr].allocation.tokensUnlocked -
                    metavestDetails[_addr].allocation.unlockedTokensWithdrawn;

                // only include 'tokensUnlocked' if the metavest type is not a token option, as that amount reflects vested but not exercised tokens, which is added to '_remainder'
                if (metavestDetails[_addr].metavestType != MetaVesTType.OPTION)
                    _transfereeAmt += metavestDetails[_addr].allocation.tokensUnlocked;
                else _remainder += _metavestDetails.allocation.tokensUnlocked;

                // delete all mappings for '_addr'
                delete metavestDetails[_addr];
                delete cliffAndMilestoneUnlocked[_addr];
                delete linearUnlocked[_addr];
                delete amountLocked[_addr];
                delete amountWithdrawable[_addr][_metavestDetails.allocation.tokenContract];
                safeTransfer(_metavestDetails.allocation.tokenContract, _addr, _transfereeAmt);

                emit MetaVesT_Deleted(_addr);
                emit MetaVesT_Withdrawal(_addr, _metavestDetails.allocation.tokenContract, _transfereeAmt);
            }
        }

        delete transferees[_grantee];

        safeTransfer(_metavestDetails.allocation.tokenContract, _grantee, _amt);
        safeTransfer(_metavestDetails.allocation.tokenContract, authority, _remainder);

        emit MetaVesT_Deleted(_grantee);
        emit MetaVesT_Withdrawal(_grantee, _metavestDetails.allocation.tokenContract, _amt);
        emit MetaVesT_Withdrawal(authority, _metavestDetails.allocation.tokenContract, _remainder);
    }

    /// @notice allows a grantee to transfer part or all of their MetaVesT to a '_transferee' if this MetaVest has transferability enabled
    /// @param _divisor: divisor corresponding to the grantee's fraction of their claim transferred via this function; i.e. for a transfer of 25% of a claim, submit '4'; to transfer the entire MetaVesT, submit '1'
    /// @param _transferee: address to which the claim is being transferred, that will have a new MetaVesT created
    function transferRights(uint256 _divisor, address _transferee) external {
        if (_divisor == 0) revert MetaVesT_ZeroAmount();
        if (_transferee == address(0)) revert MetaVesT_ZeroAddress();
        // prevent potential overwrite of existing MetaVesT
        if (metavestDetails[_transferee].grantee != address(0) || _transferee == authority || _transferee == controller)
            revert MetaVesT_AlreadyExists();

        refreshMetavest(msg.sender);

        MetaVesTDetails memory _metavestDetails = metavestDetails[msg.sender];

        // ensure MetaVesT exists and is transferable
        if (_metavestDetails.grantee == address(0) || msg.sender != _metavestDetails.grantee)
            revert MetaVesT_OnlyGrantee();
        if (!_metavestDetails.transferable) revert MetaVesT_NonTransferable();
        if (transferees[msg.sender].length == ARRAY_LENGTH_LIMIT) revert MetaVesT_TransfereeLimit();

        // update the current amountWithdrawable, if the msg.sender chooses to include it in the transfer by not first calling 'withdrawAll'
        uint256 _withdrawableTransferred = amountWithdrawable[msg.sender][_metavestDetails.allocation.tokenContract] /
            _divisor;
        amountWithdrawable[_transferee][_metavestDetails.allocation.tokenContract] = _withdrawableTransferred;
        amountWithdrawable[msg.sender][_metavestDetails.allocation.tokenContract] -= _withdrawableTransferred;

        // update unlockedTokensWithdrawn, cliffAndMilestoneUnlocked, linearUnlocked, and amountLocked similarly
        uint256 _unlockedWithdrawnTransferred = _metavestDetails.allocation.unlockedTokensWithdrawn / _divisor;
        _metavestDetails.allocation.unlockedTokensWithdrawn = _unlockedWithdrawnTransferred;
        metavestDetails[msg.sender].allocation.unlockedTokensWithdrawn -= _unlockedWithdrawnTransferred;

        uint256 _cliffAndMilestoneUnlockedTransferred = cliffAndMilestoneUnlocked[msg.sender] / _divisor;
        cliffAndMilestoneUnlocked[_transferee] = _cliffAndMilestoneUnlockedTransferred;
        cliffAndMilestoneUnlocked[msg.sender] -= _cliffAndMilestoneUnlockedTransferred;

        uint256 _linearUnlockedTransferred = linearUnlocked[msg.sender] / _divisor;
        linearUnlocked[_transferee] = _linearUnlockedTransferred;
        linearUnlocked[msg.sender] -= _linearUnlockedTransferred;

        uint256 _lockedAmtTransferred = amountLocked[msg.sender] / _divisor;
        amountLocked[_transferee] = _lockedAmtTransferred;
        amountLocked[msg.sender] -= _lockedAmtTransferred;

        // transferee's MetaVesT should mirror the calling grantee's except for amounts and grantee address, so just update necessary elements in the MLOAD
        _metavestDetails.allocation.tokenStreamTotal = _metavestDetails.allocation.tokenStreamTotal / _divisor;
        _metavestDetails.allocation.cliffCredit = _metavestDetails.allocation.cliffCredit / _divisor;
        _metavestDetails.allocation.tokenGoverningPower = _metavestDetails.allocation.tokenGoverningPower / _divisor;
        _metavestDetails.allocation.tokensUnlocked = _metavestDetails.allocation.tokensUnlocked / _divisor;
        if (_metavestDetails.rta.tokensRepurchasable != 0)
            _metavestDetails.rta.tokensRepurchasable = _metavestDetails.rta.tokensRepurchasable / _divisor;
        // update milestoneAwards; completed milestones will pass 0
        if (_metavestDetails.milestones.length != 0) {
            // delete and manually copy milestones to avoid dynamic struct array -> storage error
            delete metavestDetails[_transferee].milestones;
            for (uint256 i = 0; i < _metavestDetails.milestones.length; ++i) {
                _metavestDetails.milestones[i].milestoneAward =
                    _metavestDetails.milestones[i].milestoneAward /
                    _divisor;
                metavestDetails[_transferee].milestones.push(_metavestDetails.milestones[i]);
                // update grantee's array within same loop
                metavestDetails[msg.sender].milestones[i].milestoneAward /= _metavestDetails
                    .milestones[i]
                    .milestoneAward;
            }
        }

        // update caller's stored MetaVesT by subtracting the amounts in transferee's MetaVesT
        // delete and manually copy milestones to avoid dynamic struct array -> storage error
        delete metavestDetails[_transferee].milestones;
        for (uint256 i = 0; i < _metavestDetails.milestones.length; ++i) {
            metavestDetails[_transferee].milestones.push(_metavestDetails.milestones[i]);
        }

        metavestDetails[msg.sender].allocation.tokenStreamTotal -= _metavestDetails.allocation.tokenStreamTotal;
        metavestDetails[msg.sender].allocation.cliffCredit -= _metavestDetails.allocation.cliffCredit;
        metavestDetails[msg.sender].allocation.tokenGoverningPower -= _metavestDetails.allocation.tokenGoverningPower;
        metavestDetails[msg.sender].allocation.tokensUnlocked -= _metavestDetails.allocation.tokensUnlocked;
        metavestDetails[msg.sender].allocation.tokenStreamTotal -= _metavestDetails.allocation.tokenStreamTotal;
        if (_metavestDetails.rta.tokensRepurchasable != 0)
            metavestDetails[msg.sender].rta.tokensRepurchasable -= _metavestDetails.rta.tokensRepurchasable;

        transferees[msg.sender].push(_transferee);

        // assign other transferee details manually using the updated '_metavestDetails', avoiding milestones
        MetaVesTDetails storage detail = metavestDetails[_transferee];
        detail.grantee = _transferee;
        detail.metavestType = _metavestDetails.metavestType;
        detail.allocation = _metavestDetails.allocation;
        detail.option = _metavestDetails.option;
        detail.rta = _metavestDetails.rta;
        detail.eligibleTokens = _metavestDetails.eligibleTokens;
        detail.transferable = _metavestDetails.transferable;

        emit MetaVesT_Created(_metavestDetails);
        emit MetaVesT_TransferredRights(msg.sender, _transferee, _divisor);
    }

    /// @notice refresh the time-contingent details and amounts of '_grantee''s MetaVesT; if any tokens remain locked past the stopTime
    /// @dev updates the grantee's (and any transferees') 'tokensUnlocked'
    /// @param _grantee: address whose MetaVesT is being refreshed, along with any transferees of such MetaVesT
    function refreshMetavest(address _grantee) public {
        // check whether MetaVesT for this grantee exists
        if (metavestDetails[_grantee].grantee != _grantee || _grantee == address(0)) revert MetaVesT_NoMetaVesT();

        MetaVesTDetails memory _metavestDetails = metavestDetails[_grantee];

        uint256 _start = uint256(_metavestDetails.allocation.startTime);
        uint256 _end;

        // if token option, '_end' == exercise deadline; if RTA, '_end' == repurchase deadline
        if (_metavestDetails.metavestType == MetaVesTType.OPTION) _end = uint256(_metavestDetails.option.shortStopTime);
        else if (_metavestDetails.metavestType == MetaVesTType.RESTRICTED)
            _end = uint256(_metavestDetails.rta.shortStopTime);
        else _end = uint256(_metavestDetails.allocation.stopTime);

        // calculate unlock amounts, subtracting unlocked and withdrawn amounts
        if (block.timestamp < _start) {
            linearUnlocked[_grantee] = 0;
        } else if (block.timestamp >= _end) {
            // after '_end', unlocked == tokenStreamTotal + cliff and milestone amounts unlocked up until now - unlockedTokensWithdrawn
            metavestDetails[_grantee].allocation.tokensUnlocked =
                cliffAndMilestoneUnlocked[_grantee] +
                _metavestDetails.allocation.cliffCredit +
                _metavestDetails.allocation.tokenStreamTotal -
                _metavestDetails.allocation.unlockedTokensWithdrawn;
            linearUnlocked[_grantee] = _metavestDetails.allocation.tokenStreamTotal;
            // if token option, if long stop date reached, unlocked unexercised tokens are forfeited
            if (
                _metavestDetails.metavestType == MetaVesTType.OPTION &&
                block.timestamp >= _metavestDetails.allocation.stopTime
            ) {
                metavestDetails[_grantee].option.tokensForfeited += uint208(
                    metavestDetails[_grantee].allocation.tokensUnlocked
                );
                // make forfeited unlocked tokens withdrawable by 'authority'
                amountWithdrawable[authority][_metavestDetails.allocation.tokenContract] += metavestDetails[_grantee]
                    .allocation
                    .tokensUnlocked;
                delete metavestDetails[_grantee].allocation.tokensUnlocked;
                delete linearUnlocked[_grantee];
            }
            // if RTA, if short stop date reached, unlocked tokens are not able to be repurchased by authority
            else if (_metavestDetails.metavestType == MetaVesTType.RESTRICTED)
                delete metavestDetails[_grantee].rta.tokensRepurchasable;
        } else {
            // new tokensUnlocked = (unlockRate * passed time since start) - preexisting 'linearUnlocked' if the linear unlock hasn't already been completed
            uint256 _newlyUnlocked;
            if (linearUnlocked[_grantee] != _metavestDetails.allocation.tokenStreamTotal)
                _newlyUnlocked =
                    (_metavestDetails.allocation.unlockRate * (block.timestamp - _start)) -
                    linearUnlocked[_grantee];
            // make sure linear unlocked calculation does not surpass the token stream total, such as with a high unlockRate; if so, calculate accordingly
            if (linearUnlocked[_grantee] + _newlyUnlocked <= _metavestDetails.allocation.tokenStreamTotal) {
                metavestDetails[_grantee].allocation.tokensUnlocked +=
                    _newlyUnlocked +
                    _metavestDetails.allocation.cliffCredit; // add the newly unlocked amount (and the cliff, which == 0 after initial award by its deletion below) rather than re-assigning variable entirely as pre-existing unlocked amount was already subtracted
                if (_metavestDetails.rta.tokensRepurchasable >= _newlyUnlocked)
                    metavestDetails[_grantee].rta.tokensRepurchasable -= _newlyUnlocked;
            } else {
                _newlyUnlocked = 0;
                metavestDetails[_grantee].allocation.tokensUnlocked =
                    _metavestDetails.allocation.tokenStreamTotal +
                    cliffAndMilestoneUnlocked[_grantee] +
                    _metavestDetails.allocation.cliffCredit;
                linearUnlocked[_grantee] = _metavestDetails.allocation.tokenStreamTotal;
            }
            // delete cliff credit and remove the new unlocked amount from amountLocked mapping. After the cliff is added the first time, subsequent calls will simply pass 0 throughout this function
            amountLocked[_grantee] -= metavestDetails[_grantee].allocation.tokensUnlocked;
            linearUnlocked[_grantee] += _newlyUnlocked;
            cliffAndMilestoneUnlocked[_grantee] += _metavestDetails.allocation.cliffCredit;
            delete metavestDetails[_grantee].allocation.cliffCredit;
        }

        // recalculate governing power
        delete metavestDetails[_grantee].allocation.tokenGoverningPower;
        if (_metavestDetails.eligibleTokens.locked)
            metavestDetails[_grantee].allocation.tokenGoverningPower += amountLocked[_grantee];
        if (_metavestDetails.eligibleTokens.unlocked)
            metavestDetails[_grantee].allocation.tokenGoverningPower += _metavestDetails.allocation.tokensUnlocked;
        if (_metavestDetails.eligibleTokens.withdrawable)
            metavestDetails[_grantee].allocation.tokenGoverningPower += amountWithdrawable[_grantee][
                _metavestDetails.allocation.tokenContract
            ];

        // if claims were transferred, make similar updates (though note '_start' and '_end' will be the same) for each transferee
        /// @dev this refreshes the "first level" of transferees; so a grantee's transferees will have their MetaVesTs refreshed, but
        /// for the second-level transferees of a transferee to have theirs' refreshed, the first-level transferee will have to refresh via this function
        if (transferees[_grantee].length != 0) {
            for (uint256 i; i < transferees[_grantee].length; ++i) {
                address _addr = transferees[_grantee][i];
                MetaVesTDetails memory _mvDetails = metavestDetails[_addr];
                uint256 _totalStream = _mvDetails.allocation.tokenStreamTotal;
                if (block.timestamp < _start) {
                    linearUnlocked[_addr] = 0;
                } else if (block.timestamp >= _end) {
                    // after '_end', unlocked == tokenStreamTotal + cliff and milestone amounts unlocked up until now - unlockedTokensWithdrawn
                    metavestDetails[_addr].allocation.tokensUnlocked =
                        cliffAndMilestoneUnlocked[_addr] +
                        _mvDetails.allocation.cliffCredit +
                        _totalStream -
                        _mvDetails.allocation.unlockedTokensWithdrawn;
                    linearUnlocked[_addr] = _totalStream;
                    // if token option, if long stop date reached, unlocked unexercised tokens are forfeited and may be reclaimed by 'authority'
                    if (
                        _mvDetails.metavestType == MetaVesTType.OPTION &&
                        block.timestamp >= _metavestDetails.allocation.stopTime
                    ) {
                        metavestDetails[_addr].option.tokensForfeited += uint208(
                            metavestDetails[_addr].allocation.tokensUnlocked
                        );
                        // make forfeited unlocked tokens withdrawable by 'authority'
                        amountWithdrawable[authority][_metavestDetails.allocation.tokenContract] += metavestDetails[
                            _addr
                        ].allocation.tokensUnlocked;
                        delete metavestDetails[_addr].allocation.tokensUnlocked;
                        delete linearUnlocked[_addr];
                    }
                    // if RTA, if short stop date reached, unlocked tokens are not able to be repurchased by authority
                    else if (_mvDetails.rta.tokensRepurchasable != 0)
                        delete metavestDetails[_addr].rta.tokensRepurchasable;
                } else {
                    // new tokensUnlocked = (unlockRate * passed time since start) - preexisting 'linearUnlocked' if the linear unlock hasn't already been completed
                    uint256 _newlyUnlocked;
                    if (linearUnlocked[_addr] != _mvDetails.allocation.tokenStreamTotal)
                        _newlyUnlocked =
                            (_metavestDetails.allocation.unlockRate * (block.timestamp - _start)) -
                            linearUnlocked[_addr];
                    // make sure linear unlocked calculation does not surpass the token stream total
                    if (linearUnlocked[_addr] + _newlyUnlocked <= _totalStream) {
                        metavestDetails[_addr].allocation.tokensUnlocked +=
                            _newlyUnlocked +
                            metavestDetails[_addr].allocation.cliffCredit;
                        if (metavestDetails[_addr].rta.tokensRepurchasable >= _newlyUnlocked)
                            metavestDetails[_addr].rta.tokensRepurchasable -= _newlyUnlocked;
                    } else {
                        _newlyUnlocked = 0;
                        metavestDetails[_addr].allocation.tokensUnlocked =
                            _mvDetails.allocation.tokenStreamTotal +
                            cliffAndMilestoneUnlocked[_addr] +
                            _mvDetails.allocation.cliffCredit;
                        linearUnlocked[_addr] = _mvDetails.allocation.tokenStreamTotal;
                    }
                    // delete cliff credit and remove the new unlocked amount from amountLocked mapping. After the cliff is added the first time, later refreshes will simply pass 0
                    amountLocked[_addr] -= metavestDetails[_addr].allocation.tokensUnlocked;
                    linearUnlocked[_addr] += _newlyUnlocked;
                    cliffAndMilestoneUnlocked[_addr] += _mvDetails.allocation.cliffCredit;
                    delete metavestDetails[_addr].allocation.cliffCredit;
                }
                // recalculate governing power
                delete metavestDetails[_addr].allocation.tokenGoverningPower;
                if (_mvDetails.eligibleTokens.locked)
                    metavestDetails[_addr].allocation.tokenGoverningPower += amountLocked[_addr];
                if (_mvDetails.eligibleTokens.unlocked)
                    metavestDetails[_addr].allocation.tokenGoverningPower += _mvDetails.allocation.tokensUnlocked;
                if (_mvDetails.eligibleTokens.withdrawable)
                    metavestDetails[_addr].allocation.tokenGoverningPower += amountWithdrawable[_addr][
                        _mvDetails.allocation.tokenContract
                    ];
            }
        }
    }

    /// @notice allows a grantee (or transferee) of a token option to exercise their option by paying the exercise price in 'paymentToken' for their amount of unlocked tokens, making such tokens withdrawable
    /// @param _amount amount of tokens msg.sender seeks to exercise in their token option
    function exerciseOption(uint256 _amount) external {
        refreshMetavest(msg.sender);
        MetaVesTDetails memory _metavest = metavestDetails[msg.sender];
        if (msg.sender != _metavest.grantee) revert MetaVesT_OnlyGrantee();
        if (_metavest.metavestType != MetaVesTType.OPTION) revert MetaVesT_NoTokenOption();
        if (_metavest.allocation.tokensUnlocked < _amount) revert MetaVesT_AmountGreaterThanUnlocked();

        uint256 _payment = _amount * _metavest.option.exercisePrice;
        if (
            IERC20(paymentToken).allowance(msg.sender, address(this)) < _payment ||
            IERC20(paymentToken).balanceOf(msg.sender) < _payment
        ) revert MetaVesT_AmountNotApprovedForTransferFrom();

        safeTransferFrom(paymentToken, msg.sender, address(this), _payment);

        amountWithdrawable[controller][paymentToken] += _payment;
        amountWithdrawable[msg.sender][_metavest.allocation.tokenContract] += _amount;
        metavestDetails[msg.sender].allocation.unlockedTokensWithdrawn += _amount;
        metavestDetails[msg.sender].allocation.tokensUnlocked -= _amount;

        emit MetaVesT_OptionExercised(msg.sender, _metavest.allocation.tokenContract, _amount);
    }

    /// @notice allows an address to withdraw their 'amountWithdrawable' of their corresponding token in their MetaVesT, or amount of 'paymentToken' as a result of a tokenRepurchase
    /// @param _tokenAddress the ERC20 token address which msg.sender is withdrawing, which should be either the 'metavestDetails[msg.sender].allocation.tokenContract' or 'paymentToken'
    function withdrawAll(address _tokenAddress) external nonReentrant {
        if (_tokenAddress == address(0)) revert MetaVesT_ZeroAddress();
        uint256 _amt;
        /// @dev if caller has a MetaVesT which is a Token Option, they must call 'exerciseOption' in order to exercise their option and make their 'tokensUnlocked' (vested) withdrawable and then call this function, otherwise they would be withdrawing vested but not exercised tokens here
        if (
            msg.sender != authority &&
            msg.sender != controller &&
            _tokenAddress == metavestDetails[msg.sender].allocation.tokenContract &&
            metavestDetails[msg.sender].metavestType != MetaVesTType.OPTION
        ) {
            uint256 _preAmtWithdrawable = amountWithdrawable[msg.sender][_tokenAddress];
            refreshMetavest(msg.sender);
            MetaVesTDetails memory _metavest = metavestDetails[msg.sender];
            if (msg.sender != _metavest.grantee) revert MetaVesT_OnlyGrantee();

            uint256 _unlockedNotWithdrawn = _metavest.allocation.tokensUnlocked -
                metavestDetails[msg.sender].allocation.unlockedTokensWithdrawn;
            // add newly unlocked tokens to amountWithdrawable and unlockedTokensWithdrawn, since all are being withdrawn now
            amountWithdrawable[msg.sender][_tokenAddress] = _preAmtWithdrawable + _unlockedNotWithdrawn;
            metavestDetails[msg.sender].allocation.unlockedTokensWithdrawn += _unlockedNotWithdrawn;

            // delete 'tokensUnlocked' and 'cliffAndMilestoneUnlocked' as all are being withdrawn now; these do not affect a paymentToken withdrawal
            delete metavestDetails[msg.sender].allocation.tokensUnlocked;
            delete cliffAndMilestoneUnlocked[msg.sender];

            // if no amountLocked remains, delete the metavestDetails for this msg.sender as now all tokens are withdrawn as well (so we know after this call, no locked, unlocked, nor withdrawable tokens will remain)
            if (amountLocked[msg.sender] == 0) delete metavestDetails[msg.sender];
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

        /// @dev if caller has a MetaVesT which is a Token Option, they must call 'exerciseOption' in order to exercise their option and make their 'tokensUnlocked' (vested) withdrawable and then call this function, otherwise they would be withdrawing vested but not exercised tokens here
        if (
            msg.sender != authority &&
            msg.sender != controller &&
            _tokenAddress == metavestDetails[msg.sender].allocation.tokenContract &&
            metavestDetails[msg.sender].metavestType != MetaVesTType.OPTION
        ) {
            uint256 _preAmtWithdrawable = amountWithdrawable[msg.sender][_tokenAddress];
            refreshMetavest(msg.sender);
            MetaVesTDetails memory _metavest = metavestDetails[msg.sender];
            if (msg.sender != _metavest.grantee) revert MetaVesT_OnlyGrantee();

            uint256 _unlockedNotWithdrawn = _metavest.allocation.tokensUnlocked -
                metavestDetails[msg.sender].allocation.unlockedTokensWithdrawn;
            amountWithdrawable[msg.sender][_tokenAddress] = _preAmtWithdrawable + _unlockedNotWithdrawn;
            if (_amount > amountWithdrawable[msg.sender][_tokenAddress])
                revert MetaVesT_AmountGreaterThanWithdrawable();

            // adjust unlocked variables for '_amount' withdrawn if not just from '_preAmtWithdrawable' (not just deducted from 'amountWithdrawable')
            if (_preAmtWithdrawable < _amount) {
                uint256 _newlyUnlockedAndWithdrawn = _unlockedNotWithdrawn - _amount;
                metavestDetails[msg.sender].allocation.unlockedTokensWithdrawn += _newlyUnlockedAndWithdrawn;
                metavestDetails[msg.sender].allocation.tokensUnlocked -= _newlyUnlockedAndWithdrawn;
            }
        }

        if (_amount > amountWithdrawable[msg.sender][_tokenAddress]) revert MetaVesT_AmountGreaterThanWithdrawable();

        // subtract '_amount' from 'amountWithdrawable' for '_tokenAddress'
        amountWithdrawable[msg.sender][_tokenAddress] -= _amount;

        safeTransfer(_tokenAddress, msg.sender, _amount);
        emit MetaVesT_Withdrawal(msg.sender, _tokenAddress, _amount);
    }
}
