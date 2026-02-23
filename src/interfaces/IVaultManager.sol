// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.30;

import "@openzeppelin/contracts/proxy/beacon/UpgradeableBeacon.sol";

/// @title IVaultManager
/// @notice Interface for the sLiq beacon proxy manager
interface IVaultManager {
    event VaultDeployed(address pool, address vault);
    event VaultImplUpgraded(address newImpl);
    event VaultMathChanged(address newVaultMath);

    error VaultAlreadyExists();

    function vaultMath() external view returns (address);
    function beacon() external view returns (UpgradeableBeacon);
    function vaultOf(address pool) external view returns (address);

    function upgradeVaultImpl(address newImpl) external;
    function setVaultMath(address newVaultMath) external;

    function newVault(address pool, address collateral, address nfpm, uint256 anchorId, address seq, address feed)
        external
        returns (address vault);
}
