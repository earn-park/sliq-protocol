# Changelog

All notable changes to the sLiq Protocol will be documented in this file.

The format is based on [Common Changelog](https://common-changelog.org/), and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [0.1.0] - 2026-02-23

### Added

- Core protocol contracts: `Vault.sol`, `VaultManager.sol`, `VaultMath.sol`
- Beacon proxy architecture for atomic multi-vault upgrades
- Long and Short IL positions with configurable tick ranges
- Auto-rolling positions (Direct, InverseMinus, InversePlus strategies)
- ERC-4626-like LP share accounting (`vsLP` token)
- K-multiplier skew mechanism for self-balancing vault economics
- Chainlink oracle integration with Arbitrum sequencer uptime checks
- Fallback to Uniswap V3 `pool.slot0()` when Chainlink is unavailable
- Liquidation system with fixed bounty and keeper incentives
- Checkpoint-based cumulative fee tracking
- Solidity interfaces: `IVault`, `IVaultManager`, `IVaultMath`
- 141 tests (123 unit + 16 fuzz + 2 invariant) with full CI pipeline
- Comprehensive documentation (ARCHITECTURE, SECURITY, MATH, MARKET_ANALYSIS)
- Deployment on Arbitrum One (live beta)

[0.1.0]: https://github.com/earn-park/sliq-protocol/releases/tag/v0.1.0
