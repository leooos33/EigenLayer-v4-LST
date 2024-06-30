// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import "forge-std/console.sol";

import {Hooks} from "v4-core/libraries/Hooks.sol";
import {TickMath} from "v4-core/libraries/TickMath.sol";
import {HookEnabledSwapRouter} from "@test/libraries/HookEnabledSwapRouter.sol";
import {HookTestBase} from "@test/libraries/HookTestBase.sol";

import {IPoolManager} from "v4-core/interfaces/IPoolManager.sol";
import {PoolId, PoolIdLibrary} from "v4-core/types/PoolId.sol";
import {CurrencyLibrary, Currency} from "v4-core/types/Currency.sol";
import {LSTHook} from "@src/LSTHook.sol";

contract LSTHookTest is HookTestBase {
    using PoolIdLibrary for PoolId;
    using CurrencyLibrary for Currency;

    function setUp() public {
        deployFreshManagerAndRouters();

        labelTokens();
        init_hook();
        create_and_approve_accounts();
    }

    function test_deposit() public {
        uint256 amountToDeposit = 50 ether - 2516;
        deal(address(WSTETH), address(alice.addr), amountToDeposit);
        vm.prank(alice.addr);
        WSTETH.transfer(address(hook), amountToDeposit);

        vm.prank(alice.addr);
        positionId = hook.modifyLiquidity(
            alice.addr,
            key,
            IPoolManager.ModifyLiquidityParams({
                tickLower: -192232,
                tickUpper: -185300,
                liquidityDelta: 11433916692172150,
                salt: bytes32(ZERO_BYTES)
            })
        );

        assertV4PositionLiquidity(positionId, 11433916692172150);
        assertEqBalanceStateZero(alice.addr);
        assertEqBalanceStateZero(address(hook));
    }

    function test_rebalance_not_in_time() public {
        test_deposit();

        vm.expectRevert(LSTHook.NotEnoughTimePassed.selector);
        hook.timeRebalance(positionId);
    }

    function test_rebalance_in_time() public {
        test_deposit();

        vm.roll(block.number + 4 * 60 * 25);
        hook.timeRebalance(positionId);

        assertEqBalanceStateZero(alice.addr);
        assertV4PositionLiquidity(positionId, 11433916692172150);
    }

    // -- Helpers --

    function init_hook() internal {
        router = new HookEnabledSwapRouter(manager);

        address hookAddress = address(
            uint160(
                Hooks.BEFORE_ADD_LIQUIDITY_FLAG | Hooks.AFTER_INITIALIZE_FLAG
            )
        );
        deployCodeTo("LSTHook.sol", abi.encode(manager), hookAddress);
        hook = LSTHook(hookAddress);

        uint160 initialSQRTPrice = TickMath.getSqrtPriceAtTick(-192232);

        (key, ) = initPool(
            Currency.wrap(address(WSTETH)),
            Currency.wrap(address(USDC)),
            hook,
            200,
            initialSQRTPrice,
            ZERO_BYTES
        );
    }
}
