# Deployment Guide

This document describes how to deploy the sLiq Protocol contracts to Arbitrum.

## Prerequisites

- [Foundry](https://book.getfoundry.sh/getting-started/installation) installed
- An Arbitrum RPC endpoint (e.g., Alchemy, Infura, or public RPC)
- A funded deployer wallet
- An Arbiscan API key for contract verification

## Environment Setup

```bash
cp .env.example .env
# Edit .env with your values:
#   ARBITRUM_RPC_URL=https://arb1.arbitrum.io/rpc
#   ARBISCAN_API_KEY=your_key
#   DEPLOYER_PRIVATE_KEY=your_key
```

## Step 1: Deploy Core Contracts

Deploy VaultMath (shared math library), Vault implementation (logic contract), and VaultManager (factory + beacon owner):

```bash
forge script script/Deploy.s.sol:Deploy \
  --rpc-url $ARBITRUM_RPC_URL \
  --broadcast \
  --verify \
  --etherscan-api-key $ARBISCAN_API_KEY
```

This deploys three contracts:

| Contract | Role |
|----------|------|
| VaultMath | Stateless math library shared by all vaults |
| Vault | Implementation contract (never called directly) |
| VaultManager | Factory that deploys vault proxies via UpgradeableBeacon |

## Step 2: Deploy Vault Proxies

For each Uniswap V3 pool you want to support, deploy a vault proxy:

```bash
MANAGER=0x... POOL=0x... COLLATERAL=0x... NFPM=0x... \
ANCHOR_ID=123 SEQ=0x... FEED=0x... \
forge script script/DeployVault.s.sol:DeployVault \
  --rpc-url $ARBITRUM_RPC_URL \
  --broadcast
```

### Required Addresses (Arbitrum One)

| Contract | Address | Description |
|----------|---------|-------------|
| Uniswap V3 NFPM | `0xC36442b4a4522E871399CD717aBDD847Ab11FE88` | NonfungiblePositionManager |
| Chainlink Sequencer | `0xFdB631F5EE196F0ed6FAa767959853A9F217697D` | Arbitrum sequencer uptime feed |
| Chainlink ETH/USD | `0x639Fe6ab55C921f74e7fac1ee960C0B6293ba612` | Price feed (example) |

## Step 3: Post-Deployment

1. **Verify all contracts** on Arbiscan if `--verify` did not complete
2. **Transfer VaultManager ownership** to a multisig (recommended: Safe 3-of-5)
3. **Set fee parameters** via `vault.setFees(vaultE2, protocolE2, liquidatorE18)`
4. **Monitor** deployment events and initial transactions

## Upgrade Process

To upgrade the Vault implementation across all pools:

```bash
# Deploy new implementation
forge create src/Vault.sol:Vault --rpc-url $ARBITRUM_RPC_URL --private-key $DEPLOYER_PRIVATE_KEY

# Upgrade beacon (owner-only)
cast send $VAULT_MANAGER "upgradeVaultImpl(address)" $NEW_IMPL --rpc-url $ARBITRUM_RPC_URL --private-key $DEPLOYER_PRIVATE_KEY
```

All vault proxies automatically delegate to the new implementation after `upgradeVaultImpl()` completes.

## Network Configuration

| Network | Chain ID | RPC | Explorer |
|---------|----------|-----|----------|
| Arbitrum One | 42161 | `https://arb1.arbitrum.io/rpc` | [arbiscan.io](https://arbiscan.io) |
| Arbitrum Sepolia | 421614 | `https://sepolia-rollup.arbitrum.io/rpc` | [sepolia.arbiscan.io](https://sepolia.arbiscan.io) |
