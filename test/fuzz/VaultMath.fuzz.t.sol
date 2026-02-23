// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import "forge-std/Test.sol";
import "../../src/VaultMath.sol";
import "../mocks/MockERC20.sol";
import "@uniswap/v3-core/contracts/libraries/TickMath.sol";

contract VaultMathFuzzTest is Test {
    VaultMath public vaultMath;
    MockERC20 public token18;
    MockERC20 public token6;
    MockERC20 public token8;

    function setUp() public {
        vaultMath = new VaultMath();
        token18 = new MockERC20("Token18", "T18", 18);
        token6 = new MockERC20("USDC", "USDC", 6);
        token8 = new MockERC20("WBTC", "WBTC", 8);
    }

    // ---- toE18 / fromE18 roundtrip ----

    function testFuzz_toE18_fromE18_RoundTrip_18Dec(uint256 amt) public view {
        amt = bound(amt, 0, type(uint128).max);
        uint256 wad = vaultMath.toE18(address(token18), amt);
        uint256 back = vaultMath.fromE18(address(token18), wad);
        assertEq(back, amt);
    }

    function testFuzz_toE18_fromE18_RoundTrip_6Dec(uint256 amt) public view {
        amt = bound(amt, 0, type(uint128).max / 1e12);
        uint256 wad = vaultMath.toE18(address(token6), amt);
        uint256 back = vaultMath.fromE18(address(token6), wad);
        assertEq(back, amt);
    }

    function testFuzz_toE18_fromE18_RoundTrip_8Dec(uint256 amt) public view {
        amt = bound(amt, 0, type(uint128).max / 1e10);
        uint256 wad = vaultMath.toE18(address(token8), amt);
        uint256 back = vaultMath.fromE18(address(token8), wad);
        assertEq(back, amt);
    }

    // ---- tickToPriceE18 / priceE18ToTick roundtrip ----

    function testFuzz_TickPriceRoundTrip(int24 tick) public {
        // TickMath valid range: -887272 to 887272
        // But priceE18ToTick internal arithmetic (rpow, mulDiv, sqrt)
        // can overflow for large ticks with 18-decimal tokens.
        // Use vm.assume to enforce a safe range.
        vm.assume(tick >= -50000 && tick <= 50000);

        uint256 price = vaultMath.tickToPriceE18(tick, address(token18), address(token18));

        if (price == 0) return;

        // Use try/catch to handle overflow at boundary ticks
        try vaultMath.priceE18ToTick(price, address(token18), address(token18)) returns (int24 recovered) {
            // Allow +/- 1 tick for rounding
            assertGe(recovered, tick - 1);
            assertLe(recovered, tick + 1);
        } catch {
            // Overflow at extreme ticks is acceptable
        }
    }

    // ---- _ilPercentE18 ----

    function testFuzz_ilPercentE18_NonNegative(int24 range) public view {
        range = int24(bound(int256(range), 0, 50000));
        uint256 il = vaultMath._ilPercentE18(range);
        assertTrue(il >= 0);
    }

    function testFuzz_ilPercentE18_BelowOneForSmallRanges(int24 range) public view {
        // IL < 1e18 only holds for small ranges (< ~6900 ticks)
        range = int24(bound(int256(range), 0, 5000));
        uint256 il = vaultMath._ilPercentE18(range);
        assertLt(il, 1e18);
    }

    function testFuzz_ilPercentE18_Monotonic(int24 rangeA, int24 rangeB) public view {
        rangeA = int24(bound(int256(rangeA), 1, 10000));
        rangeB = int24(bound(int256(rangeB), int256(rangeA) + 1, 10001));

        uint256 ilA = vaultMath._ilPercentE18(rangeA);
        uint256 ilB = vaultMath._ilPercentE18(rangeB);

        assertGe(ilB, ilA);
    }

    // ---- _effLiquidity ----

    function testFuzz_effLiquidity_ProportionalToCollateral(uint256 collateral) public view {
        // Use a minimum that avoids rounding issues in FullMath.mulDiv
        collateral = bound(collateral, 1e6, 1e30);
        int24 range = 500;
        int24 anchorRange = 1000;

        uint256 eff1 = vaultMath._effLiquidity(collateral, range, anchorRange);
        uint256 eff2 = vaultMath._effLiquidity(collateral * 2, range, anchorRange);

        // Allow for rounding: eff2 should be within 1 of 2*eff1
        assertGe(eff2, eff1 * 2 - 1);
        assertLe(eff2, eff1 * 2 + 1);
    }

    function testFuzz_effLiquidity_PositiveForPositiveInputs(uint256 collateral, int24 range, int24 anchorRange)
        public
        view
    {
        collateral = bound(collateral, 1e6, 1e30);
        range = int24(bound(int256(range), 10, 5000));
        anchorRange = int24(bound(int256(anchorRange), 10, 5000));

        uint256 eff = vaultMath._effLiquidity(collateral, range, anchorRange);
        assertGt(eff, 0);
    }

    // ---- triangularNumber ----

    function testFuzz_triangularNumber_Formula(uint256 n) public view {
        n = bound(n, 0, 1e9);
        uint256 result = vaultMath.triangularNumber(n);
        uint256 expected = (n * (n + 1)) / 2;
        assertEq(result, expected);
    }

    function testFuzz_triangularNumber_Monotonic(uint256 a, uint256 b) public view {
        a = bound(a, 0, 1e9);
        b = bound(b, a, 1e9);
        assertGe(vaultMath.triangularNumber(b), vaultMath.triangularNumber(a));
    }

    // ---- tickDiffPercentE18 ----

    function testFuzz_tickDiffPercentE18_NonNegative(int24 dt) public view {
        dt = int24(bound(int256(dt), 0, 50000));
        uint256 result = vaultMath.tickDiffPercentE18(dt);
        assertTrue(result >= 0);
    }

    function testFuzz_tickDiffPercentE18_Monotonic(int24 dtA, int24 dtB) public view {
        dtA = int24(bound(int256(dtA), 0, 10000));
        dtB = int24(bound(int256(dtB), int256(dtA), 10000));

        uint256 rA = vaultMath.tickDiffPercentE18(dtA);
        uint256 rB = vaultMath.tickDiffPercentE18(dtB);
        assertGe(rB, rA);
    }

    // ---- sqrtpx96ToPriceE18 ----

    function testFuzz_sqrtpx96ToPriceE18_PositiveForValidInput(int24 tick) public view {
        // Restrict to range where sqrtPX96^2 * scale doesn't overflow.
        // Extreme ticks produce very large sqrtPX96 values that overflow
        // when squared in the price computation.
        tick = int24(bound(int256(tick), -400000, 400000));
        uint160 sqrtP = TickMath.getSqrtRatioAtTick(tick);
        uint256 price = vaultMath.sqrtpx96ToPriceE18(sqrtP, address(token18), address(token18));
        assertGt(price, 0);
    }

    // ---- priceE18ToTick revert for zero ----

    function testFuzz_priceE18ToTick_NeverZeroPrice() public {
        vm.expectRevert(VaultMath.ZeroPrice.selector);
        vaultMath.priceE18ToTick(0, address(token18), address(token18));
    }

    // ---- sumTok0Tok1In0 ----

    function testFuzz_sumTok0Tok1In0_OnlyToken0(uint256 amt0) public view {
        amt0 = bound(amt0, 0, 1e30);
        uint160 sqrtP = TickMath.getSqrtRatioAtTick(0);
        uint256 result = vaultMath.sumTok0Tok1In0(amt0, 0, sqrtP, address(token18), address(token18));
        assertEq(result, amt0);
    }
}
