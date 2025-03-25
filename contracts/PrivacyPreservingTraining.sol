// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";

contract PrivacyPreservingTraining is AccessControl, ReentrancyGuard {
    using ECDSA for bytes32;

    bytes32 public constant COORDINATOR_ROLE = keccak256("COORDINATOR_ROLE");
    bytes32 public constant PARTICIPANT_ROLE = keccak256("PARTICIPANT_ROLE");

    struct PrivateTrainingTask {
        string taskId;
        string encryptedModelHash;
        bytes publicKey;
        uint256 minParticipants;
        uint256 maxParticipants;
        uint256 roundDuration;
        uint256 startTime;
        uint256 endTime;
        TrainingStatus status;
        address coordinator;
        mapping(address => Contribution) contributions;
        address[] participants;
        uint256 contributionCount;
    }

    struct Contribution {
        string encryptedContribution;
        bytes signature;
        uint256 timestamp;
        bool isValid;
    }

    struct EncryptionKey {
        bytes publicKey;
        uint256 lastRotation;
        bool isActive;
    }

    enum TrainingStatus {
        Created,
        Collecting,
        Aggregating,
        Completed,
        Failed
    }

    mapping(string => PrivateTrainingTask) public tasks;
    mapping(address => EncryptionKey) public encryptionKeys;
    mapping(address => uint256) public participantReputations;
    
    uint256 public minContributions;
    uint256 public contributionReward;
    uint256 public keyRotationPeriod;

    event TaskCreated(
        string indexed taskId,
        string encryptedModelHash,
        uint256 minParticipants
    );
    event ContributionSubmitted(
        string indexed taskId,
        address indexed participant,
        uint256 timestamp
    );
    event TaskCompleted(
        string indexed taskId,
        string aggregatedModelHash
    );
    event KeyRotated(
        address indexed participant,
        bytes newPublicKey
    );

    constructor(
        uint256 _minContributions,
        uint256 _contributionReward,
        uint256 _keyRotationPeriod
    ) {
        _setupRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _setupRole(COORDINATOR_ROLE, msg.sender);
        
        minContributions = _minContributions;
        contributionReward = _contributionReward;
        keyRotationPeriod = _keyRotationPeriod;
    }

    function createPrivateTask(
        string memory _taskId,
        string memory _encryptedModelHash,
        bytes memory _publicKey,
        uint256 _minParticipants,
        uint256 _maxParticipants,
        uint256 _roundDuration
    ) external onlyRole(COORDINATOR_ROLE) {
        require(_minParticipants >= minContributions, "Too few participants");
        require(_maxParticipants >= _minParticipants, "Invalid max participants");
        require(_roundDuration > 0, "Invalid duration");

        PrivateTrainingTask storage task = tasks[_taskId];
        task.taskId = _taskId;
        task.encryptedModelHash = _encryptedModelHash;
        task.publicKey = _publicKey;
        task.minParticipants = _minParticipants;
        task.maxParticipants = _maxParticipants;
        task.roundDuration = _roundDuration;
        task.startTime = block.timestamp;
        task.endTime = block.timestamp + _roundDuration;
        task.status = TrainingStatus.Created;
        task.coordinator = msg.sender;

        emit TaskCreated(_taskId, _encryptedModelHash, _minParticipants);
    }

    function registerEncryptionKey(bytes memory _publicKey) external {
        require(_publicKey.length > 0, "Invalid public key");
        
        encryptionKeys[msg.sender] = EncryptionKey({
            publicKey: _publicKey,
            lastRotation: block.timestamp,
            isActive: true
        });

        emit KeyRotated(msg.sender, _publicKey);
    }

    function joinTask(string memory _taskId) external {
        require(hasRole(PARTICIPANT_ROLE, msg.sender), "Not a participant");
        require(encryptionKeys[msg.sender].isActive, "No active encryption key");

        PrivateTrainingTask storage task = tasks[_taskId];
        require(task.status == TrainingStatus.Created, "Task not accepting participants");
        require(task.participants.length < task.maxParticipants, "Task full");
        require(block.timestamp < task.endTime, "Task ended");

        task.participants.push(msg.sender);
        if (task.participants.length >= task.minParticipants) {
            task.status = TrainingStatus.Collecting;
        }
    }

    function submitContribution(
        string memory _taskId,
        string memory _encryptedContribution,
        bytes memory _signature
    ) external nonReentrant {
        PrivateTrainingTask storage task = tasks[_taskId];
        require(task.status == TrainingStatus.Collecting, "Task not collecting");
        require(block.timestamp <= task.endTime, "Task ended");
        require(!task.contributions[msg.sender].isValid, "Already contributed");

        bool isParticipant = false;
        for (uint i = 0; i < task.participants.length; i++) {
            if (task.participants[i] == msg.sender) {
                isParticipant = true;
                break;
            }
        }
        require(isParticipant, "Not a participant");

        // Verify signature
        bytes32 messageHash = keccak256(abi.encodePacked(
            _taskId,
            _encryptedContribution
        ));
        require(verifySignature(messageHash, _signature), "Invalid signature");

        task.contributions[msg.sender] = Contribution({
            encryptedContribution: _encryptedContribution,
            signature: _signature,
            timestamp: block.timestamp,
            isValid: true
        });

        task.contributionCount++;
        emit ContributionSubmitted(_taskId, msg.sender, block.timestamp);

        if (task.contributionCount >= task.minParticipants) {
            task.status = TrainingStatus.Aggregating;
        }

        // Reward participant
        payable(msg.sender).transfer(contributionReward);
    }

    function completeTask(
        string memory _taskId,
        string memory _aggregatedModelHash
    ) external onlyRole(COORDINATOR_ROLE) {
        PrivateTrainingTask storage task = tasks[_taskId];
        require(task.status == TrainingStatus.Aggregating, "Task not aggregating");

        task.status = TrainingStatus.Completed;
        distributeRewards(_taskId);
        
        emit TaskCompleted(_taskId, _aggregatedModelHash);
    }

    function distributeRewards(string memory _taskId) internal {
        PrivateTrainingTask storage task = tasks[_taskId];
        
        for (uint i = 0; i < task.participants.length; i++) {
            address participant = task.participants[i];
            if (task.contributions[participant].isValid) {
                participantReputations[participant]++;
            }
        }
    }

    function rotateEncryptionKey(bytes memory _newPublicKey) external {
        require(_newPublicKey.length > 0, "Invalid public key");
        require(
            block.timestamp >= encryptionKeys[msg.sender].lastRotation + keyRotationPeriod,
            "Too soon to rotate"
        );

        encryptionKeys[msg.sender].publicKey = _newPublicKey;
        encryptionKeys[msg.sender].lastRotation = block.timestamp;
        
        emit KeyRotated(msg.sender, _newPublicKey);
    }

    function verifySignature(
        bytes32 _messageHash,
        bytes memory _signature
    ) internal view returns (bool) {
        bytes32 ethSignedMessageHash = _messageHash.toEthSignedMessageHash();
        address signer = ethSignedMessageHash.recover(_signature);
        return signer == msg.sender;
    }

    function getTaskDetails(string memory _taskId)
        external
        view
        returns (
            string memory encryptedModelHash,
            bytes memory publicKey,
            uint256 minParticipants,
            uint256 maxParticipants,
            uint256 startTime,
            uint256 endTime,
            TrainingStatus status,
            address coordinator,
            uint256 contributionCount,
            address[] memory participants
        )
    {
        PrivateTrainingTask storage task = tasks[_taskId];
        return (
            task.encryptedModelHash,
            task.publicKey,
            task.minParticipants,
            task.maxParticipants,
            task.startTime,
            task.endTime,
            task.status,
            task.coordinator,
            task.contributionCount,
            task.participants
        );
    }

    function getContribution(
        string memory _taskId,
        address _participant
    ) external view returns (
        string memory encryptedContribution,
        uint256 timestamp,
        bool isValid
    ) {
        Contribution storage contribution = tasks[_taskId].contributions[_participant];
        return (
            contribution.encryptedContribution,
            contribution.timestamp,
            contribution.isValid
        );
    }
} 