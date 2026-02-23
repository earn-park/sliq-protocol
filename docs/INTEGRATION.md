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
(uint256 result, bool liquidatable) = IVault(vault).status(positionId);
// result: expected payout in collateral token units
// liquidatable: true if the position can be liquidated
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
| `PositionOpened(uint256 id, address owner, bool isLong, int24 tickLower, int24 tickUpper, uint256 collateral)` | New position created |
| `PositionClosed(uint256 id, uint256 result)` | Position settled |
| `Liquidated(uint256 id, address liquidator, uint256 bounty)` | Position liquidated |
| `Deposit(address depositor, uint256 amount, uint256 shares)` | LP deposit |
| `Withdraw(address withdrawer, uint256 shares, uint256 amount)` | LP withdrawal |

## Deployed Addresses

See [README.md](../README.md#deployments) for current deployment addresses. Contact the team for beta access.
