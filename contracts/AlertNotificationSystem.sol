// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@chainlink/contracts/src/v0.8/ChainlinkClient.sol";

contract AlertNotificationSystem is AccessControl, ReentrancyGuard, ChainlinkClient {
    bytes32 public constant NOTIFIER_ROLE = keccak256("NOTIFIER_ROLE");
    
    struct NotificationChannel {
        string channelType; // "email", "webhook", "telegram", etc.
        bytes endpoint;
        bool isActive;
        mapping(string => bool) alertTypes;
        uint256 minSeverity;
        uint256 cooldownPeriod;
        uint256 lastNotification;
    }

    struct NotificationTemplate {
        string name;
        string template;
        mapping(string => string) parameters;
        bool isActive;
    }

    struct NotificationBatch {
        bytes32[] alertIds;
        address[] recipients;
        uint256 timestamp;
        bool processed;
    }

    mapping(address => mapping(string => NotificationChannel)) public channels;
    mapping(string => NotificationTemplate) public templates;
    mapping(bytes32 => NotificationBatch) public batches;
    mapping(address => uint256) public notificationCounts;
    
    uint256 public constant MAX_BATCH_SIZE = 100;
    uint256 public constant MIN_COOLDOWN = 5 minutes;

    event ChannelConfigured(
        address indexed user,
        string channelType,
        bytes endpoint
    );
    event NotificationSent(
        bytes32 indexed batchId,
        address indexed recipient,
        string channelType,
        uint256 alertCount
    );
    event TemplateUpdated(
        string indexed name,
        string template
    );
    event NotificationFailed(
        bytes32 indexed batchId,
        string reason
    );

    constructor(address _link) {
        setChainlinkToken(_link);
        _setupRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _setupRole(NOTIFIER_ROLE, msg.sender);
    }

    function configureChannel(
        string memory channelType,
        bytes memory endpoint,
        string[] memory allowedAlertTypes,
        uint256 minSeverity,
        uint256 cooldownPeriod
    ) external {
        require(cooldownPeriod >= MIN_COOLDOWN, "Cooldown too short");
        
        NotificationChannel storage channel = channels[msg.sender][channelType];
        channel.channelType = channelType;
        channel.endpoint = endpoint;
        channel.isActive = true;
        channel.minSeverity = minSeverity;
        channel.cooldownPeriod = cooldownPeriod;

        for (uint256 i = 0; i < allowedAlertTypes.length; i++) {
            channel.alertTypes[allowedAlertTypes[i]] = true;
        }

        emit ChannelConfigured(msg.sender, channelType, endpoint);
    }

    function updateTemplate(
        string memory name,
        string memory template,
        string[] memory parameterNames,
        string[] memory parameterValues
    ) external onlyRole(NOTIFIER_ROLE) {
        require(parameterNames.length == parameterValues.length, "Parameter mismatch");
        
        NotificationTemplate storage notificationTemplate = templates[name];
        notificationTemplate.name = name;
        notificationTemplate.template = template;
        notificationTemplate.isActive = true;

        for (uint256 i = 0; i < parameterNames.length; i++) {
            notificationTemplate.parameters[parameterNames[i]] = parameterValues[i];
        }

        emit TemplateUpdated(name, template);
    }

    function sendNotifications(
        bytes32[] memory alertIds,
        string memory alertType,
        uint256 severity,
        address[] memory recipients
    ) external onlyRole(NOTIFIER_ROLE) returns (bytes32) {
        require(alertIds.length > 0 && alertIds.length <= MAX_BATCH_SIZE, "Invalid batch size");
        require(recipients.length > 0, "No recipients");

        bytes32 batchId = keccak256(
            abi.encodePacked(
                alertIds,
                block.timestamp,
                msg.sender
            )
        );

        NotificationBatch storage batch = batches[batchId];
        batch.alertIds = alertIds;
        batch.recipients = recipients;
        batch.timestamp = block.timestamp;

        for (uint256 i = 0; i < recipients.length; i++) {
            address recipient = recipients[i];
            
            // Check each channel type for the recipient
            string[3] memory channelTypes = ["email", "webhook", "telegram"];
            
            for (uint256 j = 0; j < channelTypes.length; j++) {
                NotificationChannel storage channel = channels[recipient][channelTypes[j]];
                
                if (_shouldNotify(channel, alertType, severity)) {
                    _sendNotification(
                        batchId,
                        recipient,
                        channel,
                        alertIds,
                        alertType,
                        severity
                    );
                }
            }
        }

        return batchId;
    }

    function _shouldNotify(
        NotificationChannel storage channel,
        string memory alertType,
        uint256 severity
    ) internal view returns (bool) {
        return channel.isActive &&
               channel.alertTypes[alertType] &&
               severity >= channel.minSeverity &&
               block.timestamp >= channel.lastNotification + channel.cooldownPeriod;
    }

    function _sendNotification(
        bytes32 batchId,
        address recipient,
        NotificationChannel storage channel,
        bytes32[] memory alertIds,
        string memory alertType,
        uint256 severity
    ) internal {
        // Prepare Chainlink request based on channel type
        bytes32 jobId;
        bytes memory payload;

        if (keccak256(bytes(channel.channelType)) == keccak256(bytes("email"))) {
            jobId = "EMAIL_NOTIFICATION_JOB";
            payload = _prepareEmailPayload(recipient, alertIds, alertType, severity);
        } else if (keccak256(bytes(channel.channelType)) == keccak256(bytes("webhook"))) {
            jobId = "WEBHOOK_NOTIFICATION_JOB";
            payload = _prepareWebhookPayload(recipient, alertIds, alertType, severity);
        } else if (keccak256(bytes(channel.channelType)) == keccak256(bytes("telegram"))) {
            jobId = "TELEGRAM_NOTIFICATION_JOB";
            payload = _prepareTelegramPayload(recipient, alertIds, alertType, severity);
        }

        Chainlink.Request memory req = buildChainlinkRequest(
            jobId,
            address(this),
            this.fulfillNotification.selector
        );

        req.addBytes("payload", payload);
        req.add("recipient", addressToString(recipient));
        req.add("channelType", channel.channelType);
        req.add("batchId", bytes32ToString(batchId));

        sendChainlinkRequestTo(
            getChainlinkOracle(channel.channelType),
            req,
            getChainlinkFee(channel.channelType)
        );

        channel.lastNotification = block.timestamp;
        notificationCounts[recipient]++;
    }

    function _prepareEmailPayload(
        address recipient,
        bytes32[] memory alertIds,
        string memory alertType,
        uint256 severity
    ) internal pure returns (bytes memory) {
        return abi.encode(
            recipient,
            alertIds,
            alertType,
            severity,
            "email"
        );
    }

    function _prepareWebhookPayload(
        address recipient,
        bytes32[] memory alertIds,
        string memory alertType,
        uint256 severity
    ) internal pure returns (bytes memory) {
        return abi.encode(
            recipient,
            alertIds,
            alertType,
            severity,
            "webhook"
        );
    }

    function _prepareTelegramPayload(
        address recipient,
        bytes32[] memory alertIds,
        string memory alertType,
        uint256 severity
    ) internal pure returns (bytes memory) {
        return abi.encode(
            recipient,
            alertIds,
            alertType,
            severity,
            "telegram"
        );
    }

    function fulfillNotification(
        bytes32 _requestId,
        bytes32 _batchId,
        bool _success,
        string memory _error
    ) external recordChainlinkFulfillment(_requestId) {
        NotificationBatch storage batch = batches[_batchId];
        require(!batch.processed, "Batch already processed");

        batch.processed = true;

        if (_success) {
            emit NotificationSent(
                _batchId,
                batch.recipients[0],
                "notification",
                batch.alertIds.length
            );
        } else {
            emit NotificationFailed(_batchId, _error);
        }
    }

    function getChainlinkOracle(string memory channelType)
        internal
        pure
        returns (address)
    {
        // Return appropriate oracle address for each channel type
        return address(0); // Placeholder
    }

    function getChainlinkFee(string memory channelType)
        internal
        pure
        returns (uint256)
    {
        // Return appropriate fee for each channel type
        return 0.1 * 10**18; // Placeholder
    }

    function bytes32ToString(bytes32 _bytes32)
        internal
        pure
        returns (string memory)
    {
        // Implementation from previous contract
    }

    function addressToString(address _addr)
        internal
        pure
        returns (string memory)
    {
        // Implementation from previous contract
    }

    receive() external payable {}
} 