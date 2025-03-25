// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "./interfaces/ISecurityService.sol";

contract ExternalSecurityIntegration is AccessControl, ReentrancyGuard {
    bytes32 public constant INTEGRATION_MANAGER = keccak256("INTEGRATION_MANAGER");

    struct SecurityService {
        string name;
        address serviceContract;
        bool isActive;
        uint256 priority;
        mapping(string => bool) supportedOperations;
        uint256 lastCheck;
        uint256 checkInterval;
    }

    struct SecurityCheck {
        bytes32 id;
        string serviceType;
        bytes parameters;
        uint256 timestamp;
        bool isComplete;
        bytes result;
        uint256 score;
    }

    struct ServiceMetrics {
        uint256 totalChecks;
        uint256 successfulChecks;
        uint256 failedChecks;
        uint256 averageResponseTime;
        uint256 averageScore;
    }

    mapping(string => SecurityService) public services;
    mapping(bytes32 => SecurityCheck) public securityChecks;
    mapping(string => ServiceMetrics) public serviceMetrics;
    
    event ServiceConfigured(
        string indexed name,
        address serviceContract,
        uint256 priority
    );
    event SecurityCheckInitiated(
        bytes32 indexed checkId,
        string serviceType,
        bytes parameters
    );
    event SecurityCheckCompleted(
        bytes32 indexed checkId,
        bytes result,
        uint256 score
    );
    event ServiceMetricsUpdated(
        string indexed serviceName,
        uint256 successRate,
        uint256 averageScore
    );

    constructor() {
        _setupRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _setupRole(INTEGRATION_MANAGER, msg.sender);
    }

    function configureService(
        string memory name,
        address serviceContract,
        string[] memory operations,
        uint256 priority,
        uint256 checkInterval
    ) external onlyRole(INTEGRATION_MANAGER) {
        require(serviceContract != address(0), "Invalid service contract");
        require(checkInterval > 0, "Invalid check interval");

        SecurityService storage service = services[name];
        service.name = name;
        service.serviceContract = serviceContract;
        service.isActive = true;
        service.priority = priority;
        service.checkInterval = checkInterval;

        for (uint256 i = 0; i < operations.length; i++) {
            service.supportedOperations[operations[i]] = true;
        }

        emit ServiceConfigured(name, serviceContract, priority);
    }

    function initiateSecurityCheck(
        string memory serviceType,
        bytes memory parameters
    ) external onlyRole(INTEGRATION_MANAGER) returns (bytes32) {
        SecurityService storage service = services[serviceType];
        require(service.isActive, "Service not active");
        require(
            block.timestamp >= service.lastCheck + service.checkInterval,
            "Check interval not elapsed"
        );

        bytes32 checkId = keccak256(
            abi.encodePacked(
                serviceType,
                parameters,
                block.timestamp
            )
        );

        SecurityCheck storage check = securityChecks[checkId];
        check.id = checkId;
        check.serviceType = serviceType;
        check.parameters = parameters;
        check.timestamp = block.timestamp;

        service.lastCheck = block.timestamp;

        // Call external service
        ISecurityService(service.serviceContract).performSecurityCheck(
            checkId,
            parameters
        );

        emit SecurityCheckInitiated(checkId, serviceType, parameters);
        return checkId;
    }

    function completeSecurityCheck(
        bytes32 checkId,
        bytes memory result,
        uint256 score
    ) external {
        SecurityCheck storage check = securityChecks[checkId];
        require(check.id == checkId, "Check not found");
        require(!check.isComplete, "Check already completed");
        require(
            msg.sender == services[check.serviceType].serviceContract,
            "Unauthorized service"
        );

        check.isComplete = true;
        check.result = result;
        check.score = score;

        // Update service metrics
        ServiceMetrics storage metrics = serviceMetrics[check.serviceType];
        metrics.totalChecks++;
        metrics.successfulChecks++;
        metrics.averageResponseTime = (
            metrics.averageResponseTime * (metrics.successfulChecks - 1) +
            (block.timestamp - check.timestamp)
        ) / metrics.successfulChecks;
        metrics.averageScore = (
            metrics.averageScore * (metrics.successfulChecks - 1) + score
        ) / metrics.successfulChecks;

        emit SecurityCheckCompleted(checkId, result, score);
        emit ServiceMetricsUpdated(
            check.serviceType,
            (metrics.successfulChecks * 100) / metrics.totalChecks,
            metrics.averageScore
        );
    }

    function getServiceMetrics(string memory serviceType)
        external
        view
        returns (
            uint256 totalChecks,
            uint256 successRate,
            uint256 averageResponseTime,
            uint256 averageScore
        )
    {
        ServiceMetrics storage metrics = serviceMetrics[serviceType];
        return (
            metrics.totalChecks,
            metrics.totalChecks > 0 ?
                (metrics.successfulChecks * 100) / metrics.totalChecks : 0,
            metrics.averageResponseTime,
            metrics.averageScore
        );
    }

    function isOperationSupported(
        string memory serviceType,
        string memory operation
    ) external view returns (bool) {
        return services[serviceType].supportedOperations[operation];
    }
} 