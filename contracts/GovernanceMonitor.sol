// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";

contract GovernanceMonitor is AccessControl, ReentrancyGuard {
    bytes32 public constant MONITOR_ROLE = keccak256("MONITOR_ROLE");
    bytes32 public constant ALERT_MANAGER_ROLE = keccak256("ALERT_MANAGER_ROLE");

    struct Alert {
        uint256 id;
        string alertType;
        string description;
        uint256 severity; // 1: Low, 2: Medium, 3: High
        uint256 timestamp;
        bool isActive;
        address reporter;
    }

    struct MonitoringRule {
        uint256 id;
        string name;
        string condition;
        uint256 threshold;
        uint256 severity;
        bool isActive;
    }

    struct HealthCheck {
        uint256 lastCheck;
        bool isHealthy;
        string status;
        uint256 errorCount;
    }

    mapping(uint256 => Alert) public alerts;
    mapping(uint256 => MonitoringRule) public rules;
    mapping(string => HealthCheck) public healthChecks;
    
    uint256 public alertCount;
    uint256 public ruleCount;
    uint256 public constant MAX_ALERTS = 1000;
    uint256 public constant HEALTH_CHECK_INTERVAL = 1 hours;

    event AlertCreated(
        uint256 indexed alertId,
        string alertType,
        uint256 severity,
        string description
    );
    event AlertResolved(uint256 indexed alertId);
    event RuleCreated(uint256 indexed ruleId, string name);
    event RuleUpdated(uint256 indexed ruleId, bool isActive);
    event HealthCheckUpdated(string component, bool isHealthy, string status);

    constructor() {
        _setupRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _setupRole(MONITOR_ROLE, msg.sender);
        _setupRole(ALERT_MANAGER_ROLE, msg.sender);
    }

    function createAlert(
        string memory alertType,
        string memory description,
        uint256 severity
    ) external onlyRole(MONITOR_ROLE) returns (uint256) {
        require(severity >= 1 && severity <= 3, "Invalid severity level");
        require(alertCount < MAX_ALERTS, "Alert limit reached");

        alertCount++;
        alerts[alertCount] = Alert({
            id: alertCount,
            alertType: alertType,
            description: description,
            severity: severity,
            timestamp: block.timestamp,
            isActive: true,
            reporter: msg.sender
        });

        emit AlertCreated(alertCount, alertType, severity, description);
        return alertCount;
    }

    function resolveAlert(uint256 alertId) external onlyRole(ALERT_MANAGER_ROLE) {
        require(alerts[alertId].isActive, "Alert already resolved");
        alerts[alertId].isActive = false;
        emit AlertResolved(alertId);
    }

    function createMonitoringRule(
        string memory name,
        string memory condition,
        uint256 threshold,
        uint256 severity
    ) external onlyRole(ALERT_MANAGER_ROLE) returns (uint256) {
        require(severity >= 1 && severity <= 3, "Invalid severity level");

        ruleCount++;
        rules[ruleCount] = MonitoringRule({
            id: ruleCount,
            name: name,
            condition: condition,
            threshold: threshold,
            severity: severity,
            isActive: true
        });

        emit RuleCreated(ruleCount, name);
        return ruleCount;
    }

    function updateRule(uint256 ruleId, bool isActive) external onlyRole(ALERT_MANAGER_ROLE) {
        require(rules[ruleId].id != 0, "Rule does not exist");
        rules[ruleId].isActive = isActive;
        emit RuleUpdated(ruleId, isActive);
    }

    function updateHealthCheck(
        string memory component,
        bool isHealthy,
        string memory status
    ) external onlyRole(MONITOR_ROLE) {
        require(bytes(component).length > 0, "Invalid component");
        
        HealthCheck storage check = healthChecks[component];
        check.lastCheck = block.timestamp;
        check.isHealthy = isHealthy;
        check.status = status;
        
        if (!isHealthy) {
            check.errorCount++;
            if (check.errorCount >= 3) {
                createAlert(
                    "HEALTH_CHECK_FAILURE",
                    string(abi.encodePacked("Component ", component, " health check failed")),
                    2
                );
            }
        } else {
            check.errorCount = 0;
        }

        emit HealthCheckUpdated(component, isHealthy, status);
    }

    function getActiveAlerts() external view returns (Alert[] memory) {
        uint256 activeCount = 0;
        for (uint256 i = 1; i <= alertCount; i++) {
            if (alerts[i].isActive) {
                activeCount++;
            }
        }

        Alert[] memory activeAlerts = new Alert[](activeCount);
        uint256 index = 0;
        for (uint256 i = 1; i <= alertCount; i++) {
            if (alerts[i].isActive) {
                activeAlerts[index] = alerts[i];
                index++;
            }
        }

        return activeAlerts;
    }

    function getActiveRules() external view returns (MonitoringRule[] memory) {
        uint256 activeCount = 0;
        for (uint256 i = 1; i <= ruleCount; i++) {
            if (rules[i].isActive) {
                activeCount++;
            }
        }

        MonitoringRule[] memory activeRules = new MonitoringRule[](activeCount);
        uint256 index = 0;
        for (uint256 i = 1; i <= ruleCount; i++) {
            if (rules[i].isActive) {
                activeRules[index] = rules[i];
                index++;
            }
        }

        return activeRules;
    }

    function checkComponentHealth(string memory component) external view returns (bool) {
        HealthCheck storage check = healthChecks[component];
        if (check.lastCheck == 0) return false;
        
        return check.isHealthy && 
               block.timestamp <= check.lastCheck + HEALTH_CHECK_INTERVAL;
    }
} 