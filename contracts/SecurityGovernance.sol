// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/utils/Counters.sol";

contract SecurityGovernance is AccessControl, ReentrancyGuard {
    using Counters for Counters.Counter;

    bytes32 public constant GOVERNANCE_ADMIN = keccak256("GOVERNANCE_ADMIN");
    bytes32 public constant PROPOSAL_CREATOR = keccak256("PROPOSAL_CREATOR");

    struct Proposal {
        uint256 id;
        string title;
        string description;
        address proposer;
        uint256 startTime;
        uint256 endTime;
        bool executed;
        bool canceled;
        uint256 forVotes;
        uint256 againstVotes;
        mapping(address => bool) hasVoted;
        bytes[] actions;
        address[] targets;
        uint256[] values;
    }

    struct VotingPower {
        uint256 amount;
        uint256 lockTime;
    }

    struct GovernanceMetrics {
        uint256 totalProposals;
        uint256 executedProposals;
        uint256 participationRate;
        uint256 averageVotingPower;
    }

    IERC20 public governanceToken;
    Counters.Counter public proposalCount;
    
    mapping(uint256 => Proposal) public proposals;
    mapping(address => VotingPower) public votingPowers;
    mapping(bytes4 => bool) public allowedFunctions;
    
    uint256 public constant MIN_PROPOSAL_THRESHOLD = 100 * 10**18; // 100 tokens
    uint256 public constant MIN_VOTING_PERIOD = 3 days;
    uint256 public constant MAX_VOTING_PERIOD = 14 days;
    uint256 public constant EXECUTION_DELAY = 2 days;

    event ProposalCreated(
        uint256 indexed proposalId,
        address indexed proposer,
        string title
    );
    event VoteCast(
        uint256 indexed proposalId,
        address indexed voter,
        bool support,
        uint256 weight
    );
    event ProposalExecuted(
        uint256 indexed proposalId,
        address executor
    );
    event ProposalCanceled(
        uint256 indexed proposalId,
        address canceler
    );
    event VotingPowerUpdated(
        address indexed account,
        uint256 amount,
        uint256 lockTime
    );

    constructor(address _governanceToken) {
        governanceToken = IERC20(_governanceToken);
        _setupRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _setupRole(GOVERNANCE_ADMIN, msg.sender);
    }

    function createProposal(
        string memory title,
        string memory description,
        bytes[] memory actions,
        address[] memory targets,
        uint256[] memory values,
        uint256 votingPeriod
    ) external onlyRole(PROPOSAL_CREATOR) returns (uint256) {
        require(
            votingPeriod >= MIN_VOTING_PERIOD && votingPeriod <= MAX_VOTING_PERIOD,
            "Invalid voting period"
        );
        require(
            actions.length == targets.length && targets.length == values.length,
            "Array length mismatch"
        );
        require(
            getVotingPower(msg.sender) >= MIN_PROPOSAL_THRESHOLD,
            "Insufficient voting power"
        );

        // Validate actions
        for (uint256 i = 0; i < actions.length; i++) {
            require(allowedFunctions[bytes4(actions[i])], "Action not allowed");
        }

        proposalCount.increment();
        uint256 proposalId = proposalCount.current();

        Proposal storage proposal = proposals[proposalId];
        proposal.id = proposalId;
        proposal.title = title;
        proposal.description = description;
        proposal.proposer = msg.sender;
        proposal.startTime = block.timestamp;
        proposal.endTime = block.timestamp + votingPeriod;
        proposal.actions = actions;
        proposal.targets = targets;
        proposal.values = values;

        emit ProposalCreated(proposalId, msg.sender, title);
        return proposalId;
    }

    function castVote(
        uint256 proposalId,
        bool support
    ) external nonReentrant {
        Proposal storage proposal = proposals[proposalId];
        require(
            block.timestamp >= proposal.startTime &&
            block.timestamp <= proposal.endTime,
            "Voting period not active"
        );
        require(!proposal.hasVoted[msg.sender], "Already voted");

        uint256 votingPower = getVotingPower(msg.sender);
        require(votingPower > 0, "No voting power");

        proposal.hasVoted[msg.sender] = true;
        if (support) {
            proposal.forVotes += votingPower;
        } else {
            proposal.againstVotes += votingPower;
        }

        emit VoteCast(proposalId, msg.sender, support, votingPower);
    }

    function executeProposal(uint256 proposalId) external nonReentrant {
        Proposal storage proposal = proposals[proposalId];
        require(!proposal.executed && !proposal.canceled, "Proposal not active");
        require(
            block.timestamp > proposal.endTime + EXECUTION_DELAY,
            "Execution delay not passed"
        );
        require(
            proposal.forVotes > proposal.againstVotes,
            "Proposal not approved"
        );

        proposal.executed = true;

        for (uint256 i = 0; i < proposal.actions.length; i++) {
            (bool success,) = proposal.targets[i].call{value: proposal.values[i]}(
                proposal.actions[i]
            );
            require(success, "Action execution failed");
        }

        emit ProposalExecuted(proposalId, msg.sender);
    }

    function cancelProposal(uint256 proposalId) external {
        Proposal storage proposal = proposals[proposalId];
        require(
            msg.sender == proposal.proposer ||
            hasRole(GOVERNANCE_ADMIN, msg.sender),
            "Not authorized"
        );
        require(!proposal.executed && !proposal.canceled, "Proposal not active");

        proposal.canceled = true;
        emit ProposalCanceled(proposalId, msg.sender);
    }

    function updateVotingPower(uint256 amount, uint256 lockTime) external {
        require(amount > 0, "Invalid amount");
        require(
            governanceToken.transferFrom(msg.sender, address(this), amount),
            "Token transfer failed"
        );

        votingPowers[msg.sender] = VotingPower({
            amount: amount,
            lockTime: block.timestamp + lockTime
        });

        emit VotingPowerUpdated(msg.sender, amount, lockTime);
    }

    function getVotingPower(address account) public view returns (uint256) {
        VotingPower memory power = votingPowers[account];
        if (block.timestamp >= power.lockTime) {
            return 0;
        }
        return power.amount;
    }

    function getProposalStatus(uint256 proposalId)
        external
        view
        returns (
            bool isActive,
            bool isExecutable,
            uint256 forVotes,
            uint256 againstVotes,
            uint256 timeRemaining
        )
    {
        Proposal storage proposal = proposals[proposalId];
        
        isActive = block.timestamp >= proposal.startTime &&
                  block.timestamp <= proposal.endTime &&
                  !proposal.executed &&
                  !proposal.canceled;
                  
        isExecutable = block.timestamp > proposal.endTime + EXECUTION_DELAY &&
                      proposal.forVotes > proposal.againstVotes &&
                      !proposal.executed &&
                      !proposal.canceled;
                      
        timeRemaining = block.timestamp <= proposal.endTime ?
                       proposal.endTime - block.timestamp : 0;

        return (
            isActive,
            isExecutable,
            proposal.forVotes,
            proposal.againstVotes,
            timeRemaining
        );
    }

    function getGovernanceMetrics()
        external
        view
        returns (GovernanceMetrics memory)
    {
        uint256 totalProposals = proposalCount.current();
        uint256 executedProposals = 0;
        uint256 totalParticipation = 0;
        uint256 totalVotingPower = 0;
        
        for (uint256 i = 1; i <= totalProposals; i++) {
            Proposal storage proposal = proposals[i];
            if (proposal.executed) {
                executedProposals++;
            }
            totalParticipation += proposal.forVotes + proposal.againstVotes;
        }

        return GovernanceMetrics({
            totalProposals: totalProposals,
            executedProposals: executedProposals,
            participationRate: totalProposals > 0 ?
                (totalParticipation * 100) / (totalProposals * MIN_PROPOSAL_THRESHOLD) : 0,
            averageVotingPower: totalProposals > 0 ?
                totalParticipation / totalProposals : 0
        });
    }

    receive() external payable {}
} 