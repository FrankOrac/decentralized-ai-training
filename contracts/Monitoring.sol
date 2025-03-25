// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";

contract Monitoring is AccessControl, ReentrancyGuard {
    struct MetricPoint {
        uint256 timestamp;
        uint256 value;
        string metadata;
    }

    struct Alert {
        string metricName;
        uint256 threshold;
        uint256 windowSize;
        address notificationAddress;
        bool isActive;
    }

    mapping(string => MetricPoint[]) public metrics;
    mapping(string => uint256[]) public metricWindows;
    mapping(string => Alert) public alerts;
    mapping(address => string[]) public userAlerts;

    event MetricRecorded(string indexed name, uint256 value, uint256 timestamp);
    event AlertTriggered(string indexed metricName, uint256 value, uint256 threshold);
    event AlertCreated(string indexed metricName, address creator);

    constructor() {
        _setupRole(DEFAULT_ADMIN_ROLE, msg.sender);
    }

    function recordMetric(
        string memory _name,
        uint256 _value,
        string memory _metadata
    ) external {
        MetricPoint memory point = MetricPoint({
            timestamp: block.timestamp,
            value: _value,
            metadata: _metadata
        });

        metrics[_name].push(point);
        updateMetricWindow(_name, _value);
        checkAlerts(_name, _value);

        emit MetricRecorded(_name, _value, block.timestamp);
    }

    function updateMetricWindow(string memory _name, uint256 _value) internal {
        metricWindows[_name].push(_value);
        
        // Keep only last 100 values
        if (metricWindows[_name].length > 100) {
            uint256[] storage window = metricWindows[_name];
            for (uint i = 0; i < window.length - 1; i++) {
                window[i] = window[i + 1];
            }
            window.pop();
        }
    }

    function createAlert(
        string memory _metricName,
        uint256 _threshold,
        uint256 _windowSize,
        address _notificationAddress
    ) external {
        require(_windowSize > 0, "Invalid window size");
        require(_notificationAddress != address(0), "Invalid notification address");

        alerts[_metricName] = Alert({
            metricName: _metricName,
            threshold: _threshold,
            windowSize: _windowSize,
            notificationAddress: _notificationAddress,
            isActive: true
        });

        userAlerts[msg.sender].push(_metricName);
        emit AlertCreated(_metricName, msg.sender);
    }

    function checkAlerts(string memory _metricName, uint256 _value) internal {
        Alert storage alert = alerts[_metricName];
        if (!alert.isActive) return;

        if (_value >= alert.threshold) {
            emit AlertTriggered(_metricName, _value, alert.threshold);
            // Implement notification logic here
        }
    }

    function getMetricHistory(
        string memory _name,
        uint256 _count
    ) external view returns (MetricPoint[] memory) {
        MetricPoint[] storage allPoints = metrics[_name];
        uint256 count = _count > allPoints.length ? allPoints.length : _count;
        
        MetricPoint[] memory result = new MetricPoint[](count);
        for (uint256 i = 0; i < count; i++) {
            result[i] = allPoints[allPoints.length - count + i];
        }
        
        return result;
    }

    function getMetricStatistics(string memory _name)
        external view returns (
            uint256 min,
            uint256 max,
            uint256 avg
        )
    {
        uint256[] storage window = metricWindows[_name];
        require(window.length > 0, "No data points");

        min = type(uint256).max;
        max = 0;
        uint256 sum = 0;

        for (uint256 i = 0; i < window.length; i++) {
            if (window[i] < min) min = window[i];
            if (window[i] > max) max = window[i];
            sum += window[i];
        }

        avg = sum / window.length;
        return (min, max, avg);
    }
} 