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
import "@uniswap/v3-core/contracts/libraries/TickMath.sol";

contract VaultTest is Test {
    Vault public vault;
    VaultManager public manager;
    VaultMath public vaultMath;
    MockERC20 public collateral;
    MockUniswapV3Pool public pool;
    MockNFPM public nfpm;
    MockChainlinkFeed public seq;
    MockChainlinkFeed public feed;

    address owner = address(this);
    address alice = address(0xA11CE);
    address bob = address(0xB0B);
    uint256 anchorId = 1;

    int24 constant ANCHOR_LOWER = -1000;
    int24 constant ANCHOR_UPPER = 1000;
    uint128 constant ANCHOR_LIQ = 1e18;

    function setUp() public {
        collateral = new MockERC20("USDC", "USDC", 6);
        pool = new MockUniswapV3Pool();
        nfpm = new MockNFPM();
        vaultMath = new VaultMath();

        uint160 sqrtP = TickMath.getSqrtRatioAtTick(0);
        pool.setSlot0(sqrtP, 0);

        nfpm.setPosition(
            anchorId, address(collateral), address(collateral), ANCHOR_LOWER, ANCHOR_UPPER, ANCHOR_LIQ, 0, 0, 0, 0
        );

        // Sequencer: force fallback to pool.slot0()
        // status=1 => sequencer DOWN, so Chainlink not used
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

        // Mint collateral for test actors
        collateral.mint(alice, 100_000e6);
        collateral.mint(bob, 100_000e6);
        collateral.mint(owner, 100_000e6);

        // Approve vault
        vm.prank(alice);
        collateral.approve(address(vault), type(uint256).max);
        vm.prank(bob);
        collateral.approve(address(vault), type(uint256).max);
        collateral.approve(address(vault), type(uint256).max);
    }

    // ---- Init ----

    function test_Init_SetsStateCorrectly() public view {
        assertEq(address(vault.collateralToken()), address(collateral));
        assertEq(address(vault.pool()), address(pool));
        assertEq(vault.anchorId(), anchorId);
        assertEq(vault.decimals(), 6);
        assertEq(vault.feeVaultPercentE2(), 300);
        assertEq(vault.feeProtocolPercentE2(), 200);
        assertEq(vault.bountyLiquidatorE18(), 15e12);
    }

    function test_Init_ShareTokenName() public view {
        assertEq(vault.name(), "Vault Share LP");
        assertEq(vault.symbol(), "vsLP");
    }

    function test_Init_NextPosIdStartsAtDefault() public view {
        // In a BeaconProxy, the storage variable nextPosId
        // starts at the default (0) since the initializer does not set it.
        // The `= 1` in the declaration is only for the implementation, not the proxy.
        assertEq(vault.nextPosId(), 0);
    }

    function test_RevertWhen_Init_CalledTwice() public {
        vm.expectRevert("Initializable: contract is already initialized");
        vault.init(
            owner,
            address(vaultMath),
            address(pool),
            address(collateral),
            address(nfpm),
            anchorId,
            address(seq),
            address(feed)
        );
    }

    // ---- Deposit ----

    function test_Deposit_FirstDepositor1to1() public {
        vm.prank(alice);
        uint256 shares = vault.deposit(1000e6);
        assertEq(shares, 1000e6);
        assertEq(vault.balanceOf(alice), 1000e6);
        assertEq(vault.totalSupply(), 1000e6);
    }

    function test_Deposit_TransfersTokens() public {
        uint256 balBefore = collateral.balanceOf(alice);
        vm.prank(alice);
        vault.deposit(1000e6);
        uint256 balAfter = collateral.balanceOf(alice);
        assertEq(balBefore - balAfter, 1000e6);
    }

    function test_Deposit_EmitsEvent() public {
        vm.prank(alice);
        vm.expectEmit(true, false, false, true);
        emit Vault.Deposit(alice, 1000e6, 1000e6);
        vault.deposit(1000e6);
    }

    function test_RevertWhen_Deposit_ZeroAmount() public {
        vm.prank(alice);
        vm.expectRevert(Vault.ZeroAmount.selector);
        vault.deposit(0);
    }

    function test_Deposit_SecondDepositor() public {
        vm.prank(alice);
        vault.deposit(1000e6);

        vm.prank(bob);
        uint256 shares = vault.deposit(1000e6);
        // Second depositor: shares = amount * totalSupply / assetsBefore
        // = 1000e6 * 1000e6 / 1000e6 = 1000e6
        assertEq(shares, 1000e6);
    }

    // ---- Withdraw ----

    function test_Withdraw_FullAmount() public {
        vm.prank(alice);
        vault.deposit(1000e6);

        uint256 balBefore = collateral.balanceOf(alice);
        vm.prank(alice);
        uint256 amount = vault.withdraw(1000e6);
        uint256 balAfter = collateral.balanceOf(alice);

        assertEq(amount, 1000e6);
        assertEq(balAfter - balBefore, 1000e6);
        assertEq(vault.balanceOf(alice), 0);
    }

    function test_Withdraw_PartialAmount() public {
        vm.prank(alice);
        vault.deposit(1000e6);

        vm.prank(alice);
        uint256 amount = vault.withdraw(500e6);
        assertEq(amount, 500e6);
        assertEq(vault.balanceOf(alice), 500e6);
    }

    function test_Withdraw_EmitsEvent() public {
        vm.prank(alice);
        vault.deposit(1000e6);

        vm.prank(alice);
        vm.expectEmit(true, false, false, true);
        emit Vault.Withdraw(alice, 1000e6, 1000e6);
        vault.withdraw(1000e6);
    }

    function test_RevertWhen_Withdraw_ZeroShares() public {
        vm.prank(alice);
        vault.deposit(1000e6);

        vm.prank(alice);
        vm.expectRevert(Vault.BadShares.selector);
        vault.withdraw(0);
    }

    function test_RevertWhen_Withdraw_MoreThanBalance() public {
        vm.prank(alice);
        vault.deposit(1000e6);

        vm.prank(alice);
        vm.expectRevert(Vault.BadShares.selector);
        vault.withdraw(2000e6);
    }

    // ---- openLong / openShort ----

    function test_OpenLong_CreatesPosition() public {
        // Deposit liquidity first so the vault can pay
        vault.deposit(10_000e6);

        vm.prank(alice);
        uint256 id = vault.openLong(500, 100e6, Vault.Rolling.No);
        assertEq(id, 0);
        assertEq(vault.nextPosId(), 1);

        (
            address posOwner,
            Vault.Side side,
            uint256 col,,
            int24 tickLow,
            int24 tickHigh,
            int256 result,
            bool active,
            Vault.Rolling rolling
        ) = vault.positions(id);

        assertEq(posOwner, alice);
        assertTrue(side == Vault.Side.Long);
        assertEq(col, 100e6);
        assertTrue(active);
        assertTrue(rolling == Vault.Rolling.No);
        assertEq(result, 0);
        assertLt(tickLow, tickHigh);
    }

    function test_OpenShort_CreatesPosition() public {
        vault.deposit(10_000e6);

        vm.prank(alice);
        uint256 id = vault.openShort(500, 100e6, Vault.Rolling.No);
        assertEq(id, 0);

        (, Vault.Side side, uint256 col,,,,,,) = vault.positions(id);

        assertTrue(side == Vault.Side.Short);
        assertEq(col, 100e6);
    }

    function test_Open_TransfersCollateral() public {
        vault.deposit(10_000e6);

        uint256 balBefore = collateral.balanceOf(alice);
        vm.prank(alice);
        vault.openLong(500, 100e6, Vault.Rolling.No);
        uint256 balAfter = collateral.balanceOf(alice);
        assertEq(balBefore - balAfter, 100e6);
    }

    function test_Open_IncrementsEffLiquidity() public {
        vault.deposit(10_000e6);

        uint256 effBefore = vault.totalEffLong();
        vm.prank(alice);
        vault.openLong(500, 100e6, Vault.Rolling.No);
        uint256 effAfter = vault.totalEffLong();
        assertGt(effAfter, effBefore);
    }

    function test_RevertWhen_Open_ZeroAmount() public {
        vault.deposit(10_000e6);

        vm.prank(alice);
        vm.expectRevert(Vault.ZeroAmount.selector);
        vault.openLong(500, 0, Vault.Rolling.No);
    }

    function test_RevertWhen_Open_ZeroRange() public {
        vault.deposit(10_000e6);

        vm.prank(alice);
        vm.expectRevert(Vault.ZeroRange.selector);
        vault.openLong(0, 100e6, Vault.Rolling.No);
    }

    function test_Open_MultiplePositions() public {
        vault.deposit(10_000e6);

        vm.prank(alice);
        uint256 id1 = vault.openLong(500, 100e6, Vault.Rolling.No);

        vm.prank(bob);
        uint256 id2 = vault.openShort(300, 200e6, Vault.Rolling.No);

        assertEq(id1, 0);
        assertEq(id2, 1);
    }

    function test_Open_WithRollingDirect() public {
        vault.deposit(10_000e6);

        vm.prank(alice);
        uint256 id = vault.openLong(500, 100e6, Vault.Rolling.Direct);

        (,,,,,,,, Vault.Rolling rolling) = vault.positions(id);
        assertTrue(rolling == Vault.Rolling.Direct);
    }

    // ---- Close ----

    function test_Close_ByOwner() public {
        vault.deposit(10_000e6);

        vm.prank(alice);
        uint256 id = vault.openLong(500, 100e6, Vault.Rolling.No);

        // Advance time for checkpoint
        vm.warp(block.timestamp + 1 hours);

        vm.prank(alice);
        vault.close(id);

        (,,,,,,, bool active,) = vault.positions(id);
        assertFalse(active);
    }

    function test_RevertWhen_Close_NotOwner() public {
        vault.deposit(10_000e6);

        vm.prank(alice);
        uint256 id = vault.openLong(500, 100e6, Vault.Rolling.No);

        vm.prank(bob);
        vm.expectRevert(Vault.NotPositionOwner.selector);
        vault.close(id);
    }

    function test_RevertWhen_Close_AlreadyClosed() public {
        vault.deposit(10_000e6);

        vm.prank(alice);
        uint256 id = vault.openLong(500, 100e6, Vault.Rolling.No);

        vm.warp(block.timestamp + 1 hours);

        vm.prank(alice);
        vault.close(id);

        vm.prank(alice);
        vm.expectRevert(Vault.PositionNotActive.selector);
        vault.close(id);
    }

    function test_Close_DecrementsEffLiquidity() public {
        vault.deposit(10_000e6);

        vm.prank(alice);
        uint256 id = vault.openLong(500, 100e6, Vault.Rolling.No);

        uint256 effBefore = vault.totalEffLong();
        assertGt(effBefore, 0);

        vm.warp(block.timestamp + 1 hours);

        vm.prank(alice);
        vault.close(id);

        uint256 effAfter = vault.totalEffLong();
        assertEq(effAfter, 0);
    }

    // ---- Liquidate ----

    function test_Liquidate_WhenOutOfRange() public {
        vault.deposit(10_000e6);

        vm.prank(alice);
        uint256 id = vault.openLong(500, 100e6, Vault.Rolling.No);

        (,,,, int24 tickLow,,,,) = vault.positions(id);

        // Move price out of position range
        int24 newTick = tickLow - 100;
        uint160 newSqrtP = TickMath.getSqrtRatioAtTick(newTick);
        pool.setSlot0(newSqrtP, newTick);

        vm.warp(block.timestamp + 1 hours);

        // Bob liquidates
        vm.prank(bob);
        vault.liquidate(id);

        (,,,,,,, bool active,) = vault.positions(id);
        assertFalse(active);
    }

    function test_RevertWhen_Liquidate_InRange() public {
        vault.deposit(10_000e6);

        vm.prank(alice);
        uint256 id = vault.openLong(500, 100e6, Vault.Rolling.No);

        // Price is still at tick 0, position is centered on 0 with range 500
        // So range is [-500, 500], tick 0 is inside

        vm.warp(block.timestamp + 1 hours);

        vm.prank(bob);
        vm.expectRevert(Vault.NotLiquidatable.selector);
        vault.liquidate(id);
    }

    function test_RevertWhen_Liquidate_NotActive() public {
        vault.deposit(10_000e6);

        vm.prank(alice);
        uint256 id = vault.openLong(500, 100e6, Vault.Rolling.No);

        vm.warp(block.timestamp + 1 hours);

        // Close it first
        vm.prank(alice);
        vault.close(id);

        vm.prank(bob);
        vm.expectRevert(Vault.PositionNotActive.selector);
        vault.liquidate(id);
    }

    // ---- Status ----

    function test_Status_ActivePosition() public {
        vault.deposit(10_000e6);

        vm.prank(alice);
        uint256 id = vault.openLong(500, 100e6, Vault.Rolling.No);

        (uint256 col,,,,, bool active) = vault.status(id);

        assertTrue(active);
        assertEq(col, 100e6);
    }

    function test_Status_ClosedPosition() public {
        vault.deposit(10_000e6);

        vm.prank(alice);
        uint256 id = vault.openLong(500, 100e6, Vault.Rolling.No);

        vm.warp(block.timestamp + 1 hours);

        vm.prank(alice);
        vault.close(id);

        (uint256 col, uint256 fee, uint256 il,,, bool active) = vault.status(id);

        assertFalse(active);
        assertEq(col, 100e6);
        assertEq(fee, 0);
        assertEq(il, 0);
    }

    // ---- setFees ----

    function test_SetFees_AsOwner() public {
        vault.setFees(500, 100, 20e12);
        assertEq(vault.feeVaultPercentE2(), 500);
        assertEq(vault.feeProtocolPercentE2(), 100);
        assertEq(vault.bountyLiquidatorE18(), 20e12);
    }

    function test_RevertWhen_SetFees_NotOwner() public {
        vm.prank(alice);
        vm.expectRevert("Ownable: caller is not the owner");
        vault.setFees(500, 100, 20e12);
    }

    // ---- estimateLong / estimateShort ----

    function test_EstimateLong_ReturnsValues() public {
        vault.deposit(10_000e6);

        (int24 lower, int24 upper,,, uint256 leverage, uint256 position) = vault.estimateLong(500, 100e6);

        assertLt(lower, upper);
        assertGt(leverage, 0);
        assertGt(position, 0);
    }

    function test_EstimateShort_ReturnsValues() public {
        vault.deposit(10_000e6);

        (int24 lower, int24 upper,,, uint256 leverage, uint256 position) = vault.estimateShort(500, 100e6);

        assertLt(lower, upper);
        assertGt(leverage, 0);
        assertGt(position, 0);
    }

    // ---- FreezBalance tracking ----

    function test_FreezBalance_IncreasesOnOpen() public {
        vault.deposit(10_000e6);

        uint256 freezBefore = vault.freezBalance();
        vm.prank(alice);
        vault.openLong(500, 100e6, Vault.Rolling.No);
        uint256 freezAfter = vault.freezBalance();

        assertEq(freezAfter - freezBefore, 100e6);
    }

    function test_FreezBalance_DecreasesOnClose() public {
        vault.deposit(10_000e6);

        vm.prank(alice);
        uint256 id = vault.openLong(500, 100e6, Vault.Rolling.No);

        uint256 freezBefore = vault.freezBalance();

        vm.warp(block.timestamp + 1 hours);

        vm.prank(alice);
        vault.close(id);

        uint256 freezAfter = vault.freezBalance();
        assertEq(freezBefore - freezAfter, 100e6);
    }

    // ---- currentTick ----

    function test_CurrentTick_FallbackToSlot0() public view {
        // Seq: startedAt = 0 => Chainlink path not taken
        int24 tick = vault.currentTick();
        assertEq(tick, 0);
    }

    // ---- Access control ----

    function test_OwnerIsManager_MsgSender() public view {
        // newVault passes msg.sender as owner
        assertEq(vault.owner(), owner);
    }
}
