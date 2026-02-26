// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import "forge-std/Base.sol";
import "forge-std/StdUtils.sol";
import "../../src/Vault.sol";
import "../mocks/MockERC20.sol";

/// @dev Handler contract for Foundry invariant testing.
///      Exposes bounded open/close actions that the fuzzer can call in arbitrary order.
contract VaultHandler is CommonBase, StdUtils {
    Vault public vault;
    MockERC20 public collateral;
    address public actor;

    uint256[] public openPositionIds;

    constructor(Vault vault_, MockERC20 collateral_, address actor_) {
        vault = vault_;
        collateral = collateral_;
        actor = actor_;
    }

    function openLong(uint256 amountSeed, uint256 rangeSeed) external {
        uint256 amount = bound(amountSeed, 10e6, 1000e6);
        int24 range = int24(int256(bound(rangeSeed, 60, 5000)));

        vm.prank(actor);
        uint256 id = vault.openLong(range, amount, Vault.Rolling.No);
        openPositionIds.push(id);
    }

    function openShort(uint256 amountSeed, uint256 rangeSeed) external {
        uint256 amount = bound(amountSeed, 10e6, 1000e6);
        int24 range = int24(int256(bound(rangeSeed, 60, 5000)));

        vm.prank(actor);
        uint256 id = vault.openShort(range, amount, Vault.Rolling.No);
        openPositionIds.push(id);
    }

    function closePosition(uint256 indexSeed) external {
        if (openPositionIds.length == 0) return;

        uint256 idx = indexSeed % openPositionIds.length;
        uint256 id = openPositionIds[idx];

        (address posOwner,,,,,,, bool active,) = vault.positions(id);
        if (!active) {
            _removeAt(idx);
            return;
        }

        vm.prank(posOwner);
        vault.close(id);
        _removeAt(idx);
    }

    function positionCount() external view returns (uint256) {
        return openPositionIds.length;
    }

    function _removeAt(uint256 idx) internal {
        openPositionIds[idx] = openPositionIds[openPositionIds.length - 1];
        openPositionIds.pop();
    }
}
