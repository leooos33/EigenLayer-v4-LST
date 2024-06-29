// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.9;

import "eigenlayer-contracts/src/contracts/libraries/BytesLib.sol";
import "./IMatchingHookTaskManager.sol";
import "@eigenlayer-middleware/src/ServiceManagerBase.sol";

contract MatchingHookServiceManager is ServiceManagerBase {
    using BytesLib for bytes;

    IMatchingHookTaskManager public immutable MatchingHookTaskManager;

    /// @notice when applied to a function, ensures that the function is only callable by the `registryCoordinator`.
    modifier onlyMatchingHookTaskManager() {
        require(
            msg.sender == address(MatchingHookTaskManager),
            "onlyMatchingHookTaskManager: not from credible squaring task manager"
        );
        _;
    }

    constructor(
        IAVSDirectory _avsDirectory,
        IRegistryCoordinator _registryCoordinator,
        IStakeRegistry _stakeRegistry,
        IMatchingHookTaskManager _MatchingHookTaskManager
    ) ServiceManagerBase(_avsDirectory, _registryCoordinator, _stakeRegistry) {
        MatchingHookTaskManager = _MatchingHookTaskManager;
    }

    /// @notice Called in the event of challenge resolution, in order to forward a call to the Slasher, which 'freezes' the `operator`.
    /// @dev The Slasher contract is under active development and its interface expected to change.
    ///      We recommend writing slashing logic without integrating with the Slasher at this point in time.
    function freezeOperator(
        address operatorAddr
    ) external onlyMatchingHookTaskManager {
        // slasher.freezeOperator(operatorAddr);
    }
}
