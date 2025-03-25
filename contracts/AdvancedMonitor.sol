// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts/security/Pausable.sol";
import "@openzeppelin/contracts/utils/Counters.sol";

contract AdvancedMonitor is AccessControl, Pausable {
    using Counters for Counters.Counter;

    bytes32 public constant MONITOR_ROLE = keccak256("MONITOR_ROLE");
    
    struct MetricData {
        string metricName;
        uint256 value;
        uint256 timestamp;
        address reporter;
        MetricType metricType;
    }

    struct Alert {
        string metricName;
        uint256 threshold;
        uint256 currentValue;
        uint256 timestamp;
        AlertSeverity severity;
        bool isActive;
        string description;
    }

    struct HealthCheck {
        string component;
        bool isHealthy;
        uint256 lastCheck;
        string status;
        uint256 responseTime;
    }

    enum MetricType {
        PERFORMANCE,
        RESOURCE_USAGE,
        NETWORK,
        SECURITY
    }

    enum AlertSeverity {
        INFO,
        WARNING,
        CRITICAL
    }

    mapping(bytes32 => MetricData[]) private metrics;
    mapping(bytes32 => Alert[]) private alerts;
    mapping(string => HealthCheck) private healthChecks;
    mapping(bytes32 => mapping(uint256 => uint256)) private metricAggregates;

    Counters.Counter private alertCounter;
    uint256 public constant MAX_METRIC_HISTORY = 1000;
    uint256 public constant AGGREGATION_PERIOD = 3600; // 1 hour

    event MetricRecorded(string metricName, uint256 value, MetricType metricType);
    event AlertTriggered(uint256 alertId, string metricName, AlertSeverity severity);
    event HealthCheckUpdated(string component, bool isHealthy, string status);
    event AggregateUpdated(string metricName, uint256 timestamp, uint256 value);

    constructor() {
        _setupRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _setupRole(MONITOR_ROLE, msg.sender);
    }

    function recordMetric(
        string memory _metricName,
        uint256 _value,
        MetricType _metricType
    ) external onlyRole(MONITOR_ROLE) whenNotPaused {
        bytes32 metricKey = keccak256(abi.encodePacked(_metricName));
        
        MetricData memory newMetric = MetricData({
            metricName: _metricName,
            value: _value,
            timestamp: block.timestamp,
            reporter: msg.sender,
            metricType: _metricType
        });

        metrics[metricKey].push(newMetric);
        
        // Maintain history limit
        if (metrics[metricKey].length > MAX_METRIC_HISTORY) {
            // Remove oldest metric
            for (uint i = 0; i < metrics[metricKey].length - 1; i++) {
                metrics[metricKey][i] = metrics[metricKey][i + 1];
            }
            metrics[metricKey].pop();
        }

        // Update aggregates
        uint256 periodStart = (block.timestamp / AGGREGATION_PERIOD) * AGGREGATION_PERIOD;
        metricAggregates[metricKey][periodStart] += _value;

        emit MetricRecorded(_metricName, _value, _metricType);
        checkThresholds(_metricName, _value);
    }

    function createAlert(
        string memory _metricName,
        uint256 _threshold,
        AlertSeverity _severity,
        string memory _description
    ) external onlyRole(MONITOR_ROLE) {
        bytes32 metricKey = keccak256(abi.encodePacked(_metricName));
        
        Alert memory newAlert = Alert({
            metricName: _metricName,
            threshold: _threshold,
            currentValue: 0,
            timestamp: block.timestamp,
            severity: _severity,
            isActive: true,
            description: _description
        });

        alerts[metricKey].push(newAlert);
        alertCounter.increment();
    }

    function updateHealthCheck(
        string memory _component,
        bool _isHealthy,
        string memory _status,
        uint256 _responseTime
    ) external onlyRole(MONITOR_ROLE) {
        healthChecks[_component] = HealthCheck({
            component: _component,
            isHealthy: _isHealthy,
            lastCheck: block.timestamp,
            status: _status,
            responseTime: _responseTime
        });

        emit HealthCheckUpdated(_component, _isHealthy, _status);
    }

    function checkThresholds(string memory _metricName, uint256 _value) internal {
        bytes32 metricKey = keccak256(abi.encodePacked(_metricName));
        Alert[] storage metricAlerts = alerts[metricKey];

        for (uint i = 0; i < metricAlerts.length; i++) {
            if (metricAlerts[i].isActive && _value >= metricAlerts[i].threshold) {
                metricAlerts[i].currentValue = _value;
                metricAlerts[i].timestamp = block.timestamp;

                emit AlertTriggered(
                    alertCounter.current(),
                    _metricName,
                    metricAlerts[i].severity
                );
            }
        }
    }

    function getMetricHistory(string memory _metricName)
        external
        view
        returns (MetricData[] memory)
    {
        bytes32 metricKey = keccak256(abi.encodePacked(_metricName));
        return metrics[metricKey];
    }

    function getActiveAlerts()
        external
        view
        returns (Alert[] memory activeAlerts)
    {
        uint256 activeCount = 0;
        bytes32[] memory keys = new bytes32[](alertCounter.current());
        
        // Count active alerts
        for (uint i = 0; i < keys.length; i++) {
            Alert[] storage alertList = alerts[keys[i]];
            for (uint j = 0; j < alertList.length; j++) {
                if (alertList[j].isActive) {
                    activeCount++;
                }
            }
        }

        // Collect active alerts
        activeAlerts = new Alert[](activeCount);
        uint256 currentIndex = 0;
        
        for (uint i = 0; i < keys.length; i++) {
            Alert[] storage alertList = alerts[keys[i]];
            for (uint j = 0; j < alertList.length; j++) {
                if (alertList[j].isActive) {
                    activeAlerts[currentIndex] = alertList[j];
                    currentIndex++;
                }
            }
        }
    }

    function getComponentHealth(string memory _component)
        external
        view
        returns (HealthCheck memory)
    {
        return healthChecks[_component];
    }

    function getMetricAggregate(
        string memory _metricName,
        uint256 _periodStart
    ) external view returns (uint256) {
        bytes32 metricKey = keccak256(abi.encodePacked(_metricName));
        return metricAggregates[metricKey][_periodStart];
    }
} 