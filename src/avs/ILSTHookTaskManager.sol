// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.9;

import "@eigenlayer-middleware/src/libraries/BN254.sol";

interface ILSTHookTaskManager {
    // EVENTS
    event NewTaskCreated(uint32 indexed taskIndex, bytes32 positionId);
    event TaskResponded(
        TaskResponse taskResponse,
        TaskResponseMetadata taskResponseMetadata
    );
    event TaskCompleted(uint32 indexed taskIndex);

    struct Task {
        bytes32 positionId;
        address firstResponder;
        uint256 created;
    }
    struct TaskResponse {
        uint32 referenceTaskIndex;
        bytes32 positionId;
    }
    struct TaskResponseMetadata {
        bytes32 positionId;
        uint256 timestamp;
    }

    // FUNCTIONS
    function createNewTask(bytes32 positionId, address firstResponder) external;

    function taskNumber() external view returns (uint32);
}
