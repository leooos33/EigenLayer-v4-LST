// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.9;

import "eigenlayer-contracts/src/contracts/libraries/BytesLib.sol";
import "./ILSTHookTaskManager.sol";
import "@eigenlayer-middleware/src/ServiceManagerBase.sol";

contract LSTHookServiceManager is ServiceManagerBase {
    using BytesLib for bytes;

    ILSTHookTaskManager public immutable LSTHookTaskManager;

    /// @notice when applied to a function, ensures that the function is only callable by the `registryCoordinator`.
    modifier onlyLSTHookTaskManager() {
        require(
            msg.sender == address(LSTHookTaskManager),
            "onlyLSTHookTaskManager: not from credible squaring task manager"
        );
        _;
    }

    constructor(
        IAVSDirectory _avsDirectory,
        IRegistryCoordinator _registryCoordinator,
        IStakeRegistry _stakeRegistry,
        ILSTHookTaskManager _LSTHookTaskManager
    ) ServiceManagerBase(_avsDirectory, _registryCoordinator, _stakeRegistry) {
        LSTHookTaskManager = _LSTHookTaskManager;
    }

    /// @notice Called in the event of challenge resolution, in order to forward a call to the Slasher, which 'freezes' the `operator`.
    /// @dev The Slasher contract is under active development and its interface expected to change.
    ///      We recommend writing slashing logic without integrating with the Slasher at this point in time.
    function freezeOperator(
        address operatorAddr
    ) external onlyLSTHookTaskManager {
        // slasher.freezeOperator(operatorAddr);
    }
}
