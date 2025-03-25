// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";

contract AITrainingNetwork is ERC20, Ownable, ReentrancyGuard {
    struct Task {
        string modelHash;
        uint256 reward;
        address creator;
        TaskStatus status;
        uint256 deadline;
        address contributor;
        uint256 startTime;
    }

    struct Contributor {
        uint256 tasksCompleted;
        uint256 earnings;
        uint256 activeTask;
        uint256 reputation;
        bool isRegistered;
    }

    struct VerificationResult {
        bool verified;
        uint256 timestamp;
        address verifier;
    }

    struct ReputationTier {
        uint256 minReputation;
        uint256 rewardMultiplier;
        string name;
    }

    struct DistributedTask {
        string modelHash;
        uint256 totalReward;
        address creator;
        TaskStatus status;
        uint256 deadline;
        uint256 minContributors;
        uint256 maxContributors;
        uint256 currentContributors;
        mapping(address => bool) contributors;
        mapping(address => string) partialResults;
        uint256 highestBid;
        address highestBidder;
        uint256 bidEndTime;
    }

    mapping(uint256 => Task) public tasks;
    mapping(address => Contributor) public contributors;
    mapping(uint256 => VerificationResult) public verifications;
    uint256 public taskCount;
    uint256 public minStakeAmount;
    uint256 public requiredVerifications = 3;
    mapping(uint256 => mapping(address => bool)) public hasVerified;

    ReputationTier[] public reputationTiers;
    mapping(address => uint256) public contributorTier;

    mapping(uint256 => DistributedTask) public distributedTasks;
    mapping(uint256 => mapping(address => uint256)) public taskBids;
    
    event TaskCreated(uint256 indexed taskId, address creator, uint256 reward);
    event TaskStarted(uint256 indexed taskId, address contributor);
    event TaskCompleted(uint256 indexed taskId, address contributor);
    event ContributorRegistered(address contributor);
    event ResultSubmitted(uint256 taskId, string resultHash);
    event ResultVerified(uint256 taskId, address verifier, bool verified);
    event TierUpdated(address contributor, uint256 newTier);
    event BidPlaced(uint256 taskId, address bidder, uint256 amount);
    event BidAccepted(uint256 taskId, address bidder);
    event PartialResultSubmitted(uint256 taskId, address contributor);
    event TaskMerged(uint256 taskId, string finalResultHash);

    constructor() ERC20("AI Training Token", "ATT") {
        minStakeAmount = 100 * 10**18; // 100 tokens
        _mint(msg.sender, 1000000 * 10**18);

        // Initialize reputation tiers
        reputationTiers.push(ReputationTier(0, 100, "Bronze"));
        reputationTiers.push(ReputationTier(50, 125, "Silver"));
        reputationTiers.push(ReputationTier(100, 150, "Gold"));
        reputationTiers.push(ReputationTier(200, 200, "Diamond"));
    }

    function registerContributor() external {
        require(!contributors[msg.sender].isRegistered, "Already registered");
        require(balanceOf(msg.sender) >= minStakeAmount, "Insufficient stake");

        contributors[msg.sender] = Contributor({
            tasksCompleted: 0,
            earnings: 0,
            activeTask: 0,
            reputation: 0,
            isRegistered: true
        });

        emit ContributorRegistered(msg.sender);
    }

    function startTask(uint256 _taskId) external nonReentrant {
        require(contributors[msg.sender].isRegistered, "Not registered");
        require(contributors[msg.sender].activeTask == 0, "Already has active task");
        require(_taskId <= taskCount, "Task doesn't exist");
        require(tasks[_taskId].status == TaskStatus.Open, "Task not available");

        Task storage task = tasks[_taskId];
        task.status = TaskStatus.InProgress;
        task.contributor = msg.sender;
        task.startTime = block.timestamp;
        
        contributors[msg.sender].activeTask = _taskId;

        emit TaskStarted(_taskId, msg.sender);
    }

    function calculateReward(uint256 _baseReward, address _contributor) 
        public view returns (uint256) 
    {
        uint256 tier = contributorTier[_contributor];
        uint256 multiplier = reputationTiers[tier].rewardMultiplier;
        return (_baseReward * multiplier) / 100;
    }

    function updateContributorTier(address _contributor) internal {
        uint256 reputation = contributors[_contributor].reputation;
        
        for (uint256 i = reputationTiers.length - 1; i >= 0; i--) {
            if (reputation >= reputationTiers[i].minReputation) {
                contributorTier[_contributor] = i;
                emit TierUpdated(_contributor, i);
                break;
            }
        }
    }

    function completeTask(uint256 _taskId, string memory _resultHash) 
        external nonReentrant 
    {
        Task storage task = tasks[_taskId];
        require(task.contributor == msg.sender, "Not task contributor");
        require(task.status == TaskStatus.InProgress, "Task not in progress");
        require(block.timestamp <= task.deadline, "Task deadline passed");

        uint256 adjustedReward = calculateReward(task.reward, msg.sender);
        
        task.status = TaskStatus.Completed;
        contributors[msg.sender].tasksCompleted++;
        contributors[msg.sender].earnings += adjustedReward;
        contributors[msg.sender].reputation += 1;
        
        updateContributorTier(msg.sender);

        _transfer(address(this), msg.sender, adjustedReward);

        emit TaskCompleted(_taskId, msg.sender);
    }

    function createTask(
        string memory _modelHash,
        uint256 _reward,
        uint256 _deadline
    ) external nonReentrant {
        require(_reward > 0, "Reward must be positive");
        require(_deadline > block.timestamp, "Invalid deadline");
        require(balanceOf(msg.sender) >= _reward, "Insufficient balance");

        taskCount++;
        tasks[taskCount] = Task({
            modelHash: _modelHash,
            reward: _reward,
            creator: msg.sender,
            status: TaskStatus.Open,
            deadline: _deadline,
            contributor: address(0),
            startTime: 0
        });

        _transfer(msg.sender, address(this), _reward);
        emit TaskCreated(taskCount, msg.sender, _reward);
    }

    function submitVerification(uint256 _taskId, bool _verified) external {
        require(contributors[msg.sender].isRegistered, "Not a registered contributor");
        require(!hasVerified[_taskId][msg.sender], "Already verified this task");
        require(tasks[_taskId].status == TaskStatus.Completed, "Task not completed");

        hasVerified[_taskId][msg.sender] = true;
        
        if (_verified) {
            verifications[_taskId].verified = true;
            verifications[_taskId].timestamp = block.timestamp;
            verifications[_taskId].verifier = msg.sender;
        }

        emit ResultVerified(_taskId, msg.sender, _verified);

        // Update contributor reputation
        contributors[msg.sender].reputation += 1;
    }

    function isResultVerified(uint256 _taskId) public view returns (bool) {
        return verifications[_taskId].verified;
    }

    // New function to claim rewards after verification
    function claimRewards(uint256 _taskId) external nonReentrant {
        require(isResultVerified(_taskId), "Result not verified");
        Task storage task = tasks[_taskId];
        require(task.contributor == msg.sender, "Not task contributor");
        require(task.status == TaskStatus.Completed, "Task not completed");

        uint256 reward = task.reward;
        task.reward = 0; // Prevent double claiming
        contributors[msg.sender].earnings += reward;
        
        _transfer(address(this), msg.sender, reward);
    }

    function getContributorTierInfo(address _contributor) 
        external view returns (
            string memory name,
            uint256 minReputation,
            uint256 rewardMultiplier
        ) 
    {
        uint256 tier = contributorTier[_contributor];
        ReputationTier storage tierInfo = reputationTiers[tier];
        return (
            tierInfo.name,
            tierInfo.minReputation,
            tierInfo.rewardMultiplier
        );
    }

    function createDistributedTask(
        string memory _modelHash,
        uint256 _totalReward,
        uint256 _deadline,
        uint256 _minContributors,
        uint256 _maxContributors,
        uint256 _bidDuration
    ) external nonReentrant {
        require(_totalReward > 0, "Invalid reward");
        require(_deadline > block.timestamp, "Invalid deadline");
        require(_minContributors > 0, "Invalid min contributors");
        require(_maxContributors >= _minContributors, "Invalid max contributors");
        
        taskCount++;
        DistributedTask storage task = distributedTasks[taskCount];
        task.modelHash = _modelHash;
        task.totalReward = _totalReward;
        task.creator = msg.sender;
        task.status = TaskStatus.Open;
        task.deadline = _deadline;
        task.minContributors = _minContributors;
        task.maxContributors = _maxContributors;
        task.bidEndTime = block.timestamp + _bidDuration;

        _transfer(msg.sender, address(this), _totalReward);
        emit TaskCreated(taskCount, msg.sender, _totalReward);
    }

    function placeBid(uint256 _taskId, uint256 _bidAmount) external {
        DistributedTask storage task = distributedTasks[_taskId];
        require(block.timestamp < task.bidEndTime, "Bidding ended");
        require(_bidAmount > task.highestBid, "Bid too low");
        
        taskBids[_taskId][msg.sender] = _bidAmount;
        task.highestBid = _bidAmount;
        task.highestBidder = msg.sender;
        
        emit BidPlaced(_taskId, msg.sender, _bidAmount);
    }

    function submitPartialResult(
        uint256 _taskId, 
        string memory _resultHash
    ) external {
        DistributedTask storage task = distributedTasks[_taskId];
        require(task.contributors[msg.sender], "Not a contributor");
        require(task.status == TaskStatus.InProgress, "Task not in progress");
        
        task.partialResults[msg.sender] = _resultHash;
        emit PartialResultSubmitted(_taskId, msg.sender);
    }

    function mergeResults(
        uint256 _taskId,
        string memory _finalResultHash
    ) external {
        DistributedTask storage task = distributedTasks[_taskId];
        require(msg.sender == task.creator, "Not task creator");
        require(task.currentContributors >= task.minContributors, "Insufficient contributors");
        
        task.status = TaskStatus.Completed;
        distributeRewards(_taskId);
        
        emit TaskMerged(_taskId, _finalResultHash);
    }

    function distributeRewards(uint256 _taskId) internal {
        DistributedTask storage task = distributedTasks[_taskId];
        uint256 rewardPerContributor = task.totalReward / task.currentContributors;
        
        // Distribute rewards based on reputation and contribution
        // Implementation details...
    }
} 