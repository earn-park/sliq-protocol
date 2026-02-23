// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.30;

import { Script, console } from "forge-std/Script.sol";
import { TimelockController } from "@openzeppelin/contracts/governance/TimelockController.sol";
import { VaultManager } from "src/VaultManager.sol";

/// @title DeployGovernance -- deploy TimelockController and transfer ownership
/// @notice Deploys a TimelockController with configurable delay and transfers
///   VaultManager ownership to it. This enforces a time delay on all admin
///   operations (upgrades, fee changes, new vault deployments).
/// @dev Usage:
///   MANAGER=0x... MULTISIG=0x... DELAY=86400 \
///   forge script script/DeployGovernance.s.sol:DeployGovernance \
///     --rpc-url $ARBITRUM_RPC_URL \
///     --broadcast
contract DeployGovernance is Script {
    function run() external {
        uint256 deployerPrivateKey = vm.envUint("DEPLOYER_PRIVATE_KEY");
        address manager = vm.envAddress("MANAGER");
        address multisig = vm.envAddress("MULTISIG");
        uint256 delay = vm.envOr("DELAY", uint256(86400)); // default 24h

        address[] memory proposers = new address[](1);
        proposers[0] = multisig;

        address[] memory executors = new address[](1);
        executors[0] = multisig;

        vm.startBroadcast(deployerPrivateKey);

        // 1. Deploy TimelockController
        //    - minDelay: configurable (default 24h)
        //    - proposers: multisig only
        //    - executors: multisig only
        //    - admin: address(0) => no admin, timelock governs itself
        TimelockController timelock = new TimelockController(delay, proposers, executors, address(0));
        console.log("TimelockController deployed at:", address(timelock));
        console.log("  Min delay:", delay, "seconds");

        // 2. Transfer VaultManager ownership to the timelock
        VaultManager(manager).transferOwnership(address(timelock));
        console.log("VaultManager ownership transferred to timelock");

        vm.stopBroadcast();

        console.log("---");
        console.log("Governance setup complete.");
        console.log("  All VaultManager operations now require:");
        console.log("  1. Multisig proposes via timelock.schedule()");
        console.log("  2. Wait", delay, "seconds");
        console.log("  3. Multisig executes via timelock.execute()");
    }
}
