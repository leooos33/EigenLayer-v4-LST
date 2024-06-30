// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import "forge-std/console.sol";

import {Hooks} from "v4-core/libraries/Hooks.sol";
import {TickMath} from "v4-core/libraries/TickMath.sol";
import {HookEnabledSwapRouter} from "@test/libraries/HookEnabledSwapRouter.sol";
import {HookTestBase} from "@test/libraries/HookTestBase.sol";

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
        uint256 amountToDeposit = 100 ether;
        deal(address(WSTETH), address(alice.addr), amountToDeposit);
        vm.prank(alice.addr);
        optionId = hook.deposit(key, amountToDeposit, alice.addr);

        assertV4PositionLiquidity(optionId, 11433916692172150);
        assertEqBalanceStateZero(alice.addr);
        assertEqBalanceStateZero(address(hook));
    }

    // function test_deposit_withdraw_not_option_owner_revert() public {
    //     test_deposit();

    //     vm.expectRevert(IOption.NotAnOptionOwner.selector);
    //     hook.withdraw(key, 0, alice.addr);
    // }

    // function test_deposit_withdraw() public {
    //     test_deposit();

    //     vm.prank(alice.addr);
    //     hook.withdraw(key, 0, alice.addr);

    //     assertEqBalanceStateZero(address(hook));
    //     assertEqBalanceState(alice.addr, 100 ether, 0);
    //     assertV4PositionLiquidity(optionId, 0);
    //     assertEqMorphoState(address(hook), 0, 0, 0);
    // }

    // function test_swap_price_down_revert() public {
    //     test_deposit();

    //     deal(address(WSTETH), address(swapper.addr), 1 ether);
    //     vm.expectRevert(IOption.NoSwapWillOccur.selector);
    //     swapWSTETH_USDC_Out(1 ether);
    // }

    // function test_swap_price_up() public {
    //     test_deposit();

    //     deal(address(USDC), address(swapper.addr), 4513632092);

    //     swapUSDC_WSTETH_Out(1 ether);

    //     assertEqBalanceState(swapper.addr, 1 ether, 0);
    //     assertEqBalanceState(address(hook), 0, 0, 0, 16851686274526807531);
    //     assertEqMorphoState(address(hook), 0, 4513632092000000, 50 ether);
    // }

    // function test_swap_price_up_then_down() public {
    //     test_swap_price_up();

    //     swapWSTETH_USDC_Out(4513632092 / 2);

    //     assertEqBalanceState(swapper.addr, 501269034773216656, 4513632092 / 2);
    //     assertEqBalanceState(address(hook), 0, 0, 0, 8389745616890331647);
    //     assertEqMorphoState(address(hook), 0, 2256816046000000, 50 ether);
    // }

    // function test_swap_price_up_then_withdraw() public {
    //     test_swap_price_up();

    //     vm.prank(alice.addr);
    //     hook.withdraw(key, 0, alice.addr);

    //     assertEqBalanceStateZero(address(hook));
    //     assertEqBalanceState(alice.addr, 99999472645338963870, 0);
    //     assertV4PositionLiquidity(optionId, 0);
    //     assertEqMorphoState(address(hook), 0, 0, 0);
    // }

    // function test_swap_price_up_then_rebalance() public {
    //     test_swap_price_up();

    //     assertEq(hook.isPriceRebalance(key, 0), true);
    //     hook.priceRebalance(key, 0);

    //     assertEqBalanceState(address(hook), 0, 0);
    //     assertEqBalanceState(alice.addr, 0, 0);
    //     assertV4PositionLiquidity(optionId, 0);
    //     assertEqMorphoState(address(hook), 0, 0, 49999736322669483551);
    // }

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
