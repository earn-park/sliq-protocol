// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.30;

/// @title Vault
/// @author sLiq Protocol
/// @notice Synthetic Concentrated-Liquidity Vault for trading impermanent loss.
///   Holds an Anchor NFT position, balances Short/Long PnL, ERC-4626-like share accounting.
/// @dev Deployed as a BeaconProxy via VaultManager. Uses Initializable pattern.

import "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import "@uniswap/v3-core/contracts/libraries/FullMath.sol";
import "@uniswap/v3-periphery/contracts/interfaces/INonfungiblePositionManager.sol";
import "@uniswap/v3-core/contracts/interfaces/IUniswapV3Pool.sol";
import "@uniswap/v3-core/contracts/libraries/TickMath.sol";
import "@uniswap/v3-periphery/contracts/libraries/LiquidityAmounts.sol";

import "@chainlink/contracts/src/v0.8/shared/interfaces/AggregatorV3Interface.sol";

import { Initializable } from "@openzeppelin-upgradeable/contracts/proxy/utils/Initializable.sol";
import { ERC20Upgradeable } from "@openzeppelin-upgradeable/contracts/token/ERC20/ERC20Upgradeable.sol";
import { OwnableUpgradeable } from "@openzeppelin-upgradeable/contracts/access/OwnableUpgradeable.sol";
import {
    ReentrancyGuardUpgradeable
} from "@openzeppelin-upgradeable/contracts/security/ReentrancyGuardUpgradeable.sol";
import { PausableUpgradeable } from "@openzeppelin-upgradeable/contracts/security/PausableUpgradeable.sol";

import "./VaultMath.sol";

contract Vault is Initializable, ERC20Upgradeable, OwnableUpgradeable, ReentrancyGuardUpgradeable, PausableUpgradeable {
    using SafeERC20 for IERC20;

    /* ~~~~ Constants ~~~~ */
    /// @dev Minimum dead shares divisor. Actual dead shares = 10^decimals / DEAD_SHARES_DIVISOR.
    /// For WETH (18 dec): 1e15 (~0.001 ETH). For USDC (6 dec): 1e3 ($0.001).
    uint256 private constant DEAD_SHARES_DIVISOR = 1000;
    uint256 private constant MAX_TOTAL_FEE_E2 = 2000;
    uint256 private constant MAX_BOUNTY_E18 = 1e18;
    uint256 private constant FEE_BUFFER_E18 = 13e17;
    int24 private constant MIN_RANGE = 60;
    int24 private constant MAX_RANGE = 100_000;
    uint256 private constant STALENESS_THRESHOLD = 3600;

    /* ~~~~ Custom Errors ~~~~ */
    error ZeroAmount();
    error ZeroRange();
    error RangeTooSmall();
    error RangeTooLarge();
    error PositionNotActive();
    error NotPositionOwner();
    error BadShares();
    error InsufficientLiquidity();
    error NotLiquidatable();
    error FeeTooHigh();
    error BountyTooHigh();
    error ZeroAnchorCollateral();
    error AnchorNotOwned();
    error NotGuardian();
    error TransferAmountMismatch();
    error ZeroAddress();

    /* ~~~~ Events ~~~~ */
    event PayoutShortfall(uint256 indexed positionId, address indexed owner, uint256 entitled, uint256 paid);
    event FeesUpdated(uint16 vaultE2, uint16 protocolE2, uint256 liquidatorE18);
    event RollSkipped(uint256 indexed positionId, address indexed owner);

    /* ~~~~ Immutable & basic config ~~~~ */
    IERC20 public collateralToken; // e.g. USDC
    IUniswapV3Pool public pool;
    INonfungiblePositionManager public nfpm;
    uint256 public anchorId; // NFT id
    uint8 private _decimals;
    uint16 public feeVaultPercentE2;
    uint16 public feeProtocolPercentE2;
    uint256 public bountyLiquidatorE18;

    AggregatorV3Interface public seq;
    AggregatorV3Interface public feed;

    VaultMath public vaultMath;

    address public guardian;
    uint8 private _feedDecimals;

    /* ~~~~ Checkpoints & global state ~~~~ */
    struct Checkpoint {
        uint64 timestamp;
        uint256 totalFeeCum;
        uint256 skewShortCum;
        uint256 skewLongCum;
        uint160 sqrtPX96;
        uint256 anchorCollateral;
    }
    Checkpoint[] public cps;

    uint256 lastFee0Cum;
    uint256 lastFee1Cum;
    uint256 lastEffShort;
    uint256 lastEffLong;

    uint256 public totalEffLong;
    uint256 public totalEffShort;

    uint256 public freezBalance;

    /* ~~~~ Position storage ~~~~ */
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

    struct Position {
        address owner;
        Side side;
        uint256 collateral;
        uint32 cpIndexOpen;
        int24 tickLower;
        int24 tickUpper;
        int256 result;
        bool active;
        Rolling rolling;
    }
    mapping(uint256 => Position) public positions;
    uint256 public nextPosId = 1;

    /// @dev Reserved storage gap for future upgrades (Beacon proxy pattern)
    uint256[50] private __gap;

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

    /*~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~*
        CONSTRUCTOR && INIT
    *~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~*/

    /// @dev Disable initializers on the implementation contract to prevent
    ///      direct initialization (only proxies should be initialized).
    constructor() {
        _disableInitializers();
    }

    /// @notice Initialize the vault (called once via proxy)
    function init(
        address _owner,
        address _vaultMath,
        address _pool,
        address _collateral,
        address _nfpm,
        uint256 _anchorId,
        address _seq,
        address _feed
    ) external initializer {
        if (_owner == address(0)) revert ZeroAddress();
        if (_vaultMath == address(0)) revert ZeroAddress();
        if (_pool == address(0)) revert ZeroAddress();
        if (_collateral == address(0)) revert ZeroAddress();
        if (_nfpm == address(0)) revert ZeroAddress();

        __ERC20_init("Vault Share LP", "vsLP");
        __Ownable_init();
        transferOwnership(_owner);
        __ReentrancyGuard_init();
        __Pausable_init();

        guardian = _owner;
        vaultMath = VaultMath(_vaultMath);

        // Cache collateral token decimals for share accounting
        _decimals = vaultMath.decimals(_collateral);

        pool = IUniswapV3Pool(_pool);
        collateralToken = IERC20(_collateral);
        nfpm = INonfungiblePositionManager(_nfpm);
        anchorId = _anchorId;
        if (nfpm.ownerOf(_anchorId) != address(this) && nfpm.ownerOf(_anchorId) != _owner) revert AnchorNotOwned();

        seq = AggregatorV3Interface(_seq);
        feed = AggregatorV3Interface(_feed);
        _feedDecimals = feed.decimals();

        feeVaultPercentE2 = 300;
        feeProtocolPercentE2 = 200;
        bountyLiquidatorE18 = 15e12;
        nextPosId = 1;

        // Initial checkpoint
        cps.push(Checkpoint(0, 0, 0, 0, 0, 0));
        _checkpoint();
    }

    /// @notice Returns the number of decimals (matches collateral token)
    function decimals() public view override returns (uint8) {
        return _decimals;
    }

    /*~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~*
        UNISWAP POOL INFO HELPERS
    *~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~*/

    /// @return tick current tick (can be used to check if price inside range)
    function currentTick() public view returns (int24 tick) {
        uint256 priceE18Chainlink = 0;
        (, int256 s, uint256 startedAt,,) = seq.latestRoundData();
        // status == 0 => sequencer UP, status == 1 => DOWN
        if (s == 0 && startedAt != 0 && block.timestamp - startedAt > 1 hours) {
            (uint80 roundId, int256 answer,, uint256 updatedAt, uint80 answeredInRound) = feed.latestRoundData();
            if (
                answer > 0 && updatedAt != 0 && answeredInRound >= roundId
                    && block.timestamp - updatedAt < STALENESS_THRESHOLD
            ) {
                uint8 dec = _feedDecimals;
                // Convert answer from feed decimals to 1e18
                if (dec < 18) {
                    priceE18Chainlink = uint256(answer) * (10 ** uint256(18 - dec));
                } else if (dec > 18) {
                    // Safe division for large decimals
                    priceE18Chainlink = FullMath.mulDiv(uint256(answer), 1, 10 ** uint256(dec - 18));
                } else {
                    priceE18Chainlink = uint256(answer);
                }
            }
        }
        if (priceE18Chainlink > 0) {
            tick = vaultMath.priceE18ToTick(priceE18Chainlink, token0(), token1());
        } else {
            (, tick,,,,,) = pool.slot0();
        }
    }

    function token0() public view returns (address t) {
        (,, t,,,,,,,,,) = nfpm.positions(anchorId);
    }

    function token1() public view returns (address t) {
        (,,, t,,,,,,,,) = nfpm.positions(anchorId);
    }

    function _anchorLower() internal view returns (int24) {
        (,,,,, int24 anchorLower,,,,,,) = nfpm.positions(anchorId);
        return anchorLower;
    }

    function _anchorUpper() internal view returns (int24) {
        (,,,,,, int24 anchorUpper,,,,,) = nfpm.positions(anchorId);
        return anchorUpper;
    }

    function _anchorRange() internal view returns (int24) {
        (,,,,, int24 anchorLower, int24 anchorUpper,,,,,) = nfpm.positions(anchorId);
        return (anchorUpper - anchorLower) / 2;
    }

    function _anchorCollateral() internal view returns (uint256 amount) {
        uint160 sqrtPX96 = TickMath.getSqrtRatioAtTick(currentTick());
        (,,,,, int24 anchorLower, int24 anchorUpper, uint128 liquidity,,,,) = nfpm.positions(anchorId);
        (uint256 amount0, uint256 amount1) = LiquidityAmounts.getAmountsForLiquidity(
            sqrtPX96, TickMath.getSqrtRatioAtTick(anchorLower), TickMath.getSqrtRatioAtTick(anchorUpper), liquidity
        );

        amount = vaultMath.sumTok0Tok1In0(amount0, amount1, sqrtPX96, token0(), token1());
    }

    function _calcSkewE18(uint256 num, uint256 den) internal view returns (uint256) {
        if (num == 0 || den == 0) return 0;
        return FullMath.mulDiv(
            FullMath.mulDiv(num, 1e18, den),
            (10_000 - uint256(feeVaultPercentE2) - uint256(feeProtocolPercentE2)),
            10_000
        );
    }

    function _calc_new_position(int24 range, uint256 amount)
        internal
        view
        returns (int24 lower, int24 upper, uint256 eff, uint256 leverageE18)
    {
        if (amount == 0) revert ZeroAmount();
        if (range <= 0) revert ZeroRange();
        if (range < MIN_RANGE) revert RangeTooSmall();
        if (range > MAX_RANGE) revert RangeTooLarge();

        lower = currentTick() - range;
        upper = currentTick() + range;
        eff = vaultMath._effLiquidity(amount, range, _anchorRange());

        uint256 ilE18 = vaultMath._ilPercentE18(range);
        leverageE18 = FullMath.mulDiv(2 * 1e18, 1e18, ilE18);
    }

    function _estimate(Side side, int24 range, uint256 amount)
        internal
        view
        returns (
            int24 lowerTick,
            int24 upperTick,
            uint256 beforeSkew,
            uint256 afterSkew,
            uint256 leverageE18,
            uint256 position
        )
    {
        (int24 lower, int24 upper, uint256 eff, uint256 lavarage) = _calc_new_position(range, amount);
        lowerTick = lower;
        upperTick = upper;
        leverageE18 = lavarage;
        position = FullMath.mulDiv(leverageE18, amount, 1e18);
        if (side == Side.Long) beforeSkew = _calcSkewE18(2 * totalEffShort, totalEffLong + totalEffShort);
        else beforeSkew = _calcSkewE18(2 * totalEffLong, totalEffLong + totalEffShort);
        if (side == Side.Long) afterSkew = _calcSkewE18(2 * totalEffShort, totalEffLong + totalEffShort + eff);
        else afterSkew = _calcSkewE18(2 * totalEffLong, totalEffLong + totalEffShort + eff);
    }

    function _open(address positionOwner, Side side, int24 range, uint256 amount, Rolling rolling)
        internal
        returns (uint256 id)
    {
        uint256 balBefore = collateralToken.balanceOf(address(this));
        collateralToken.safeTransferFrom(positionOwner, address(this), amount);
        if (collateralToken.balanceOf(address(this)) - balBefore != amount) revert TransferAmountMismatch();
        freezBalance = freezBalance + amount;

        (int24 lower, int24 upper, uint256 eff,) = _calc_new_position(range, amount);

        if (side == Side.Long) totalEffLong += eff;
        else totalEffShort += eff;

        id = nextPosId++;
        positions[id] = Position(positionOwner, side, amount, uint32(cps.length), lower, upper, 0, true, rolling);

        _checkpoint();

        uint256 kE18 =
            (side == Side.Long
                ? _calcSkewE18(2 * totalEffShort, totalEffLong + totalEffShort)
                : _calcSkewE18(2 * totalEffLong, totalEffLong + totalEffShort));
        emit Open(id, positionOwner, side, amount, lower, upper, kE18, rolling);
    }

    function openShort(int24 range, uint256 amount, Rolling rolling)
        external
        nonReentrant
        whenNotPaused
        returns (uint256 id)
    {
        return _open(msg.sender, Side.Short, range, amount, rolling);
    }

    function openLong(int24 range, uint256 amount, Rolling rolling)
        external
        nonReentrant
        whenNotPaused
        returns (uint256 id)
    {
        return _open(msg.sender, Side.Long, range, amount, rolling);
    }

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
        )
    {
        return _estimate(Side.Short, range, amount);
    }

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
        )
    {
        return _estimate(Side.Long, range, amount);
    }

    /// @dev Create and store a new checkpoint with current state
    function _checkpoint() internal {
        (Checkpoint memory cp, uint256 fee0, uint256 fee1) = _view_new_checkpoint();
        cps.push(cp);

        lastFee0Cum = fee0;
        lastFee1Cum = fee1;
        lastEffShort = totalEffShort;
        lastEffLong = totalEffLong;
    }

    function _view_new_checkpoint() internal view returns (Checkpoint memory cp, uint256 fee0, uint256 fee1) {
        uint64 ts = uint64(block.timestamp);

        int24 tick = currentTick();
        (fee0, fee1) = vaultMath.calcFees(nfpm, pool, anchorId, tick, _anchorLower(), _anchorUpper());
        uint160 sqrtPX96 = TickMath.getSqrtRatioAtTick(tick);

        Checkpoint memory from = cps[cps.length - 1];
        uint256 dFee0 = fee0 - lastFee0Cum;
        uint256 dFee1 = fee1 - lastFee1Cum;
        uint256 totalFee = vaultMath.sumTok0Tok1In0(dFee0, dFee1, sqrtPX96, token0(), token1());
        uint256 totalTime = ts - from.timestamp;
        uint256 skewShortE18 =
            (lastEffLong + lastEffShort) == 0 ? 0 : FullMath.mulDiv(2 * lastEffLong, 1e18, lastEffLong + lastEffShort);
        uint256 skewLongE18 =
            (lastEffLong + lastEffShort) == 0 ? 0 : FullMath.mulDiv(2 * lastEffShort, 1e18, lastEffLong + lastEffShort);
        uint256 skewShortW = totalTime * skewShortE18;
        uint256 skewLongW = totalTime * skewLongE18;
        uint256 skewShortCum = from.skewShortCum + skewShortW;
        uint256 skewLongCum = from.skewLongCum + skewLongW;
        uint256 totalFeeCum = from.totalFeeCum + totalFee;

        uint256 anchorCollateral = _anchorCollateral();
        cp = Checkpoint(ts, totalFeeCum, skewShortCum, skewLongCum, sqrtPX96, anchorCollateral);
    }

    /* ────── Status long/short ────── */
    function _statusCalc(uint256 id)
        internal
        view
        returns (uint256 collateral, uint256 fee, uint256 il, uint256 kE18, int256 result)
    {
        Position storage p = positions[id];
        if (!p.active) revert PositionNotActive();

        int24 range = (p.tickUpper - p.tickLower) / 2;
        uint256 liqEff = vaultMath._effLiquidity(p.collateral, range, _anchorRange());

        Checkpoint memory from = cps[p.cpIndexOpen];
        (Checkpoint memory to,,) = _view_new_checkpoint();
        if (from.anchorCollateral == 0) revert ZeroAnchorCollateral();
        uint256 liqShareE18 = FullMath.mulDiv(liqEff, 1e18, from.anchorCollateral);
        uint256 totalFee = to.totalFeeCum - from.totalFeeCum;
        uint256 totalTime = to.timestamp - from.timestamp;
        uint256 wFee = FullMath.mulDiv(totalFee, liqShareE18, FEE_BUFFER_E18);

        int24 ct = currentTick();
        int24 tickMid = p.tickLower + range;
        int24 move = ct < tickMid ? tickMid - ct : ct - tickMid;
        if (move > range && p.side == Side.Short) move = range; // safe short

        // IL calculation delegated to VaultMath to reduce Vault bytecode (EIP-170)
        uint256 ilCalc = vaultMath.calcPositionIL(range, move, p.collateral);

        if (p.side == Side.Short) {
            uint256 skewShortE18 = totalTime == 0
                ? _calcSkewE18(2 * totalEffLong, totalEffLong + totalEffShort)
                : FullMath.mulDiv(
                    (to.skewShortCum - from.skewShortCum),
                    (10_000 - uint256(feeVaultPercentE2) - uint256(feeProtocolPercentE2)),
                    10_000 * totalTime
                );
            il = FullMath.mulDiv(ilCalc, skewShortE18, 1e18);
            kE18 = skewShortE18;
            fee = wFee;
        } else if (p.side == Side.Long) {
            uint256 skewLongE18 = totalTime == 0
                ? _calcSkewE18(2 * totalEffShort, totalEffLong + totalEffShort)
                : FullMath.mulDiv(
                    (to.skewLongCum - from.skewLongCum),
                    (10_000 - uint256(feeVaultPercentE2) - uint256(feeProtocolPercentE2)),
                    10_000 * totalTime
                );
            fee = FullMath.mulDiv(wFee, skewLongE18, 1e18);
            kE18 = skewLongE18;
            il = ilCalc;
        }

        collateral = p.collateral;

        if (p.side == Side.Long) {
            result = int256(collateral) + int256(fee) - int256(il);
        } else if (p.side == Side.Short) {
            result = int256(collateral) - int256(fee) + int256(il);
        }
    }

    function status(uint256 id)
        external
        view
        returns (uint256 collateral, uint256 fee, uint256 il, uint256 kE18, int256 result, bool active)
    {
        Position storage p = positions[id];
        active = p.active;
        if (active) {
            (collateral, fee, il, kE18, result) = _statusCalc(id);
        } else {
            collateral = p.collateral;
            fee = 0;
            il = 0;
            result = p.result;
        }
    }

    /* ────── Close / claim ────── */
    function _close(uint256 id, bool liquidation)
        internal
        returns (int256 payout, uint256 bounty, uint256 fee, uint256 il, uint256 kE18)
    {
        Position storage p = positions[id];
        if (!p.active) revert PositionNotActive();

        (uint256 collateral, uint256 _fee, uint256 _il, uint256 _kE18, int256 result) = _statusCalc(id);
        fee = _fee;
        il = _il;
        kE18 = _kE18;
        payout = result;
        bounty = vaultMath.fromE18(address(collateralToken), bountyLiquidatorE18);

        uint256 feeProtocol = (p.side == Side.Long ? fee : il) * uint256(feeProtocolPercentE2) / 10_000;
        int24 range = (p.tickUpper - p.tickLower) / 2;
        uint256 eff = vaultMath._effLiquidity(p.collateral, range, _anchorRange());
        uint256 positionAmount = p.collateral;
        Side positionSide = p.side;
        Rolling positionRolling = p.rolling;
        address positionOwner = p.owner;

        // Effects: all state updates before external calls (CEI pattern)
        freezBalance = freezBalance - collateral;
        p.active = false;
        p.result = payout;
        if (positionSide == Side.Long) totalEffLong -= eff;
        else totalEffShort -= eff;

        // Interactions: external transfers after state is consistent
        bool shortfall = false;
        if (payout > 0) {
            uint256 balanceVault = collateralToken.balanceOf(address(this));
            uint256 transferAmt = balanceVault > uint256(payout) ? uint256(payout) : balanceVault;
            if (transferAmt < uint256(payout)) {
                emit PayoutShortfall(id, positionOwner, uint256(payout), transferAmt);
                shortfall = true;
            }
            payout = int256(transferAmt);
            p.result = payout;
            collateralToken.safeTransfer(positionOwner, transferAmt);
        }

        // Skip protocol fee during insolvency to preserve liquidity for remaining positions
        if (feeProtocol > 0 && !shortfall) {
            uint256 balanceVault = collateralToken.balanceOf(address(this));
            uint256 transferAmt = balanceVault > feeProtocol ? feeProtocol : balanceVault;
            collateralToken.safeTransfer(owner(), transferAmt);
        }

        if (
            liquidation && positionRolling != Rolling.No && collateralToken.balanceOf(positionOwner) >= positionAmount
                && collateralToken.allowance(positionOwner, address(this)) >= positionAmount
        ) {
            Side rollingSide = positionSide;
            if (positionRolling == Rolling.InverseMinus) {
                if (payout < int256(positionAmount)) {
                    rollingSide = positionSide == Side.Long ? Side.Short : Side.Long;
                }
            } else if (positionRolling == Rolling.InversePlus) {
                if (payout > int256(positionAmount)) {
                    rollingSide = positionSide == Side.Long ? Side.Short : Side.Long;
                }
            }
            _open(positionOwner, rollingSide, range, positionAmount, positionRolling);
        } else {
            if (liquidation && positionRolling != Rolling.No) {
                emit RollSkipped(id, positionOwner);
            }
            _checkpoint();
        }
    }

    function close(uint256 id) external nonReentrant {
        Position storage p = positions[id];
        if (p.owner != msg.sender) revert NotPositionOwner();

        (int256 result,, uint256 fee, uint256 il, uint256 kE18) = _close(id, false);

        emit Close(id, msg.sender, p.side, p.collateral, p.tickLower, p.tickUpper, result, fee, il, kE18);
    }

    function liquidate(uint256 id) external nonReentrant {
        Position storage p = positions[id];
        if (!p.active) revert PositionNotActive();

        int24 tickNow = currentTick();
        (uint256 collateral, uint256 _fee,,,) = _statusCalc(id);
        uint256 liquidateR = 0;
        if (p.side == Side.Short) {
            liquidateR = collateral;
        }
        if (!(tickNow <= p.tickLower || tickNow >= p.tickUpper || (liquidateR > 0 && _fee >= liquidateR))) {
            revert NotLiquidatable();
        }

        (int256 result, uint256 bounty, uint256 fee, uint256 il, uint256 kE18) = _close(id, true);
        uint256 balanceVault = collateralToken.balanceOf(address(this));
        if (balanceVault > bounty) {
            collateralToken.safeTransfer(msg.sender, bounty);
        } else {
            collateralToken.safeTransfer(msg.sender, balanceVault);
        }

        emit Liquidate(id, msg.sender, p.side, p.collateral, p.tickLower, p.tickUpper, result, fee, il, kE18, bounty);
    }

    /// @dev Returns the total collateral token balance held by the vault
    function _totalAssets() internal view returns (uint256) {
        return collateralToken.balanceOf(address(this));
    }

    /// @notice Deposit collateral tokens and receive vault shares
    function deposit(uint256 amount) external nonReentrant whenNotPaused returns (uint256 shares) {
        if (amount == 0) revert ZeroAmount();

        uint256 assetsBefore = _totalAssets() - freezBalance;
        uint256 balBefore = collateralToken.balanceOf(address(this));
        collateralToken.safeTransferFrom(msg.sender, address(this), amount);
        if (collateralToken.balanceOf(address(this)) - balBefore != amount) revert TransferAmountMismatch();

        if (totalSupply() == 0 && assetsBefore == 0) {
            // First depositor: lock dead shares to prevent share inflation attack.
            // Scales with token decimals: WETH (18 dec) = 1e15, USDC (6 dec) = 1e3.
            uint256 deadShares = 10 ** uint256(_decimals) / DEAD_SHARES_DIVISOR;
            shares = amount - deadShares;
            _mint(address(1), deadShares);
        } else {
            shares = FullMath.mulDiv(amount, totalSupply(), assetsBefore);
        }
        if (shares == 0) revert ZeroAmount();
        _mint(msg.sender, shares);

        emit Deposit(msg.sender, amount, shares);
    }

    /// @notice Burn vault shares and withdraw collateral tokens
    function withdraw(uint256 shares) external nonReentrant returns (uint256 amount) {
        uint256 unfreezeAssets = (_totalAssets() - freezBalance);
        if (shares == 0 || balanceOf(msg.sender) < shares) revert BadShares();
        if (unfreezeAssets < totalSupply()) revert InsufficientLiquidity();

        amount = FullMath.mulDiv(shares, unfreezeAssets, totalSupply());
        _burn(msg.sender, shares);

        collateralToken.safeTransfer(msg.sender, amount);

        emit Withdraw(msg.sender, amount, shares);
    }

    function setFees(uint16 vaultE2, uint16 protocolE2, uint256 liquidatorE18) external onlyOwner {
        if (uint256(vaultE2) + uint256(protocolE2) > MAX_TOTAL_FEE_E2) revert FeeTooHigh();
        if (liquidatorE18 > MAX_BOUNTY_E18) revert BountyTooHigh();
        feeVaultPercentE2 = vaultE2;
        feeProtocolPercentE2 = protocolE2;
        bountyLiquidatorE18 = liquidatorE18;
        emit FeesUpdated(vaultE2, protocolE2, liquidatorE18);
    }

    /* ~~~~ Pausable ~~~~ */

    function pause() external {
        if (msg.sender != guardian && msg.sender != owner()) revert NotGuardian();
        _pause();
    }

    function unpause() external onlyOwner {
        _unpause();
    }

    function setGuardian(address _guardian) external onlyOwner {
        guardian = _guardian;
    }
}
