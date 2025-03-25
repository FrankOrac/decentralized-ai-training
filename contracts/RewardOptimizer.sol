// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";

contract RewardOptimizer is AccessControl, ReentrancyGuard {
    struct ContributorScore {
        uint256 qualityScore;
        uint256 participationScore;
        uint256 reputationScore;
        uint256 lastUpdated;
    }

    struct RewardPool {
        uint256 totalAmount;
        uint256 distributedAmount;
        uint256 remainingAmount;
        uint256 startTime;
        uint256 endTime;
        mapping(address => bool) hasReceived;
    }

    mapping(address => ContributorScore) public contributorScores;
    mapping(uint256 => RewardPool) public rewardPools;
    uint256 public poolCount;

    uint256 public constant QUALITY_WEIGHT = 40;
    uint256 public constant PARTICIPATION_WEIGHT = 30;
    uint256 public constant REPUTATION_WEIGHT = 30;

    event ScoreUpdated(address indexed contributor, uint256 newScore);
    event RewardDistributed(address indexed contributor, uint256 amount);
    event PoolCreated(uint256 indexed poolId, uint256 amount);

    constructor() {
        _setupRole(DEFAULT_ADMIN_ROLE, msg.sender);
    }

    function createRewardPool(uint256 _duration) external payable {
        require(msg.value > 0, "Must provide rewards");
        
        poolCount++;
        RewardPool storage pool = rewardPools[poolCount];
        pool.totalAmount = msg.value;
        pool.remainingAmount = msg.value;
        pool.startTime = block.timestamp;
        pool.endTime = block.timestamp + _duration;

        emit PoolCreated(poolCount, msg.value);
    }

    function updateContributorScore(
        address _contributor,
        uint256 _qualityScore,
        uint256 _participationScore,
        uint256 _reputationScore
    ) external onlyRole(DEFAULT_ADMIN_ROLE) {
        require(_qualityScore <= 100, "Invalid quality score");
        require(_participationScore <= 100, "Invalid participation score");
        require(_reputationScore <= 100, "Invalid reputation score");

        ContributorScore storage score = contributorScores[_contributor];
        score.qualityScore = _qualityScore;
        score.participationScore = _participationScore;
        score.reputationScore = _reputationScore;
        score.lastUpdated = block.timestamp;

        emit ScoreUpdated(_contributor, calculateTotalScore(_contributor));
    }

    function calculateTotalScore(address _contributor) 
        public view returns (uint256) 
    {
        ContributorScore storage score = contributorScores[_contributor];
        
        return (
            (score.qualityScore * QUALITY_WEIGHT) +
            (score.participationScore * PARTICIPATION_WEIGHT) +
            (score.reputationScore * REPUTATION_WEIGHT)
        ) / 100;
    }

    function claimReward(uint256 _poolId) external nonReentrant {
        RewardPool storage pool = rewardPools[_poolId];
        require(block.timestamp >= pool.startTime, "Pool not started");
        require(block.timestamp <= pool.endTime, "Pool ended");
        require(!pool.hasReceived[msg.sender], "Already claimed");
        require(pool.remainingAmount > 0, "Pool empty");

        uint256 score = calculateTotalScore(msg.sender);
        require(score > 0, "No score");

        uint256 reward = (pool.totalAmount * score) / 10000; // Base reward on score
        if (reward > pool.remainingAmount) {
            reward = pool.remainingAmount;
        }

        pool.remainingAmount -= reward;
        pool.distributedAmount += reward;
        pool.hasReceived[msg.sender] = true;

        (bool success, ) = msg.sender.call{value: reward}("");
        require(success, "Transfer failed");

        emit RewardDistributed(msg.sender, reward);
    }

    function getPoolDetails(uint256 _poolId)
        external view returns (
            uint256 totalAmount,
            uint256 distributedAmount,
            uint256 remainingAmount,
            uint256 startTime,
            uint256 endTime
        )
    {
        RewardPool storage pool = rewardPools[_poolId];
        return (
            pool.totalAmount,
            pool.distributedAmount,
            pool.remainingAmount,
            pool.startTime,
            pool.endTime
        );
    }

    function getContributorDetails(address _contributor)
        external view returns (
            uint256 qualityScore,
            uint256 participationScore,
            uint256 reputationScore,
            uint256 totalScore
        )
    {
        ContributorScore storage score = contributorScores[_contributor];
        return (
            score.qualityScore,
            score.participationScore,
            score.reputationScore,
            calculateTotalScore(_contributor)
        );
    }
} 