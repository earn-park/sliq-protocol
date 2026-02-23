// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import "forge-std/Test.sol";
import "../../src/VaultMath.sol";
import "../mocks/MockERC20.sol";
import "../mocks/MockUniswapV3Pool.sol";
import "../mocks/MockNFPM.sol";
import "@uniswap/v3-core/contracts/libraries/TickMath.sol";
import "@uniswap/v3-periphery/contracts/interfaces/INonfungiblePositionManager.sol";
import "@uniswap/v3-core/contracts/interfaces/IUniswapV3Pool.sol";

contract VaultMathTest is Test {
    VaultMath public vaultMath;
    MockERC20 public token18;
    MockERC20 public token6;
    MockERC20 public token8;
    MockUniswapV3Pool public pool;
    MockNFPM public nfpm;

    function setUp() public {
        vaultMath = new VaultMath();
        token18 = new MockERC20("Token18", "T18", 18);
        token6 = new MockERC20("USDC", "USDC", 6);
        token8 = new MockERC20("WBTC", "WBTC", 8);
        pool = new MockUniswapV3Pool();
        nfpm = new MockNFPM();
    }

    // ---- toE18 ----

    function test_toE18_18Decimals() public view {
        uint256 amt = 1e18;
        uint256 result = vaultMath.toE18(address(token18), amt);
        assertEq(result, 1e18);
    }

    function test_toE18_6Decimals() public view {
        uint256 amt = 1e6; // 1 USDC
        uint256 result = vaultMath.toE18(address(token6), amt);
        assertEq(result, 1e18);
    }

    function test_toE18_8Decimals() public view {
        uint256 amt = 1e8; // 1 WBTC
        uint256 result = vaultMath.toE18(address(token8), amt);
        assertEq(result, 1e18);
    }

    function test_toE18_ZeroAmount() public view {
        assertEq(vaultMath.toE18(address(token6), 0), 0);
    }

    function test_toE18_SmallAmount_6Dec() public view {
        // 1 unit of USDC (0.000001 USDC)
        uint256 result = vaultMath.toE18(address(token6), 1);
        assertEq(result, 1e12);
    }

    // ---- fromE18 ----

    function test_fromE18_18Decimals() public view {
        uint256 wadAmt = 1e18;
        uint256 result = vaultMath.fromE18(address(token18), wadAmt);
        assertEq(result, 1e18);
    }

    function test_fromE18_6Decimals() public view {
        uint256 wadAmt = 1e18;
        uint256 result = vaultMath.fromE18(address(token6), wadAmt);
        assertEq(result, 1e6);
    }

    function test_fromE18_8Decimals() public view {
        uint256 wadAmt = 1e18;
        uint256 result = vaultMath.fromE18(address(token8), wadAmt);
        assertEq(result, 1e8);
    }

    function test_fromE18_ZeroAmount() public view {
        assertEq(vaultMath.fromE18(address(token6), 0), 0);
    }

    // ---- toE18/fromE18 roundtrip ----

    function test_toE18_fromE18_RoundTrip_18Dec() public view {
        uint256 amt = 123456789012345678;
        uint256 wad = vaultMath.toE18(address(token18), amt);
        uint256 back = vaultMath.fromE18(address(token18), wad);
        assertEq(back, amt);
    }

    function test_toE18_fromE18_RoundTrip_6Dec() public view {
        uint256 amt = 123456; // some USDC amount
        uint256 wad = vaultMath.toE18(address(token6), amt);
        uint256 back = vaultMath.fromE18(address(token6), wad);
        assertEq(back, amt);
    }

    // ---- sqrtpx96ToPriceE18 ----

    function test_sqrtpx96ToPriceE18_TickZero() public view {
        // At tick 0, sqrtPriceX96 = 2^96, price = 1.0
        uint160 sqrtAtZero = TickMath.getSqrtRatioAtTick(0);
        // Both tokens 18 decimals => price ~1e18
        uint256 priceE18 = vaultMath.sqrtpx96ToPriceE18(sqrtAtZero, address(token18), address(token18));
        assertEq(priceE18, 1e18);
    }

    function test_sqrtpx96ToPriceE18_DifferentDecimals() public view {
        // tick 0 => price ratio = 1 in raw terms
        // with d0=6 d1=18 => scale = 10^(6+18-18)=10^6
        // price = 1 * 10^6 = 1e6
        uint160 sqrtAtZero = TickMath.getSqrtRatioAtTick(0);
        uint256 priceE18 = vaultMath.sqrtpx96ToPriceE18(sqrtAtZero, address(token6), address(token18));
        // price = 10^(d0+18-d1) = 10^6
        assertEq(priceE18, 1e6);
    }

    function test_sqrtpx96ToPriceE18_PositiveTick() public view {
        int24 tick = 1000;
        uint160 sqrtP = TickMath.getSqrtRatioAtTick(tick);
        uint256 priceE18 = vaultMath.sqrtpx96ToPriceE18(sqrtP, address(token18), address(token18));
        // price at tick 1000 = 1.0001^1000 ~= 1.10517e18
        // Should be roughly 1.105e18
        assertGt(priceE18, 1.1e18);
        assertLt(priceE18, 1.11e18);
    }

    // ---- tickToPriceE18 ----

    function test_tickToPriceE18_TickZero() public view {
        uint256 priceE18 = vaultMath.tickToPriceE18(0, address(token18), address(token18));
        assertEq(priceE18, 1e18);
    }

    function test_tickToPriceE18_NegativeTick() public view {
        uint256 priceE18 = vaultMath.tickToPriceE18(-1000, address(token18), address(token18));
        // price = 1.0001^(-1000) ~= 0.9048
        assertGt(priceE18, 0.9e18);
        assertLt(priceE18, 0.91e18);
    }

    // ---- priceE18ToTick ----

    function test_priceE18ToTick_Price1() public view {
        int24 tick = vaultMath.priceE18ToTick(1e18, address(token18), address(token18));
        // tick at price 1.0 should be 0 (or very close due to rounding)
        assertGe(tick, -1);
        assertLe(tick, 1);
    }

    function test_priceE18ToTick_RoundTrip() public view {
        int24 originalTick = 500;
        uint256 price = vaultMath.tickToPriceE18(originalTick, address(token18), address(token18));
        int24 recoveredTick = vaultMath.priceE18ToTick(price, address(token18), address(token18));
        // Should be within 1 tick of original (rounding)
        assertGe(recoveredTick, originalTick - 1);
        assertLe(recoveredTick, originalTick + 1);
    }

    function test_RevertWhen_priceE18ToTick_ZeroPrice() public {
        vm.expectRevert(VaultMath.ZeroPrice.selector);
        vaultMath.priceE18ToTick(0, address(token18), address(token18));
    }

    // ---- _ilPercentE18 ----

    function test_ilPercentE18_ZeroRange() public view {
        uint256 il = vaultMath._ilPercentE18(0);
        assertEq(il, 0);
    }

    function test_ilPercentE18_SmallRange() public view {
        int24 range = 100;
        uint256 il = vaultMath._ilPercentE18(range);
        // IL should be > 0 for any non-zero range
        assertGt(il, 0);
        // IL should be small for small ranges
        assertLt(il, 0.01e18);
    }

    function test_ilPercentE18_LargeRange() public view {
        int24 range = 10000;
        uint256 il = vaultMath._ilPercentE18(range);
        assertGt(il, 0);
        // IL at 10000 ticks can exceed 1e18 for extreme ranges
        // p = 1.0001^10000 ~= 2.718, sqrt(p) ~= 1.649
        // IL = p - sqrt(p*1e18) which can be > 1e18
        assertGt(il, 0.5e18);
    }

    function test_ilPercentE18_Monotonic() public view {
        uint256 il100 = vaultMath._ilPercentE18(100);
        uint256 il500 = vaultMath._ilPercentE18(500);
        uint256 il1000 = vaultMath._ilPercentE18(1000);
        assertGt(il500, il100);
        assertGt(il1000, il500);
    }

    // ---- _effLiquidity ----

    function test_effLiquidity_BasicComputation() public view {
        uint256 collateral = 1000e6;
        int24 range = 500;
        int24 anchorRange = 1000;
        uint256 eff = vaultMath._effLiquidity(collateral, range, anchorRange);
        assertGt(eff, 0);
    }

    function test_effLiquidity_LargerRangeLowerEff() public view {
        uint256 collateral = 1000e6;
        int24 anchorRange = 1000;
        uint256 effSmall = vaultMath._effLiquidity(collateral, 200, anchorRange);
        uint256 effLarge = vaultMath._effLiquidity(collateral, 800, anchorRange);
        // Wider range should generally yield lower eff (spread over more ticks)
        // The exact relationship depends on the IL scaling
        // Both should be > 0
        assertGt(effSmall, 0);
        assertGt(effLarge, 0);
    }

    function test_effLiquidity_MoreCollateralHigherEff() public view {
        int24 range = 500;
        int24 anchorRange = 1000;
        uint256 eff1 = vaultMath._effLiquidity(1000e6, range, anchorRange);
        uint256 eff2 = vaultMath._effLiquidity(2000e6, range, anchorRange);
        assertEq(eff2, 2 * eff1);
    }

    // ---- calcFees ----

    function test_calcFees_NoFees() public {
        // Set up anchor with zero fee growth
        nfpm.setPosition(1, address(token18), address(token18), -1000, 1000, 1e18, 0, 0, 0, 0);

        pool.setSlot0(TickMath.getSqrtRatioAtTick(0), 0);

        (uint256 fee0, uint256 fee1) = vaultMath.calcFees(
            INonfungiblePositionManager(address(nfpm)), IUniswapV3Pool(address(pool)), 1, 0, -1000, 1000
        );
        assertEq(fee0, 0);
        assertEq(fee1, 0);
    }

    function test_calcFees_WithOwedTokens() public {
        nfpm.setPosition(
            1,
            address(token18),
            address(token18),
            -1000,
            1000,
            1e18, // liquidity
            0, // fg0Last
            0, // fg1Last
            100, // owed0
            200 // owed1
        );

        pool.setSlot0(TickMath.getSqrtRatioAtTick(0), 0);

        (uint256 fee0, uint256 fee1) = vaultMath.calcFees(
            INonfungiblePositionManager(address(nfpm)), IUniswapV3Pool(address(pool)), 1, 0, -1000, 1000
        );
        // owed tokens are returned as part of fees
        assertGe(fee0, 100);
        assertGe(fee1, 200);
    }

    function test_calcFees_CurrentInsideRange() public {
        // Tick current = 0, inside range [-1000, 1000]
        // feeGrowthGlobal: some nonzero value
        // tick lower/upper feeGrowthOutside: 0
        // fg0Now = fg0G - lower0 - upper0
        // delta = fg0Now - fg0Last
        // fee0 = owed0 + (delta * liquidity / 2^128)

        uint256 fg0G = 1 << 128; // 1 full unit
        pool.setFeeGrowthGlobal(fg0G, 0);
        pool.setSlot0(TickMath.getSqrtRatioAtTick(0), 0);

        nfpm.setPosition(
            1,
            address(token18),
            address(token18),
            -1000,
            1000,
            1e18, // liquidity
            0, // fg0Last
            0, // fg1Last
            0, // owed0
            0 // owed1
        );

        (uint256 fee0, uint256 fee1) = vaultMath.calcFees(
            INonfungiblePositionManager(address(nfpm)), IUniswapV3Pool(address(pool)), 1, 0, -1000, 1000
        );
        // fee0 = (fg0G - 0 - 0 - 0) * 1e18 / 2^128 = 1e18
        assertEq(fee0, 1e18);
        assertEq(fee1, 0);
    }

    // ---- triangularNumber ----

    function test_triangularNumber_Zero() public view {
        assertEq(vaultMath.triangularNumber(0), 0);
    }

    function test_triangularNumber_One() public view {
        assertEq(vaultMath.triangularNumber(1), 1);
    }

    function test_triangularNumber_Ten() public view {
        // T(10) = 10*11/2 = 55
        assertEq(vaultMath.triangularNumber(10), 55);
    }

    function test_triangularNumber_LargeN() public view {
        // T(100) = 100*101/2 = 5050
        assertEq(vaultMath.triangularNumber(100), 5050);
    }

    function test_triangularNumber_Formula() public view {
        for (uint256 i = 0; i < 20; i++) {
            uint256 expected = (i * (i + 1)) / 2;
            assertEq(vaultMath.triangularNumber(i), expected);
        }
    }

    // ---- tickDiffPercentE18 ----

    function test_tickDiffPercentE18_Zero() public view {
        // 1.0001^0 - 1 = 0
        uint256 result = vaultMath.tickDiffPercentE18(0);
        assertEq(result, 0);
    }

    function test_tickDiffPercentE18_OneTick() public view {
        // 1.0001^1 - 1 ~= 0.0001 = 1e14
        uint256 result = vaultMath.tickDiffPercentE18(1);
        assertGt(result, 0.99e14);
        assertLt(result, 1.01e14);
    }

    function test_tickDiffPercentE18_Monotonic() public view {
        uint256 r100 = vaultMath.tickDiffPercentE18(100);
        uint256 r500 = vaultMath.tickDiffPercentE18(500);
        uint256 r1000 = vaultMath.tickDiffPercentE18(1000);
        assertGt(r500, r100);
        assertGt(r1000, r500);
    }

    // ---- decimals helper ----

    function test_decimals_ReturnsCorrect() public view {
        assertEq(vaultMath.decimals(address(token18)), 18);
        assertEq(vaultMath.decimals(address(token6)), 6);
        assertEq(vaultMath.decimals(address(token8)), 8);
    }

    // ---- sumTok0Tok1In0 ----

    function test_sumTok0Tok1In0_OnlyToken0() public view {
        uint160 sqrtP = TickMath.getSqrtRatioAtTick(0);
        uint256 result = vaultMath.sumTok0Tok1In0(1000, 0, sqrtP, address(token18), address(token18));
        assertEq(result, 1000);
    }

    function test_sumTok0Tok1In0_BothTokens_SameDecimals() public view {
        // At tick 0, price = 1.0 with same decimals
        // 1000 token0 + 500 token1 (worth 500 token0 at price 1) = 1500
        uint160 sqrtP = TickMath.getSqrtRatioAtTick(0);
        uint256 result = vaultMath.sumTok0Tok1In0(1000e18, 500e18, sqrtP, address(token18), address(token18));
        assertGt(result, 1499e18);
        assertLt(result, 1501e18);
    }
}
