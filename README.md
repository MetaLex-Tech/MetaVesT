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

- Unopinionated token allocations 
- Token Options
- Restricted Token Awards

with both vesting and unlock schedules, rates, and cliffs, as well as any number of milestones (each with any number of conditions and tokens to be awarded), internal transfer abilities, and configurable governing power for MetaVesTed tokens. 

Each MetaVest framework supports any number of grantees and different ERC20 tokens.

## User Flow

Each MetaVesT framework is designed to be on a per-BORG or more general per-authority basis. 

A MetaVesT framework is initiated by calling `deployMetavestAndController` in `MetaVesTFactory`, supplying:

`authority`: contract address for permissioned control of the MetaVesT framework, ideally a BORG. 

`dao`: contract address for any applicable DAO governance to check the technical powers of authority, if desired/applicable

`paymentToken`: contract address for the token used to pay for option exercises (for a grantee) or restricted token repurchases (for authority). 

This call deploys (1) [MetaVesT.sol](https://github.com/MetaLex-Tech/MetaVesT/blob/main/src/MetaVesT.sol), the grantee-facing contract and home of all state under the particular MetaVesT framework (including each individual MetaVesT and all tokens), and 
(2) [MetaVesTController.sol](https://github.com/MetaLex-Tech/MetaVesT/blob/main/src/MetaVesTController.sol), the authority-facing contract which it uses to create individual MetaVesTs, update MetaVesT details, add/remove/confirm milestones, terminate MetaVesTs, toggle transferability, etc. subject to grantee or majority-in-tokenGoverningPower consent where applicable (see below). 

Each MetaVesT initiated thereunder can have unique MetaVesTDetails in the same contract, including different ERC20s, different `MetaVesTType`s (allocation, option, RTA), amounts, transferability, milestone amounts and conditions, vesting and unlock schedules, etc.

When a grantee’s MetaVesT is created by authority, the full amount of corresponding tokens will be transferred from `authority` to MetaVesT.sol in the same transaction. This consists of any combination of:

- Tokens to be linearly vested and unlocked, with any vested lump sum (cliff) credit at the `vestingStartTime` (`Allocation.vestingCliffCredit`) or unlocked lump sum (cliff) credit at the `unlockStartTime` (`Allocation.unlockingCliffCredit`). Altogether this amount is the `tokenStreamTotal`
- Tokens to be vested and unlocked as a `milestoneAward`, according to any applicable `conditionContracts` assigned, within the `milestones` array of Milestone structs 

Tokens become withdrawable by the applicable grantee when both vested and unlocked (or in the case of a token option, vested and exercised, and unlocked), and when a milestone is confirmed complete according to its conditions.

For each MetaVesTType:

- Allocation: Grantee may call `withdraw` or `withdrawAll` to withdraw their eligible tokens
- Token Options: Grantee may call `exerciseOption` (with corresponding payment in `paymentToken` according to their `exercisePrice`) to exercise their vested tokens, then call `withdraw` or `withdrawAll` to withdraw their eligible tokens (note the exercised tokens are still subject to the grantee's unlock schedule, which may be different than the vesting schedule)
- Restricted Token Awards: unvested tokens are repurchasable by authority (with payment in `paymentToken` according to their `repurchasePrice`), but as they lapse (become vested), grantee may call `withdraw` or `withdrawAll` to withdraw them if also unlocked. If MetaVesTed tokens are repurchased, they are directly sent to the authority address, and the payment amount becomes withdrawable for grantee and in pro rata amounts for each transferee of grantee’s MetaVesT (who also have pro rata locked tokens repurchased)

If a grantee's MetaVesT is `transferable`, a grantee may transfer some fraction of their MetaVesT to a `transferee` (an address without an active MetaVesT in the current MetaVesT.sol contract) via `transferRights`, and such transferee will have a proportional MetaVesT created for them. 

## MetaVesT.sol

In MetaVest.sol, a `grantee` (and any transferee of a grantee) is able to:

- Refresh the details and values in its MetaVesT (public function which is also called when any re-calculation is necessary) and view all details

- Query a milestone for completion

- Query its `tokenGoverningPower` corresponding to nonwithdrawable, vested, or unlocked tokens (as configured by authority)

- If its MetaVesT is transferable, transfer some fraction of its MetaVesT to another address that does not have an active MetaVesT

- If its MetaVesT is a token option, exercise such token option for its vested amount of tokens simultaneously with transferring payment

- Withdraw any amount of its withdrawable tokens (MetaVesTed tokens and any amount of paymentToken as a result of a repurchase, if applicable)




## MetaVesTController.sol

In MetaVesTController.sol, `authority` is able to:

- Create a new MetaVesT for a grantee that does not have an active MetaVesT and transfer the corresponding total amount of tokens

- Terminate the vesting of an active MetaVesT

- Add a milestone to an active MetaVesT and transfer the corresponding total amount of additional tokens

- Repurchase tokens from an RTA, including pro rata from each transferee

- Withdraw controller’s withdrawable tokens from MetaVesT.sol to the controller, and from controller to itself

- Replace its own address

- Propose any of the following amendments to a grantee’s MetaVesT, executing IFF it passes the `amendmentCheck` (either consent by the affected grantee, or > 50% consent by a majority-in-`tokenGoverningPower` of grantees with the same token):
  
  * Terminate a MetaVesT entirely
  * Amend a MetaVesT’s:
    - transferability, including current transferees
    - token option exercise price, including current transferees
    - repurchase price, including current transferees
    - stop time and short stop time
    - unlock rate, 
    - vesting rate, and
    - remove a milestone, including current transferees

Such amendment proposals have a one-week expiry. They are initiated by `authority` calling `proposeMetavestAmendment`, and then consented either by the affected grantee calling `consentToMetavestAmendment` or by grantees with the same MetaVesTed token voting in `voteOnMetavestAmendment` and > 50% of such grantees weighted by `tokenGoverningPower` voting in favor.

To alter a MetaVesT’s type, grantee, or token, the current MetaVesT must be terminated entirely and a new one created. Any address can refresh any active MetaVesT and request whether any milestone in any active MetaVesT is completed (and if so, state updates and if completed, the `milestoneAward` is vested and unlocked for the grantee).

In MetaVesTController.sol, `dao` is able to replace its own address, and impose conditions on authority's ability to call certain functions (including if consented) by calling `updateFunctionCondition`. This requires a conditionContract be satisfied in order for the supplied msg.sig (function selector) to execute.



## Other Contracts

- [MetaVesTFactory](https://github.com/MetaLex-Tech/MetaVesT/blob/main/src/MetaVesTFactory.sol) enables easy deployment of a new MetaVesT framework (MetaVesTController.sol and MetaVesT.sol) 

- Each `conditionContract` (used in milestones as well, either alone or in combination, as well as any `conditionCheck` imposed by `dao` on MetaVesTController functions) is intended to follow the [MetaLeX condition contract specs](https://github.com/MetaLex-Tech/BORG-CORE/tree/main/src/libs/conditions) and must return a boolean.
    

## Restrictions and Considerations

Each address may only be `grantee` for one MetaVesT (and thus one MetaVesTType) with a given framework (within a MetaVest.sol contract) at a time, including as a transferee.

Each `grantee` address must be capable of calling functions (for example, to withdraw tokens)

MetaVesT does not support native gas tokens (ERC20 wrappers will be necessary) nor fee-on-transfer nor rebasing tokens.

If a milestone is added to a MetaVesT (after initial creation), any prior transferees will not have the new milestoneAward added to their balances.

Each `refreshMetavest` (which can be called directly by any address and pass any address, and is automatically called at the beginning of each state-changing function with respect to the applicable grantee) refreshes the passed address’s MetaVesT and that of their transferees, but not _their transferees’ transferees_ and so on). However, this function is still called in each state-changing function that would be called by a transferee (which would then update their transferee’s values).


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

