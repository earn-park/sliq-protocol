// SPDX-License-Identifier: NO
pragma solidity ^0.8.30;

import "@uniswap/v3-periphery/contracts/interfaces/INonfungiblePositionManager.sol";
import "@uniswap/v3-core/contracts/interfaces/IUniswapV3Pool.sol";

/// @title IVaultMath
/// @notice Interface for the sLiq math library
interface IVaultMath {
    function calcFees(
        INonfungiblePositionManager nfpm,
        IUniswapV3Pool pool,
        uint256 anchorId,
        int24 tickCurrent,
        int24 tickLower,
        int24 tickUpper
    ) external view returns (uint256 fee0, uint256 fee1);

    function toE18(address token, uint256 amt) external view returns (uint256);
    function fromE18(address token, uint256 wadAmt) external view returns (uint256);

    function sqrtpx96ToPriceE18(uint160 sqrtPX96, address token0, address token1)
        external
        view
        returns (uint256 priceE18);
    function tickToPriceE18(int24 tick, address token0, address token1) external view returns (uint256 priceE18);
    function priceE18ToTick(uint256 priceE18, address token0, address token1) external view returns (int24 tick);

    function sumTok0Tok1In0(uint256 token0Raw, uint256 token1Raw, uint160 sqrtPX96, address token0, address token1)
        external
        view
        returns (uint256);

    function _ilPercentE18(int24 range) external pure returns (uint256 ilE18);
    function _effLiquidity(uint256 collateral, int24 range, int24 anchorRange) external pure returns (uint256 eff);
    function tickDiffPercentE18(int24 dt) external pure returns (uint256 percentE18);

    function decimals(address t) external view returns (uint8);
    function triangularNumber(uint256 n) external pure returns (uint256);
}
