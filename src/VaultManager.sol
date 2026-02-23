// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.30;

import "@openzeppelin/contracts/proxy/beacon/UpgradeableBeacon.sol";
import "@openzeppelin/contracts/proxy/beacon/BeaconProxy.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "./Vault.sol";

/// @title VaultManager
/// @author sLiq Protocol
/// @notice Beacon proxy manager that deploys and administrates individual Vault instances
contract VaultManager is Ownable {
    /* ~~~~ Custom Errors ~~~~ */
    error VaultAlreadyExists();

    address public vaultMath;
    UpgradeableBeacon public immutable beacon;

    mapping(address => address) public vaultOf; // pool -> vault

    event VaultDeployed(address pool, address vault);
    event VaultImplUpgraded(address newImpl);
    event VaultMathChanged(address newVaultMath);

    constructor(address vaultImpl_, address vaultMath_) {
        vaultMath = vaultMath_;
        beacon = new UpgradeableBeacon(vaultImpl_); // owner = VaultManager (msg.sender in beacon constructor)
    }

    /// @notice Upgrade the Vault implementation for ALL vault proxies
    /// @param newImpl The address of the new implementation contract
    function upgradeVaultImpl(address newImpl) external onlyOwner {
        beacon.upgradeTo(newImpl);
        emit VaultImplUpgraded(newImpl);
    }

    /// @notice Set a new VaultMath library address
    /// @param newVaultMath The address of the new VaultMath contract
    function setVaultMath(address newVaultMath) external onlyOwner {
        vaultMath = newVaultMath;
        emit VaultMathChanged(newVaultMath);
    }

    /// @notice Deploy a new Vault for a given Uniswap V3 pool
    /// @param pool The Uniswap V3 pool address
    /// @param collateral The collateral token address (e.g. USDC)
    /// @param nfpm The Nonfungible Position Manager address
    /// @param anchorId The NFT token ID of the anchor position
    /// @param seq The Chainlink sequencer uptime feed address
    /// @param feed The Chainlink price feed address
    /// @return vault The deployed vault proxy address
    function newVault(address pool, address collateral, address nfpm, uint256 anchorId, address seq, address feed)
        external
        onlyOwner
        returns (address vault)
    {
        if (vaultOf[pool] != address(0)) revert VaultAlreadyExists();

        bytes32 salt = keccak256(abi.encode(pool, anchorId));

        bytes memory initData = abi.encodeCall(
            Vault.init,
            (
                msg.sender, // owner vault
                vaultMath,
                pool,
                collateral,
                nfpm,
                anchorId,
                seq,
                feed
            )
        );

        vault = address(new BeaconProxy{ salt: salt }(address(beacon), initData));

        vaultOf[pool] = vault;
        emit VaultDeployed(pool, vault);
    }
}
