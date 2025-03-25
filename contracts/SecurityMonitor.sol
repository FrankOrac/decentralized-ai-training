// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/security/Pausable.sol";
import "@chainlink/contracts/src/v0.8/ChainlinkClient.sol";

contract SecurityMonitor is AccessControl, ReentrancyGuard, Pausable, ChainlinkClient {
    bytes32 public constant GUARDIAN_ROLE = keccak256("GUARDIAN_ROLE");
    bytes32 public constant MONITOR_ROLE = keccak256("MONITOR_ROLE");

    struct SecurityThreshold {
        uint256 maxGasPerTx;
        uint256 maxTxPerBlock;
        uint256 maxValuePerTx;
        uint256 cooldownPeriod;
        uint256 requiredConfirmations;
    }

    struct SecurityIncident {
        bytes32 id;
        string incidentType;
        address target;
        uint256 severity;
        uint256 timestamp;
        bool isResolved;
        mapping(address => bool) guardianApprovals;
        bytes evidence;
    }

    struct ContractGuard {
        bool isProtected;
        mapping(bytes4 => bool) restrictedFunctions;
        mapping(address => uint256) lastInteraction;
        uint256 dailyLimit;
        uint256 dailyUsed;
        uint256 lastResetTime;
    }

    mapping(address => ContractGuard) public protectedContracts;
    mapping(bytes32 => SecurityIncident) public incidents;
    mapping(address => SecurityThreshold) public thresholds;
    
    uint256 public constant SEVERITY_THRESHOLD = 7;
    uint256 public constant MAX_INCIDENT_DURATION = 24 hours;

    event SecurityIncidentReported(
        bytes32 indexed incidentId,
        string incidentType,
        address target,
        uint256 severity
    );
    event IncidentResolved(
        bytes32 indexed incidentId,
        address resolver
    );
    event ThresholdUpdated(
        address indexed contract_,
        uint256 maxGasPerTx,
        uint256 maxTxPerBlock
    );
    event ContractProtectionEnabled(
        address indexed contract_,
        bytes4[] restrictedFunctions
    );
    event EmergencyShutdown(
        bytes32 indexed incidentId,
        string reason
    );

    constructor(address _link) {
        setChainlinkToken(_link);
        _setupRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _setupRole(GUARDIAN_ROLE, msg.sender);
    }

    function enableContractProtection(
        address contract_,
        bytes4[] calldata restrictedFunctions,
        SecurityThreshold calldata threshold
    ) external onlyRole(GUARDIAN_ROLE) {
        require(contract_ != address(0), "Invalid contract address");
        
        ContractGuard storage guard = protectedContracts[contract_];
        guard.isProtected = true;
        
        for (uint256 i = 0; i < restrictedFunctions.length; i++) {
            guard.restrictedFunctions[restrictedFunctions[i]] = true;
        }
        
        guard.dailyLimit = threshold.maxValuePerTx;
        thresholds[contract_] = threshold;

        emit ContractProtectionEnabled(contract_, restrictedFunctions);
        emit ThresholdUpdated(
            contract_,
            threshold.maxGasPerTx,
            threshold.maxTxPerBlock
        );
    }

    function reportSecurityIncident(
        string calldata incidentType,
        address target,
        uint256 severity,
        bytes calldata evidence
    ) external onlyRole(MONITOR_ROLE) returns (bytes32) {
        require(severity > 0 && severity <= 10, "Invalid severity");
        
        bytes32 incidentId = keccak256(
            abi.encodePacked(
                incidentType,
                target,
                block.timestamp,
                msg.sender
            )
        );

        SecurityIncident storage incident = incidents[incidentId];
        incident.id = incidentId;
        incident.incidentType = incidentType;
        incident.target = target;
        incident.severity = severity;
        incident.timestamp = block.timestamp;
        incident.evidence = evidence;

        emit SecurityIncidentReported(
            incidentId,
            incidentType,
            target,
            severity
        );

        if (severity >= SEVERITY_THRESHOLD) {
            _initiateEmergencyResponse(incidentId);
        }

        return incidentId;
    }

    function approveIncidentResolution(bytes32 incidentId)
        external
        onlyRole(GUARDIAN_ROLE)
    {
        SecurityIncident storage incident = incidents[incidentId];
        require(incident.id == incidentId, "Incident not found");
        require(!incident.isResolved, "Already resolved");
        require(
            !incident.guardianApprovals[msg.sender],
            "Already approved"
        );

        incident.guardianApprovals[msg.sender] = true;

        uint256 approvals = 0;
        for (uint256 i = 0; i < getRoleMemberCount(GUARDIAN_ROLE); i++) {
            address guardian = getRoleMember(GUARDIAN_ROLE, i);
            if (incident.guardianApprovals[guardian]) {
                approvals++;
            }
        }

        if (approvals >= thresholds[incident.target].requiredConfirmations) {
            incident.isResolved = true;
            emit IncidentResolved(incidentId, msg.sender);
        }
    }

    function validateTransaction(
        address contract_,
        bytes4 functionSig,
        uint256 gasLimit,
        uint256 value
    ) external view returns (bool) {
        ContractGuard storage guard = protectedContracts[contract_];
        if (!guard.isProtected) return true;

        SecurityThreshold storage threshold = thresholds[contract_];
        
        // Check function restrictions
        if (guard.restrictedFunctions[functionSig]) return false;

        // Check gas limit
        if (gasLimit > threshold.maxGasPerTx) return false;

        // Check value limits
        if (value > threshold.maxValuePerTx) return false;

        // Check cooldown period
        if (block.timestamp - guard.lastInteraction[msg.sender] < threshold.cooldownPeriod) {
            return false;
        }

        // Check daily limits
        if (block.timestamp - guard.lastResetTime >= 1 days) {
            guard.dailyUsed = 0;
            guard.lastResetTime = block.timestamp;
        }
        
        if (guard.dailyUsed + value > guard.dailyLimit) return false;

        return true;
    }

    function _initiateEmergencyResponse(bytes32 incidentId) internal {
        SecurityIncident storage incident = incidents[incidentId];
        
        if (incident.severity >= SEVERITY_THRESHOLD) {
            // Pause protected contract
            Pausable(incident.target).pause();
            
            // Emit emergency shutdown event
            emit EmergencyShutdown(
                incidentId,
                "Critical security incident detected"
            );
            
            // Notify guardians via Chainlink oracle
            _notifyGuardians(incidentId);
        }
    }

    function _notifyGuardians(bytes32 incidentId) internal {
        SecurityIncident storage incident = incidents[incidentId];
        
        Chainlink.Request memory req = buildChainlinkRequest(
            keccak256("SECURITY_ALERT"),
            address(this),
            this.fulfillNotification.selector
        );

        req.add("incidentId", bytes32ToString(incidentId));
        req.add("incidentType", incident.incidentType);
        req.add("target", addressToString(incident.target));
        req.add("severity", uint256ToString(incident.severity));

        sendChainlinkRequestTo(
            getRoleMember(MONITOR_ROLE, 0),
            req,
            0.1 * 10**18
        );
    }

    function bytes32ToString(bytes32 _bytes32) internal pure returns (string memory) {
        bytes memory bytesArray = new bytes(64);
        for (uint256 i = 0; i < 32; i++) {
            bytes1 char = bytes1(uint8(uint256(_bytes32) / (2**(8*(31 - i)))));
            bytes1 hi = bytes1(uint8(char) / 16);
            bytes1 lo = bytes1(uint8(char) - 16 * uint8(hi));
            bytesArray[i*2] = char2hex(hi);
            bytesArray[i*2+1] = char2hex(lo);
        }
        return string(bytesArray);
    }

    function char2hex(bytes1 char) internal pure returns (bytes1) {
        if (uint8(char) < 10) return bytes1(uint8(char) + 0x30);
        else return bytes1(uint8(char) + 0x57);
    }

    function addressToString(address _addr) internal pure returns (string memory) {
        bytes memory s = new bytes(40);
        for (uint i = 0; i < 20; i++) {
            bytes1 b = bytes1(uint8(uint160(_addr) / (2**(8*(19 - i)))));
            bytes1 hi = bytes1(uint8(b) / 16);
            bytes1 lo = bytes1(uint8(b) - 16 * uint8(hi));
            s[2*i] = char2hex(hi);
            s[2*i+1] = char2hex(lo);
        }
        return string(s);
    }

    function uint256ToString(uint256 value) internal pure returns (string memory) {
        if (value == 0) {
            return "0";
        }
        uint256 temp = value;
        uint256 digits;
        while (temp != 0) {
            digits++;
            temp /= 10;
        }
        bytes memory buffer = new bytes(digits);
        while (value != 0) {
            digits -= 1;
            buffer[digits] = bytes1(uint8(48 + uint256(value % 10)));
            value /= 10;
        }
        return string(buffer);
    }
} 