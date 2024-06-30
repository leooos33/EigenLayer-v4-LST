// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import "forge-std/console.sol";

import {TickMath} from "v4-core/libraries/TickMath.sol";
import {Hooks} from "v4-core/libraries/Hooks.sol";
import {CurrencySettler} from "v4-core-test/utils/CurrencySettler.sol";
import {StateLibrary} from "v4-core/libraries/StateLibrary.sol";
import {HookBaseLib} from "@src/libraries/HookBaseLib.sol";
import {HookMathLib} from "@src/libraries/HookMathLib.sol";

import {Position} from "v4-core/libraries/Position.sol";
import {Currency} from "v4-core/types/Currency.sol";
import {PoolId, PoolIdLibrary} from "v4-core/types/PoolId.sol";
import {PoolKey} from "v4-core/types/PoolKey.sol";
import {BalanceDelta} from "v4-core/types/BalanceDelta.sol";
import {BaseHook} from "@forks/BaseHook.sol";
import {PoolKey} from "v4-core/types/PoolKey.sol";
import {PoolIdLibrary} from "v4-core/types/PoolId.sol";
import {BalanceDelta} from "v4-core/types/BalanceDelta.sol";
import {LiquidityAmounts} from "v4-core/../test/utils/LiquidityAmounts.sol";
import {ERC721} from "solmate/tokens/ERC721.sol";
import {IERC20Minimal as IERC20} from "v4-core/interfaces/external/IERC20Minimal.sol";

import {IPoolManager} from "v4-core/interfaces/IPoolManager.sol";

/// @title LST hook to automatically adjust lp position
/// @author IVikkk
/// @custom:contact vivan.volovik@gmail.com
contract LSTHook is BaseHook {
    using PoolIdLibrary for PoolKey;
    using CurrencySettler for Currency;

    IERC20 WSTETH = IERC20(HookBaseLib.WSTETH);
    IERC20 WETH = IERC20(HookBaseLib.WETH);
    IERC20 USDC = IERC20(HookBaseLib.USDC);

    error AddLiquidityThroughHook();
    error NotEnoughTimePassed();

    struct PositionInfo {
        PoolKey key;
        int24 tickLower;
        int24 tickUpper;
        int256 liquidity;
        uint256 lastUpdated;
    }

    mapping(bytes32 => PositionInfo) positionInfo;

    // Setup for dev then depend on the protocol and AVS
    uint256 public priceScalingFactor = 1e18 + 1e16;
    uint256 public distanceBetweenUpdates = 4 * 60 * 24;

    function getPositionInfo(
        bytes32 positionId
    ) external view returns (PositionInfo memory) {
        return positionInfo[positionId];
    }

    constructor(IPoolManager poolManager) BaseHook(poolManager) {}

    function afterInitialize(
        address,
        PoolKey calldata key,
        uint160,
        int24 tick,
        bytes calldata
    ) external override returns (bytes4) {
        console.log(">> afterInitialize");

        USDC.approve(HookBaseLib.SWAP_ROUTER, type(uint256).max);
        WETH.approve(HookBaseLib.SWAP_ROUTER, type(uint256).max);
        WSTETH.approve(HookBaseLib.SWAP_ROUTER, type(uint256).max);

        return LSTHook.afterInitialize.selector;
    }

    function getHookPermissions()
        public
        pure
        override
        returns (Hooks.Permissions memory)
    {
        return
            Hooks.Permissions({
                beforeInitialize: false,
                afterInitialize: true,
                beforeAddLiquidity: true,
                afterAddLiquidity: false,
                beforeRemoveLiquidity: false,
                afterRemoveLiquidity: false,
                beforeSwap: false,
                afterSwap: false,
                beforeDonate: false,
                afterDonate: false,
                beforeSwapReturnDelta: false,
                afterSwapReturnDelta: false,
                afterAddLiquidityReturnDelta: false,
                afterRemoveLiquidityReturnDelta: false
            });
    }

    function modifyLiquidity(
        address user,
        PoolKey calldata key,
        IPoolManager.ModifyLiquidityParams calldata params
    ) external returns (bytes32) {
        poolManager.unlock(
            abi.encodeCall(this.unlockModifyPosition, (user, key, params))
        );

        return
            keccak256(
                abi.encodePacked(
                    user,
                    params.tickLower,
                    params.tickUpper,
                    params.liquidityDelta,
                    params.salt
                )
            );
    }

    /// @notice  Disable adding liquidity through the PM
    function beforeAddLiquidity(
        address,
        PoolKey calldata,
        IPoolManager.ModifyLiquidityParams calldata,
        bytes calldata
    ) external pure override returns (bytes4) {
        revert AddLiquidityThroughHook();
    }

    function unlockModifyPosition(
        address user,
        PoolKey calldata key,
        IPoolManager.ModifyLiquidityParams calldata params
    ) external selfOnly returns (bytes memory) {
        console.log("> unlockModifyPosition");

        (BalanceDelta delta, ) = poolManager.modifyLiquidity(
            key,
            params,
            ZERO_BYTES
        );

        // console.log("~ delta");
        // console.logInt(delta.amount0());
        // console.logInt(delta.amount1());

        if (delta.amount0() < 0) {
            key.currency0.settle(
                poolManager,
                address(this),
                uint256(uint128(-delta.amount0())),
                false
            );
        }

        if (delta.amount0() > 0) {
            key.currency0.take(
                poolManager,
                address(this),
                uint256(uint128(delta.amount0())),
                false
            );
        }

        if (delta.amount1() < 0) {
            key.currency1.settle(
                poolManager,
                address(this),
                uint256(uint128(-delta.amount1())),
                false
            );
        }

        if (delta.amount1() > 0) {
            key.currency1.take(
                poolManager,
                address(this),
                uint256(uint128(delta.amount1())),
                false
            );
        }

        bytes32 id = keccak256(
            abi.encodePacked(
                user,
                params.tickLower,
                params.tickUpper,
                params.liquidityDelta,
                params.salt
            )
        );

        // account for user here, maybe some NFT
        positionInfo[id] = PositionInfo({
            key: key,
            tickLower: params.tickLower,
            tickUpper: params.tickUpper,
            liquidity: params.liquidityDelta,
            lastUpdated: block.number
        });

        return ZERO_BYTES;
    }

    function isTimeRebalance(bytes32 positionId) public view returns (bool) {
        PositionInfo memory info = positionInfo[positionId];
        if (info.lastUpdated == 0) {
            return false;
        }
        // console.log(block.number);
        // console.log(info.lastUpdated);
        // console.log(block.number - info.lastUpdated);
        // console.log(distanceBetweenUpdates);
        if (block.number - info.lastUpdated < distanceBetweenUpdates) {
            return false;
        }
        return true;
    }

    function timeRebalance(bytes32 positionId) external {
        if (!isTimeRebalance(positionId)) revert NotEnoughTimePassed();

        // This could be done with less slippage and more effectively if some CoWs or matching engine is utilized on the AVS side

        PositionInfo memory info = positionInfo[positionId];
        {
            poolManager.unlock(
                abi.encodeCall(
                    this.unlockModifyPosition,
                    (
                        msg.sender,
                        info.key,
                        IPoolManager.ModifyLiquidityParams({
                            tickLower: info.tickLower,
                            tickUpper: info.tickUpper,
                            liquidityDelta: -info.liquidity,
                            salt: bytes32(ZERO_BYTES)
                        })
                    )
                )
            );
        }

        int24 tickLower = HookMathLib.tickRoundDown(
            HookMathLib.getTickFromPrice(
                (HookMathLib.getPriceFromTick(info.tickLower) *
                    priceScalingFactor) / 1e18
            ),
            info.key.tickSpacing
        );
        int24 tickUpper = HookMathLib.tickRoundDown(
            HookMathLib.getTickFromPrice(
                (HookMathLib.getPriceFromTick(info.tickUpper) *
                    priceScalingFactor) / 1e18
            ),
            info.key.tickSpacing
        );

        console.log("TickLower:");
        console.logInt(info.tickLower);
        console.logInt(tickLower);
        console.log("TickUpper:");
        console.logInt(info.tickUpper);
        console.logInt(tickUpper);

        // Here we should do some smart swaps to get the best price. In other pools bro.
        // Also we should recalculate liquidity based on the curve, but will do it in next versions.

        poolManager.unlock(
            abi.encodeCall(
                this.unlockModifyPosition,
                (
                    msg.sender,
                    info.key,
                    IPoolManager.ModifyLiquidityParams({
                        tickLower: tickLower,
                        tickUpper: tickUpper,
                        liquidityDelta: info.liquidity,
                        salt: bytes32(ZERO_BYTES)
                    })
                )
            )
        );

        positionInfo[positionId].lastUpdated = block.number;
        positionInfo[positionId].tickLower = tickLower;
        positionInfo[positionId].tickUpper = tickUpper;
        positionInfo[positionId].liquidity = info.liquidity;
    }

    function getPosition(
        bytes32 positionId
    ) public view returns (uint128, int24, int24) {
        PositionInfo memory info = positionInfo[positionId];

        // console.log("Position:");
        // console.logInt(info.liquidity);
        // console.logInt(info.tickLower);
        // console.logInt(info.tickUpper);

        Position.Info memory _positionInfo = StateLibrary.getPosition(
            poolManager,
            PoolIdLibrary.toId(info.key),
            address(this),
            info.tickLower,
            info.tickUpper,
            bytes32(ZERO_BYTES)
        );
        return (_positionInfo.liquidity, info.tickLower, info.tickUpper);
    }
}
