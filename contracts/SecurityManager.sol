// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/security/Pausable.sol";
import "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";

contract SecurityManager is AccessControl, ReentrancyGuard, Pausable {
    using ECDSA for bytes32;

    bytes32 public constant GUARDIAN_ROLE = keccak256("GUARDIAN_ROLE");
    bytes32 public constant OPERATOR_ROLE = keccak256("OPERATOR_ROLE");

    struct SecurityConfig {
        uint256 maxTransactionValue;
        uint256 dailyLimit;
        uint256 cooldownPeriod;
        uint256 requiredConfirmations;
        bool requireGuardianApproval;
    }

    struct GuardianKey {
        address guardian;
        uint256 lastRotation;
        bool isActive;
    }

    struct SecurityIncident {
        uint256 id;
        string incidentType;
        string description;
        uint256 timestamp;
        address reporter;
        bool isResolved;
        mapping(address => bool) guardianApprovals;
        uint256 approvalCount;
    }

    mapping(bytes32 => SecurityConfig) public securityConfigs;
    mapping(address => GuardianKey) public guardianKeys;
    mapping(uint256 => SecurityIncident) public incidents;
    mapping(address => uint256) public dailyTransactions;
    mapping(address => uint256) public lastTransactionTime;
    
    uint256 public incidentCount;
    uint256 public constant KEY_ROTATION_PERIOD = 30 days;
    uint256 public constant INCIDENT_RESOLUTION_TIMEOUT = 24 hours;

    event SecurityConfigUpdated(
        bytes32 indexed configType,
        SecurityConfig config
    );
    event GuardianKeyRotated(
        address indexed guardian,
        uint256 timestamp
    );
    event SecurityIncidentReported(
        uint256 indexed incidentId,
        string incidentType,
        address indexed reporter
    );
    event IncidentResolved(
        uint256 indexed incidentId,
        uint256 timestamp
    );
    event EmergencyShutdown(
        address indexed initiator,
        string reason
    );

    constructor() {
        _setupRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _setupRole(GUARDIAN_ROLE, msg.sender);
        _setupRole(OPERATOR_ROLE, msg.sender);

        // Initialize default security config
        SecurityConfig memory defaultConfig = SecurityConfig({
            maxTransactionValue: 100 ether,
            dailyLimit: 1000 ether,
            cooldownPeriod: 1 hours,
            requiredConfirmations: 2,
            requireGuardianApproval: true
        });
        
        securityConfigs[keccak256("DEFAULT")] = defaultConfig;
    }

    function updateSecurityConfig(
        bytes32 configType,
        SecurityConfig memory newConfig
    ) external onlyRole(GUARDIAN_ROLE) {
        require(newConfig.maxTransactionValue > 0, "Invalid max transaction value");
        require(newConfig.dailyLimit > 0, "Invalid daily limit");
        securityConfigs[configType] = newConfig;
        emit SecurityConfigUpdated(configType, newConfig);
    }

    function rotateGuardianKey(
        address newGuardian
    ) external onlyRole(GUARDIAN_ROLE) {
        require(newGuardian != address(0), "Invalid guardian address");
        require(
            block.timestamp >= guardianKeys[msg.sender].lastRotation + KEY_ROTATION_PERIOD,
            "Too early for rotation"
        );

        guardianKeys[msg.sender].isActive = false;
        guardianKeys[newGuardian] = GuardianKey({
            guardian: newGuardian,
            lastRotation: block.timestamp,
            isActive: true
        });

        revokeRole(GUARDIAN_ROLE, msg.sender);
        grantRole(GUARDIAN_ROLE, newGuardian);

        emit GuardianKeyRotated(newGuardian, block.timestamp);
    }

    function reportSecurityIncident(
        string memory incidentType,
        string memory description
    ) external nonReentrant returns (uint256) {
        require(
            hasRole(GUARDIAN_ROLE, msg.sender) || hasRole(OPERATOR_ROLE, msg.sender),
            "Not authorized"
        );

        incidentCount++;
        SecurityIncident storage incident = incidents[incidentCount];
        incident.id = incidentCount;
        incident.incidentType = incidentType;
        incident.description = description;
        incident.timestamp = block.timestamp;
        incident.reporter = msg.sender;
        incident.isResolved = false;
        incident.approvalCount = 0;

        emit SecurityIncidentReported(incidentCount, incidentType, msg.sender);

        // Automatically pause if high severity incident
        if (keccak256(bytes(incidentType)) == keccak256(bytes("HIGH_SEVERITY"))) {
            _pause();
            emit EmergencyShutdown(msg.sender, description);
        }

        return incidentCount;
    }

    function approveIncidentResolution(
        uint256 incidentId
    ) external onlyRole(GUARDIAN_ROLE) {
        SecurityIncident storage incident = incidents[incidentId];
        require(!incident.isResolved, "Incident already resolved");
        require(!incident.guardianApprovals[msg.sender], "Already approved");

        incident.guardianApprovals[msg.sender] = true;
        incident.approvalCount++;

        SecurityConfig memory config = securityConfigs[keccak256("DEFAULT")];
        if (incident.approvalCount >= config.requiredConfirmations) {
            incident.isResolved = true;
            emit IncidentResolved(incidentId, block.timestamp);

            // Automatically unpause if system was paused
            if (paused()) {
                _unpause();
            }
        }
    }

    function validateTransaction(
        address sender,
        uint256 value
    ) external view returns (bool) {
        SecurityConfig memory config = securityConfigs[keccak256("DEFAULT")];
        
        require(value <= config.maxTransactionValue, "Transaction value too high");
        require(
            dailyTransactions[sender] + value <= config.dailyLimit,
            "Daily limit exceeded"
        );
        require(
            block.timestamp >= lastTransactionTime[sender] + config.cooldownPeriod,
            "Cooldown period not elapsed"
        );

        return true;
    }

    function recordTransaction(
        address sender,
        uint256 value
    ) external onlyRole(OPERATOR_ROLE) {
        uint256 currentDay = block.timestamp / 1 days;
        uint256 lastDay = lastTransactionTime[sender] / 1 days;

        if (currentDay > lastDay) {
            dailyTransactions[sender] = 0;
        }

        dailyTransactions[sender] += value;
        lastTransactionTime[sender] = block.timestamp;
    }

    function getIncidentApprovals(
        uint256 incidentId
    ) external view returns (uint256) {
        return incidents[incidentId].approvalCount;
    }

    function isGuardianKeyValid(
        address guardian
    ) external view returns (bool) {
        return guardianKeys[guardian].isActive &&
               block.timestamp < guardianKeys[guardian].lastRotation + KEY_ROTATION_PERIOD;
    }

    function emergencyShutdown(
        string memory reason
    ) external onlyRole(GUARDIAN_ROLE) {
        _pause();
        emit EmergencyShutdown(msg.sender, reason);
    }
} 