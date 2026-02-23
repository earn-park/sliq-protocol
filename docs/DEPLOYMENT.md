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
3. **Set fee parameters** via `vault.setFees(vaultE2, protocolE2, liquidatorE18)`:
   - Default vault fee: 300 basis points (3%)
   - Default protocol fee: 200 basis points (2%)
   - Default liquidator bounty: 15e12 (0.000015 tokens)
   - On-chain caps: combined vault + protocol fee capped at 2000 bps (20%), bounty capped at 1e18
4. **Set guardian** for emergency pause via `vault.setGuardian(guardianAddress)`
5. **Deploy governance** (optional): run `script/DeployGovernance.s.sol` to set up a TimelockController with configurable delay (recommended 48-72h)
6. **Monitor** deployment events and initial transactions

## Governance Setup (Multisig + Timelock)

Production deployments must transfer admin control from the deployer EOA to a governance stack: Safe multisig + TimelockController. This section documents the full procedure.

### 1. Deploy a Safe Multisig

Create a [Safe](https://app.safe.global) on Arbitrum One with the following configuration:

| Parameter | Recommended Value | Rationale |
|-----------|------------------|-----------|
| Signers | 5 addresses | Team leads, advisors, or known community members |
| Threshold | 3-of-5 | Balances security (no single key compromise) with availability |
| Network | Arbitrum One (42161) | Match the protocol deployment chain |

Record the Safe address as `$MULTISIG`.

### 2. Deploy TimelockController

The timelock enforces a mandatory delay between proposal and execution of admin operations.

```bash
MANAGER=$VAULT_MANAGER MULTISIG=$MULTISIG DELAY=172800 \
forge script script/DeployGovernance.s.sol:DeployGovernance \
  --rpc-url $ARBITRUM_RPC_URL \
  --broadcast \
  --verify \
  --etherscan-api-key $ARBISCAN_API_KEY
```

| Parameter | Default | Production Recommendation |
|-----------|---------|--------------------------|
| `DELAY` | 86400 (24h) | 172800 (48h) for mainnet |

This script:
1. Deploys a `TimelockController` with the multisig as sole proposer and executor
2. Sets `admin` to `address(0)` (timelock governs itself -- no backdoor)
3. Transfers `VaultManager` ownership to the timelock

After this, the ownership chain is:

```
Safe Multisig (3-of-5)
  └─ proposes/executes on ──▶ TimelockController (48h delay)
                                └─ owns ──▶ VaultManager
                                              ├─ UpgradeableBeacon (vault implementation)
                                              └─ newVault(), setVaultMath()
```

### 3. Verify Ownership Transfer

```bash
# Confirm VaultManager owner is the timelock
cast call $VAULT_MANAGER "owner()(address)" --rpc-url $ARBITRUM_RPC_URL

# Confirm timelock has correct delay
cast call $TIMELOCK "getMinDelay()(uint256)" --rpc-url $ARBITRUM_RPC_URL
```

### 4. Transfer Vault Ownership

Each vault proxy also has an `owner` (receives protocol fees, sets fees/guardian). Transfer each vault's ownership to the timelock:

```bash
# For each vault proxy:
cast send $VAULT "transferOwnership(address)" $TIMELOCK \
  --rpc-url $ARBITRUM_RPC_URL \
  --private-key $DEPLOYER_PRIVATE_KEY
```

### 5. Guardian Setup

The guardian can pause vaults without timelock delay (for emergency response). This should be a separate hot wallet or a 2-of-3 ops multisig, NOT the main 3-of-5 multisig:

```bash
# Set guardian on each vault (must be called by current owner before timelock transfer)
cast send $VAULT "setGuardian(address)" $GUARDIAN_ADDRESS \
  --rpc-url $ARBITRUM_RPC_URL \
  --private-key $DEPLOYER_PRIVATE_KEY
```

## Upgrade Process via Multisig + Timelock

All upgrades after governance setup require a two-phase process: propose through the timelock, wait for the delay, then execute.

### Vault Implementation Upgrade

Upgrades the Vault logic for ALL vault proxies atomically via the beacon.

**Phase 1: Deploy and verify the new implementation**

```bash
# Deploy new Vault implementation
forge create src/Vault.sol:Vault \
  --rpc-url $ARBITRUM_RPC_URL \
  --private-key $DEPLOYER_PRIVATE_KEY \
  --verify \
  --etherscan-api-key $ARBISCAN_API_KEY
```

Record the new implementation address as `$NEW_IMPL`.

**Pre-upgrade checklist:**
- [ ] New implementation compiles with `forge build --sizes` (under 24,576 bytes)
- [ ] All tests pass with `forge test`
- [ ] Storage layout is backward-compatible (no reordering, only appending new variables)
- [ ] New implementation is verified on Arbiscan
- [ ] Diff reviewed by at least 2 signers

**Phase 2: Propose via timelock (from Safe UI)**

In the Safe Transaction Builder, create a batch transaction:

1. **Target:** `$TIMELOCK`
2. **Function:** `schedule(address target, uint256 value, bytes data, bytes32 predecessor, bytes32 salt, uint256 delay)`
3. **Parameters:**
   - `target`: `$VAULT_MANAGER`
   - `value`: `0`
   - `data`: `abi.encodeCall(VaultManager.upgradeVaultImpl, ($NEW_IMPL))`
   - `predecessor`: `0x0000...0000` (no dependency)
   - `salt`: unique bytes32 (e.g., `keccak256("upgrade-v1.1-2026-03-01")`)
   - `delay`: `172800` (or current timelock min delay)

Using `cast`:
```bash
# Encode the upgrade call
UPGRADE_DATA=$(cast calldata "upgradeVaultImpl(address)" $NEW_IMPL)

# Encode the schedule call
cast calldata "schedule(address,uint256,bytes,bytes32,bytes32,uint256)" \
  $VAULT_MANAGER 0 $UPGRADE_DATA \
  0x0000000000000000000000000000000000000000000000000000000000000000 \
  $(cast keccak "upgrade-v1.1") \
  172800
```

Submit this as a Safe transaction requiring 3-of-5 signatures.

**Phase 3: Wait for delay**

The timelock enforces the configured delay (48h). During this window:
- Monitor for any reports of issues with the new implementation
- Community has time to review the pending upgrade on-chain
- If issues are found, the proposal can be cancelled via `timelock.cancel()`

**Phase 4: Execute via timelock (from Safe UI)**

After the delay has passed:

```bash
EXECUTE_DATA=$(cast calldata "upgradeVaultImpl(address)" $NEW_IMPL)

cast calldata "execute(address,uint256,bytes,bytes32,bytes32)" \
  $VAULT_MANAGER 0 $EXECUTE_DATA \
  0x0000000000000000000000000000000000000000000000000000000000000000 \
  $(cast keccak "upgrade-v1.1")
```

Submit as a Safe transaction requiring 3-of-5 signatures.

**Phase 5: Post-upgrade verification**

```bash
# Verify beacon points to new implementation
cast call $VAULT_MANAGER "beacon()(address)" --rpc-url $ARBITRUM_RPC_URL
BEACON=$(cast call $VAULT_MANAGER "beacon()(address)" --rpc-url $ARBITRUM_RPC_URL)
cast call $BEACON "implementation()(address)" --rpc-url $ARBITRUM_RPC_URL

# Verify existing vaults still function
cast call $VAULT "totalSupply()(uint256)" --rpc-url $ARBITRUM_RPC_URL
cast call $VAULT "nextPosId()(uint256)" --rpc-url $ARBITRUM_RPC_URL

# Run a test status query on a known position
cast call $VAULT "status(uint256)(uint256,uint256,uint256,uint256,int256,bool)" 1 --rpc-url $ARBITRUM_RPC_URL
```

### VaultMath Upgrade

Updates the math library. Note: only affects newly deployed vaults; existing vaults keep their VaultMath reference.

```bash
# Deploy new VaultMath
forge create src/VaultMath.sol:VaultMath \
  --rpc-url $ARBITRUM_RPC_URL \
  --private-key $DEPLOYER_PRIVATE_KEY \
  --verify --etherscan-api-key $ARBISCAN_API_KEY

# Schedule via timelock (same pattern as above)
MATH_DATA=$(cast calldata "setVaultMath(address)" $NEW_VAULT_MATH)

# Propose -> Wait -> Execute (same 3-phase process)
```

### Fee Parameter Changes

Fee changes on individual vaults also go through the timelock (since the timelock is the vault owner):

```bash
# Encode setFees call
FEE_DATA=$(cast calldata "setFees(uint16,uint16,uint256)" 300 200 15000000000000)

# Schedule on the timelock targeting the specific vault
cast calldata "schedule(address,uint256,bytes,bytes32,bytes32,uint256)" \
  $VAULT 0 $FEE_DATA \
  0x0000000000000000000000000000000000000000000000000000000000000000 \
  $(cast keccak "fee-update-2026-03") \
  172800
```

### New Vault Deployment

Deploying a vault for a new pool also requires timelock approval:

```bash
# Encode newVault call
VAULT_DATA=$(cast calldata "newVault(address,address,address,uint256,address,address)" \
  $POOL $COLLATERAL $NFPM $ANCHOR_ID $SEQ $FEED)

# Schedule -> Wait -> Execute (same 3-phase process targeting $VAULT_MANAGER)
```

### Emergency Pause

The guardian role is intentionally outside the timelock for rapid response:

```bash
# Guardian can pause any vault immediately (no timelock delay)
cast send $VAULT "pause()" --rpc-url $ARBITRUM_RPC_URL --private-key $GUARDIAN_PRIVATE_KEY
```

Only the vault owner (timelock) can unpause, ensuring pause is reviewed before resuming:

```bash
# Unpause requires full timelock cycle
UNPAUSE_DATA=$(cast calldata "unpause()")
# Schedule -> Wait -> Execute targeting $VAULT
```

### Cancelling a Pending Operation

If an issue is discovered during the timelock delay:

```bash
# Compute the operation ID
OPERATION_ID=$(cast call $TIMELOCK "hashOperation(address,uint256,bytes,bytes32,bytes32)(bytes32)" \
  $TARGET 0 $DATA $PREDECESSOR $SALT --rpc-url $ARBITRUM_RPC_URL)

# Cancel (requires proposer role = multisig)
cast calldata "cancel(bytes32)" $OPERATION_ID
# Submit as Safe transaction
```

## Storage Layout Compatibility

When upgrading Vault implementations, the new contract MUST preserve storage layout compatibility:

1. **Never reorder** existing storage variables
2. **Never remove** existing storage variables (mark unused ones with `__deprecated_` prefix)
3. **Only append** new storage variables after existing ones
4. The `uint256[50] private __gap` reserve provides 50 slots (1,600 bytes) for new state variables
5. When adding N new variables, reduce `__gap` to `__gap[50 - N]` to maintain the total slot count

**Verification:** Before proposing an upgrade, compare storage layouts:

```bash
# Generate storage layout for current and new implementations
forge inspect Vault storageLayout --pretty > layout-current.json
# (after building new implementation)
forge inspect Vault storageLayout --pretty > layout-new.json
diff layout-current.json layout-new.json
```

## Network Configuration

| Network | Chain ID | RPC | Explorer |
|---------|----------|-----|----------|
| Arbitrum One | 42161 | `https://arb1.arbitrum.io/rpc` | [arbiscan.io](https://arbiscan.io) |
| Arbitrum Sepolia | 421614 | `https://sepolia-rollup.arbitrum.io/rpc` | [sepolia.arbiscan.io](https://sepolia.arbiscan.io) |
