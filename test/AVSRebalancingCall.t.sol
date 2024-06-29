// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {Test} from "forge-std/Test.sol";

import {Deployers} from "@uniswap/v4-core/test/utils/Deployers.sol";
import {PoolSwapTest} from "v4-core/test/PoolSwapTest.sol";
import {MockERC20} from "solmate/test/utils/mocks/MockERC20.sol";

import {PoolManager} from "v4-core/PoolManager.sol";
import {IPoolManager} from "v4-core/interfaces/IPoolManager.sol";

import {Currency, CurrencyLibrary} from "v4-core/types/Currency.sol";

import {Hooks} from "v4-core/libraries/Hooks.sol";
import {TickMath} from "v4-core/libraries/TickMath.sol";
import {BalanceDelta, BalanceDeltaLibrary, toBalanceDelta} from "v4-core/types/BalanceDelta.sol";
import {BeforeSwapDelta} from "v4-core/types/BeforeSwapDelta.sol";

import {OptionRebalancingTaskManager} from "@src/avs/OptionRebalancingTaskManager.sol";
import {IOptionRebalancingTaskManager} from "@src/avs/IOptionRebalancingTaskManager.sol";
import {OptionRebalancingServiceManager} from "@src/avs/OptionRebalancingServiceManager.sol";
import {IRegistryCoordinator} from "@eigenlayer-middleware/src/interfaces/IRegistryCoordinator.sol";
import {IPauserRegistry} from "@eigenlayer-middleware/lib/eigenlayer-contracts/src/contracts/interfaces/IPauserRegistry.sol";
import {BLSMockAVSDeployer} from "@eigenlayer-middleware/test/utils/BLSMockAVSDeployer.sol";
import {TransparentUpgradeableProxy} from "@eigenlayer-middleware/lib/openzeppelin-contracts/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";

contract TestAVSRebalancingCall is Test, Deployers {
    OptionRebalancingServiceManager sm;
    OptionRebalancingServiceManager smImplementation;
    OptionRebalancingTaskManager tm;
    OptionRebalancingTaskManager tmImplementation;
    BLSMockAVSDeployer avsDeployer;

    uint32 public constant TASK_RESPONSE_WINDOW_BLOCK = 30;
    address aggregator =
        address(uint160(uint256(keccak256(abi.encodePacked("aggregator")))));
    address generator =
        address(uint160(uint256(keccak256(abi.encodePacked("generator")))));

    using CurrencyLibrary for Currency;
    using BalanceDeltaLibrary for BalanceDelta;

    MockERC20 token; // our token to use in the ETH-TOKEN pool

    // Native tokens are represented by address(0)
    Currency ethCurrency = Currency.wrap(address(0));
    Currency tokenCurrency;

    // MevAuctionHook hook;
    IPoolManager poolManager; // Declare poolManager

    uint160 constant SQRT_RATIO_1_1 = 79228162514264337593543950336;

    function setUp() public {
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

        emit log("Deploying OptionRebalancingTaskManager implementation");
        tmImplementation = new OptionRebalancingTaskManager(
            IRegistryCoordinator(registryCoordinator),
            TASK_RESPONSE_WINDOW_BLOCK
        );
        emit log("OptionRebalancingTaskManager implementation deployed");

        // Third, upgrade the proxy contracts to use the correct implementation contracts and initialize them.
        emit log(
            "Deploying TransparentUpgradeableProxy for OptionRebalancingTaskManager"
        );
        tm = OptionRebalancingTaskManager(
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
        emit log(
            "TransparentUpgradeableProxy for OptionRebalancingTaskManager deployed"
        );
    }

    function testCreateNewTask() public {
        vm.prank(generator);
        tm.createNewTask(0);
        assertEq(tm.latestTaskNum(), 1);
    }
}
