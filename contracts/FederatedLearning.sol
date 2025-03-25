// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";

contract FederatedLearning is AccessControl, ReentrancyGuard {
    using ECDSA for bytes32;

    bytes32 public constant COORDINATOR_ROLE = keccak256("COORDINATOR_ROLE");
    bytes32 public constant PARTICIPANT_ROLE = keccak256("PARTICIPANT_ROLE");

    struct TrainingRound {
        bytes32 roundId;
        string globalModelHash;
        string aggregationStrategy;
        uint256 minParticipants;
        uint256 maxParticipants;
        uint256 startTime;
        uint256 endTime;
        RoundStatus status;
        address[] participants;
        mapping(address => LocalUpdate) updates;
        uint256 updateCount;
        mapping(address => bool) hasVoted;
        uint256 voteCount;
        uint256 approvalCount;
    }

    struct LocalUpdate {
        string modelHash;
        uint256 dataSize;
        uint256 computeTime;
        bytes signature;
        bool isValid;
        uint256 timestamp;
        uint256 score;
    }

    struct ParticipantMetrics {
        uint256 totalUpdates;
        uint256 validUpdates;
        uint256 totalComputeTime;
        uint256 averageDataSize;
        uint256 reputation;
        uint256 lastActiveRound;
    }

    enum RoundStatus {
        Created,
        Active,
        Aggregating,
        Validating,
        Completed,
        Failed
    }

    mapping(bytes32 => TrainingRound) public rounds;
    mapping(address => ParticipantMetrics) public participantMetrics;
    mapping(string => bytes32[]) public modelRounds;
    
    uint256 public roundDuration;
    uint256 public minReputation;
    uint256 public baseReward;
    uint256 public validationThreshold;

    event RoundCreated(
        bytes32 indexed roundId,
        string globalModelHash,
        uint256 startTime,
        uint256 endTime
    );
    event ParticipantJoined(
        bytes32 indexed roundId,
        address indexed participant
    );
    event LocalUpdateSubmitted(
        bytes32 indexed roundId,
        address indexed participant,
        string modelHash
    );
    event RoundValidated(
        bytes32 indexed roundId,
        bool success,
        uint256 approvalCount
    );
    event RewardsDistributed(
        bytes32 indexed roundId,
        uint256 totalReward
    );

    constructor(
        uint256 _roundDuration,
        uint256 _minReputation,
        uint256 _baseReward,
        uint256 _validationThreshold
    ) {
        _setupRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _setupRole(COORDINATOR_ROLE, msg.sender);
        
        roundDuration = _roundDuration;
        minReputation = _minReputation;
        baseReward = _baseReward;
        validationThreshold = _validationThreshold;
    }

    function createRound(
        string memory _globalModelHash,
        string memory _aggregationStrategy,
        uint256 _minParticipants,
        uint256 _maxParticipants
    ) external onlyRole(COORDINATOR_ROLE) returns (bytes32) {
        require(_minParticipants > 0, "Invalid min participants");
        require(_maxParticipants >= _minParticipants, "Invalid max participants");

        bytes32 roundId = keccak256(abi.encodePacked(
            _globalModelHash,
            block.timestamp,
            msg.sender
        ));

        TrainingRound storage round = rounds[roundId];
        round.roundId = roundId;
        round.globalModelHash = _globalModelHash;
        round.aggregationStrategy = _aggregationStrategy;
        round.minParticipants = _minParticipants;
        round.maxParticipants = _maxParticipants;
        round.startTime = block.timestamp;
        round.endTime = block.timestamp + roundDuration;
        round.status = RoundStatus.Active;

        modelRounds[_globalModelHash].push(roundId);
        
        emit RoundCreated(
            roundId,
            _globalModelHash,
            round.startTime,
            round.endTime
        );

        return roundId;
    }

    function joinRound(bytes32 _roundId) external {
        require(hasRole(PARTICIPANT_ROLE, msg.sender), "Not a participant");
        require(
            participantMetrics[msg.sender].reputation >= minReputation,
            "Insufficient reputation"
        );

        TrainingRound storage round = rounds[_roundId];
        require(round.status == RoundStatus.Active, "Round not active");
        require(
            round.participants.length < round.maxParticipants,
            "Round full"
        );
        require(
            block.timestamp < round.endTime,
            "Round ended"
        );

        round.participants.push(msg.sender);
        emit ParticipantJoined(_roundId, msg.sender);
    }

    function submitUpdate(
        bytes32 _roundId,
        string memory _modelHash,
        uint256 _dataSize,
        uint256 _computeTime,
        bytes memory _signature
    ) external nonReentrant {
        TrainingRound storage round = rounds[_roundId];
        require(round.status == RoundStatus.Active, "Round not active");
        require(block.timestamp <= round.endTime, "Round ended");
        require(!round.updates[msg.sender].isValid, "Already submitted");

        bool isParticipant = false;
        for (uint i = 0; i < round.participants.length; i++) {
            if (round.participants[i] == msg.sender) {
                isParticipant = true;
                break;
            }
        }
        require(isParticipant, "Not a participant");

        // Verify signature
        bytes32 messageHash = keccak256(abi.encodePacked(
            _roundId,
            _modelHash,
            _dataSize,
            _computeTime
        ));
        require(verifySignature(messageHash, _signature), "Invalid signature");

        round.updates[msg.sender] = LocalUpdate({
            modelHash: _modelHash,
            dataSize: _dataSize,
            computeTime: _computeTime,
            signature: _signature,
            isValid: true,
            timestamp: block.timestamp,
            score: 0
        });

        round.updateCount++;
        emit LocalUpdateSubmitted(_roundId, msg.sender, _modelHash);

        if (round.updateCount >= round.minParticipants) {
            round.status = RoundStatus.Aggregating;
        }
    }

    function validateUpdate(
        bytes32 _roundId,
        address _participant,
        bool _isValid,
        uint256 _score
    ) external onlyRole(COORDINATOR_ROLE) {
        TrainingRound storage round = rounds[_roundId];
        require(
            round.status == RoundStatus.Aggregating,
            "Round not in aggregation"
        );
        require(!round.hasVoted[msg.sender], "Already voted");

        LocalUpdate storage update = round.updates[_participant];
        require(update.isValid, "Update not found");

        if (_isValid) {
            update.score = _score;
            round.approvalCount++;
        }

        round.hasVoted[msg.sender] = true;
        round.voteCount++;

        if (round.voteCount >= validationThreshold) {
            finalizeRound(_roundId);
        }
    }

    function finalizeRound(bytes32 _roundId) internal {
        TrainingRound storage round = rounds[_roundId];
        bool isSuccessful = round.approvalCount >= round.minParticipants;
        
        round.status = isSuccessful ? 
            RoundStatus.Completed : 
            RoundStatus.Failed;

        if (isSuccessful) {
        distributeRewards(_roundId);
        }
        
        emit RoundValidated(_roundId, isSuccessful, round.approvalCount);
    }

    function distributeRewards(bytes32 _roundId) internal {
        TrainingRound storage round = rounds[_roundId];
        uint256 totalScore = 0;
        uint256 participantCount = 0;

        // Calculate total score
        for (uint i = 0; i < round.participants.length; i++) {
            address participant = round.participants[i];
            LocalUpdate storage update = round.updates[participant];
            if (update.isValid && update.score > 0) {
                totalScore += update.score;
                participantCount++;
            }
        }

        if (totalScore == 0 || participantCount == 0) return;

        // Distribute rewards
        uint256 totalReward = baseReward * participantCount;
        for (uint i = 0; i < round.participants.length; i++) {
            address participant = round.participants[i];
            LocalUpdate storage update = round.updates[participant];
            
            if (update.isValid && update.score > 0) {
                uint256 reward = (baseReward * update.score) / totalScore;
                payable(participant).transfer(reward);

                // Update metrics
                ParticipantMetrics storage metrics = participantMetrics[participant];
                metrics.totalUpdates++;
                metrics.validUpdates++;
                metrics.totalComputeTime += update.computeTime;
                metrics.averageDataSize = (metrics.averageDataSize * (metrics.totalUpdates - 1) + update.dataSize) / metrics.totalUpdates;
                metrics.reputation++;
                metrics.lastActiveRound = block.number;
            }
        }

        emit RewardsDistributed(_roundId, totalReward);
    }

    function verifySignature(
        bytes32 _messageHash,
        bytes memory _signature
    ) internal view returns (bool) {
        bytes32 ethSignedMessageHash = _messageHash.toEthSignedMessageHash();
        address signer = ethSignedMessageHash.recover(_signature);
        return signer == msg.sender;
    }

    function getRoundDetails(bytes32 _roundId)
        external
        view
        returns (
            string memory globalModelHash,
            string memory aggregationStrategy,
            uint256 minParticipants,
            uint256 maxParticipants,
            uint256 startTime,
            uint256 endTime,
            RoundStatus status,
            uint256 updateCount,
            address[] memory participants
        )
    {
        TrainingRound storage round = rounds[_roundId];
        return (
            round.globalModelHash,
            round.aggregationStrategy,
            round.minParticipants,
            round.maxParticipants,
            round.startTime,
            round.endTime,
            round.status,
            round.updateCount,
            round.participants
        );
    }

    function getUpdateDetails(
        bytes32 _roundId,
        address _participant
    ) external view returns (
        string memory modelHash,
        uint256 dataSize,
        uint256 computeTime,
        bool isValid,
        uint256 timestamp,
        uint256 score
    ) {
        LocalUpdate storage update = rounds[_roundId].updates[_participant];
        return (
            update.modelHash,
            update.dataSize,
            update.computeTime,
            update.isValid,
            update.timestamp,
            update.score
        );
    }
} 