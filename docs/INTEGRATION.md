# Integration Guide

This document describes how external protocols and frontends can integrate with sLiq Protocol vaults on Arbitrum.

## Contract Interfaces

All public interfaces are defined in `src/interfaces/`:

| Interface | Description |
|-----------|-------------|
| [`IVault`](../src/interfaces/IVault.sol) | Position management, LP deposits/withdrawals, checkpoints |
| [`IVaultManager`](../src/interfaces/IVaultManager.sol) | Vault registry, deployment, upgrades |
| [`IVaultMath`](../src/interfaces/IVaultMath.sol) | Price conversions, IL calculations, fee computations |

## Reading Vault State

### Get vault address for a pool

```solidity
address vault = IVaultManager(manager).vaultOf(poolAddress);
```

### Check position status

```solidity
(uint256 collateral, uint256 fee, uint256 il, uint256 kE18, int256 result, bool active) =
    IVault(vault).status(positionId);
// collateral: initial deposit amount
// fee: accumulated fee entitlement in collateral units
// il: accumulated impermanent loss in collateral units
// kE18: current K-multiplier for this position's side (1e18 = 1.0)
// result: net payout (positive = profit, negative = loss)
// active: true if the position is still open
```

### Get LP share price

```solidity
uint256 totalAssets = IERC20(collateral).balanceOf(vault);
uint256 totalShares = IVault(vault).totalSupply();
uint256 pricePerShare = totalAssets * 1e18 / totalShares;
```

### Read current oracle price

```solidity
int24 tick = IVault(vault).currentTick();
uint256 priceE18 = IVaultMath(vaultMath).tickToPriceE18(tick);
```

## Opening Positions

### Prerequisites

1. Approve collateral token spending: `collateral.approve(vault, amount)`
2. Choose position parameters:
   - `range`: tick range width (determines leverage; narrower = higher leverage)
   - `amount`: collateral in token units
   - `rolling`: auto-roll strategy (0 = No, 1 = Direct, 2 = InverseMinus, 3 = InversePlus)

### Open a Long IL position

```solidity
uint256 positionId = IVault(vault).openLong(range, amount, rolling);
```

### Open a Short IL position

```solidity
uint256 positionId = IVault(vault).openShort(range, amount, rolling);
```

### Estimate PnL before opening

```solidity
(uint256 estResult,) = IVault(vault).estimateLong(range, amount);
(uint256 estResult,) = IVault(vault).estimateShort(range, amount);
```

## LP Integration

### Deposit collateral

```solidity
collateral.approve(vault, amount);
IVault(vault).deposit(amount);
// Caller receives vsLP shares proportional to deposit
```

### Withdraw collateral

```solidity
IVault(vault).withdraw(shares);
// Burns shares, returns proportional collateral
```

## Keeper / Liquidator Integration

Liquidators earn a fixed bounty for liquidating positions that meet criteria:

```solidity
// Check if a position is liquidatable
(, bool liquidatable) = IVault(vault).status(positionId);

if (liquidatable) {
    IVault(vault).liquidate(positionId);
    // Liquidator receives bountyLiquidatorE18 from the position
}
```

### Liquidation criteria

| Position Type | Condition |
|---------------|-----------|
| Long IL | Current tick is outside the position's `[tickLower, tickUpper]` range |
| Short IL | Accumulated fees exceed the position's collateral |

## Events

Key events emitted by the Vault:

| Event | Description |
|-------|-------------|
| `Open(uint256 id, address owner, Side side, uint256 collateral, int24 tickLower, int24 tickUpper, uint256 kE18, Rolling rolling)` | New position created |
| `Close(uint256 id, address owner, Side side, uint256 collateral, int24 tickLower, int24 tickUpper, int256 result, uint256 fee, uint256 il, uint256 kE18)` | Position settled |
| `Liquidate(uint256 id, address owner, Side side, uint256 collateral, int24 tickLower, int24 tickUpper, int256 result, uint256 fee, uint256 il, uint256 kE18, uint256 bountys)` | Position liquidated |
| `Deposit(address from, uint256 assets, uint256 shares)` | LP deposit |
| `Withdraw(address from, uint256 assets, uint256 shares)` | LP withdrawal |
| `PayoutShortfall(uint256 positionId, address owner, uint256 entitled, uint256 paid)` | Partial payout due to insufficient vault balance |
| `FeesUpdated(uint16 vaultE2, uint16 protocolE2, uint256 liquidatorE18)` | Fee parameters changed |
| `RollSkipped(uint256 positionId, address owner)` | Auto-roll failed (insufficient balance or allowance) |

## Deployed Addresses

See [README.md](../README.md#deployments) for current deployment addresses. Contact the team for beta access.
