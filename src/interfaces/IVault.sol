// SPDX-License-Identifier: NO
pragma solidity ^0.8.30;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@uniswap/v3-core/contracts/interfaces/IUniswapV3Pool.sol";
import "@uniswap/v3-periphery/contracts/interfaces/INonfungiblePositionManager.sol";
import "@chainlink/contracts/src/v0.8/shared/interfaces/AggregatorV3Interface.sol";

import "../VaultMath.sol";

/// @title IVault
/// @notice Interface for the sLiq Synthetic Concentrated-Liquidity Vault
interface IVault {
    /* ~~~~ Enums ~~~~ */
    enum Rolling {
        No,
        Direct,
        InverseMinus,
        InversePlus
    }
    enum Side {
        Long,
        Short
    }

    /* ~~~~ Custom Errors ~~~~ */
    error ZeroAmount();
    error ZeroRange();
    error PositionNotActive();
    error NotPositionOwner();
    error BadShares();
    error InsufficientLiquidity();
    error NotLiquidatable();

    /* ~~~~ Events ~~~~ */
    event Open(
        uint256 indexed id,
        address indexed owner,
        Side side,
        uint256 collateral,
        int24 tickLower,
        int24 tickUpper,
        uint256 kE18,
        Rolling rolling
    );
    event Close(
        uint256 indexed id,
        address indexed owner,
        Side side,
        uint256 collateral,
        int24 tickLower,
        int24 tickUpper,
        int256 result,
        uint256 fee,
        uint256 il,
        uint256 kE18
    );
    event Liquidate(
        uint256 indexed id,
        address indexed owner,
        Side side,
        uint256 collateral,
        int24 tickLower,
        int24 tickUpper,
        int256 result,
        uint256 fee,
        uint256 il,
        uint256 kE18,
        uint256 bountys
    );
    event Deposit(address indexed from, uint256 assets, uint256 shares);
    event Withdraw(address indexed from, uint256 assets, uint256 shares);

    /* ~~~~ Initialization ~~~~ */
    function init(
        address _owner,
        address _vaultMath,
        address _pool,
        address _collateral,
        address _nfpm,
        uint256 _anchorId,
        address _seq,
        address _feed
    ) external;

    /* ~~~~ View Functions ~~~~ */
    function collateralToken() external view returns (IERC20);
    function pool() external view returns (IUniswapV3Pool);
    function nfpm() external view returns (INonfungiblePositionManager);
    function anchorId() external view returns (uint256);
    function feeVaultPercentE2() external view returns (uint16);
    function feeProtocolPercentE2() external view returns (uint16);
    function bountyLiquidatorE18() external view returns (uint256);
    function seq() external view returns (AggregatorV3Interface);
    function feed() external view returns (AggregatorV3Interface);
    function vaultMath() external view returns (VaultMath);
    function totalEffLong() external view returns (uint256);
    function totalEffShort() external view returns (uint256);
    function freezBalance() external view returns (uint256);
    function nextPosId() external view returns (uint256);

    function currentTick() external view returns (int24 tick);
    function token0() external view returns (address t);
    function token1() external view returns (address t);

    function status(uint256 id)
        external
        view
        returns (uint256 collateral, uint256 fee, uint256 il, uint256 kE18, int256 result, bool active);

    function estimateShort(int24 range, uint256 amount)
        external
        view
        returns (
            int24 lowerTick,
            int24 upperTick,
            uint256 beforeSkew,
            uint256 afterSkew,
            uint256 leverageE18,
            uint256 position
        );

    function estimateLong(int24 range, uint256 amount)
        external
        view
        returns (
            int24 lowerTick,
            int24 upperTick,
            uint256 beforeSkew,
            uint256 afterSkew,
            uint256 leverageE18,
            uint256 position
        );

    /* ~~~~ State-Changing Functions ~~~~ */
    function openShort(int24 range, uint256 amount, Rolling rolling) external returns (uint256 id);
    function openLong(int24 range, uint256 amount, Rolling rolling) external returns (uint256 id);
    function close(uint256 id) external;
    function liquidate(uint256 id) external;
    function deposit(uint256 amount) external returns (uint256 shares);
    function withdraw(uint256 shares) external returns (uint256 amount);

    /* ~~~~ Admin Functions ~~~~ */
    function setFees(uint16 vaultE2, uint16 protocolE2, uint256 liquidatorE18) external;
}
