// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.25;

import "forge-std/Test.sol";
import "forge-std/console.sol";

import {TickMath} from "v4-core/libraries/TickMath.sol";
import {HookBaseLib} from "@src/libraries/HookBaseLib.sol";

import {IPoolManager} from "v4-core/interfaces/IPoolManager.sol";

import {TestERC20} from "v4-core/test/TestERC20.sol";
import {Deployers} from "v4-core-test/utils/Deployers.sol";
import {HookEnabledSwapRouter} from "@test/libraries/HookEnabledSwapRouter.sol";
import {TestAccount, TestAccountLib} from "@test/libraries/TestAccountLib.t.sol";
import {LSTHook} from "@src/LSTHook.sol";

abstract contract HookTestBase is Test, Deployers {
    using TestAccountLib for TestAccount;

    LSTHook hook;

    TestERC20 WSTETH;
    TestERC20 USDC;
    TestERC20 OSQTH;
    TestERC20 WETH;

    TestAccount alice;
    TestAccount swapper;

    HookEnabledSwapRouter router;
    uint256 optionId;

    function labelTokens() public {
        WSTETH = TestERC20(HookBaseLib.WSTETH);
        vm.label(address(WSTETH), "WSTETH");
        USDC = TestERC20(HookBaseLib.USDC);
        vm.label(address(USDC), "USDC");
        OSQTH = TestERC20(HookBaseLib.OSQTH);
        vm.label(address(OSQTH), "OSQTH");
        WETH = TestERC20(HookBaseLib.WETH);
        vm.label(address(WETH), "WETH");
    }

    function create_and_approve_accounts() public {
        alice = TestAccountLib.createTestAccount("alice");
        swapper = TestAccountLib.createTestAccount("swapper");

        vm.startPrank(alice.addr);
        WSTETH.approve(address(hook), type(uint256).max);
        USDC.approve(address(hook), type(uint256).max);
        vm.stopPrank();

        vm.startPrank(swapper.addr);
        WSTETH.approve(address(router), type(uint256).max);
        USDC.approve(address(router), type(uint256).max);
        vm.stopPrank();
    }

    // -- Uniswap V4 -- //

    function swapUSDC_WSTETH_Out(uint256 amountOut) public {
        vm.prank(swapper.addr);
        router.swap(
            key,
            IPoolManager.SwapParams(
                false, // USDC -> WSTETH
                int256(amountOut),
                TickMath.MAX_SQRT_PRICE - 1
            ),
            HookEnabledSwapRouter.TestSettings(false, false),
            ZERO_BYTES
        );
    }

    function swapWSTETH_USDC_Out(uint256 amountOut) public {
        vm.prank(swapper.addr);
        router.swap(
            key,
            IPoolManager.SwapParams(
                true, // WSTETH -> USDC
                int256(amountOut),
                TickMath.MIN_SQRT_PRICE + 1
            ),
            HookEnabledSwapRouter.TestSettings(false, false),
            ZERO_BYTES
        );
    }

    // -- Uniswap V3 -- //

    function getETH_OSQTHPriceV3() public view returns (uint256) {
        return
            HookBaseLib.getV3PoolPrice(
                0x82c427AdFDf2d245Ec51D8046b41c4ee87F0d29C
            );
    }

    function getETH_USDCPriceV3() public view returns (uint256) {
        return
            HookBaseLib.getV3PoolPrice(
                0x88e6A0c2dDD26FEEb64F039a2c41296FcB3f5640
            );
    }

    // -- Custom assertions -- //

    function assertV4PositionLiquidity(
        bytes32 _optionId,
        uint256 _liquidity
    ) public view {
        (uint128 liquidity, , ) = hook.getPosition(_optionId);
        assertApproxEqAbs(liquidity, _liquidity, 10, "liquidity not equal");
    }

    function assertEqBalanceStateZero(address owner) public view {
        assertEqBalanceState(owner, 0, 0, 0, 0);
    }

    function assertEqBalanceState(
        address owner,
        uint256 _balanceWSTETH,
        uint256 _balanceUSDC
    ) public view {
        assertEqBalanceState(owner, _balanceWSTETH, _balanceUSDC, 0, 0);
    }

    function assertEqBalanceState(
        address owner,
        uint256 _balanceWSTETH,
        uint256 _balanceUSDC,
        uint256 _balanceWETH,
        uint256 _balanceOSQTH
    ) public view {
        assertEqBalanceState(
            owner,
            _balanceWSTETH,
            _balanceUSDC,
            _balanceWETH,
            _balanceOSQTH,
            0
        );
    }

    function assertEqBalanceState(
        address owner,
        uint256 _balanceWSTETH,
        uint256 _balanceUSDC,
        uint256 _balanceWETH,
        uint256 _balanceOSQTH,
        uint256 _balanceETH
    ) public view {
        assertApproxEqAbs(
            USDC.balanceOf(owner),
            _balanceUSDC,
            10,
            "Balance USDC not equal"
        );
        assertApproxEqAbs(
            WETH.balanceOf(owner),
            _balanceWETH,
            10,
            "Balance WETH not equal"
        );
        assertApproxEqAbs(
            OSQTH.balanceOf(owner),
            _balanceOSQTH,
            10,
            "Balance OSQTH not equal"
        );
        assertApproxEqAbs(
            WSTETH.balanceOf(owner),
            _balanceWSTETH,
            10,
            "Balance WSTETH not equal"
        );

        assertApproxEqAbs(
            owner.balance,
            _balanceETH,
            10,
            "Balance ETH not equal"
        );
    }
}
