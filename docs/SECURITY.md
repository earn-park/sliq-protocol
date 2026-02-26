# Security

This document describes the trust model, known limitations, economic invariants, and emergency procedures for the sLiq Protocol. It is intended for auditors, grant reviewers, and security researchers.

## Audit Status

The sLiq Protocol has undergone internal security review. A formal third-party audit is planned prior to mainnet launch.

## Trust Assumptions

### Protocol Owner (VaultManager owner)

The VaultManager owner has the highest privilege level in the system:

- **Vault implementation upgrade**: Can call `upgradeVaultImpl()` to change the implementation contract for all vault proxies simultaneously. A malicious implementation could drain all deposited funds.
- **VaultMath replacement**: Can call `setVaultMath()` to change the math library. A malicious math contract could manipulate IL calculations, fee distributions, and price conversions.
- **Vault deployment**: Can deploy new vaults for any Uniswap V3 pool.

**Mitigations** (deployment script ready, see `script/DeployGovernance.s.sol` and [Governance Progression](#governance-progression)):
- Governance timelock (configurable delay, default 24h) on all admin operations
- Multisig wallet (3-of-5 Safe) as VaultManager owner via TimelockController
- Implementation upgrade event monitoring with automatic pause (planned)

### Vault Owner

Each vault proxy has its own owner (set to `msg.sender` during `newVault()`, which is the VaultManager owner). The vault owner can:

- **Set fee parameters**: `setFees(vaultE2, protocolE2, liquidatorE18)` with on-chain caps: combined vault + protocol fees capped at 20% (`MAX_TOTAL_FEE_E2 = 2000`), liquidator bounty capped at 1e18 (`MAX_BOUNTY_E18`).
- **Receive protocol fees**: Protocol fee share of closed positions is sent to the vault owner address.
- **Pause/unpause**: Owner can pause and unpause the vault. Guardian can pause only (emergency fast-path).
- **Set guardian**: Owner can designate a guardian address for emergency pause.

**Recommended mitigations** (operational):
- Transfer vault ownership to a timelock or multisig
- Deploy `script/DeployGovernance.s.sol` TimelockController with 24-48h delay

### Chainlink Oracles

The protocol depends on Chainlink for price data:

- **Sequencer uptime feed**: Used to detect Arbitrum sequencer downtime. If the sequencer is down or recently restarted (< 1 hour), the system falls back to `pool.slot0()`.
- **Price feed**: Used as the primary price source when the sequencer is healthy. Staleness checks: round completeness, positive answer, non-zero update time, and `block.timestamp - updatedAt < STALENESS_THRESHOLD` (3600s).
- **Fallback**: If Chainlink is unavailable or stale, `pool.slot0()` is used. This is susceptible to sandwich attacks and flash loan manipulation, but is the standard fallback for Arbitrum protocols.
- **Oracle consistency**: Both `_anchorCollateral()` and `_view_new_checkpoint()` derive `sqrtPX96` from `currentTick()` (which uses Chainlink when available) rather than reading `pool.slot0()` directly. This ensures price consistency across all vault calculations.

### Uniswap V3

- **Fee accrual**: The vault depends on accurate fee growth accounting from the Uniswap V3 pool and NonfungiblePositionManager.
- **Price data**: Used as fallback oracle via `pool.slot0()`.
- **NFT position**: The anchor position must remain valid and owned by the vault or the vault owner. Ownership is verified during `init()`. If the NFT is transferred out after initialization or the position is burned externally, the vault would break.

## Known Limitations

### 1. Fee Caps

`setFees()` enforces on-chain caps: combined vault + protocol fees are capped at 20% (`MAX_TOTAL_FEE_E2 = 2000 basis points`), and liquidator bounty is capped at `1e18`. The vault owner cannot set fees above these limits.

### 2. Anchor Position Management

The anchor Uniswap V3 NFT (`anchorId`) is set during initialization and cannot be changed. There is no mechanism to:
- Rebalance the anchor position if the price moves far from its range
- Collect accumulated fees from the anchor NFT and reinvest
- Replace the anchor if it becomes inactive

If the price moves permanently outside the anchor range, fee accrual drops to zero, and the system stops generating yield for positions.

### 3. Share Accounting

The first deposit locks dead shares at `address(1)` to prevent share inflation attacks. The dead shares amount scales with the collateral token's decimals: `10^decimals / 1000`. This ensures meaningful protection regardless of the token:
- **WETH (18 decimals)**: 1e15 dead shares (~0.001 ETH, ~$2-3) — makes donation-based inflation attacks economically unfeasible.
- **USDC (6 decimals)**: 1e3 dead shares ($0.001) — standard ERC-4626 protection.

Subsequent deposits use standard ERC-4626-like share accounting (`shares = amount * totalSupply / totalAssets`).
- The withdrawal liquidity check (`unfreezeAssets >= totalSupply`) may block withdrawals when a large fraction of vault assets is locked in position collateral (`freezBalance`).
- There is no withdrawal queue or pro-rata mechanism; first-come-first-served withdrawal applies.
- Partial payouts emit a `PayoutShortfall` event and record the actual amount paid, rather than silently truncating.

### 4. Liquidation Bounty

The liquidator bounty (`bountyLiquidatorE18`, default 15e12) is a fixed amount, not a percentage. For very small positions, the bounty may exceed the position's collateral value. For very large positions, the bounty may be insufficient to incentivize timely liquidation.

### 5. Oracle Fallback Risk

When Chainlink is unavailable, the `pool.slot0()` fallback is used. On-chain prices from AMM pools can be manipulated via flash loans or sandwich attacks. An attacker could:
- Force the sequencer uptime check to fail (not directly, but by waiting for natural sequencer issues)
- Manipulate pool.slot0() in the same transaction
- Open or close positions at a favorable price

The 1-hour sequencer grace period mitigates this for sequencer restarts but does not protect against manipulation during extended Chainlink outages.

### 6. Precision Loss in IL Calculation

The IL calculation uses `FPM.rpow(1000100000000000000, ticks, 1e18)` for `1.0001^ticks`. For very large tick values, cumulative rounding in the fixed-point exponentiation could lead to precision loss. The practical impact is small (sub-basis-point errors for typical ranges) but should be verified for extreme ranges.

### 7. Position Rolling Trust

Auto-rolling positions (`Rolling.Direct`, `Rolling.InverseMinus`, `Rolling.InversePlus`) require the position owner to maintain both collateral balance and approval on the vault. Rolling is attempted during liquidation -- if the owner has revoked approval or spent their tokens, rolling silently fails and the position simply closes.

### 8. No Position Transfer

Positions are tied to the `owner` address and cannot be transferred to another address. There is no ERC-721 or similar token representing positions.

### 9. Fee-on-Transfer Tokens

The vault guards against fee-on-transfer (deflationary) tokens by checking `balanceOf` before and after each transfer in `deposit()` and `_open()`. If the received amount differs from the expected amount, the transaction reverts with `TransferAmountMismatch`. Standard tokens (USDC, WETH, ARB) are unaffected by this check.

### 10. Position Range Bounds

Positions are constrained to `MIN_RANGE = 60` and `MAX_RANGE = 100_000` ticks. This prevents:
- Extremely narrow ranges that could cause numerical instability in IL calculations
- Extremely wide ranges that exceed practical Uniswap V3 tick bounds

## Economic Invariants

The following invariants should hold at all times. Violations indicate a bug.

### Invariant 1: Collateral Accounting

```
freezBalance == sum of collateral for all active positions
```

Every `_open` increases `freezBalance` by the position's collateral. Every `_close` decreases it by the same amount.

### Invariant 2: Effective Liquidity Tracking

```
totalEffLong == sum of effLiquidity for all active Long positions
totalEffShort == sum of effLiquidity for all active Short positions
```

### Invariant 3: Skew Bounds

```
0 <= K_short <= 2.0 * (1 - feePercent)
0 <= K_long  <= 2.0 * (1 - feePercent)
```

The K-multiplier is bounded by 0 (when one side has 100% of effective liquidity) and approximately 1.9 (when the other side has near-zero effective liquidity, scaled by fee deduction). At balance, K = ~0.95 for both sides (1.0 scaled by fee deduction).

### Invariant 4: Vault Solvency (LP Protection)

```
collateralToken.balanceOf(vault) >= freezBalance
```

The vault should always hold at least enough collateral to cover all active positions' principal. LP assets (`totalAssets - freezBalance`) can decrease if positions are profitable, but position collateral itself is always present.

### Invariant 5: Checkpoint Monotonicity

```
cps[i].timestamp <= cps[i+1].timestamp
cps[i].totalFeeCum <= cps[i+1].totalFeeCum
```

Timestamps and cumulative fees are monotonically non-decreasing.

### Invariant 6: No Duplicate Vaults

```
For any pool address p: at most one entry in vaultOf[p]
```

`VaultManager.newVault()` reverts with `VaultAlreadyExists` if `vaultOf[pool] != address(0)`.

## Emergency Procedures

### Pause Mechanism

The vault implements OpenZeppelin's `PausableUpgradeable` pattern:

- **Guardian fast-path**: The designated guardian address can call `pause()` to immediately halt `deposit`, `openLong`, and `openShort`. This allows sub-second emergency response.
- **Owner pause/unpause**: The vault owner can both `pause()` and `unpause()`. Only the owner can unpause.
- **Scope**: When paused, `close()`, `withdraw()`, and `liquidate()` remain operational so users can exit positions and withdraw funds.

### Guardian Role

The guardian is set during `init()` (defaults to the vault owner). The owner can update it via `setGuardian()`. The guardian has exactly one power: calling `pause()`. This enables a faster emergency response than a multisig-controlled owner while limiting the guardian's blast radius.

### Recommended Additions (Not Yet Implemented)

1. **Circuit breaker**: Automatically pause if single-block PnL exceeds a threshold.
2. **Timelock on unpause**: Require a delay before unpausing to give users time to exit.

## Governance Progression

The protocol follows a progressive decentralization path, moving from rapid iteration during beta to hardened on-chain governance at mainnet.

### Current State: Beta (Single EOA)

During beta, the VaultManager owner is a single EOA. This enables fast iteration: bug fixes, parameter tuning, and vault deployment without coordination overhead. The trade-off is centralization risk -- a compromised key can upgrade all vaults instantly.

### Target State: Multisig + Timelock

`script/DeployGovernance.s.sol` deploys an OpenZeppelin `TimelockController` and transfers VaultManager ownership to it. After deployment:

- **All admin operations** (upgradeVaultImpl, setVaultMath, newVault) must be proposed through the timelock
- **Configurable delay** (env `DELAY`, default 24 hours) gives LP depositors time to review proposed changes and exit if they disagree
- **Multisig as proposer/executor** -- requires M-of-N signatures to propose or execute any admin action
- **No admin backdoor** -- TimelockController is deployed with `admin = address(0)`, meaning the timelock governs itself. The delay can only be changed through the timelock's own schedule/execute flow

### Why Timelock + Multisig

1. **LP protection**: Depositors can monitor proposed upgrades and withdraw before execution. A 24-48h delay is the industry standard (Compound, Uniswap governance).
2. **Key compromise resilience**: A multisig (e.g., 3-of-5) means a single compromised key cannot execute admin actions.
3. **Transparency**: All proposed operations are visible on-chain before execution. Block explorers and monitoring tools can alert the community.
4. **Self-governing**: The timelock's own parameters (delay, roles) can only be modified through the same schedule/execute flow, preventing privilege escalation.

### Governance Phases

| Phase | Owner | Delay | Status |
|-------|-------|-------|--------|
| Beta | Single EOA | None | Current |
| Mainnet v1 | 3/5 Safe Multisig | 24h via TimelockController | Planned (M2) |
| Mainnet v2 | Expanded multisig | 48-72h | Planned (M3) |
| DAO | On-chain governance token voting | Configurable | Planned (M4+) |

## Frequently Asked Questions

### Does sLiq have a governance token?

Not currently. sLiq Protocol does not have its own token. The governance roadmap (see [Governance Progression](#governance-progression)) outlines a phased approach:

- **M1-M3**: Governance via multisig + timelock. No token required.
- **M4+**: On-chain governance is under consideration as a potential final decentralization step.

The governance token question remains open and is subject to ongoing discussion. Several options are being evaluated:

1. **A dedicated sLiq governance token** — purpose-built for the protocol, with its own distribution and voting mechanics.
2. **Integration with an existing ecosystem token** (e.g., an EarnPark token or an Arbitrum-native mechanism) — leveraging an established holder base.
3. **No token at all** — governance could remain multisig-based with expanded signer sets and community oversight, without introducing a token.

The final decision will depend on regulatory considerations, community feedback, ecosystem alignment, and whether token-based governance genuinely serves the protocol's security and decentralization goals better than alternatives. No commitment to any specific token model has been made. If a governance token is introduced, its design, distribution, and voting parameters will be specified in a separate public governance proposal well in advance.

### What is the relationship between sLiq and EarnPark?

[EarnPark](https://earnpark.com) is the development team and company behind sLiq Protocol. EarnPark handles:
- Protocol development and maintenance
- Security review and audit coordination
- Operational deployment and monitoring
- Community and ecosystem engagement

The protocol contracts are designed to eventually operate independently under on-chain governance. The progressive decentralization path (EOA → multisig → DAO) ensures that the protocol can function without any single entity. The exact relationship between EarnPark's broader product ecosystem and sLiq Protocol governance will be defined transparently as the protocol matures.

### Is `vsLP` a transferable token?

Yes. `vsLP` is a standard ERC-20 token (via `ERC20Upgradeable`) representing LP shares. It can be transferred, used as collateral in other protocols, or integrated into DeFi composability flows.

## Bug Bounty

A bug bounty program is planned but not yet active. Details will be published at [sliq.finance](https://sliq.finance) and linked here when available.

Scope will include:
- All deployed contracts on Arbitrum One
- Critical: fund loss, unauthorized access, oracle manipulation
- High: griefing, DoS, incorrect PnL calculation
- Medium: gas optimization issues, view function errors

## Contact

For responsible disclosure of security vulnerabilities, contact the EarnPark security team via [earnpark.com](https://earnpark.com).
