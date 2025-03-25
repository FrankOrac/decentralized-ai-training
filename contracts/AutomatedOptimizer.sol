// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";

contract AutomatedOptimizer is AccessControl, ReentrancyGuard {
    bytes32 public constant OPTIMIZER_ROLE = keccak256("OPTIMIZER_ROLE");

    struct OptimizationTask {
        string taskId;
        string modelHash;
        string[] hyperparameters;
        uint256[] parameterRanges;
        string targetMetric;
        uint256 targetValue;
        uint256 maxIterations;
        uint256 currentIteration;
        OptimizationStatus status;
        mapping(uint256 => IterationResult) results;
        uint256 bestMetricValue;
        uint256[] bestConfiguration;
        address creator;
        uint256 creationTime;
    }

    struct IterationResult {
        uint256[] configuration;
        uint256 metricValue;
        uint256 timestamp;
        address validator;
    }

    struct OptimizationStrategy {
        string name;
        string description;
        bool isActive;
        uint256 convergenceThreshold;
        uint256 explorationRate;
    }

    enum OptimizationStatus {
        Created,
        Running,
        Completed,
        Failed
    }

    mapping(string => OptimizationTask) public tasks;
    mapping(string => OptimizationStrategy) public strategies;
    mapping(address => uint256) public optimizerReputations;
    
    uint256 public minIterations;
    uint256 public maxIterations;
    uint256 public optimizationReward;

    event OptimizationTaskCreated(
        string indexed taskId,
        string modelHash,
        string targetMetric,
        uint256 targetValue
    );
    event IterationCompleted(
        string indexed taskId,
        uint256 iteration,
        uint256 metricValue
    );
    event OptimizationCompleted(
        string indexed taskId,
        uint256 bestMetricValue,
        uint256[] bestConfiguration
    );
    event StrategyUpdated(
        string indexed name,
        uint256 convergenceThreshold,
        uint256 explorationRate
    );

    constructor(
        uint256 _minIterations,
        uint256 _maxIterations,
        uint256 _optimizationReward
    ) {
        _setupRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _setupRole(OPTIMIZER_ROLE, msg.sender);
        
        minIterations = _minIterations;
        maxIterations = _maxIterations;
        optimizationReward = _optimizationReward;

        // Initialize default optimization strategy
        strategies["bayesian"] = OptimizationStrategy({
            name: "bayesian",
            description: "Bayesian Optimization",
            isActive: true,
            convergenceThreshold: 1,
            explorationRate: 20
        });
    }

    function createOptimizationTask(
        string memory _taskId,
        string memory _modelHash,
        string[] memory _hyperparameters,
        uint256[] memory _parameterRanges,
        string memory _targetMetric,
        uint256 _targetValue,
        uint256 _maxIterations
    ) external onlyRole(OPTIMIZER_ROLE) {
        require(_hyperparameters.length == _parameterRanges.length, "Parameter mismatch");
        require(_maxIterations <= maxIterations, "Exceeds max iterations");
        require(_maxIterations >= minIterations, "Below min iterations");

        OptimizationTask storage task = tasks[_taskId];
        task.taskId = _taskId;
        task.modelHash = _modelHash;
        task.hyperparameters = _hyperparameters;
        task.parameterRanges = _parameterRanges;
        task.targetMetric = _targetMetric;
        task.targetValue = _targetValue;
        task.maxIterations = _maxIterations;
        task.status = OptimizationStatus.Created;
        task.creator = msg.sender;
        task.creationTime = block.timestamp;

        emit OptimizationTaskCreated(_taskId, _modelHash, _targetMetric, _targetValue);
    }

    function submitIterationResult(
        string memory _taskId,
        uint256[] memory _configuration,
        uint256 _metricValue
    ) external nonReentrant {
        OptimizationTask storage task = tasks[_taskId];
        require(task.status == OptimizationStatus.Created || 
                task.status == OptimizationStatus.Running, "Invalid task status");
        require(task.currentIteration < task.maxIterations, "Max iterations reached");
        require(_configuration.length == task.hyperparameters.length, "Invalid configuration");

        task.status = OptimizationStatus.Running;
        uint256 currentIteration = task.currentIteration++;

        task.results[currentIteration] = IterationResult({
            configuration: _configuration,
            metricValue: _metricValue,
            timestamp: block.timestamp,
            validator: msg.sender
        });

        // Update best result if necessary
        if (_metricValue > task.bestMetricValue) {
            task.bestMetricValue = _metricValue;
            task.bestConfiguration = _configuration;
        }

        emit IterationCompleted(_taskId, currentIteration, _metricValue);

        // Check for completion
        if (task.currentIteration >= task.maxIterations || 
            task.bestMetricValue >= task.targetValue) {
            finalizeOptimization(_taskId);
        }

        // Reward optimizer
        payable(msg.sender).transfer(optimizationReward);
    }

    function finalizeOptimization(string memory _taskId) internal {
        OptimizationTask storage task = tasks[_taskId];
        task.status = OptimizationStatus.Completed;

        emit OptimizationCompleted(
            _taskId,
            task.bestMetricValue,
            task.bestConfiguration
        );
    }

    function suggestNextConfiguration(
        string memory _taskId,
        string memory _strategy
    ) external view returns (uint256[] memory) {
        OptimizationTask storage task = tasks[_taskId];
        require(task.status == OptimizationStatus.Running, "Task not running");
        require(strategies[_strategy].isActive, "Invalid strategy");

        // Implement strategy-specific logic
        if (keccak256(bytes(_strategy)) == keccak256(bytes("bayesian"))) {
            return suggestBayesianConfiguration(task);
        }

        revert("Unsupported strategy");
    }

    function suggestBayesianConfiguration(OptimizationTask storage _task)
        internal
        view
        returns (uint256[] memory)
    {
        uint256[] memory configuration = new uint256[](_task.hyperparameters.length);
        
        // Simplified Bayesian optimization logic
        for (uint i = 0; i < _task.hyperparameters.length; i++) {
            uint256 range = _task.parameterRanges[i];
            uint256 exploration = (range * strategies["bayesian"].explorationRate) / 100;
            
            if (_task.currentIteration > 0) {
                // Use best configuration as base
                configuration[i] = _task.bestConfiguration[i];
                // Add exploration factor
                if (configuration[i] + exploration <= range) {
                    configuration[i] += exploration;
                } else {
                    configuration[i] -= exploration;
                }
            } else {
                // Initial random configuration
                configuration[i] = uint256(keccak256(abi.encodePacked(
                    block.timestamp,
                    i
                ))) % range;
            }
        }

        return configuration;
    }

    function updateStrategy(
        string memory _name,
        string memory _description,
        uint256 _convergenceThreshold,
        uint256 _explorationRate
    ) external onlyRole(OPTIMIZER_ROLE) {
        strategies[_name] = OptimizationStrategy({
            name: _name,
            description: _description,
            isActive: true,
            convergenceThreshold: _convergenceThreshold,
            explorationRate: _explorationRate
        });

        emit StrategyUpdated(_name, _convergenceThreshold, _explorationRate);
    }

    function getTaskDetails(string memory _taskId)
        external
        view
        returns (
            string memory modelHash,
            string[] memory hyperparameters,
            uint256[] memory parameterRanges,
            string memory targetMetric,
            uint256 targetValue,
            uint256 currentIteration,
            OptimizationStatus status,
            uint256 bestMetricValue,
            uint256[] memory bestConfiguration
        )
    {
        OptimizationTask storage task = tasks[_taskId];
        return (
            task.modelHash,
            task.hyperparameters,
            task.parameterRanges,
            task.targetMetric,
            task.targetValue,
            task.currentIteration,
            task.status,
            task.bestMetricValue,
            task.bestConfiguration
        );
    }

    function getIterationResult(
        string memory _taskId,
        uint256 _iteration
    ) external view returns (
        uint256[] memory configuration,
        uint256 metricValue,
        uint256 timestamp,
        address validator
    ) {
        IterationResult storage result = tasks[_taskId].results[_iteration];
        return (
            result.configuration,
            result.metricValue,
            result.timestamp,
            result.validator
        );
    }
} 