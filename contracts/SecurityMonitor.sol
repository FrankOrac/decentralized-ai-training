// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/security/Pausable.sol";
import "@chainlink/contracts/src/v0.8/interfaces/AggregatorV3Interface.sol";

contract SecurityMonitor is AccessControl, ReentrancyGuard, Pausable {
    bytes32 public constant SECURITY_ADMIN = keccak256("SECURITY_ADMIN");
    bytes32 public constant MONITOR_ROLE = keccak256("MONITOR_ROLE");

    struct SecurityThreshold {
        uint256 minTrustScore;
        uint256 maxLatency;
        uint256 minParticipation;
        uint256 consensusThreshold;
    }

    struct SecurityIncident {
        bytes32 id;
        uint256 timestamp;
        uint16 chainId;
        string incidentType;
        string description;
        uint256 severity;
        bool resolved;
        mapping(address => bool) validations;
        uint256 validationCount;
    }

    struct ChainHealth {
        uint256 lastUpdate;
        uint256 latency;
        uint256 participation;
        uint256 trustScore;
        bool isHealthy;
    }

    mapping(uint16 => SecurityThreshold) public chainThresholds;
    mapping(bytes32 => SecurityIncident) public incidents;
    mapping(uint16 => ChainHealth) public chainHealth;
    mapping(string => address) public securityOracles;
    
    uint256 public constant MIN_VALIDATIONS = 2;
    uint256 public immutable VALIDATION_TIMEOUT;

    event SecurityIncidentReported(
        bytes32 indexed incidentId,
        uint16 chainId,
        string incidentType,
        uint256 severity
    );
    event IncidentValidated(
        bytes32 indexed incidentId,
        address validator,
        bool validated
    );
    event IncidentResolved(bytes32 indexed incidentId);
    event ChainHealthUpdated(
        uint16 indexed chainId,
        bool isHealthy,
        uint256 trustScore
    );
    event ThresholdUpdated(
        uint16 indexed chainId,
        string thresholdType,
        uint256 newValue
    );

    constructor(uint256 validationTimeout) {
        _setupRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _setupRole(SECURITY_ADMIN, msg.sender);
        VALIDATION_TIMEOUT = validationTimeout;
    }

    function setSecurityThreshold(
        uint16 chainId,
        uint256 minTrustScore,
        uint256 maxLatency,
        uint256 minParticipation,
        uint256 consensusThreshold
    ) external onlyRole(SECURITY_ADMIN) {
        require(minTrustScore <= 100, "Invalid trust score");
        require(minParticipation <= 100, "Invalid participation");
        require(consensusThreshold <= 100, "Invalid consensus threshold");

        chainThresholds[chainId] = SecurityThreshold({
            minTrustScore: minTrustScore,
            maxLatency: maxLatency,
            minParticipation: minParticipation,
            consensusThreshold: consensusThreshold
        });

        emit ThresholdUpdated(chainId, "trustScore", minTrustScore);
        emit ThresholdUpdated(chainId, "latency", maxLatency);
        emit ThresholdUpdated(chainId, "participation", minParticipation);
        emit ThresholdUpdated(chainId, "consensus", consensusThreshold);
    }

    function reportSecurityIncident(
        uint16 chainId,
        string memory incidentType,
        string memory description,
        uint256 severity
    ) external onlyRole(MONITOR_ROLE) returns (bytes32) {
        require(severity <= 100, "Invalid severity");
        require(bytes(incidentType).length > 0, "Empty incident type");
        
        bytes32 incidentId = keccak256(
            abi.encodePacked(
                chainId,
                incidentType,
                block.timestamp,
                msg.sender
            )
        );

        SecurityIncident storage incident = incidents[incidentId];
        incident.id = incidentId;
        incident.timestamp = block.timestamp;
        incident.chainId = chainId;
        incident.incidentType = incidentType;
        incident.description = description;
        incident.severity = severity;
        incident.resolved = false;
        incident.validationCount = 0;

        emit SecurityIncidentReported(incidentId, chainId, incidentType, severity);
        
        if (severity >= 80) {
            _pause();
        }

        return incidentId;
    }

    function validateIncident(bytes32 incidentId, bool validate)
        external
        onlyRole(SECURITY_ADMIN)
    {
        SecurityIncident storage incident = incidents[incidentId];
        require(incident.id != bytes32(0), "Incident not found");
        require(
            !incident.validations[msg.sender],
            "Already validated"
        );
        require(
            block.timestamp <= incident.timestamp + VALIDATION_TIMEOUT,
            "Validation timeout"
        );

        incident.validations[msg.sender] = true;
        if (validate) {
            incident.validationCount++;
        }

        emit IncidentValidated(incidentId, msg.sender, validate);

        if (incident.validationCount >= MIN_VALIDATIONS) {
            _handleValidatedIncident(incident);
        }
    }

    function resolveIncident(bytes32 incidentId)
        external
        onlyRole(SECURITY_ADMIN)
    {
        SecurityIncident storage incident = incidents[incidentId];
        require(incident.id != bytes32(0), "Incident not found");
        require(!incident.resolved, "Already resolved");
        require(
            incident.validationCount >= MIN_VALIDATIONS,
            "Not enough validations"
        );

        incident.resolved = true;
        emit IncidentResolved(incidentId);

        if (paused()) {
            _unpause();
        }
    }

    function updateChainHealth(
        uint16 chainId,
        uint256 latency,
        uint256 participation,
        uint256 trustScore
    ) external onlyRole(MONITOR_ROLE) {
        require(trustScore <= 100, "Invalid trust score");
        require(participation <= 100, "Invalid participation");

        SecurityThreshold memory threshold = chainThresholds[chainId];
        bool isHealthy = 
            trustScore >= threshold.minTrustScore &&
            latency <= threshold.maxLatency &&
            participation >= threshold.minParticipation;

        chainHealth[chainId] = ChainHealth({
            lastUpdate: block.timestamp,
            latency: latency,
            participation: participation,
            trustScore: trustScore,
            isHealthy: isHealthy
        });

        emit ChainHealthUpdated(chainId, isHealthy, trustScore);

        if (!isHealthy) {
            reportSecurityIncident(
                chainId,
                "HEALTH_CHECK",
                "Chain health check failed",
                70
            );
        }
    }

    function _handleValidatedIncident(SecurityIncident storage incident)
        private
    {
        if (incident.severity >= 80 && !paused()) {
            _pause();
        }

        // Additional handling based on incident type
        if (keccak256(bytes(incident.incidentType)) == keccak256(bytes("CONSENSUS_FAILURE"))) {
            // Handle consensus failure
            _handleConsensusFailure(incident.chainId);
        } else if (keccak256(bytes(incident.incidentType)) == keccak256(bytes("SECURITY_BREACH"))) {
            // Handle security breach
            _handleSecurityBreach(incident.chainId);
        }
    }

    function _handleConsensusFailure(uint16 chainId) private {
        // Implementation specific to consensus failure
    }

    function _handleSecurityBreach(uint16 chainId) private {
        // Implementation specific to security breach
    }

    function getIncidentValidations(bytes32 incidentId, address validator)
        external
        view
        returns (bool)
    {
        return incidents[incidentId].validations[validator];
    }

    function isChainHealthy(uint16 chainId) external view returns (bool) {
        return chainHealth[chainId].isHealthy;
    }
} 