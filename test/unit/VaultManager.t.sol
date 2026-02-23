// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import "forge-std/Test.sol";
import "../../src/VaultManager.sol";
import "../../src/Vault.sol";
import "../../src/VaultMath.sol";
import "../mocks/MockERC20.sol";
import "../mocks/MockUniswapV3Pool.sol";
import "../mocks/MockNFPM.sol";
import "../mocks/MockChainlinkFeed.sol";
import "@uniswap/v3-core/contracts/libraries/TickMath.sol";

contract VaultManagerTest is Test {
    VaultManager public manager;
    Vault public vaultImpl;
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
        collateral = new MockERC20("USDC", "USDC", 6);
        pool = new MockUniswapV3Pool();
        nfpm = new MockNFPM();
        vaultMath = new VaultMath();

        // Set up pool: sqrtPriceX96 at tick 0
        uint160 sqrtP = TickMath.getSqrtRatioAtTick(0);
        pool.setSlot0(sqrtP, 0);

        // Set up NFPM position for anchor
        nfpm.setPosition(anchorId, address(collateral), address(collateral), -1000, 1000, 1e18, 0, 0, 0, 0);

        // Sequencer: status=0 (UP), startedAt=0 => Chainlink won't be used
        // This forces fallback to pool.slot0()
        seq = new MockChainlinkFeed(0);
        seq.setLatestRoundData(1, 1, 0, 0, 1);

        feed = new MockChainlinkFeed(8);
        feed.setLatestRoundData(1, 0, 0, 0, 1);

        vaultImpl = new Vault();
        manager = new VaultManager(address(vaultImpl), address(vaultMath));
    }

    // ---- Construction ----

    function test_Constructor_SetsBeaconAndVaultMath() public view {
        assertEq(manager.vaultMath(), address(vaultMath));
        assertEq(address(manager.beacon().implementation()), address(vaultImpl));
    }

    function test_Constructor_OwnerIsDeployer() public view {
        assertEq(manager.owner(), owner);
    }

    // ---- newVault ----

    function test_newVault_DeploysVault() public {
        address vault = manager.newVault(
            address(pool), address(collateral), address(nfpm), anchorId, address(seq), address(feed)
        );
        assertTrue(vault != address(0));
        assertEq(manager.vaultOf(address(pool)), vault);
    }

    function test_newVault_EmitsVaultDeployed() public {
        // We cannot predict the exact vault address due to CREATE2 salt,
        // so we just check the event is emitted with the correct pool.
        vm.expectEmit(true, false, false, false);
        emit VaultManager.VaultDeployed(address(pool), address(0));
        manager.newVault(address(pool), address(collateral), address(nfpm), anchorId, address(seq), address(feed));
    }

    function test_newVault_VaultInitializedCorrectly() public {
        address vaultAddr = manager.newVault(
            address(pool), address(collateral), address(nfpm), anchorId, address(seq), address(feed)
        );
        Vault v = Vault(vaultAddr);
        assertEq(address(v.collateralToken()), address(collateral));
        assertEq(address(v.pool()), address(pool));
        assertEq(v.anchorId(), anchorId);
        assertEq(v.owner(), owner);
        assertEq(v.feeVaultPercentE2(), 300);
        assertEq(v.feeProtocolPercentE2(), 200);
    }

    function test_RevertWhen_newVault_DuplicatePool() public {
        manager.newVault(address(pool), address(collateral), address(nfpm), anchorId, address(seq), address(feed));

        vm.expectRevert(VaultManager.VaultAlreadyExists.selector);
        manager.newVault(address(pool), address(collateral), address(nfpm), anchorId, address(seq), address(feed));
    }

    function test_RevertWhen_newVault_NotOwner() public {
        vm.prank(alice);
        vm.expectRevert("Ownable: caller is not the owner");
        manager.newVault(address(pool), address(collateral), address(nfpm), anchorId, address(seq), address(feed));
    }

    // ---- upgradeVaultImpl ----

    function test_upgradeVaultImpl_ChangesImplementation() public {
        Vault newImpl = new Vault();
        manager.upgradeVaultImpl(address(newImpl));
        assertEq(address(manager.beacon().implementation()), address(newImpl));
    }

    function test_upgradeVaultImpl_EmitsEvent() public {
        Vault newImpl = new Vault();
        vm.expectEmit(true, false, false, true);
        emit VaultManager.VaultImplUpgraded(address(newImpl));
        manager.upgradeVaultImpl(address(newImpl));
    }

    function test_RevertWhen_upgradeVaultImpl_NotOwner() public {
        Vault newImpl = new Vault();
        vm.prank(alice);
        vm.expectRevert("Ownable: caller is not the owner");
        manager.upgradeVaultImpl(address(newImpl));
    }

    // ---- setVaultMath ----

    function test_setVaultMath_ChangesAddress() public {
        VaultMath newMath = new VaultMath();
        manager.setVaultMath(address(newMath));
        assertEq(manager.vaultMath(), address(newMath));
    }

    function test_setVaultMath_EmitsEvent() public {
        VaultMath newMath = new VaultMath();
        vm.expectEmit(true, false, false, true);
        emit VaultManager.VaultMathChanged(address(newMath));
        manager.setVaultMath(address(newMath));
    }

    function test_RevertWhen_setVaultMath_NotOwner() public {
        vm.prank(alice);
        vm.expectRevert("Ownable: caller is not the owner");
        manager.setVaultMath(address(0x1234));
    }

    // ---- Multiple vaults ----

    function test_newVault_MultiplePoolsDifferentVaults() public {
        MockUniswapV3Pool pool2 = new MockUniswapV3Pool();
        pool2.setSlot0(TickMath.getSqrtRatioAtTick(0), 0);

        address v1 = manager.newVault(
            address(pool), address(collateral), address(nfpm), anchorId, address(seq), address(feed)
        );

        nfpm.setPosition(2, address(collateral), address(collateral), -1000, 1000, 1e18, 0, 0, 0, 0);

        address v2 =
            manager.newVault(address(pool2), address(collateral), address(nfpm), 2, address(seq), address(feed));

        assertTrue(v1 != v2);
        assertEq(manager.vaultOf(address(pool)), v1);
        assertEq(manager.vaultOf(address(pool2)), v2);
    }
}
