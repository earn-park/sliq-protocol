# Roadmap

This document outlines the sLiq Protocol development roadmap. Items marked **TBD** are planned but not yet scheduled.

## Completed

- [x] Core protocol design and whitepaper
- [x] Smart contract implementation (Vault, VaultManager, VaultMath)
- [x] Beacon proxy architecture for multi-vault upgrades
- [x] Chainlink oracle integration with Arbitrum sequencer uptime checks
- [x] K-multiplier skew mechanism for self-balancing economics
- [x] Auto-rolling position strategies
- [x] Unit and fuzz test suite (109 tests)
- [x] Internal security review (static analysis, economic modeling, business logic)
- [x] Live beta deployment on Arbitrum One
- [x] Organic traction: 2,400+ positions, 175 ETH collateral in 30 days

## In Progress

- [ ] Third-party security audit (firm selection underway)
- [ ] Arbitrum Foundation grant application
- [ ] Expanded pool coverage on Arbitrum

## Planned

### Security and Operations

- [ ] **Third-party audit** -- formal audit by a reputable security firm prior to mainnet launch
- [ ] **Bug bounty program** -- launch on Immunefi with tiered rewards (Critical/High/Medium)
- [ ] **Multisig deployment** -- transfer VaultManager ownership to a Safe 3-of-5 multisig
- [ ] **Timelock integration** -- 48-hour timelock on implementation upgrades and math library changes
- [ ] **Pausable pattern** -- add OpenZeppelin `PausableUpgradeable` for emergency response
- [ ] **Guardian role** -- dedicated pause-only address for rapid incident response

### Protocol Enhancements

- [ ] **On-chain fee caps** -- enforce maximum fee bounds in `setFees()` to prevent abuse
- [ ] **Anchor position rebalancing** -- mechanism to adjust the anchor NFT range as price drifts
- [ ] **ERC-721 position tokens** -- tokenize positions for transferability and composability
- [ ] **Slippage protection** -- optional `maxTick`/`minTick` parameters on position opens
- [ ] **Event enrichment** -- emit events for failed rolling attempts and fee parameter changes

### Ecosystem Growth

- [ ] **Multi-pool expansion** -- deploy vaults for top Arbitrum Uniswap V3 pools (ARB/ETH, WBTC/ETH, GMX/ETH)
- [ ] **Chain expansion** -- deploy on additional L2s (Base, Optimism) leveraging chain-agnostic design
- [ ] **Subgraph and indexer** -- The Graph subgraph for position tracking and analytics
- [ ] **SDK and developer tools** -- TypeScript SDK for frontend and bot integration
- [ ] **Vault Depot integrations** -- composability with yield aggregators and portfolio managers

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
