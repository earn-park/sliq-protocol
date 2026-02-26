# Roadmap

This document outlines the sLiq Protocol development roadmap. Items marked **TBD** are planned but not yet scheduled.

## Completed

- [x] Core protocol design and whitepaper
- [x] Smart contract implementation (Vault, VaultManager, VaultMath)
- [x] Beacon proxy architecture for multi-vault upgrades
- [x] Chainlink oracle integration with Arbitrum sequencer uptime checks
- [x] K-multiplier skew mechanism for self-balancing economics
- [x] Auto-rolling position strategies
- [x] Unit and fuzz test suite (131 tests)
- [x] Internal security review (static analysis, economic modeling, business logic)
- [x] On-chain fee caps (`MAX_TOTAL_FEE_E2 = 2000`, `MAX_BOUNTY_E18 = 1e18`)
- [x] Pausable pattern with guardian role for emergency response
- [x] Dead shares defense against share inflation attacks
- [x] Chainlink staleness check (`STALENESS_THRESHOLD = 3600s`)
- [x] Oracle consistency (Chainlink-derived sqrtPX96 across all price-dependent functions)
- [x] Position range bounds (`MIN_RANGE = 60`, `MAX_RANGE = 100,000` ticks)
- [x] Anchor NFT ownership verification in `init()`
- [x] Fee-on-transfer token guard
- [x] CI pipeline with tests, linting, Slither, and coverage
- [x] Governance deployment script (TimelockController)
- [x] Bytecode size optimization (IL calc extracted to VaultMath; Vault 23,437/24,576 B)
- [x] Zero-address validation in `init()`
- [x] `RollSkipped` event for failed auto-roll attempts
- [x] Protocol fee subordination during vault shortfall
- [x] Live beta deployment on Arbitrum One
- [x] Organic traction: 2,400+ positions, 175 ETH collateral in 30 days

## In Progress

- [ ] Third-party security audit (firm selection underway)
- [ ] Arbitrum Foundation grant application
- [ ] Expanded pool coverage on Arbitrum
- [ ] **v2 pricing model** -- transition from anchor-fee-based pricing to GBM-based implied volatility model (see [MATH.md — Pricing Model Evolution](./MATH.md#pricing-model-evolution-from-anchor-fees-to-gbm-based-implied-volatility))
- [ ] **On-chain implied volatility derivation** -- extract a volatility signal from the K-multiplier skew equilibrium state, enabling the protocol to natively produce an IV metric analogous to VIX
- [ ] **Per-LP delta exposure view** -- on-chain function computing each LP's net delta (directional price exposure) from vault state

## Planned

### Security and Operations

- [ ] **Third-party audit** -- formal audit by a reputable security firm prior to mainnet launch
- [ ] **Bug bounty program** -- launch on Immunefi with tiered rewards (Critical/High/Medium)
- [ ] **Multisig deployment** -- transfer VaultManager ownership to a Safe 3-of-5 multisig
- [ ] **Timelock integration** -- 48-hour timelock on implementation upgrades and math library changes
- [x] **Pausable pattern** -- OpenZeppelin `PausableUpgradeable` with `whenNotPaused` on deposit/open
- [x] **Guardian role** -- dedicated pause-only address for rapid incident response
- [ ] **Circuit breakers** -- automatic pause on anomalous activity (large withdrawals, oracle deviations)
- [ ] **Runtime monitoring** -- on-chain tracking of k-multiplier values, collateralization ratios, and pool health

### Governance Progression

The protocol follows a progressive decentralization path:

1. **Current (beta):** Single EOA owner for rapid iteration
2. **v1 (mainnet):** 3-of-5 Safe multisig + 48-hour timelock on critical operations
3. **v2:** Expanded governance parameters (leverage bounds, risk caps, k-multiplier methods)
4. **v3+:** Protocol token and DAO governance with on-chain voting

### Protocol Enhancements

- [x] **On-chain fee caps** -- `MAX_TOTAL_FEE_E2 = 2000` (20%), `MAX_BOUNTY_E18 = 1e18`, with `FeesUpdated` event
- [ ] **Leverage range expansion** -- reduce `MIN_RANGE` from 60 to ~39 ticks, enabling leverage up to ~1000x (currently capped at ~660x). Requires additional precision testing for narrow-range IL calculations. Planned for Phase 2.
- [ ] **Anchor position governance** -- anchor NFT ownership via multisig or watchdog contract, with rebalancing mechanism as price drifts
- [ ] **TWAP oracle fallback** -- integrate `pool.observe()` as secondary fallback between Chainlink and raw `slot0()`
- [ ] **Oracle deviation checks** -- compare Chainlink price to pool price, revert if deviation exceeds threshold
- [ ] **ERC-721 position tokens** -- tokenize positions for transferability and composability
- [ ] **Slippage protection** -- optional `maxTick`/`minTick` parameters on position opens
- [ ] **Event enrichment** -- emit events for failed rolling attempts and oracle fallbacks (fee parameter change event `FeesUpdated` now implemented)
- [ ] **VaR and stress testing** -- scenario analysis for extreme price moves, volatility clustering, and prolonged trends

### Ecosystem Growth

- [ ] **Multi-pool expansion** -- deploy vaults for top Arbitrum Uniswap V3 pools (ARB/ETH, WBTC/ETH, GMX/ETH)
- [ ] **Chain expansion** -- deploy on additional L2s (Base, Optimism) leveraging chain-agnostic design
- [ ] **Cross-pair support** -- Chainlink feeds for cross-pair risk controls and hedging
- [ ] **Subgraph and indexer** -- The Graph subgraph for position tracking and analytics
- [ ] **SDK and developer tools** -- TypeScript SDK for frontend and bot integration
- [ ] **Open-source simulation scripts** -- backtesting and scenario modeling tools
- [ ] **Vault Depot integrations** -- composability with yield aggregators and portfolio managers
- [ ] **Protocol token** -- governance token with staking, emission schedules, and anti-sybil mechanics (details in whitepaper Section 10.5)

### Formal Verification (TBD)

- [ ] **Certora Prover** or **Halmos** for IL math and share accounting invariants
- [ ] **Invariant test suite** -- Foundry `invariant_*` tests for all economic invariants
- [ ] **Symbolic execution** -- Manticore or Mythril for reachability analysis

## Grant Milestones

Milestones for the Arbitrum Foundation grant are defined in the grant application and will be tracked here upon approval.

| Milestone | Scope | Status |
|-----------|-------|--------|
| M1: Security audit | Third-party audit completion | Planned |
| M2: Mainnet launch | Production deployment with multisig and timelock | Planned |
| M3: Multi-pool expansion | 5+ active vaults on Arbitrum | Planned |
| M4: Ecosystem integration | SDK, subgraph, and at least one aggregator integration | Planned |
