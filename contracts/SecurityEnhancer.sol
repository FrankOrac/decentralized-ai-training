// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/security/Pausable.sol";
import "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import "@openzeppelin/contracts/utils/cryptography/MerkleProof.sol";

contract SecurityEnhancer is AccessControl, ReentrancyGuard, Pausable {
    using ECDSA for bytes32;

    bytes32 public constant SECURITY_ADMIN = keccak256("SECURITY_ADMIN");
    bytes32 public constant VALIDATOR_ROLE = keccak256("VALIDATOR_ROLE");

    struct SecurityConfig {
        uint256 maxTransactionValue;
        uint256 dailyLimit;
        uint256 cooldownPeriod;
        uint256 validationThreshold;
        bool requireMultiSig;
    }

    struct ValidationRequest {
        bytes32 id;
        address initiator;
        bytes32 operationHash;
        uint256 timestamp;
        uint256 validations;
        mapping(address => bool) hasValidated;
        bool executed;
    }

    struct SecurityMetrics {
        uint256 suspiciousTransactions;
        uint256 blockedTransactions;
        uint256 lastUpdated;
        bytes32 securityStateRoot;
    }

    mapping(uint256 => SecurityConfig) public chainConfigs;
    mapping(bytes32 => ValidationRequest) public validationRequests;
    mapping(address => uint256) public dailyTransactionVolume;
    mapping(address => uint256) public lastTransactionTimestamp;
    mapping(bytes32 => bool) public blacklistedOperations;

    bytes32 public immutable DOMAIN_SEPARATOR;
    mapping(address => uint256) public nonces;

    event SecurityConfigUpdated(uint256 indexed chainId, SecurityConfig config);
    event ValidationRequested(bytes32 indexed requestId, address initiator);
    event ValidationProvided(bytes32 indexed requestId, address validator);
    event OperationExecuted(bytes32 indexed requestId, bool success);
    event SecurityAlert(
        uint256 indexed chainId,
        string alertType,
        uint256 severity
    );

    constructor() {
        _setupRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _setupRole(SECURITY_ADMIN, msg.sender);

        DOMAIN_SEPARATOR = keccak256(
            abi.encode(
                keccak256("EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)"),
                keccak256(bytes("SecurityEnhancer")),
                keccak256(bytes("1")),
                block.chainid,
                address(this)
            )
        );
    }

    function updateSecurityConfig(
        uint256 chainId,
        SecurityConfig memory config
    ) external onlyRole(SECURITY_ADMIN) {
        require(config.maxTransactionValue > 0, "Invalid max value");
        require(config.dailyLimit > 0, "Invalid daily limit");
        chainConfigs[chainId] = config;
        emit SecurityConfigUpdated(chainId, config);
    }

    function requestValidation(
        bytes32 operationHash
    ) external whenNotPaused returns (bytes32) {
        require(!blacklistedOperations[operationHash], "Operation blacklisted");
        
        bytes32 requestId = keccak256(
            abi.encodePacked(
                operationHash,
                msg.sender,
                block.timestamp
            )
        );

        ValidationRequest storage request = validationRequests[requestId];
        request.id = requestId;
        request.initiator = msg.sender;
        request.operationHash = operationHash;
        request.timestamp = block.timestamp;
        request.validations = 0;
        request.executed = false;

        emit ValidationRequested(requestId, msg.sender);
        return requestId;
    }

    function validateOperation(
        bytes32 requestId,
        bytes calldata signature
    ) external whenNotPaused nonReentrant {
        ValidationRequest storage request = validationRequests[requestId];
        require(request.id != bytes32(0), "Request not found");
        require(!request.executed, "Already executed");
        require(
            !request.hasValidated[msg.sender],
            "Already validated"
        );
        require(
            hasRole(VALIDATOR_ROLE, msg.sender),
            "Not a validator"
        );

        bytes32 messageHash = keccak256(
            abi.encodePacked(
                "\x19\x01",
                DOMAIN_SEPARATOR,
                keccak256(abi.encode(
                    requestId,
                    request.operationHash,
                    nonces[msg.sender]++
                ))
            )
        );

        address signer = messageHash.recover(signature);
        require(signer == msg.sender, "Invalid signature");

        request.hasValidated[msg.sender] = true;
        request.validations++;

        emit ValidationProvided(requestId, msg.sender);

        SecurityConfig memory config = chainConfigs[block.chainid];
        if (request.validations >= config.validationThreshold) {
            _executeOperation(requestId);
        }
    }

    function _executeOperation(bytes32 requestId) private {
        ValidationRequest storage request = validationRequests[requestId];
        require(!request.executed, "Already executed");

        SecurityConfig memory config = chainConfigs[block.chainid];
        address initiator = request.initiator;

        // Check daily limit
        uint256 currentDay = block.timestamp / 1 days;
        uint256 lastDay = lastTransactionTimestamp[initiator] / 1 days;
        if (currentDay > lastDay) {
            dailyTransactionVolume[initiator] = 0;
        }

        require(
            dailyTransactionVolume[initiator] + msg.value <= config.dailyLimit,
            "Daily limit exceeded"
        );

        // Check cooldown
        require(
            block.timestamp >= lastTransactionTimestamp[initiator] + config.cooldownPeriod,
            "Cooldown period active"
        );

        request.executed = true;
        dailyTransactionVolume[initiator] += msg.value;
        lastTransactionTimestamp[initiator] = block.timestamp;

        emit OperationExecuted(requestId, true);
    }

    function blacklistOperation(
        bytes32 operationHash
    ) external onlyRole(SECURITY_ADMIN) {
        blacklistedOperations[operationHash] = true;
    }

    function isOperationValid(
        bytes32 operationHash,
        bytes32[] calldata merkleProof,
        bytes32 root
    ) external pure returns (bool) {
        return MerkleProof.verify(merkleProof, root, operationHash);
    }

    function emergencyShutdown() external onlyRole(SECURITY_ADMIN) {
        _pause();
    }

    function resumeOperations() external onlyRole(SECURITY_ADMIN) {
        _unpause();
    }

    receive() external payable {
        require(msg.value <= chainConfigs[block.chainid].maxTransactionValue, "Value too high");
    }
} 