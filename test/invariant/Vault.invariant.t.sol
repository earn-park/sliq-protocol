// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import "forge-std/Test.sol";
import "../../src/Vault.sol";
import "../../src/VaultManager.sol";
import "../../src/VaultMath.sol";
import "../mocks/MockERC20.sol";
import "../mocks/MockUniswapV3Pool.sol";
import "../mocks/MockNFPM.sol";
import "../mocks/MockChainlinkFeed.sol";
import "./VaultHandler.sol";
import "@uniswap/v3-core/contracts/libraries/TickMath.sol";

/// @dev Invariant test: freezBalance == sum of collateral for all active positions
contract VaultInvariantTest is Test {
    Vault public vault;
    VaultManager public manager;
    VaultMath public vaultMath;
    MockERC20 public collateral;
    MockUniswapV3Pool public pool;
    MockNFPM public nfpm;
    MockChainlinkFeed public seq;
    MockChainlinkFeed public feed;
    VaultHandler public handler;

    address actor = address(0xA11CE);
    uint256 anchorId = 1;

    function setUp() public {
        collateral = new MockERC20("USDC", "USDC", 6);
        pool = new MockUniswapV3Pool();
        nfpm = new MockNFPM();
        vaultMath = new VaultMath();

        uint160 sqrtP = TickMath.getSqrtRatioAtTick(0);
        pool.setSlot0(sqrtP, 0);

        nfpm.setPosition(anchorId, address(collateral), address(collateral), -1000, 1000, 1e18, 0, 0, 0, 0);
        nfpm.setOwner(anchorId, address(this));

        seq = new MockChainlinkFeed(0);
        seq.setLatestRoundData(1, 1, 0, 0, 1);

        feed = new MockChainlinkFeed(8);
        feed.setLatestRoundData(1, 0, 0, 0, 1);

        Vault vaultImpl = new Vault();
        manager = new VaultManager(address(vaultImpl), address(vaultMath));

        address vaultAddr = manager.newVault(
            address(pool), address(collateral), address(nfpm), anchorId, address(seq), address(feed)
        );
        vault = Vault(vaultAddr);

        // Fund actor and LP deposit
        collateral.mint(actor, 10_000_000e6);
        vm.prank(actor);
        collateral.approve(address(vault), type(uint256).max);

        // LP deposit so vault has liquidity for payouts
        collateral.mint(address(this), 1_000_000e6);
        collateral.approve(address(vault), type(uint256).max);
        vault.deposit(500_000e6);

        // Deploy handler and target it
        handler = new VaultHandler(vault, collateral, actor);
        targetContract(address(handler));
    }

    /// @dev Invariant 1: freezBalance == sum of collateral for all active positions
    function invariant_CollateralAccounting() public view {
        uint256 sumCollateral = 0;
        uint256 nextId = vault.nextPosId();

        for (uint256 i = 1; i < nextId; i++) {
            (,,uint256 posCollateral,,,,, bool active,) = vault.positions(i);
            if (active) {
                sumCollateral += posCollateral;
            }
        }

        assertEq(vault.freezBalance(), sumCollateral, "Invariant 1 violated: freezBalance != sum of active collateral");
    }

    /// @dev Invariant 4: vault balance >= freezBalance (solvency)
    function invariant_VaultSolvency() public view {
        uint256 vaultBalance = collateral.balanceOf(address(vault));
        uint256 frozen = vault.freezBalance();

        assertGe(vaultBalance, frozen, "Invariant 4 violated: vault balance < freezBalance");
    }
}
