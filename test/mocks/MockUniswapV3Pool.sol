// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

contract MockUniswapV3Pool {
    uint160 public _sqrtPriceX96;
    int24 public _tick;
    uint256 public _feeGrowthGlobal0X128;
    uint256 public _feeGrowthGlobal1X128;

    struct TickData {
        uint128 liquidityGross;
        int128 liquidityNet;
        uint256 feeGrowthOutside0X128;
        uint256 feeGrowthOutside1X128;
        int56 tickCumulativeOutside;
        uint160 secondsPerLiquidityOutsideX128;
        uint32 secondsOutside;
        bool initialized;
    }

    mapping(int24 => TickData) public _ticks;

    function setSlot0(uint160 sqrtPriceX96_, int24 tick_) external {
        _sqrtPriceX96 = sqrtPriceX96_;
        _tick = tick_;
    }

    function setFeeGrowthGlobal(uint256 fg0, uint256 fg1) external {
        _feeGrowthGlobal0X128 = fg0;
        _feeGrowthGlobal1X128 = fg1;
    }

    function setTick(int24 tick_, uint128 liquidityGross_, int128 liquidityNet_, uint256 fgo0_, uint256 fgo1_)
        external
    {
        _ticks[tick_] = TickData(liquidityGross_, liquidityNet_, fgo0_, fgo1_, 0, 0, 0, true);
    }

    function slot0()
        external
        view
        returns (
            uint160 sqrtPriceX96,
            int24 tick,
            uint16 observationIndex,
            uint16 observationCardinality,
            uint16 observationCardinalityNext,
            uint8 feeProtocol,
            bool unlocked
        )
    {
        return (_sqrtPriceX96, _tick, 0, 0, 0, 0, true);
    }

    function feeGrowthGlobal0X128() external view returns (uint256) {
        return _feeGrowthGlobal0X128;
    }

    function feeGrowthGlobal1X128() external view returns (uint256) {
        return _feeGrowthGlobal1X128;
    }

    function ticks(int24 tick_)
        external
        view
        returns (
            uint128 liquidityGross,
            int128 liquidityNet,
            uint256 feeGrowthOutside0X128,
            uint256 feeGrowthOutside1X128,
            int56 tickCumulativeOutside,
            uint160 secondsPerLiquidityOutsideX128,
            uint32 secondsOutside,
            bool initialized
        )
    {
        TickData storage td = _ticks[tick_];
        return (
            td.liquidityGross,
            td.liquidityNet,
            td.feeGrowthOutside0X128,
            td.feeGrowthOutside1X128,
            td.tickCumulativeOutside,
            td.secondsPerLiquidityOutsideX128,
            td.secondsOutside,
            td.initialized
        );
    }

    function factory() external pure returns (address) {
        return address(0);
    }

    function token0() external pure returns (address) {
        return address(0);
    }

    function token1() external pure returns (address) {
        return address(0);
    }

    function fee() external pure returns (uint24) {
        return 3000;
    }

    function tickSpacing() external pure returns (int24) {
        return 60;
    }

    function maxLiquidityPerTick() external pure returns (uint128) {
        return type(uint128).max;
    }

    function protocolFees() external pure returns (uint128, uint128) {
        return (0, 0);
    }

    function liquidity() external pure returns (uint128) {
        return 0;
    }

    function tickBitmap(int16) external pure returns (uint256) {
        return 0;
    }

    function positions(bytes32) external pure returns (uint128, uint256, uint256, uint128, uint128) {
        return (0, 0, 0, 0, 0);
    }

    function observations(uint256) external pure returns (uint32, int56, uint160, bool) {
        return (0, 0, 0, false);
    }

    function observe(uint32[] calldata)
        external
        pure
        returns (int56[] memory tickCumulatives, uint160[] memory secondsPerLiquidityCumulativeX128s)
    {
        tickCumulatives = new int56[](0);
        secondsPerLiquidityCumulativeX128s = new uint160[](0);
    }

    function snapshotCumulativesInside(int24, int24) external pure returns (int56, uint160, uint32) {
        return (0, 0, 0);
    }

    function initialize(uint160) external { }

    function mint(address, int24, int24, uint128, bytes calldata) external pure returns (uint256, uint256) {
        return (0, 0);
    }

    function collect(address, int24, int24, uint128, uint128) external pure returns (uint128, uint128) {
        return (0, 0);
    }

    function burn(int24, int24, uint128) external pure returns (uint256, uint256) {
        return (0, 0);
    }

    function swap(address, bool, int256, uint160, bytes calldata) external pure returns (int256, int256) {
        return (0, 0);
    }

    function flash(address, uint256, uint256, bytes calldata) external { }

    function increaseObservationCardinalityNext(uint16) external { }

    function setFeeProtocol(uint8, uint8) external { }

    function collectProtocol(address, uint128, uint128) external pure returns (uint128, uint128) {
        return (0, 0);
    }
}
