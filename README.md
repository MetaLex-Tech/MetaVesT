```
███╗   ███╗███████╗████████╗  █████╗ ██╗   ██╗███████╗ ███████╗████████╗
████╗ ████║██╔════╝╚══██╔══╝ ██╔══██╗██║   ██║██╔════╝ ██╔════╝╚══██╔══╝
██╔████╔██║█████╗     ██║    ███████║██║   ██║█████╗   ███████╗   ██║
██║╚██╔╝██║██╔══╝     ██║    ██╔══██║ ██╗ ██╔╝██╔══╝   ╚════██║   ██║
██║ ╚═╝ ██║███████╗   ██║    ██║  ██║  ╚██╔═╝ ███████╗ ███████║   ██║
╚═╝     ╚═╝╚══════╝   ╚═╝    ╚═╝  ╚═╝   ╚═╝   ╚══════╝ ╚══════╝   ╚═╝
///BORG-Compatible Token Vesting/Lockup Protocol.
   ╚══╝ ╚════════╝ ╚═══╝ ╚════════════╝ ╚══════╝
```

# Overview

MetaVesT is a BORG-compatible token vesting/lockup protocol for ERC20 tokens, supporting:

- Vesting allocations
- Token Options
- Restricted Token Awards

with both vesting and unlock schedules, rates, and cliffs, as well as any number of milestones (each with any number of conditions and tokens to be awarded), internal transfer abilities, and configurable governing power for MetaVesTed tokens.

Each MetaVest framework supports any number of grantees and different ERC20 tokens.

## Initiating a MetaVesT Framework

Each MetaVesT framework is designed to be on a per-BORG or more general per-authority basis.

A MetaVesT framework is initiated by calling `deployMetavestAndController()` in `MetaVesTFactory`, supplying:

`_authority`: address of the `authority` who will have the ability to call the functions in the MetaVesTController (including creating and updating MetaVesTs within the framework) such as a BORG.

`_dao`: DAO governance contract address which exercises control over ability of 'authority' to call certain functions via imposing conditions through 'updateFunctionCondition'

`_vestingAllocationFactory`: factory contract address which will be used to create each vesting allocation in this MetaVesT framework

`_tokenOptionFactory`: factory contract address which will be used to create each token option in this MetaVesT framework

`_restrictedTokenFactory`: factory contract address which will be used to create each restricted token award in this MetaVesT framework

This call deploys a [MetaVesTController.sol](https://github.com/MetaLex-Tech/MetaVesT/blob/main/src/MetaVesTController.sol), the authority-facing contract which it uses to create individual MetaVesTs, update MetaVesT details, add/remove/confirm milestones, terminate MetaVesTs, toggle transferability, etc. subject to grantee or majority-in-tokenGoverningPower consent where applicable (see below).

## Creating and Using MetaVesTs

Each MetaVesT initiated via the MetaVesT Controller by the `authority` is designed to be on a per-grantee basis.

Each separate MetaVesT under the framework can have a variety of different attributes, including different ERC20s, different MetaVesT types (vesting allocation, option, RTA), amounts, transferability, milestone amounts and conditions, vesting and unlock schedules, etc. The `authority` for a given MetaVesT framework creates a new MetaVesT for a given recipient by calling `createMetavest()` in the `MetaVesTController`, supplying:

`_type`: enum of the MetaVesT type for this `grantee`, either `Vesting` (simple vesting allocation), `RestrictedToken` (restricted token award), or `TokenOption` (token option)

`_grantee`: address of the `grantee` for the new MetaVesT

`_allocation`: calldata of the `BaseAllocation.Allocation` struct for this grantee, comprised of:

- `tokenStreamTotal`: uint256 total number of tokens subject to linear vesting/restriction removal (includes cliff credits but not each 'milestoneAward')
- `vestingCliffCredit`: uint128 lump sum of tokens which become vested at `vestingStartTime`
- `unlockingCliffCredit`: uint128 lump sum of tokens which become unlocked at `unlockStartTime`
- `vestingRate`: uint160 tokens per second that become vested; if RestrictedToken type, this amount corresponds to 'lapse rate' for tokens that become non-repurchasable
- `vestingStartTime`: uint48 linear vesting start time; if RestrictedToken type, this amount corresponds to 'lapse start time'
- `unlockRate`: uint160 tokens per second that become unlocked
- `unlockStartTime`: uint48 linear unlocking start time
- `tokenContract`: contract address of the ERC20 token included in the MetaVesT

`_milestones`: calldata array of `Milestone` structs for this grantee, comprised of:

- `milestoneAward`: uint256 per-milestone indexed lump sums of tokens vested upon corresponding milestone completion
- `unlockOnCompletion`: boolean whether the `milestoneAward` is to be unlocked upon completion
- `complete`: bool whether the Milestone is satisfied and the `milestoneAward` is to be released
- `conditionContracts`: array of contract addresses corresponding to condition(s) that must satisfied for this Milestone to be 'complete'

`_exercisePrice`: if `_type` == `TokenOption`, the uint256 price in at which a token option may be exercised in vesting token decimals but only up to payment decimal precision. If `_type` == `RestrictedToken`, this corresponds to the `_repurchasePrice`: the uint256 price at which the restricted tokens can be repurchased in vesting token decimals but only up to payment decimal precision.

`_paymentToken`: contract address for the token used to pay for option exercises (for a grantee) or restricted token repurchases (for authority); immutable for this MetaVesT.

`_shortStopDuration`: uint256 if `_type` == `TokenOption`, length of period before vesting stop time and exercise deadline; if `_type` == `RestrictedToken`, length of period before lapse stop time and repurchase deadline

When a grantee’s MetaVesT is created by authority, the full amount of corresponding tokens will be transferred from `authority` to the applicable newly deployed contract (either `VestingAllocation.sol`, `RestrictedTokenAllocation.sol`, or `TokenOptionAllocation.sol`) in the same transaction. This consists of any combination of:

- Tokens to be linearly vested and unlocked, with any vested lump sum (cliff) credit at the `vestingStartTime` (`Allocation.vestingCliffCredit`) or unlocked lump sum (cliff) credit at the `unlockStartTime` (`Allocation.unlockingCliffCredit`). Altogether this amount is the `tokenStreamTotal`
- Tokens to be vested and unlocked as a `milestoneAward`, according to any applicable `conditionContracts` assigned, within the `milestones` array of Milestone structs

Tokens become withdrawable by the applicable grantee when both vested and unlocked (or in the case of a token option, vested and exercised, and unlocked), and when a milestone is confirmed complete according to its conditions.

## Contract Details

### MetaVesTController.sol

In MetaVesTController.sol, `authority` is able to:

- Create a new MetaVesT for a grantee that does not have an active MetaVesT and transfer the corresponding total amount of tokens

- Terminate the vesting of an active MetaVesT

- Add a milestone to an active MetaVesT and transfer the corresponding total amount of additional tokens

- Repurchase tokens from an Restricted Token Allocation

- Withdraw controller’s withdrawable tokens to the controller, and from controller to itself

- Replace its own address

- Propose any of the following amendments to a grantee’s MetaVesT, executing IFF it passes the `consentCheck()` (either consent by the affected grantee, or > 50% consent by a majority-in-`tokenGoverningPower` of grantees with the same token):

  - Terminate a MetaVesT entirely
  - Amend a MetaVesT’s:
    - transferability
    - token option exercise price
    - repurchase price
    - stop time and short stop time
    - unlock rate,
    - vesting rate, and
    - remove a milestone

Such amendment proposals have a one-week expiry. They are initiated by `authority` calling `proposeMetavestAmendment()`, and then consented either by the affected grantee calling `consentToMetavestAmendment()` or by grantees with the same MetaVesTed token voting in `voteOnMetavestAmendment()` and > 50% of such grantees weighted by `tokenGoverningPower` voting in favor.

To alter a MetaVesT’s type, grantee, or token, the current MetaVesT must be terminated entirely and a new one created. Any address can refresh any active MetaVesT and query whether any milestone in any active MetaVesT is completed (and if so, state updates and if completed, the `milestoneAward` is unlocked for the grantee).

In MetaVesTController.sol, `dao` is able to replace its own address, and impose conditions on authority's ability to call certain functions (including if consented) by calling `updateFunctionCondition()`. This requires a conditionContract be satisfied in order for the supplied msg.sig (function selector) to execute.

### BaseAllocation.sol

Each MetaVesT contract type inherits the Base Allocation. In each type of MetaVesT, a `grantee` is able to:

- view the details of its MetaVesT via `getMetavestDetails()`

- Query a milestone for completion by calling `confirmMilestone()` with the applicable milestone index

- Query its `tokenGoverningPower` corresponding to nonwithdrawable, vested, or unlocked tokens (as configured by authority)

- If its MetaVesT is `transferable`, transfer its MetaVesT to another address

- Withdraw any amount of its withdrawable tokens (calculated in `getAmountWithdrawable()`) by calling `withdraw()`

### VestingAllocation.sol

Vesting Allocation inherits the Base Allocation and contains the vesting and unlocking rate calculations, providing a `grantee`'s amount of withdrawable tokens in `getAmountWithdrawable()`.

### TokenOptionAllocation.sol

Token Option Allocation inherits the Base Allocation and contains the vesting and unlocking rate calculations, as well as exercisable (`getAmountExercisable()`) and forfeited tokens pursuant to the token option terms. `Grantee` exercises the option by calling `exerciseTokenOption()` with its applicable `_tokensToExercise` and necessary payment amount in its balance which will be transferred to `authority` during the call, and `authority` recovers non-exercised tokens following the short stop time by calling `recoverForfeitTokens()`.

### RestrictedTokenAllocation.sol

Restricted Token Allocation inherits the Base Allocation and contains the vesting and unlocking rate calculations, as well as repurchasable (`getAmountRepurchasable()`) tokens pursuant to the restricted token award terms. `Authority` repurchases available tokens by calling `repurchaseTokens()` with its applicable `_amount` and necessary payment amount in its balance which will be transferred to the contract during the call, and `grantee` claims the payment amount for any repurchased tokens by calling `claimRepurchasedTokens()`.

### Milestone Conditions

- Each `conditionContract` (used in milestones as well, either alone or in combination, as well as any `conditionCheck()` imposed by `dao` on MetaVesTController functions) is intended to follow the [MetaLeX condition contract specs](https://github.com/MetaLex-Tech/BORG-CORE/tree/main/src/libs/conditions) and must return a boolean.

## Restrictions and Considerations

Each `grantee` address must be capable of calling functions (for example, to withdraw tokens)

MetaVesT does not support native gas tokens (ERC20 wrappers will be necessary) nor fee-on-transfer nor rebasing tokens.

## Prerequisites

Before you begin, ensure you have the following installed:

- [Node.js](https://nodejs.org/)
- [Foundry](https://book.getfoundry.sh/getting-started/installation.html)
- solc v0.8.20

## Installation

To set up the project locally, follow these steps:

1. **Clone the repository**
   ```bash
   git clone https://github.com/MetaLex-Tech/MetaVesT
   cd MetaVesT
   ```
2. **Install dependencies**
   ```bash
   foundryup # Update Foundry tools
   forge install # Install project dependencies
   ```
3. **Compile Contracts**

   ```base
   forge build --optimize --optimizer-runs 200 --use solc:0.8.20
   ```
