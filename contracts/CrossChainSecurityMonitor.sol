// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "./interfaces/ILayerZeroEndpoint.sol";

contract CrossChainSecurityMonitor is AccessControl, ReentrancyGuard {
    bytes32 public constant MONITOR_ROLE = keccak256("MONITOR_ROLE");
    bytes32 public constant VALIDATOR_ROLE = keccak256("VALIDATOR_ROLE");

    struct SecurityAlert {
        bytes32 id;
        uint256 sourceChainId;
        string alertType;
        uint256 severity;
        bytes evidence;
        uint256 timestamp;
        bool isVerified;
        mapping(uint256 => bool) chainVerifications;
    }

    struct ChainMetrics {
        uint256 chainId;
        uint256 alertCount;
        uint256 verifiedAlerts;
        uint256 falsePositives;
        uint256 lastUpdateTimestamp;
        mapping(string => uint256) alertTypeFrequency;
    }

    ILayerZeroEndpoint public immutable lzEndpoint;
    
    mapping(bytes32 => SecurityAlert) public alerts;
    mapping(uint256 => ChainMetrics) public chainMetrics;
    mapping(bytes32 => bool) public processedMessages;
    
    uint256 public constant MIN_VERIFICATIONS = 2;
    uint256 public constant ALERT_EXPIRY = 24 hours;

    event SecurityAlertRaised(
        bytes32 indexed alertId,
        uint256 indexed sourceChainId,
        string alertType,
        uint256 severity
    );
    event AlertVerified(
        bytes32 indexed alertId,
        uint256 indexed chainId,
        bool verified
    );
    event ChainMetricsUpdated(
        uint256 indexed chainId,
        uint256 alertCount,
        uint256 verifiedAlerts
    );
    event CrossChainMessageReceived(
        bytes32 indexed messageId,
        uint256 indexed sourceChainId,
        bytes data
    );

    constructor(address _lzEndpoint) {
        lzEndpoint = ILayerZeroEndpoint(_lzEndpoint);
        _setupRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _setupRole(MONITOR_ROLE, msg.sender);
        _setupRole(VALIDATOR_ROLE, msg.sender);
    }

    function raiseSecurityAlert(
        string memory alertType,
        uint256 severity,
        bytes memory evidence
    ) external onlyRole(MONITOR_ROLE) returns (bytes32) {
        require(severity > 0 && severity <= 3, "Invalid severity");

        bytes32 alertId = keccak256(
            abi.encodePacked(
                alertType,
                block.timestamp,
                msg.sender
            )
        );

        SecurityAlert storage alert = alerts[alertId];
        alert.id = alertId;
        alert.sourceChainId = getChainId();
        alert.alertType = alertType;
        alert.severity = severity;
        alert.evidence = evidence;
        alert.timestamp = block.timestamp;

        // Update chain metrics
        ChainMetrics storage metrics = chainMetrics[getChainId()];
        metrics.alertCount++;
        metrics.alertTypeFrequency[alertType]++;
        metrics.lastUpdateTimestamp = block.timestamp;

        // Propagate alert to other chains
        _propagateAlert(alertId, alertType, severity, evidence);

        emit SecurityAlertRaised(alertId, getChainId(), alertType, severity);
        return alertId;
    }

    function verifyAlert(
        bytes32 alertId,
        bool isValid
    ) external onlyRole(VALIDATOR_ROLE) {
        SecurityAlert storage alert = alerts[alertId];
        require(alert.id == alertId, "Alert not found");
        require(
            block.timestamp <= alert.timestamp + ALERT_EXPIRY,
            "Alert expired"
        );
        require(
            !alert.chainVerifications[getChainId()],
            "Already verified"
        );

        alert.chainVerifications[getChainId()] = true;

        uint256 verificationCount = 0;
        for (uint256 i = 0; i < getRoleMemberCount(VALIDATOR_ROLE); i++) {
            if (alert.chainVerifications[i]) {
                verificationCount++;
            }
        }

        if (verificationCount >= MIN_VERIFICATIONS) {
            alert.isVerified = true;
            
            // Update metrics
            ChainMetrics storage metrics = chainMetrics[alert.sourceChainId];
            metrics.verifiedAlerts++;
            if (!isValid) {
                metrics.falsePositives++;
            }
        }

        emit AlertVerified(alertId, getChainId(), isValid);
    }

    function _propagateAlert(
        bytes32 alertId,
        string memory alertType,
        uint256 severity,
        bytes memory evidence
    ) internal {
        bytes memory payload = abi.encode(
            alertId,
            alertType,
            severity,
            evidence
        );

        uint16[] memory destChains = _getDestinationChains();
        for (uint256 i = 0; i < destChains.length; i++) {
            lzEndpoint.send(
                destChains[i],
                abi.encodePacked(address(this), address(this)),
                payload,
                payable(msg.sender),
                address(0),
                bytes("")
            );
        }
    }

    function lzReceive(
        uint16 _srcChainId,
        bytes memory _srcAddress,
        uint64 _nonce,
        bytes memory _payload
    ) external {
        require(msg.sender == address(lzEndpoint), "Invalid endpoint");
        
        bytes32 messageId = keccak256(
            abi.encodePacked(_srcChainId, _srcAddress, _nonce, _payload)
        );
        require(!processedMessages[messageId], "Message already processed");

        (
            bytes32 alertId,
            string memory alertType,
            uint256 severity,
            bytes memory evidence
        ) = abi.decode(_payload, (bytes32, string, uint256, bytes));

        SecurityAlert storage alert = alerts[alertId];
        alert.id = alertId;
        alert.sourceChainId = _srcChainId;
        alert.alertType = alertType;
        alert.severity = severity;
        alert.evidence = evidence;
        alert.timestamp = block.timestamp;

        processedMessages[messageId] = true;
        emit CrossChainMessageReceived(messageId, _srcChainId, _payload);
    }

    function getAlertVerifications(bytes32 alertId)
        external
        view
        returns (uint256)
    {
        uint256 verifications = 0;
        SecurityAlert storage alert = alerts[alertId];
        
        for (uint256 i = 0; i < getRoleMemberCount(VALIDATOR_ROLE); i++) {
            if (alert.chainVerifications[i]) {
                verifications++;
            }
        }
        
        return verifications;
    }

    function getChainMetrics(uint256 chainId)
        external
        view
        returns (
            uint256 alertCount,
            uint256 verifiedAlerts,
            uint256 falsePositives,
            uint256 lastUpdateTimestamp
        )
    {
        ChainMetrics storage metrics = chainMetrics[chainId];
        return (
            metrics.alertCount,
            metrics.verifiedAlerts,
            metrics.falsePositives,
            metrics.lastUpdateTimestamp
        );
    }

    function _getDestinationChains()
        internal
        pure
        returns (uint16[] memory)
    {
        // Implement your chain configuration logic
        uint16[] memory chains = new uint16[](3);
        chains[0] = 1; // Mainnet
        chains[1] = 2; // Arbitrum
        chains[2] = 3; // Optimism
        return chains;
    }

    function getChainId() public view returns (uint256) {
        uint256 chainId;
        assembly {
            chainId := chainid()
        }
        return chainId;
    }
} 