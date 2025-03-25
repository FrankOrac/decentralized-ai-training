// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/utils/math/SafeMath.sol";

contract GovernanceSystem is AccessControl, ReentrancyGuard {
    using SafeMath for uint256;

    bytes32 public constant PROPOSER_ROLE = keccak256("PROPOSER_ROLE");
    bytes32 public constant EXECUTOR_ROLE = keccak256("EXECUTOR_ROLE");

    struct Proposal {
        uint256 id;
        address proposer;
        string description;
        bytes[] calldatas;
        address[] targets;
        uint256[] values;
        uint256 startBlock;
        uint256 endBlock;
        uint256 forVotes;
        uint256 againstVotes;
        bool executed;
        bool canceled;
        mapping(address => bool) hasVoted;
    }

    struct SystemParameters {
        uint256 votingPeriod;
        uint256 votingDelay;
        uint256 proposalThreshold;
        uint256 quorumPercentage;
        uint256 executionDelay;
    }

    mapping(uint256 => Proposal) public proposals;
    uint256 public proposalCount;
    SystemParameters public parameters;

    event ProposalCreated(
        uint256 indexed proposalId,
        address indexed proposer,
        string description
    );
    event VoteCast(
        address indexed voter,
        uint256 indexed proposalId,
        bool support
    );
    event ProposalExecuted(uint256 indexed proposalId);
    event ProposalCanceled(uint256 indexed proposalId);
    event ParametersUpdated(SystemParameters parameters);

    constructor() {
        _setupRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _setupRole(PROPOSER_ROLE, msg.sender);
        _setupRole(EXECUTOR_ROLE, msg.sender);

        parameters = SystemParameters({
            votingPeriod: 40320, // ~7 days in blocks
            votingDelay: 1,      // 1 block
            proposalThreshold: 100e18, // 100 tokens
            quorumPercentage: 4,  // 4%
            executionDelay: 2     // 2 blocks
        });
    }

    function propose(
        address[] memory targets,
        uint256[] memory values,
        bytes[] memory calldatas,
        string memory description
    ) public returns (uint256) {
        require(
            hasRole(PROPOSER_ROLE, msg.sender),
            "GovernanceSystem: must have proposer role"
        );
        require(
            targets.length == values.length &&
            targets.length == calldatas.length,
            "GovernanceSystem: invalid proposal length"
        );

        proposalCount++;
        Proposal storage newProposal = proposals[proposalCount];
        newProposal.id = proposalCount;
        newProposal.proposer = msg.sender;
        newProposal.description = description;
        newProposal.targets = targets;
        newProposal.values = values;
        newProposal.calldatas = calldatas;
        newProposal.startBlock = block.number.add(parameters.votingDelay);
        newProposal.endBlock = newProposal.startBlock.add(parameters.votingPeriod);

        emit ProposalCreated(proposalCount, msg.sender, description);
        return proposalCount;
    }

    function castVote(uint256 proposalId, bool support) public {
        Proposal storage proposal = proposals[proposalId];
        require(
            block.number >= proposal.startBlock,
            "GovernanceSystem: voting not started"
        );
        require(
            block.number <= proposal.endBlock,
            "GovernanceSystem: voting ended"
        );
        require(
            !proposal.hasVoted[msg.sender],
            "GovernanceSystem: already voted"
        );

        proposal.hasVoted[msg.sender] = true;
        if (support) {
            proposal.forVotes = proposal.forVotes.add(1);
        } else {
            proposal.againstVotes = proposal.againstVotes.add(1);
        }

        emit VoteCast(msg.sender, proposalId, support);
    }

    function executeProposal(uint256 proposalId) public nonReentrant {
        require(
            hasRole(EXECUTOR_ROLE, msg.sender),
            "GovernanceSystem: must have executor role"
        );
        Proposal storage proposal = proposals[proposalId];
        require(
            block.number > proposal.endBlock.add(parameters.executionDelay),
            "GovernanceSystem: execution delay not met"
        );
        require(!proposal.executed, "GovernanceSystem: already executed");
        require(!proposal.canceled, "GovernanceSystem: proposal canceled");
        require(
            _quorumReached(proposal) && _voteSucceeded(proposal),
            "GovernanceSystem: quorum not reached or vote unsuccessful"
        );

        proposal.executed = true;

        for (uint256 i = 0; i < proposal.targets.length; i++) {
            (bool success, ) = proposal.targets[i].call{value: proposal.values[i]}(
                proposal.calldatas[i]
            );
            require(success, "GovernanceSystem: execution failed");
        }

        emit ProposalExecuted(proposalId);
    }

    function cancelProposal(uint256 proposalId) public {
        Proposal storage proposal = proposals[proposalId];
        require(
            msg.sender == proposal.proposer || hasRole(DEFAULT_ADMIN_ROLE, msg.sender),
            "GovernanceSystem: only proposer or admin"
        );
        require(!proposal.executed, "GovernanceSystem: already executed");
        require(!proposal.canceled, "GovernanceSystem: already canceled");

        proposal.canceled = true;
        emit ProposalCanceled(proposalId);
    }

    function updateParameters(SystemParameters memory newParameters) public {
        require(
            hasRole(DEFAULT_ADMIN_ROLE, msg.sender),
            "GovernanceSystem: must have admin role"
        );
        parameters = newParameters;
        emit ParametersUpdated(newParameters);
    }

    function _quorumReached(Proposal storage proposal) internal view returns (bool) {
        uint256 totalVotes = proposal.forVotes.add(proposal.againstVotes);
        return totalVotes.mul(100) >= parameters.quorumPercentage;
    }

    function _voteSucceeded(Proposal storage proposal) internal pure returns (bool) {
        return proposal.forVotes > proposal.againstVotes;
    }

    receive() external payable {}
} 