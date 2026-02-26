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
        nfpm.setOwner(anchorId, owner);

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

    function test_Init_NextPosIdStartsAtOne() public view {
        // init() explicitly sets nextPosId = 1 for proxy storage consistency
        assertEq(vault.nextPosId(), 1);
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

    function test_Deposit_FirstDepositor() public {
        vm.prank(alice);
        uint256 shares = vault.deposit(1000e6);
        uint256 expectedShares = 1000e6 - 1000; // DEAD_SHARES locked
        assertEq(shares, expectedShares);
        assertEq(vault.balanceOf(alice), expectedShares);
        assertEq(vault.totalSupply(), 1000e6); // includes dead shares at address(1)
    }

    function test_Deposit_TransfersTokens() public {
        uint256 balBefore = collateral.balanceOf(alice);
        vm.prank(alice);
        vault.deposit(1000e6);
        uint256 balAfter = collateral.balanceOf(alice);
        assertEq(balBefore - balAfter, 1000e6);
    }

    function test_Deposit_EmitsEvent() public {
        uint256 expectedShares = 1000e6 - 1000;
        vm.prank(alice);
        vm.expectEmit(true, false, false, true);
        emit Vault.Deposit(alice, 1000e6, expectedShares);
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

        uint256 aliceShares = vault.balanceOf(alice);
        uint256 balBefore = collateral.balanceOf(alice);
        vm.prank(alice);
        uint256 amount = vault.withdraw(aliceShares);
        uint256 balAfter = collateral.balanceOf(alice);

        assertEq(amount, aliceShares);
        assertEq(balAfter - balBefore, aliceShares);
        assertEq(vault.balanceOf(alice), 0);
    }

    function test_Withdraw_PartialAmount() public {
        vm.prank(alice);
        vault.deposit(1000e6);

        uint256 aliceShares = vault.balanceOf(alice);
        uint256 halfShares = aliceShares / 2;

        vm.prank(alice);
        uint256 amount = vault.withdraw(halfShares);
        assertEq(amount, halfShares);
        assertEq(vault.balanceOf(alice), aliceShares - halfShares);
    }

    function test_Withdraw_EmitsEvent() public {
        vm.prank(alice);
        vault.deposit(1000e6);

        uint256 aliceShares = vault.balanceOf(alice);
        vm.prank(alice);
        vm.expectEmit(true, false, false, true);
        emit Vault.Withdraw(alice, aliceShares, aliceShares);
        vault.withdraw(aliceShares);
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
        assertEq(id, 1);
        assertEq(vault.nextPosId(), 2);

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
        assertEq(id, 1);

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

        assertEq(id1, 1);
        assertEq(id2, 2);
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

    function test_RevertWhen_SetFees_TooHigh() public {
        vm.expectRevert(Vault.FeeTooHigh.selector);
        vault.setFees(1500, 600, 20e12); // 2100 > 2000
    }

    function test_RevertWhen_SetFees_BountyTooHigh() public {
        vm.expectRevert(Vault.BountyTooHigh.selector);
        vault.setFees(500, 100, 2e18); // > 1e18
    }

    function test_SetFees_AtMaximum() public {
        vault.setFees(1000, 1000, 1e18); // exactly at cap
        assertEq(vault.feeVaultPercentE2(), 1000);
        assertEq(vault.feeProtocolPercentE2(), 1000);
        assertEq(vault.bountyLiquidatorE18(), 1e18);
    }

    // ---- Range bounds ----

    function test_RevertWhen_Open_RangeTooSmall() public {
        vault.deposit(10_000e6);

        vm.prank(alice);
        vm.expectRevert(Vault.RangeTooSmall.selector);
        vault.openLong(59, 100e6, Vault.Rolling.No);
    }

    function test_RevertWhen_Open_RangeTooLarge() public {
        vault.deposit(10_000e6);

        vm.prank(alice);
        vm.expectRevert(Vault.RangeTooLarge.selector);
        vault.openLong(100_001, 100e6, Vault.Rolling.No);
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

    // ---- Pausable ----

    function test_Pause_ByOwner() public {
        vault.pause();
        assertTrue(vault.paused());
    }

    function test_Pause_ByGuardian() public {
        vault.setGuardian(alice);
        vm.prank(alice);
        vault.pause();
        assertTrue(vault.paused());
    }

    function test_RevertWhen_Pause_NotGuardianOrOwner() public {
        vm.prank(bob);
        vm.expectRevert(Vault.NotGuardian.selector);
        vault.pause();
    }

    function test_Unpause_OnlyOwner() public {
        vault.pause();
        vault.unpause();
        assertFalse(vault.paused());
    }

    function test_RevertWhen_Unpause_NotOwner() public {
        vault.pause();
        vm.prank(alice);
        vm.expectRevert("Ownable: caller is not the owner");
        vault.unpause();
    }

    function test_RevertWhen_Deposit_WhenPaused() public {
        vault.pause();
        vm.prank(alice);
        vm.expectRevert("Pausable: paused");
        vault.deposit(1000e6);
    }

    function test_RevertWhen_OpenLong_WhenPaused() public {
        vault.deposit(10_000e6);
        vault.pause();
        vm.prank(alice);
        vm.expectRevert("Pausable: paused");
        vault.openLong(500, 100e6, Vault.Rolling.No);
    }

    function test_RevertWhen_OpenShort_WhenPaused() public {
        vault.deposit(10_000e6);
        vault.pause();
        vm.prank(alice);
        vm.expectRevert("Pausable: paused");
        vault.openShort(500, 100e6, Vault.Rolling.No);
    }

    function test_Close_WorksWhenPaused() public {
        vault.deposit(10_000e6);
        vm.prank(alice);
        uint256 id = vault.openLong(500, 100e6, Vault.Rolling.No);
        vm.warp(block.timestamp + 1 hours);

        vault.pause();

        // Close should still work when paused (users must be able to exit)
        vm.prank(alice);
        vault.close(id);
        (,,,,,,, bool active,) = vault.positions(id);
        assertFalse(active);
    }

    function test_Withdraw_WorksWhenPaused() public {
        vm.prank(alice);
        vault.deposit(1000e6);

        vault.pause();

        // Withdraw should still work when paused
        uint256 aliceShares = vault.balanceOf(alice);
        vm.prank(alice);
        vault.withdraw(aliceShares);
        assertEq(vault.balanceOf(alice), 0);
    }

    // ---- Guardian ----

    function test_SetGuardian() public {
        vault.setGuardian(alice);
        assertEq(vault.guardian(), alice);
    }

    function test_RevertWhen_SetGuardian_NotOwner() public {
        vm.prank(alice);
        vm.expectRevert("Ownable: caller is not the owner");
        vault.setGuardian(bob);
    }

    // ---- NextPosId ----

    function test_Init_NextPosIdIsOne() public view {
        assertEq(vault.nextPosId(), 1);
    }

    // ---- Range at boundaries ----

    function test_Open_AtMinRange() public {
        vault.deposit(10_000e6);
        vm.prank(alice);
        uint256 id = vault.openLong(60, 100e6, Vault.Rolling.No); // exactly at MIN_RANGE
        assertGt(id, 0);
    }

    // ---- Invariant: freezBalance matches active positions ----

    function test_FreezBalance_MatchesActivePositions() public {
        vault.deposit(50_000e6);

        vm.prank(alice);
        vault.openLong(500, 100e6, Vault.Rolling.No);
        vm.prank(bob);
        vault.openShort(300, 200e6, Vault.Rolling.No);

        assertEq(vault.freezBalance(), 300e6);

        vm.warp(block.timestamp + 1 hours);

        vm.prank(alice);
        vault.close(1);

        assertEq(vault.freezBalance(), 200e6);
    }

    // ---- Invariant: effective liquidity tracking ----

    function test_EffLiquidity_ZeroAfterAllClosed() public {
        vault.deposit(50_000e6);

        vm.prank(alice);
        vault.openLong(500, 100e6, Vault.Rolling.No);
        vm.prank(bob);
        vault.openShort(300, 200e6, Vault.Rolling.No);

        assertGt(vault.totalEffLong(), 0);
        assertGt(vault.totalEffShort(), 0);

        vm.warp(block.timestamp + 1 hours);

        vm.prank(alice);
        vault.close(1);
        vm.prank(bob);
        vault.close(2);

        assertEq(vault.totalEffLong(), 0);
        assertEq(vault.totalEffShort(), 0);
    }

    // ---- Second depositor share pricing ----

    function test_Deposit_SecondDepositorSharePricing() public {
        vm.prank(alice);
        vault.deposit(1000e6);

        uint256 totalSupplyAfterFirst = vault.totalSupply();
        assertEq(totalSupplyAfterFirst, 1000e6); // includes dead shares

        vm.prank(bob);
        uint256 bobShares = vault.deposit(2000e6);

        // shares = 2000e6 * 1000e6 / 1000e6 = 2000e6
        assertEq(bobShares, 2000e6);
    }

    // ---- Oracle: Chainlink / Fallback ----

    /// @dev Helper: warp to a reasonable timestamp and configure sequencer UP
    function _setSequencerUp() internal {
        vm.warp(100_000);
        // status=0 => UP, startedAt > 1 hour ago (past grace period)
        seq.setLatestRoundData(1, 0, block.timestamp - 2 hours, block.timestamp - 2 hours, 1);
    }

    /// @dev Helper: configure a valid Chainlink price feed answer
    function _setFeedPrice(int256 answer) internal {
        // roundId=1, answeredInRound=1, updatedAt=recent (fresh)
        feed.setLatestRoundData(1, answer, block.timestamp - 60, block.timestamp - 60, 1);
    }

    function test_Oracle_ChainlinkHappyPath() public {
        // Set slot0 to tick=0 (price=1.0)
        uint160 sqrtPTick0 = TickMath.getSqrtRatioAtTick(0);
        pool.setSlot0(sqrtPTick0, 0);

        // Configure Chainlink: sequencer UP, feed=2e8 (price $2.00, 8 decimals)
        // With d0==d1==6, priceE18=2e18, this maps to a positive tick (~6931)
        _setSequencerUp();
        _setFeedPrice(2e8);

        int24 tick = vault.currentTick();
        // If Chainlink is used, tick should NOT be 0 (the slot0 value)
        assertTrue(tick != 0, "Should use Chainlink, not slot0");
        // priceE18=2e18 → tick ~6931 (ln(2)/ln(1.0001))
        assertGt(tick, 6900);
        assertLt(tick, 6970);
    }

    function test_Oracle_SequencerDown_FallsBackToSlot0() public {
        vm.warp(100_000);

        // Set slot0 to tick=500
        uint160 sqrtP500 = TickMath.getSqrtRatioAtTick(500);
        pool.setSlot0(sqrtP500, 500);

        // Sequencer DOWN (status=1) — even with valid feed, should fallback
        seq.setLatestRoundData(1, 1, block.timestamp - 2 hours, block.timestamp - 2 hours, 1);
        _setFeedPrice(2e8);

        int24 tick = vault.currentTick();
        assertEq(tick, 500, "Should fallback to slot0 when sequencer is down");
    }

    function test_Oracle_SequencerGracePeriod_FallsBackToSlot0() public {
        vm.warp(100_000);

        // Set slot0 to tick=500
        uint160 sqrtP500 = TickMath.getSqrtRatioAtTick(500);
        pool.setSlot0(sqrtP500, 500);

        // Sequencer UP but just restarted 30 min ago (< 1 hour grace)
        seq.setLatestRoundData(1, 0, block.timestamp - 30 minutes, block.timestamp - 30 minutes, 1);
        _setFeedPrice(2e8);

        int24 tick = vault.currentTick();
        assertEq(tick, 500, "Should fallback during sequencer grace period");
    }

    function test_Oracle_StaleData_FallsBackToSlot0() public {
        // Sequencer UP and healthy
        _setSequencerUp();

        // Set slot0 to tick=500
        uint160 sqrtP500 = TickMath.getSqrtRatioAtTick(500);
        pool.setSlot0(sqrtP500, 500);

        // Feed data is stale: updatedAt = 2 hours ago (> STALENESS_THRESHOLD of 3600s)
        feed.setLatestRoundData(1, 2e8, block.timestamp - 2 hours, block.timestamp - 2 hours, 1);

        int24 tick = vault.currentTick();
        assertEq(tick, 500, "Should fallback when feed data is stale");
    }

    function test_Oracle_NegativeAnswer_FallsBackToSlot0() public {
        _setSequencerUp();

        // Set slot0 to tick=500
        uint160 sqrtP500 = TickMath.getSqrtRatioAtTick(500);
        pool.setSlot0(sqrtP500, 500);

        // Feed returns negative answer
        feed.setLatestRoundData(1, -1, block.timestamp - 60, block.timestamp - 60, 1);

        int24 tick = vault.currentTick();
        assertEq(tick, 500, "Should fallback when feed answer is negative");
    }
}

/// @dev Separate test contract using 18-decimal collateral (WETH-like)
contract VaultTest18Dec is Test {
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
    uint256 anchorId = 1;

    function setUp() public {
        collateral = new MockERC20("WETH", "WETH", 18);
        pool = new MockUniswapV3Pool();
        nfpm = new MockNFPM();
        vaultMath = new VaultMath();

        uint160 sqrtP = TickMath.getSqrtRatioAtTick(0);
        pool.setSlot0(sqrtP, 0);

        nfpm.setPosition(anchorId, address(collateral), address(collateral), -1000, 1000, 1e18, 0, 0, 0, 0);
        nfpm.setOwner(anchorId, owner);

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

        collateral.mint(alice, 100_000e18);
        collateral.mint(owner, 100_000e18);

        vm.prank(alice);
        collateral.approve(address(vault), type(uint256).max);
        collateral.approve(address(vault), type(uint256).max);
    }

    function test_18Dec_DeadSharesScaled() public {
        vm.prank(alice);
        uint256 shares = vault.deposit(10e18);

        // deadShares = 10^18 / 1000 = 1e15
        uint256 expectedShares = 10e18 - 1e15;
        assertEq(shares, expectedShares, "Dead shares should be 1e15 for 18-decimal token");
        assertEq(vault.totalSupply(), 10e18, "Total supply includes dead shares");
    }

    function test_18Dec_DepositWithdrawRoundTrip() public {
        vm.prank(alice);
        uint256 shares = vault.deposit(5e18);

        vm.prank(alice);
        uint256 withdrawn = vault.withdraw(shares);

        // Should get back deposit minus dead shares (1e15 locked)
        assertEq(withdrawn, 5e18 - 1e15, "Withdraw should return deposit minus dead shares");
    }

    function test_18Dec_OpenLongPosition() public {
        vm.prank(alice);
        vault.deposit(10e18);

        vm.prank(alice);
        uint256 id = vault.openLong(200, 1e18, Vault.Rolling.No);

        (address posOwner,, uint256 posCollateral,,,,, bool active,) = vault.positions(id);
        assertEq(posOwner, alice);
        assertEq(posCollateral, 1e18);
        assertTrue(active);
        assertEq(vault.freezBalance(), 1e18);
    }
}
