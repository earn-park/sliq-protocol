// SPDX-License-Identifier: NO
pragma solidity ^0.8.30;

import "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";

import "@uniswap/v3-core/contracts/libraries/FullMath.sol";
import "@uniswap/v3-periphery/contracts/interfaces/INonfungiblePositionManager.sol";
import "@uniswap/v3-core/contracts/interfaces/IUniswapV3Pool.sol";
import "@uniswap/v3-core/contracts/libraries/TickMath.sol";

import { FixedPointMathLib as FPM } from "solmate/utils/FixedPointMathLib.sol";

/// @title VaultMath
/// @author sLiq Protocol
/// @notice Math library for the sLiq Synthetic Concentrated-Liquidity Vault System
/// @dev Provides fee calculation, price conversion, IL estimation, and effective liquidity helpers
contract VaultMath {
    /* ~~~~ Custom Errors ~~~~ */
    error ZeroPrice();
    error SqrtOverflow();

    /// @notice Calculate accrued fees for a Uniswap V3 position
    /// @param nfpm The Nonfungible Position Manager contract
    /// @param pool The Uniswap V3 pool contract
    /// @param anchorId The NFT token ID of the anchor position
    /// @param tickCurrent The current tick of the pool
    /// @param tickLower The lower tick bound of the position
    /// @param tickUpper The upper tick bound of the position
    /// @return fee0 Accumulated fee for token0
    /// @return fee1 Accumulated fee for token1
    function calcFees(
        INonfungiblePositionManager nfpm,
        IUniswapV3Pool pool,
        uint256 anchorId,
        int24 tickCurrent,
        int24 tickLower,
        int24 tickUpper
    ) public view returns (uint256 fee0, uint256 fee1) {
        (,,,,,,, uint128 liquidity, uint256 fg0Last, uint256 fg1Last, uint128 owed0, uint128 owed1) =
            nfpm.positions(anchorId);
        uint256 fg0G = pool.feeGrowthGlobal0X128(); // fee for token0, Q128.128
        uint256 fg1G = pool.feeGrowthGlobal1X128(); // fee for token1, Q128.128
        (,, uint256 lower0, uint256 lower1,,,,) = pool.ticks(tickLower);
        (,, uint256 upper0, uint256 upper1,,,,) = pool.ticks(tickUpper);
        uint256 fg0Now;
        uint256 fg1Now;
        if (tickCurrent < tickLower) {
            fg0Now = lower0 - upper0;
            fg1Now = lower1 - upper1;
        } else if (tickCurrent >= tickUpper) {
            fg0Now = upper0 - lower0;
            fg1Now = upper1 - lower1;
        } else {
            fg0Now = fg0G - lower0 - upper0;
            fg1Now = fg1G - lower1 - upper1;
        }
        // delta feeGrowthInside * L / 2^128
        uint256 add0 = FullMath.mulDiv(fg0Now - fg0Last, liquidity, 1 << 128);
        uint256 add1 = FullMath.mulDiv(fg1Now - fg1Last, liquidity, 1 << 128);

        fee0 = uint256(owed0) + add0;
        fee1 = uint256(owed1) + add1;
    }

    /// @notice Convert token-native amount to 1e18 (wad) format
    /// @param token The token address to read decimals from
    /// @param amt The amount in token-native units
    /// @return The amount scaled to 1e18
    function toE18(address token, uint256 amt) public view returns (uint256) {
        uint8 d = decimals(token);
        return d == 18 ? amt : d < 18 ? amt * 10 ** (18 - d) : amt / 10 ** (d - 18);
    }

    /// @notice Convert 1e18 (wad) amount back to token-native units
    /// @param token The token address to read decimals from
    /// @param wadAmt The amount in 1e18 format
    /// @return The amount in token-native units
    function fromE18(address token, uint256 wadAmt) public view returns (uint256) {
        uint8 d = decimals(token);
        return d == 18 ? wadAmt : d < 18 ? wadAmt / 10 ** (18 - d) : wadAmt * 10 ** (d - 18);
    }

    /// @notice Convert a sqrtPriceX96 value to a price in 1e18 format
    /// @param sqrtPX96 The sqrt price in Q64.96 format
    /// @param token0 Address of token0
    /// @param token1 Address of token1
    /// @return priceE18 The price scaled to 1e18
    function sqrtpx96ToPriceE18(uint160 sqrtPX96, address token0, address token1)
        public
        view
        returns (uint256 priceE18)
    {
        uint8 d0 = decimals(address(token0));
        uint8 d1 = decimals(address(token1));
        // sqrt(P) in Q64.96

        // (sqrt(P))^2 in Q128.192
        uint256 priceQ128x192 = uint256(sqrtPX96) * uint256(sqrtPX96);
        // scale by 10^(18 + d0 - d1)
        uint256 scale = 10 ** (uint256(d0) + 18 - uint256(d1));
        // perform exact multiplication and shift: priceE18 = (priceQ128x192 * scale) >> 192
        priceE18 = FullMath.mulDiv(priceQ128x192, scale, 1 << 192);
    }

    /// @notice Convert a tick to a price in 1e18 format
    /// @param tick The Uniswap V3 tick value
    /// @param token0 Address of token0
    /// @param token1 Address of token1
    /// @return priceE18 The price scaled to 1e18
    function tickToPriceE18(int24 tick, address token0, address token1) public view returns (uint256 priceE18) {
        // sqrt(P) in Q64.96
        uint160 sqrtPX96 = TickMath.getSqrtRatioAtTick(tick);
        priceE18 = sqrtpx96ToPriceE18(sqrtPX96, token0, token1);
    }

    /// @notice Convert a price in 1e18 format to a Uniswap V3 tick
    /// @param priceE18 The price scaled to 1e18
    /// @param token0 Address of token0
    /// @param token1 Address of token1
    /// @return tick The corresponding Uniswap V3 tick
    function priceE18ToTick(uint256 priceE18, address token0, address token1) public view returns (int24 tick) {
        if (priceE18 == 0) revert ZeroPrice();

        uint8 d0 = IERC20Metadata(token0).decimals();
        uint8 d1 = IERC20Metadata(token1).decimals();

        // ratioX192 = rawRatio * 2^192
        // rawRatio = (priceE18 / 1e18) * 10^(d1 - d0)
        uint256 ratioX192 = FullMath.mulDiv(priceE18, uint256(1) << 192, 1e18);

        if (d1 > d0) {
            uint256 scaleUp = FPM.rpow(10, uint256(d1 - d0), 1); // 10^(d1-d0)
            ratioX192 = FullMath.mulDiv(ratioX192, scaleUp, 1);
        } else if (d0 > d1) {
            uint256 scaleDown = FPM.rpow(10, uint256(d0 - d1), 1); // 10^(d0-d1)
            ratioX192 = FullMath.mulDiv(ratioX192, 1, scaleDown);
        }

        // sqrtPX96 = sqrt(ratioX192)
        uint256 sqrtU = FPM.sqrt(ratioX192);
        if (sqrtU > type(uint160).max) revert SqrtOverflow();

        tick = TickMath.getTickAtSqrtRatio(uint160(sqrtU));
    }

    /// @notice Sum token0 and token1 amounts, denominated in token0
    /// @param token0Raw Raw amount of token0
    /// @param token1Raw Raw amount of token1
    /// @param sqrtPX96 Current sqrt price in Q64.96
    /// @param token0 Address of token0
    /// @param token1 Address of token1
    /// @return The combined value in token0 units
    function sumTok0Tok1In0(uint256 token0Raw, uint256 token1Raw, uint160 sqrtPX96, address token0, address token1)
        public
        view
        returns (uint256)
    {
        uint256 token1E18 = toE18(token1, token1Raw);
        uint256 tok1InTok0E18 = FullMath.mulDiv(token1E18, 1e18, sqrtpx96ToPriceE18(sqrtPX96, token0, token1));
        uint256 tok1InTok0 = fromE18(token0, tok1InTok0E18);

        return token0Raw + tok1InTok0;
    }

    /// @notice Calculate the impermanent loss percentage (in 1e18) for a given tick range
    /// @param range Half the tick range width
    /// @return ilE18 The IL percentage scaled to 1e18
    function _ilPercentE18(int24 range) public pure returns (uint256 ilE18) {
        if (range == 0) return 0;

        uint256 absTicks = uint256(int256(range > 0 ? range : -range));
        // 1.0001 in 1e18 fixed: 1000100000000000000 => p = 1.0001^(ticks)
        uint256 pE18 = FPM.rpow(1000100000000000000, absTicks, 1e18);
        uint256 gE18 = FPM.sqrt(pE18 * 1e18);
        ilE18 = pE18 - gE18;
    }

    /// @notice Calculate effective liquidity for a position
    /// @param collateral The collateral amount
    /// @param range Half the tick range width of the position
    /// @param anchorRange Half the tick range width of the anchor
    /// @return eff The effective liquidity value
    function _effLiquidity(uint256 collateral, int24 range, int24 anchorRange) public pure returns (uint256 eff) {
        uint256 ilE18 = _ilPercentE18(range);
        // eff = 2*(collateral / il%) * (anchorRange / range)
        eff = FullMath.mulDiv(2 * collateral, uint256(int256(anchorRange)) * 1e18, (uint256(int256(range)) * ilE18));
    }

    /// @notice Calculate the price difference percentage for a given tick delta
    /// @param dt The tick delta
    /// @return percentE18 The price difference percentage scaled to 1e18
    function tickDiffPercentE18(int24 dt) public pure returns (uint256 percentE18) {
        uint256 p = FPM.rpow(
            1000100000000000000, // 1.0001 * 1e18
            uint256(int256(dt)),
            1e18
        ); // p = 1.0001^{|tick_delta|} * 1e18
        percentE18 = (p - 1e18);
    }

    /// @notice Get the decimals of an ERC20 token
    /// @param t The token address
    /// @return The number of decimals
    function decimals(address t) public view returns (uint8) {
        return IERC20Metadata(address(t)).decimals();
    }

    /// @notice Compute the triangular number n*(n+1)/2 without intermediate overflow
    /// @param n The input number
    /// @return The triangular number
    function triangularNumber(uint256 n) public pure returns (uint256) {
        // n*(n+1)/2 without overflow on intermediate multiplication
        return FullMath.mulDiv(n, n + 1, 2);
    }
}
