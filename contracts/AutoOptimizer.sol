// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";

contract AutoOptimizer is AccessControl, ReentrancyGuard {
    struct OptimizationTask {
        string modelHash;
        string hyperparameters;
        uint256 targetMetric;
        uint256 currentBestMetric;
        string bestConfig;
        uint256 iterationsCompleted;
        uint256 maxIterations;
        OptimizationStatus status;
        mapping(uint256 => IterationResult) results;
    }

    struct IterationResult {
        string configHash;
        uint256 metric;
        string resultHash;
        uint256 timestamp;
    }

    enum OptimizationStatus {
        Pending,
        Running,
        Completed,
        Failed
    }

    mapping(uint256 => OptimizationTask) public tasks;
    mapping(string => string[]) public modelOptimizationHistory;
    uint256 public taskCount;

    event OptimizationTaskCreated(uint256 indexed taskId, string modelHash);
    event IterationCompleted(uint256 indexed taskId, uint256 iteration, uint256 metric);
    event OptimizationCompleted(uint256 indexed taskId, string bestConfig);

    constructor() {
        _setupRole(DEFAULT_ADMIN_ROLE, msg.sender);
    }

    function createOptimizationTask(
        string memory _modelHash,
        string memory _hyperparameters,
        uint256 _targetMetric,
        uint256 _maxIterations
    ) external returns (uint256) {
        taskCount++;
        OptimizationTask storage task = tasks[taskCount];
        task.modelHash = _modelHash;
        task.hyperparameters = _hyperparameters;
        task.targetMetric = _targetMetric;
        task.maxIterations = _maxIterations;
        task.status = OptimizationStatus.Pending;

        emit OptimizationTaskCreated(taskCount, _modelHash);
        return taskCount;
    }

    function submitIterationResult(
        uint256 _taskId,
        uint256 _iteration,
        string memory _configHash,
        uint256 _metric,
        string memory _resultHash
    ) external nonReentrant {
        require(_taskId <= taskCount, "Invalid task ID");
        OptimizationTask storage task = tasks[_taskId];
        require(task.status == OptimizationStatus.Running, "Task not running");
        require(_iteration <= task.maxIterations, "Invalid iteration");

        task.results[_iteration] = IterationResult({
            configHash: _configHash,
            metric: _metric,
            resultHash: _resultHash,
            timestamp: block.timestamp
        });

        if (_metric > task.currentBestMetric) {
            task.currentBestMetric = _metric;
            task.bestConfig = _configHash;
        }

        task.iterationsCompleted++;
        emit IterationCompleted(_taskId, _iteration, _metric);

        if (task.iterationsCompleted >= task.maxIterations ||
            _metric >= task.targetMetric) {
            completeOptimization(_taskId);
        }
    }

    function completeOptimization(uint256 _taskId) internal {
        OptimizationTask storage task = tasks[_taskId];
        task.status = OptimizationStatus.Completed;
        modelOptimizationHistory[task.modelHash].push(task.bestConfig);
        emit OptimizationCompleted(_taskId, task.bestConfig);
    }

    function getOptimizationResults(uint256 _taskId, uint256 _iteration)
        external view returns (IterationResult memory)
    {
        return tasks[_taskId].results[_iteration];
    }

    function getOptimizationHistory(string memory _modelHash)
        external view returns (string[] memory)
    {
        return modelOptimizationHistory[_modelHash];
    }
} 