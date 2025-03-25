// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";

contract PrivacyPreservingAnalytics is AccessControl, ReentrancyGuard {
    using ECDSA for bytes32;

    bytes32 public constant ANALYST_ROLE = keccak256("ANALYST_ROLE");
    
    struct AnalyticsTask {
        bytes32 taskId;
        string encryptedQuery;
        string[] dataProviders;
        uint256 minResponses;
        uint256 responseCount;
        bytes32 aggregationKey;
        TaskStatus status;
        uint256 deadline;
        mapping(address => bool) hasResponded;
    }

    struct EncryptedResponse {
        bytes32 taskId;
        string encryptedData;
        bytes signature;
        uint256 timestamp;
    }

    enum TaskStatus {
        Created,
        InProgress,
        Completed,
        Failed
    }

    mapping(bytes32 => AnalyticsTask) public tasks;
    mapping(bytes32 => EncryptedResponse[]) public responses;
    mapping(address => bytes) public publicKeys;
    
    uint256 public constant MIN_PROVIDERS = 3;
    uint256 public constant MAX_TASK_DURATION = 24 hours;

    event TaskCreated(
        bytes32 indexed taskId,
        string encryptedQuery,
        uint256 minResponses,
        uint256 deadline
    );
    event ResponseSubmitted(
        bytes32 indexed taskId,
        address indexed provider,
        uint256 timestamp
    );
    event TaskCompleted(
        bytes32 indexed taskId,
        uint256 responseCount
    );
    event PublicKeyRegistered(
        address indexed provider,
        bytes publicKey
    );

    constructor() {
        _setupRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _setupRole(ANALYST_ROLE, msg.sender);
    }

    function registerPublicKey(bytes calldata _publicKey) external {
        require(_publicKey.length > 0, "Invalid public key");
        publicKeys[msg.sender] = _publicKey;
        emit PublicKeyRegistered(msg.sender, _publicKey);
    }

    function createAnalyticsTask(
        string memory _encryptedQuery,
        string[] memory _dataProviders,
        uint256 _minResponses,
        bytes32 _aggregationKey
    ) external onlyRole(ANALYST_ROLE) returns (bytes32) {
        require(_dataProviders.length >= MIN_PROVIDERS, "Insufficient providers");
        require(_minResponses <= _dataProviders.length, "Invalid min responses");

        bytes32 taskId = keccak256(abi.encodePacked(
            _encryptedQuery,
            block.timestamp,
            msg.sender
        ));

        AnalyticsTask storage task = tasks[taskId];
        task.taskId = taskId;
        task.encryptedQuery = _encryptedQuery;
        task.dataProviders = _dataProviders;
        task.minResponses = _minResponses;
        task.aggregationKey = _aggregationKey;
        task.status = TaskStatus.Created;
        task.deadline = block.timestamp + MAX_TASK_DURATION;

        emit TaskCreated(
            taskId,
            _encryptedQuery,
            _minResponses,
            task.deadline
        );

        return taskId;
    }

    function submitResponse(
        bytes32 _taskId,
        string memory _encryptedData,
        bytes memory _signature
    ) external nonReentrant {
        AnalyticsTask storage task = tasks[_taskId];
        require(task.status == TaskStatus.Created, "Invalid task status");
        require(block.timestamp <= task.deadline, "Task expired");
        require(!task.hasResponded[msg.sender], "Already responded");

        bool isValidProvider = false;
        for (uint i = 0; i < task.dataProviders.length; i++) {
            if (keccak256(abi.encodePacked(task.dataProviders[i])) == 
                keccak256(abi.encodePacked(addressToString(msg.sender)))) {
                isValidProvider = true;
                break;
            }
        }
        require(isValidProvider, "Not authorized provider");

        // Verify signature
        bytes32 messageHash = keccak256(abi.encodePacked(_taskId, _encryptedData));
        require(verifySignature(messageHash, _signature), "Invalid signature");

        responses[_taskId].push(EncryptedResponse({
            taskId: _taskId,
            encryptedData: _encryptedData,
            signature: _signature,
            timestamp: block.timestamp
        }));

        task.hasResponded[msg.sender] = true;
        task.responseCount++;

        emit ResponseSubmitted(_taskId, msg.sender, block.timestamp);

        if (task.responseCount >= task.minResponses) {
            task.status = TaskStatus.Completed;
            emit TaskCompleted(_taskId, task.responseCount);
        }
    }

    function getTaskResponses(bytes32 _taskId)
        external
        view
        onlyRole(ANALYST_ROLE)
        returns (EncryptedResponse[] memory)
    {
        return responses[_taskId];
    }

    function verifySignature(bytes32 _messageHash, bytes memory _signature)
        internal
        view
        returns (bool)
    {
        bytes32 ethSignedMessageHash = _messageHash.toEthSignedMessageHash();
        address signer = ethSignedMessageHash.recover(_signature);
        return signer == msg.sender;
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
            str[2+i*2] = alphabet[uint8(value[i + 12] >> 4)];
            str[3+i*2] = alphabet[uint8(value[i + 12] & 0x0f)];
        }
        return string(str);
    }
} 