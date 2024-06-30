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

import {LSTHookTaskManager} from "@src/avs/LSTHookTaskManager.sol";
import {ILSTHookTaskManager} from "@src/avs/ILSTHookTaskManager.sol";
import {LSTHookServiceManager} from "@src/avs/LSTHookServiceManager.sol";
import {IRegistryCoordinator} from "@eigenlayer-middleware/src/interfaces/IRegistryCoordinator.sol";
import {IPauserRegistry} from "@eigenlayer-middleware/lib/eigenlayer-contracts/src/contracts/interfaces/IPauserRegistry.sol";
import {BLSMockAVSDeployer} from "@eigenlayer-middleware/test/utils/BLSMockAVSDeployer.sol";
import {TransparentUpgradeableProxy} from "@eigenlayer-middleware/lib/openzeppelin-contracts/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";

contract LSTHookTest is HookTestBase {
    using PoolIdLibrary for PoolId;
    using CurrencyLibrary for Currency;
    LSTHookServiceManager sm;
    LSTHookServiceManager smImplementation;
    LSTHookTaskManager tm;
    LSTHookTaskManager tmImplementation;
    BLSMockAVSDeployer avsDeployer;

    uint32 public constant TASK_RESPONSE_WINDOW_BLOCK = 30;
    address aggregator =
        address(uint160(uint256(keccak256(abi.encodePacked("aggregator")))));
    address generator =
        address(uint160(uint256(keccak256(abi.encodePacked("generator")))));

    function setUp() public {
        deployFreshManagerAndRouters();

        deploy_avs_magic();
        labelTokens();
        init_hook();
        create_and_approve_accounts();

        vm.prank(tm.owner());
        tm.setHook(address(hook));
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

    function test_CreateNewTask() public {
        vm.prank(generator);
        tm.createNewTask(0, generator);
        assertEq(tm.latestTaskNum(), 1);
    }

    function test_simulateWatchTowerEmptyCreateTasks() public {
        vm.prank(generator);

        tm.createRebalanceTask(positionId);
        assertEq(tm.latestTaskNum(), 0);
    }

    function test_simulateWatchTowerCreateTasks() public {
        test_deposit();

        vm.roll(block.number + 4 * 60 * 25);

        vm.prank(generator);
        tm.createRebalanceTask(positionId);
        assertEq(tm.latestTaskNum(), 1);
    }

    function test_swap_price_up_then_watchtower_rebalance() public {
        test_deposit();

        vm.roll(block.number + 4 * 60 * 25);

        vm.prank(generator);
        tm.createRebalanceTask(positionId);
        assertEq(tm.latestTaskNum(), 1);

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

    function deploy_avs_magic() internal {
        emit log("Setting up BLSMockAVSDeployer");
        avsDeployer = new BLSMockAVSDeployer();
        avsDeployer._setUpBLSMockAVSDeployer();
        emit log("BLSMockAVSDeployer set up");

        address registryCoordinator = address(
            avsDeployer.registryCoordinator()
        );
        address proxyAdmin = address(avsDeployer.proxyAdmin());
        address pauserRegistry = address(avsDeployer.pauserRegistry());
        address registryCoordinatorOwner = avsDeployer
            .registryCoordinatorOwner();

        emit log_named_address("Registry Coordinator", registryCoordinator);
        emit log_named_address("Proxy Admin", proxyAdmin);
        emit log_named_address("Pauser Registry", pauserRegistry);
        emit log_named_address(
            "Registry Coordinator Owner",
            registryCoordinatorOwner
        );

        emit log("Deploying LSTHookTaskManager implementation");
        tmImplementation = new LSTHookTaskManager(
            IRegistryCoordinator(registryCoordinator),
            TASK_RESPONSE_WINDOW_BLOCK
        );
        emit log("LSTHookTaskManager implementation deployed");

        // Third, upgrade the proxy contracts to use the correct implementation contracts and initialize them.
        emit log(
            "Deploying TransparentUpgradeableProxy for LSTHookTaskManager"
        );
        tm = LSTHookTaskManager(
            address(
                new TransparentUpgradeableProxy(
                    address(tmImplementation),
                    proxyAdmin,
                    abi.encodeWithSelector(
                        tm.initialize.selector,
                        pauserRegistry,
                        registryCoordinatorOwner,
                        aggregator,
                        generator
                    )
                )
            )
        );
        emit log("TransparentUpgradeableProxy for LSTHookTaskManager deployed");
    }
}
