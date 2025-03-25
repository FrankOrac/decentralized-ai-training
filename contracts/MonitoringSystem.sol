// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";

contract MonitoringSystem is AccessControl, ReentrancyGuard {
    bytes32 public constant MONITOR_ROLE = keccak256("MONITOR_ROLE");

    struct Metric {
        string name;
        uint256[] values;
        uint256[] timestamps;
        uint256 lastValue;
        uint256 average;
        uint256 minimum;
        uint256 maximum;
        MetricType metricType;
    }

    struct Alert {
        bytes32 alertId;
        string metricName;
        uint256 threshold;
        AlertType alertType;
        bool isActive;
        uint256 lastTriggered;
        uint256 triggerCount;
    }

    struct HealthStatus {
        string component;
        bool isHealthy;
        uint256 lastCheck;
        uint256 uptime;
        uint256 downtime;
        uint256 lastIncident;
    }

    enum MetricType {
        Counter,
        Gauge,
        Histogram,
        Summary
    }

    enum AlertType {
        GreaterThan,
        LessThan,
        Deviation,
        RateOfChange
    }

    mapping(string => Metric) public metrics;
    mapping(bytes32 => Alert) public alerts;
    mapping(string => HealthStatus) public healthStatus;
    mapping(string => mapping(uint256 => uint256)) public historicalData;

    uint256 public constant MAX_HISTORY = 1000;
    uint256 public constant ALERT_COOLDOWN = 1 hours;
    uint256 public constant HEALTH_CHECK_INTERVAL = 5 minutes;

    event MetricUpdated(
        string indexed name,
        uint256 value,
        uint256 timestamp
    );
    event AlertTriggered(
        bytes32 indexed alertId,
        string metricName,
        uint256 value,
        uint256 threshold
    );
    event HealthStatusChanged(
        string indexed component,
        bool isHealthy,
        uint256 timestamp
    );
    event AnomalyDetected(
        string indexed metricName,
        uint256 value,
        uint256 expectedValue,
        uint256 deviation
    );

    constructor() {
        _setupRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _setupRole(MONITOR_ROLE, msg.sender);
    }

    function recordMetric(
        string memory _name,
        uint256 _value,
        MetricType _type
    ) external onlyRole(MONITOR_ROLE) {
        Metric storage metric = metrics[_name];
        
        if (metric.values.length == 0) {
            metric.name = _name;
            metric.metricType = _type;
            metric.minimum = _value;
            metric.maximum = _value;
        }

        metric.values.push(_value);
        metric.timestamps.push(block.timestamp);
        metric.lastValue = _value;

        // Update statistics
        metric.minimum = _value < metric.minimum ? _value : metric.minimum;
        metric.maximum = _value > metric.maximum ? _value : metric.maximum;
        metric.average = (metric.average * (metric.values.length - 1) + _value) / metric.values.length;

        // Maintain history limit
        if (metric.values.length > MAX_HISTORY) {
            for (uint i = 0; i < metric.values.length - 1; i++) {
                metric.values[i] = metric.values[i + 1];
                metric.timestamps[i] = metric.timestamps[i + 1];
            }
            metric.values.pop();
            metric.timestamps.pop();
        }

        // Store historical data
        uint256 timeframe = (block.timestamp / 1 days) * 1 days;
        historicalData[_name][timeframe] = _value;

        emit MetricUpdated(_name, _value, block.timestamp);
        checkAlerts(_name, _value);
        detectAnomalies(_name, _value);
    }

    function createAlert(
        string memory _metricName,
        uint256 _threshold,
        AlertType _alertType
    ) external onlyRole(MONITOR_ROLE) returns (bytes32) {
        bytes32 alertId = keccak256(abi.encodePacked(
            _metricName,
            _threshold,
            block.timestamp
        ));

        alerts[alertId] = Alert({
            alertId: alertId,
            metricName: _metricName,
            threshold: _threshold,
            alertType: _alertType,
            isActive: true,
            lastTriggered: 0,
            triggerCount: 0
        });

        return alertId;
    }

    function updateHealthStatus(
        string memory _component,
        bool _isHealthy
    ) external onlyRole(MONITOR_ROLE) {
        HealthStatus storage status = healthStatus[_component];
        
        if (status.lastCheck == 0) {
            status.component = _component;
        }

        uint256 timeDiff = block.timestamp - status.lastCheck;
        if (_isHealthy) {
            status.uptime += timeDiff;
        } else {
            status.downtime += timeDiff;
            status.lastIncident = block.timestamp;
        }

        status.isHealthy = _isHealthy;
        status.lastCheck = block.timestamp;

        emit HealthStatusChanged(_component, _isHealthy, block.timestamp);
    }

    function checkAlerts(string memory _metricName, uint256 _value) internal {
        Metric storage metric = metrics[_metricName];
        
        bytes32[] memory activeAlertIds = getActiveAlerts(_metricName);
        for (uint i = 0; i < activeAlertIds.length; i++) {
            Alert storage alert = alerts[activeAlertIds[i]];
            
            if (block.timestamp - alert.lastTriggered < ALERT_COOLDOWN) {
                continue;
            }

            bool shouldTrigger = false;
            if (alert.alertType == AlertType.GreaterThan) {
                shouldTrigger = _value > alert.threshold;
            } else if (alert.alertType == AlertType.LessThan) {
                shouldTrigger = _value < alert.threshold;
            } else if (alert.alertType == AlertType.Deviation) {
                uint256 deviation = calculateDeviation(_value, metric.average);
                shouldTrigger = deviation > alert.threshold;
            } else if (alert.alertType == AlertType.RateOfChange) {
                uint256 rateOfChange = calculateRateOfChange(_metricName);
                shouldTrigger = rateOfChange > alert.threshold;
            }

            if (shouldTrigger) {
                alert.lastTriggered = block.timestamp;
                alert.triggerCount++;
                emit AlertTriggered(alert.alertId, _metricName, _value, alert.threshold);
            }
        }
    }

    function detectAnomalies(string memory _metricName, uint256 _value) internal {
        Metric storage metric = metrics[_metricName];
        
        if (metric.values.length < 10) return;

        uint256 expectedValue = calculateExpectedValue(_metricName);
        uint256 deviation = calculateDeviation(_value, expectedValue);
        uint256 deviationThreshold = (expectedValue * 20) / 100; // 20% threshold

        if (deviation > deviationThreshold) {
            emit AnomalyDetected(_metricName, _value, expectedValue, deviation);
        }
    }

    function calculateExpectedValue(string memory _metricName)
        internal
        view
        returns (uint256)
    {
        Metric storage metric = metrics[_metricName];
        uint256 windowSize = 10;
        uint256 sum = 0;
        
        for (uint i = metric.values.length - windowSize; i < metric.values.length; i++) {
            sum += metric.values[i];
        }
        
        return sum / windowSize;
    }

    function calculateDeviation(uint256 _value, uint256 _reference)
        internal
        pure
        returns (uint256)
    {
        return _value > _reference ? 
            _value - _reference :
            _reference - _value;
    }

    function calculateRateOfChange(string memory _metricName)
        internal
        view
        returns (uint256)
    {
        Metric storage metric = metrics[_metricName];
        if (metric.values.length < 2) return 0;

        uint256 latest = metric.values[metric.values.length - 1];
        uint256 previous = metric.values[metric.values.length - 2];
        uint256 timeDiff = metric.timestamps[metric.timestamps.length - 1] - 
                          metric.timestamps[metric.timestamps.length - 2];

        return (latest > previous ? latest - previous : previous - latest) * 3600 / timeDiff;
    }

    function getActiveAlerts(string memory _metricName)
        internal
        view
        returns (bytes32[] memory)
    {
        uint256 count = 0;
        bytes32[] memory allAlertIds = new bytes32[](100); // Arbitrary limit

        for (uint i = 0; i < allAlertIds.length; i++) {
            Alert storage alert = alerts[allAlertIds[i]];
            if (alert.isActive && keccak256(bytes(alert.metricName)) == keccak256(bytes(_metricName))) {
                allAlertIds[count] = alert.alertId;
                count++;
            }
        }

        bytes32[] memory activeAlerts = new bytes32[](count);
        for (uint i = 0; i < count; i++) {
            activeAlerts[i] = allAlertIds[i];
        }

        return activeAlerts;
    }

    function getMetricStats(string memory _name)
        external
        view
        returns (
            uint256 lastValue,
            uint256 average,
            uint256 minimum,
            uint256 maximum,
            uint256[] memory values,
            uint256[] memory timestamps
        )
    {
        Metric storage metric = metrics[_name];
        return (
            metric.lastValue,
            metric.average,
            metric.minimum,
            metric.maximum,
            metric.values,
            metric.timestamps
        );
    }

    function getHealthStats(string memory _component)
        external
        view
        returns (
            bool isHealthy,
            uint256 lastCheck,
            uint256 uptime,
            uint256 downtime,
            uint256 lastIncident
        )
    {
        HealthStatus storage status = healthStatus[_component];
        return (
            status.isHealthy,
            status.lastCheck,
            status.uptime,
            status.downtime,
            status.lastIncident
        );
    }
} 