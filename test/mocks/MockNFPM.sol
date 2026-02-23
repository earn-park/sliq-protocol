// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

contract MockNFPM {
    struct PositionData {
        uint96 nonce;
        address operator;
        address token0;
        address token1;
        uint24 fee;
        int24 tickLower;
        int24 tickUpper;
        uint128 liquidity;
        uint256 feeGrowthInside0LastX128;
        uint256 feeGrowthInside1LastX128;
        uint128 tokensOwed0;
        uint128 tokensOwed1;
    }

    mapping(uint256 => PositionData) public _positions;

    function setPosition(
        uint256 tokenId,
        address token0_,
        address token1_,
        int24 tickLower_,
        int24 tickUpper_,
        uint128 liquidity_,
        uint256 fg0Last_,
        uint256 fg1Last_,
        uint128 owed0_,
        uint128 owed1_
    ) external {
        _positions[tokenId] = PositionData(
            0,
            address(0),
            token0_,
            token1_,
            3000,
            tickLower_,
            tickUpper_,
            liquidity_,
            fg0Last_,
            fg1Last_,
            owed0_,
            owed1_
        );
    }

    function positions(uint256 tokenId)
        external
        view
        returns (
            uint96 nonce,
            address operator,
            address token0,
            address token1,
            uint24 fee,
            int24 tickLower,
            int24 tickUpper,
            uint128 liquidity,
            uint256 feeGrowthInside0LastX128,
            uint256 feeGrowthInside1LastX128,
            uint128 tokensOwed0,
            uint128 tokensOwed1
        )
    {
        PositionData storage p = _positions[tokenId];
        return (
            p.nonce,
            p.operator,
            p.token0,
            p.token1,
            p.fee,
            p.tickLower,
            p.tickUpper,
            p.liquidity,
            p.feeGrowthInside0LastX128,
            p.feeGrowthInside1LastX128,
            p.tokensOwed0,
            p.tokensOwed1
        );
    }

    // Stubs for the full INonfungiblePositionManager interface
    // ERC721 stubs
    function balanceOf(address) external pure returns (uint256) {
        return 0;
    }

    function ownerOf(uint256) external pure returns (address) {
        return address(0);
    }

    function safeTransferFrom(address, address, uint256) external { }
    function safeTransferFrom(address, address, uint256, bytes calldata) external { }
    function transferFrom(address, address, uint256) external { }
    function approve(address, uint256) external { }

    function getApproved(uint256) external pure returns (address) {
        return address(0);
    }

    function setApprovalForAll(address, bool) external { }

    function isApprovedForAll(address, address) external pure returns (bool) {
        return false;
    }

    // ERC721Metadata stubs
    function name() external pure returns (string memory) {
        return "MockNFPM";
    }

    function symbol() external pure returns (string memory) {
        return "MNFPM";
    }

    function tokenURI(uint256) external pure returns (string memory) {
        return "";
    }

    // ERC721Enumerable stubs
    function totalSupply() external pure returns (uint256) {
        return 0;
    }

    function tokenOfOwnerByIndex(address, uint256) external pure returns (uint256) {
        return 0;
    }

    function tokenByIndex(uint256) external pure returns (uint256) {
        return 0;
    }

    // ERC165
    function supportsInterface(bytes4) external pure returns (bool) {
        return false;
    }

    // IPoolInitializer
    function createAndInitializePoolIfNecessary(address, address, uint24, uint160) external pure returns (address) {
        return address(0);
    }

    // IPeripheryPayments
    function unwrapWETH9(uint256, address) external { }
    function refundETH() external { }
    function sweepToken(address, uint256, address) external { }

    // IPeripheryImmutableState
    function WETH9() external pure returns (address) {
        return address(0);
    }

    // IERC721Permit
    function PERMIT_TYPEHASH() external pure returns (bytes32) {
        return bytes32(0);
    }

    function DOMAIN_SEPARATOR() external pure returns (bytes32) {
        return bytes32(0);
    }

    function permit(address, uint256, uint256, uint8, bytes32, bytes32) external { }

    // NFPM specific
    function mint(bytes calldata) external payable returns (uint256, uint128, uint256, uint256) {
        return (0, 0, 0, 0);
    }

    function increaseLiquidity(bytes calldata) external payable returns (uint128, uint256, uint256) {
        return (0, 0, 0);
    }

    function decreaseLiquidity(bytes calldata) external payable returns (uint256, uint256) {
        return (0, 0);
    }

    function collect(bytes calldata) external payable returns (uint256, uint256) {
        return (0, 0);
    }

    function burn(uint256) external payable { }
}
