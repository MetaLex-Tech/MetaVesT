# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added

- Third-party contract interfaces
  - src/interfaces/zk-governance/IMintable.sol
  - src/interfaces/zk-governance/IMintableAndDelegatable.sol
  - src/interfaces/zk-governance/IZkCappedMinterV2.sol
  - src/interfaces/zk-governance/IZkCappedMinterV2Factory.sol
  - src/interfaces/zk-governance/IZkTokenV1.sol

### Updated

- VestingAllocation.sol
  - Mint tokens on-demand through `controller` instead of escrow in the contract
  - Added `recipient` so the grantee can change withdrawal destinations

- src/MetaVesTController.sol
  - Become `UUPSUpgradeable`
  - Integrated agreement-signing with `CyberAgreementRegistry`
  - Added `deals` to handle agreement signing process and store MetaVesT parameters for each grantee
  - Added `proposeAndSignDeal()` for Guardian SAFE to propose deal for grantee
  - Combined grantee deal-signing and MetaVesT contract deployment into `signDealAndCreateMetavest()`
  - Added `mint()` as a proxy to `zkCappedMinter` so that authorized MetaVesT contracts can mint tokens on-demand (instead of escrow)
  - Temporarily disabled unsupported MetaVesT types until future integration: `TokenOption` and `RestrictedTokenAward`

- Minor compiler version changes
  - src/interfaces/IAllocationFactory.sol
  - src/interfaces/IBaseAllocation.sol
  - src/interfaces/IPriceAllocation.sol
  - src/interfaces/IRestrictedTokenAward.sol

### Removed

- Temporarily removed unsupported MetaVesT types and helpers
  - src/MetaVesTFactory.sol
  - src/RestrictedTokenAllocation.sol
  - src/RestrictedTokenFactory.sol
  - src/TokenOptionAllocation.sol
  - src/TokenOptionFactory.sol
