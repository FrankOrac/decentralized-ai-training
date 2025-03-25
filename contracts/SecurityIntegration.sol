// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import "@chainlink/contracts/src/v0.8/ChainlinkClient.sol";

contract SecurityIntegration is AccessControl, ReentrancyGuard, ChainlinkClient {
    using ECDSA for bytes32;
    using Chainlink for Chainlink.Request;

    bytes32 public constant SECURITY_PROVIDER = keccak256("SECURITY_PROVIDER");
    bytes32 public constant ORACLE_ROLE = keccak256("ORACLE_ROLE");

    struct SecurityAudit {
        bytes32 id;
        string auditType;
        address contractAddress;
        uint256 timestamp;
        uint256 score;
        string findings;
        bool passed;
        mapping(address => bool) validatorApprovals;
    }

    struct ThreatAlert {
        bytes32 id;
        string alertType;
        uint256 severity;
        string description;
        uint256 timestamp;
        bool isResolved;
        bytes evidence;
    }

    struct SecurityMetrics {
        uint256 totalAudits;
        uint256 passedAudits;
        uint256 activeThreats;
        uint256 resolvedThreats;
        uint256 averageAuditScore;
        uint256 lastUpdateTimestamp;
    }

    mapping(bytes32 => SecurityAudit) public audits;
    mapping(bytes32 => ThreatAlert) public threats;
    mapping(address => SecurityMetrics) public contractMetrics;
    mapping(address => bool) public trustedValidators;
    
    bytes32 private jobId;
    uint256 private fee;
    
    event AuditRequested(
        bytes32 indexed auditId,
        address indexed contractAddress,
        string auditType
    );
    event AuditCompleted(
        bytes32 indexed auditId,
        uint256 score,
        bool passed
    );
    event ThreatDetected(
        bytes32 indexed threatId,
        string alertType,
        uint256 severity
    );
    event ThreatResolved(
        bytes32 indexed threatId,
        uint256 timestamp
    );
    event ValidatorAdded(address indexed validator);
    event ValidatorRemoved(address indexed validator);

    constructor(address _link, address _oracle) {
        setChainlinkToken(_link);
        setChainlinkOracle(_oracle);
        jobId = "security_audit_job_id";
        fee = 0.1 * 10 ** 18; // 0.1 LINK

        _setupRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _setupRole(SECURITY_PROVIDER, msg.sender);
        _setupRole(ORACLE_ROLE, _oracle);
    }

    function requestAudit(
        address contractAddress,
        string memory auditType
    ) external onlyRole(SECURITY_PROVIDER) returns (bytes32) {
        bytes32 auditId = keccak256(
            abi.encodePacked(
                contractAddress,
                auditType,
                block.timestamp
            )
        );

        SecurityAudit storage audit = audits[auditId];
        audit.id = auditId;
        audit.auditType = auditType;
        audit.contractAddress = contractAddress;
        audit.timestamp = block.timestamp;

        Chainlink.Request memory req = buildChainlinkRequest(
            jobId,
            address(this),
            this.fulfillAudit.selector
        );
        req.add("contractAddress", addressToString(contractAddress));
        req.add("auditType", auditType);
        
        bytes32 requestId = sendChainlinkRequest(req, fee);
        
        emit AuditRequested(auditId, contractAddress, auditType);
        
        return auditId;
    }

    function fulfillAudit(
        bytes32 _requestId,
        bytes32 _auditId,
        uint256 _score,
        string memory _findings,
        bool _passed
    ) external onlyRole(ORACLE_ROLE) {
        SecurityAudit storage audit = audits[_auditId];
        require(audit.id == _auditId, "Invalid audit ID");

        audit.score = _score;
        audit.findings = _findings;
        audit.passed = _passed;

        // Update metrics
        SecurityMetrics storage metrics = contractMetrics[audit.contractAddress];
        metrics.totalAudits++;
        if (_passed) metrics.passedAudits++;
        metrics.averageAuditScore = (metrics.averageAuditScore * (metrics.totalAudits - 1) + _score) / metrics.totalAudits;
        metrics.lastUpdateTimestamp = block.timestamp;

        emit AuditCompleted(_auditId, _score, _passed);
    }

    function reportThreat(
        string memory alertType,
        uint256 severity,
        string memory description,
        bytes memory evidence
    ) external onlyRole(SECURITY_PROVIDER) returns (bytes32) {
        require(severity > 0 && severity <= 3, "Invalid severity level");

        bytes32 threatId = keccak256(
            abi.encodePacked(
                alertType,
                block.timestamp,
                msg.sender
            )
        );

        threats[threatId] = ThreatAlert({
            id: threatId,
            alertType: alertType,
            severity: severity,
            description: description,
            timestamp: block.timestamp,
            isResolved: false,
            evidence: evidence
        });

        // Update metrics for affected contracts
        SecurityMetrics storage metrics = contractMetrics[msg.sender];
        metrics.activeThreats++;
        metrics.lastUpdateTimestamp = block.timestamp;

        emit ThreatDetected(threatId, alertType, severity);
        
        return threatId;
    }

    function resolveThreat(bytes32 threatId)
        external
        onlyRole(SECURITY_PROVIDER)
    {
        ThreatAlert storage threat = threats[threatId];
        require(!threat.isResolved, "Threat already resolved");

        threat.isResolved = true;

        // Update metrics
        SecurityMetrics storage metrics = contractMetrics[msg.sender];
        metrics.activeThreats--;
        metrics.resolvedThreats++;
        metrics.lastUpdateTimestamp = block.timestamp;

        emit ThreatResolved(threatId, block.timestamp);
    }

    function addValidator(address validator)
        external
        onlyRole(DEFAULT_ADMIN_ROLE)
    {
        require(!trustedValidators[validator], "Validator already trusted");
        trustedValidators[validator] = true;
        emit ValidatorAdded(validator);
    }

    function removeValidator(address validator)
        external
        onlyRole(DEFAULT_ADMIN_ROLE)
    {
        require(trustedValidators[validator], "Validator not trusted");
        trustedValidators[validator] = false;
        emit ValidatorRemoved(validator);
    }

    function validateAudit(bytes32 auditId)
        external
    {
        require(trustedValidators[msg.sender], "Not a trusted validator");
        SecurityAudit storage audit = audits[auditId];
        require(!audit.validatorApprovals[msg.sender], "Already validated");
        
        audit.validatorApprovals[msg.sender] = true;
    }

    function getAuditValidations(bytes32 auditId)
        external
        view
        returns (uint256)
    {
        uint256 validations = 0;
        SecurityAudit storage audit = audits[auditId];
        
        for (uint256 i = 0; i < getRoleMemberCount(SECURITY_PROVIDER); i++) {
            address validator = getRoleMember(SECURITY_PROVIDER, i);
            if (audit.validatorApprovals[validator]) {
                validations++;
            }
        }
        
        return validations;
    }

    function addressToString(address _addr)
        internal
        pure
        returns (string memory)
    {
        bytes32 value = bytes32(uint256(uint160(_addr)));
        bytes memory alphabet = "0123456789abcdef";
        bytes memory str = new bytes(42);
        str[0] = "0";
        str[1] = "x";
        for (uint256 i = 0; i < 20; i++) {
            str[2 + i * 2] = alphabet[uint8(value[i + 12] >> 4)];
            str[3 + i * 2] = alphabet[uint8(value[i + 12] & 0x0f)];
        }
        return string(str);
    }
} 