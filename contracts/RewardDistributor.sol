// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/utils/math/SafeMath.sol";

contract RewardDistributor is AccessControl, ReentrancyGuard {
    using SafeMath for uint256;

    bytes32 public constant DISTRIBUTOR_ROLE = keccak256("DISTRIBUTOR_ROLE");

    struct RewardPool {
        bytes32 poolId;
        uint256 totalAmount;
        uint256 remainingAmount;
        uint256 startTime;
        uint256 endTime;
        DistributionStrategy strategy;
        mapping(address => uint256) contributions;
        mapping(address => uint256) claimedRewards;
        address[] participants;
        bool isActive;
    }

    struct ParticipantScore {
        uint256 qualityScore;
        uint256 participationScore;
        uint256 reputationScore;
        uint256 timeWeight;
        uint256 totalScore;
        bool isCalculated;
    }

    struct DistributionStrategy {
        uint256 qualityWeight;
        uint256 participationWeight;
        uint256 reputationWeight;
        uint256 timeWeight;
        uint256 minQualityThreshold;
        uint256 bonusThreshold;
        uint256 bonusMultiplier;
    }

    mapping(bytes32 => RewardPool) public rewardPools;
    mapping(bytes32 => mapping(address => ParticipantScore)) public participantScores;
    mapping(address => uint256) public participantReputation;
    
    uint256 public constant SCORE_PRECISION = 1e6;
    uint256 public constant MAX_PARTICIPANTS = 1000;
    uint256 public constant MIN_POOL_DURATION = 1 hours;

    event RewardPoolCreated(
        bytes32 indexed poolId,
        uint256 totalAmount,
        uint256 startTime,
        uint256 endTime
    );
    event ContributionRecorded(
        bytes32 indexed poolId,
        address indexed participant,
        uint256 amount
    );
    event ScoreCalculated(
        bytes32 indexed poolId,
        address indexed participant,
        uint256 totalScore
    );
    event RewardClaimed(
        bytes32 indexed poolId,
        address indexed participant,
        uint256 amount
    );
    event PoolFinalized(
        bytes32 indexed poolId,
        uint256 totalDistributed
    );

    constructor() {
        _setupRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _setupRole(DISTRIBUTOR_ROLE, msg.sender);
    }

    function createRewardPool(
        uint256 _totalAmount,
        uint256 _duration,
        DistributionStrategy memory _strategy
    ) external onlyRole(DISTRIBUTOR_ROLE) returns (bytes32) {
        require(_totalAmount > 0, "Invalid reward amount");
        require(_duration >= MIN_POOL_DURATION, "Duration too short");
        require(
            _strategy.qualityWeight.add(_strategy.participationWeight)
                .add(_strategy.reputationWeight).add(_strategy.timeWeight) == SCORE_PRECISION,
            "Invalid weights"
        );

        bytes32 poolId = keccak256(abi.encodePacked(
            block.timestamp,
            _totalAmount,
            msg.sender
        ));

        RewardPool storage pool = rewardPools[poolId];
        pool.poolId = poolId;
        pool.totalAmount = _totalAmount;
        pool.remainingAmount = _totalAmount;
        pool.startTime = block.timestamp;
        pool.endTime = block.timestamp.add(_duration);
        pool.strategy = _strategy;
        pool.isActive = true;

        emit RewardPoolCreated(poolId, _totalAmount, pool.startTime, pool.endTime);
        return poolId;
    }

    function recordContribution(
        bytes32 _poolId,
        address _participant,
        uint256 _qualityScore,
        uint256 _participationValue
    ) external onlyRole(DISTRIBUTOR_ROLE) {
        RewardPool storage pool = rewardPools[_poolId];
        require(pool.isActive, "Pool not active");
        require(block.timestamp <= pool.endTime, "Pool ended");
        require(_qualityScore <= SCORE_PRECISION, "Invalid quality score");

        if (!isParticipant(pool, _participant)) {
            require(pool.participants.length < MAX_PARTICIPANTS, "Pool full");
            pool.participants.push(_participant);
        }

        pool.contributions[_participant] = pool.contributions[_participant].add(_participationValue);

        ParticipantScore storage score = participantScores[_poolId][_participant];
        score.qualityScore = _qualityScore;
        score.participationScore = _participationValue;
        score.reputationScore = participantReputation[_participant];
        score.timeWeight = calculateTimeWeight(pool.startTime, block.timestamp, pool.endTime);
        score.isCalculated = false;

        emit ContributionRecorded(_poolId, _participant, _participationValue);
    }

    function calculateScores(bytes32 _poolId) external onlyRole(DISTRIBUTOR_ROLE) {
        RewardPool storage pool = rewardPools[_poolId];
        require(pool.isActive, "Pool not active");

        for (uint256 i = 0; i < pool.participants.length; i++) {
            address participant = pool.participants[i];
            ParticipantScore storage score = participantScores[_poolId][participant];
            
            if (!score.isCalculated) {
                uint256 totalScore = calculateTotalScore(
                    pool.strategy,
                    score.qualityScore,
                    score.participationScore,
                    score.reputationScore,
                    score.timeWeight
                );

                // Apply bonus if applicable
                if (totalScore > pool.strategy.bonusThreshold) {
                    totalScore = totalScore.mul(pool.strategy.bonusMultiplier).div(SCORE_PRECISION);
                }

                score.totalScore = totalScore;
                score.isCalculated = true;

                emit ScoreCalculated(_poolId, participant, totalScore);
            }
        }
    }

    function claimReward(bytes32 _poolId) external nonReentrant {
        RewardPool storage pool = rewardPools[_poolId];
        require(pool.isActive, "Pool not active");
        require(block.timestamp > pool.endTime, "Pool not ended");

        ParticipantScore storage score = participantScores[_poolId][msg.sender];
        require(score.isCalculated, "Score not calculated");
        require(pool.claimedRewards[msg.sender] == 0, "Already claimed");

        uint256 totalPoolScore = calculatePoolTotalScore(_poolId);
        require(totalPoolScore > 0, "No valid scores");

        uint256 reward = pool.totalAmount.mul(score.totalScore).div(totalPoolScore);
        require(reward <= pool.remainingAmount, "Insufficient pool balance");

        pool.remainingAmount = pool.remainingAmount.sub(reward);
        pool.claimedRewards[msg.sender] = reward;
        
        // Update reputation
        participantReputation[msg.sender] = participantReputation[msg.sender].add(
            score.qualityScore.mul(reward).div(pool.totalAmount)
        );

        payable(msg.sender).transfer(reward);
        emit RewardClaimed(_poolId, msg.sender, reward);
    }

    function finalizePool(bytes32 _poolId) external onlyRole(DISTRIBUTOR_ROLE) {
        RewardPool storage pool = rewardPools[_poolId];
        require(pool.isActive, "Pool not active");
        require(block.timestamp > pool.endTime, "Pool not ended");

        uint256 totalDistributed = pool.totalAmount.sub(pool.remainingAmount);
        pool.isActive = false;

        // Return remaining funds to distributor
        if (pool.remainingAmount > 0) {
            payable(msg.sender).transfer(pool.remainingAmount);
        }

        emit PoolFinalized(_poolId, totalDistributed);
    }

    function calculateTotalScore(
        DistributionStrategy memory _strategy,
        uint256 _qualityScore,
        uint256 _participationScore,
        uint256 _reputationScore,
        uint256 _timeWeight
    ) internal pure returns (uint256) {
        if (_qualityScore < _strategy.minQualityThreshold) {
            return 0;
        }

        return _qualityScore.mul(_strategy.qualityWeight)
            .add(_participationScore.mul(_strategy.participationWeight))
            .add(_reputationScore.mul(_strategy.reputationWeight))
            .add(_timeWeight.mul(_strategy.timeWeight))
            .div(SCORE_PRECISION);
    }

    function calculateTimeWeight(
        uint256 _startTime,
        uint256 _contributionTime,
        uint256 _endTime
    ) internal pure returns (uint256) {
        if (_contributionTime <= _startTime || _contributionTime >= _endTime) {
        return 0;
    }

        uint256 timeRange = _endTime.sub(_startTime);
        uint256 timePassed = _contributionTime.sub(_startTime);
        
        // Earlier contributions get higher weights
        return SCORE_PRECISION.sub(
            timePassed.mul(SCORE_PRECISION).div(timeRange)
        );
    }

    function calculatePoolTotalScore(bytes32 _poolId) internal view returns (uint256) {
        RewardPool storage pool = rewardPools[_poolId];
        uint256 totalScore = 0;

        for (uint256 i = 0; i < pool.participants.length; i++) {
            address participant = pool.participants[i];
            ParticipantScore storage score = participantScores[_poolId][participant];
            if (score.isCalculated) {
                totalScore = totalScore.add(score.totalScore);
            }
        }

        return totalScore;
    }

    function isParticipant(
        RewardPool storage _pool,
        address _participant
    ) internal view returns (bool) {
        for (uint256 i = 0; i < _pool.participants.length; i++) {
            if (_pool.participants[i] == _participant) {
                return true;
            }
        }
        return false;
    }

    function getPoolDetails(bytes32 _poolId)
        external
        view
        returns (
            uint256 totalAmount,
            uint256 remainingAmount,
            uint256 startTime,
            uint256 endTime,
            bool isActive,
            uint256 participantCount,
            DistributionStrategy memory strategy
        )
    {
        RewardPool storage pool = rewardPools[_poolId];
        return (
            pool.totalAmount,
            pool.remainingAmount,
            pool.startTime,
            pool.endTime,
            pool.isActive,
            pool.participants.length,
            pool.strategy
        );
    }

    function getParticipantScore(
        bytes32 _poolId,
        address _participant
    ) external view returns (
        uint256 qualityScore,
        uint256 participationScore,
        uint256 reputationScore,
        uint256 timeWeight,
        uint256 totalScore,
        bool isCalculated
    ) {
        ParticipantScore storage score = participantScores[_poolId][_participant];
        return (
            score.qualityScore,
            score.participationScore,
            score.reputationScore,
            score.timeWeight,
            score.totalScore,
            score.isCalculated
        );
    }

    function updateDistributionStrategy(
        bytes32 _poolId,
        DistributionStrategy memory _newStrategy
    ) external onlyRole(DISTRIBUTOR_ROLE) {
        RewardPool storage pool = rewardPools[_poolId];
        require(pool.isActive, "Pool not active");
        require(
            _newStrategy.qualityWeight.add(_newStrategy.participationWeight)
                .add(_newStrategy.reputationWeight).add(_newStrategy.timeWeight) == SCORE_PRECISION,
            "Invalid weights"
        );

        pool.strategy = _newStrategy;
        
        // Reset score calculations
        for (uint256 i = 0; i < pool.participants.length; i++) {
            participantScores[_poolId][pool.participants[i]].isCalculated = false;
        }
    }

    receive() external payable {
        // Accept ETH transfers
    }
} 