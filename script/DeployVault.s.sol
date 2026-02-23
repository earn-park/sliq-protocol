// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.30;

import { Script, console } from "forge-std/Script.sol";
import { VaultManager } from "src/VaultManager.sol";

/// @title DeployVault -- deploy a new vault proxy for a Uniswap V3 pool
/// @notice Creates a new Vault BeaconProxy via VaultManager.newVault().
/// @dev Usage:
///   MANAGER=0x... POOL=0x... COLLATERAL=0x... NFPM=0x... ANCHOR_ID=123 SEQ=0x... FEED=0x... \
///   forge script script/DeployVault.s.sol:DeployVault \
///     --rpc-url $ARBITRUM_RPC_URL \
///     --broadcast
contract DeployVault is Script {
    function run() external {
        uint256 deployerPrivateKey = vm.envUint("DEPLOYER_PRIVATE_KEY");
        address manager = vm.envAddress("MANAGER");
        address pool = vm.envAddress("POOL");
        address collateral = vm.envAddress("COLLATERAL");
        address nfpm = vm.envAddress("NFPM");
        uint256 anchorId = vm.envUint("ANCHOR_ID");
        address seq = vm.envAddress("SEQ");
        address feed = vm.envAddress("FEED");

        vm.startBroadcast(deployerPrivateKey);

        address vault = VaultManager(manager).newVault(pool, collateral, nfpm, anchorId, seq, feed);

        vm.stopBroadcast();

        console.log("Vault proxy deployed at:", vault);
        console.log("  Pool:", pool);
        console.log("  Collateral:", collateral);
        console.log("  Anchor NFT ID:", anchorId);
    }
}
