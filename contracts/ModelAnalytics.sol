// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";

contract ModelAnalytics is AccessControl, ReentrancyGuard {
    struct ModelMetrics {
        uint256 accuracy;
        uint256 latency;
        uint256 resourceUsage;
        uint256 convergenceRate;
        uint256 lastUpdated;
    }

    struct PerformanceHistory {
        uint256 timestamp;
        uint256 metric;
        string details;
    }

    mapping(string => ModelMetrics) public modelMetrics;
    mapping(string => PerformanceHistory[]) public performanceHistory;
    mapping(string => mapping(string => uint256)) public customMetrics;

    event MetricsUpdated(string indexed modelHash, uint256 timestamp);
    event CustomMetricAdded(string indexed modelHash, string metricName, uint256 value);

    constructor() {
        _setupRole(DEFAULT_ADMIN_ROLE, msg.sender);
    }

    function updateModelMetrics(
        string memory _modelHash,
        uint256 _accuracy,
        uint256 _latency,
        uint256 _resourceUsage,
        uint256 _convergenceRate
    ) external {
        ModelMetrics storage metrics = modelMetrics[_modelHash];
        metrics.accuracy = _accuracy;
        metrics.latency = _latency;
        metrics.resourceUsage = _resourceUsage;
        metrics.convergenceRate = _convergenceRate;
        metrics.lastUpdated = block.timestamp;

        performanceHistory[_modelHash].push(PerformanceHistory({
            timestamp: block.timestamp,
            metric: _accuracy,
            details: "Accuracy update"
        }));

        emit MetricsUpdated(_modelHash, block.timestamp);
    }

    function addCustomMetric(
        string memory _modelHash,
        string memory _metricName,
        uint256 _value
    ) external {
        customMetrics[_modelHash][_metricName] = _value;
        emit CustomMetricAdded(_modelHash, _metricName, _value);
    }

    function getModelPerformanceHistory(string memory _modelHash)
        external view returns (PerformanceHistory[] memory)
    {
        return performanceHistory[_modelHash];
    }

    function getModelMetrics(string memory _modelHash)
        external view returns (ModelMetrics memory)
    {
        return modelMetrics[_modelHash];
    }

    function getCustomMetric(
        string memory _modelHash,
        string memory _metricName
    ) external view returns (uint256) {
        return customMetrics[_modelHash][_metricName];
    }

    function calculatePerformanceScore(string memory _modelHash)
        external view returns (uint256)
    {
        ModelMetrics storage metrics = modelMetrics[_modelHash];
        
        // Weight factors for different metrics
        uint256 accuracyWeight = 40;
        uint256 latencyWeight = 25;
        uint256 resourceWeight = 20;
        uint256 convergenceWeight = 15;

        // Calculate weighted score (out of 100)
        uint256 score = (
            (metrics.accuracy * accuracyWeight) +
            (metrics.latency * latencyWeight) +
            (metrics.resourceUsage * resourceWeight) +
            (metrics.convergenceRate * convergenceWeight)
        ) / 100;

        return score;
    }
} 