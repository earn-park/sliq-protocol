// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.30;

import { Script, console } from "forge-std/Script.sol";
import { VaultManager } from "src/VaultManager.sol";
import { VaultMath } from "src/VaultMath.sol";
import { Vault } from "src/Vault.sol";

/// @title Deploy -- sLiq Protocol deployment script
/// @notice Deploys VaultMath, Vault implementation, and VaultManager to the target network.
/// @dev Usage:
///   forge script script/Deploy.s.sol:Deploy \
///     --rpc-url $ARBITRUM_RPC_URL \
///     --broadcast \
///     --verify \
///     --etherscan-api-key $ARBISCAN_API_KEY
contract Deploy is Script {
    function run() external {
        uint256 deployerPrivateKey = vm.envUint("DEPLOYER_PRIVATE_KEY");

        vm.startBroadcast(deployerPrivateKey);

        // 1. Deploy the math library (stateless, shared by all vaults)
        VaultMath vaultMath = new VaultMath();
        console.log("VaultMath deployed at:", address(vaultMath));

        // 2. Deploy the Vault implementation (logic contract, never called directly)
        Vault vaultImpl = new Vault();
        console.log("Vault implementation deployed at:", address(vaultImpl));

        // 3. Deploy VaultManager (owns the beacon, deploys vault proxies)
        VaultManager manager = new VaultManager(address(vaultImpl), address(vaultMath));
        console.log("VaultManager deployed at:", address(manager));

        vm.stopBroadcast();

        console.log("---");
        console.log("Deployment complete. Next steps:");
        console.log("  1. Verify contracts on Arbiscan");
        console.log("  2. Call manager.newVault() to deploy vault proxies for target pools");
        console.log("  3. Transfer VaultManager ownership to multisig");
    }
}
