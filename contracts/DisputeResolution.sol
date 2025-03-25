// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";

contract DisputeResolution is AccessControl, ReentrancyGuard {
    bytes32 public constant ARBITRATOR_ROLE = keccak256("ARBITRATOR_ROLE");

    struct Dispute {
        uint256 taskId;
        address initiator;
        string reason;
        string evidence;
        DisputeStatus status;
        uint256 timestamp;
        mapping(address => Vote) votes;
        uint256 votesFor;
        uint256 votesAgainst;
        string resolution;
    }

    struct Vote {
        bool hasVoted;
        bool support;
        string justification;
    }

    enum DisputeStatus {
        Pending,
        UnderReview,
        Resolved,
        Rejected
    }

    mapping(uint256 => Dispute) public disputes;
    mapping(address => uint256[]) public userDisputes;
    mapping(address => uint256) public arbitratorReputation;
    
    uint256 public disputeCount;
    uint256 public minArbitratorReputation;
    uint256 public requiredVotes;
    uint256 public votingPeriod;

    event DisputeCreated(uint256 indexed disputeId, uint256 indexed taskId, address initiator);
    event DisputeVoteCast(uint256 indexed disputeId, address arbitrator, bool support);
    event DisputeResolved(uint256 indexed disputeId, DisputeStatus status);

    constructor(
        uint256 _minReputation,
        uint256 _requiredVotes,
        uint256 _votingPeriod
    ) {
        _setupRole(DEFAULT_ADMIN_ROLE, msg.sender);
        minArbitratorReputation = _minReputation;
        requiredVotes = _requiredVotes;
        votingPeriod = _votingPeriod;
    }

    function createDispute(
        uint256 _taskId,
        string memory _reason,
        string memory _evidence
    ) external nonReentrant returns (uint256) {
        disputeCount++;
        Dispute storage dispute = disputes[disputeCount];
        dispute.taskId = _taskId;
        dispute.initiator = msg.sender;
        dispute.reason = _reason;
        dispute.evidence = _evidence;
        dispute.status = DisputeStatus.Pending;
        dispute.timestamp = block.timestamp;

        userDisputes[msg.sender].push(disputeCount);
        emit DisputeCreated(disputeCount, _taskId, msg.sender);
        return disputeCount;
    }

    function castVote(
        uint256 _disputeId,
        bool _support,
        string memory _justification
    ) external onlyRole(ARBITRATOR_ROLE) nonReentrant {
        require(arbitratorReputation[msg.sender] >= minArbitratorReputation, "Insufficient reputation");
        
        Dispute storage dispute = disputes[_disputeId];
        require(dispute.status == DisputeStatus.UnderReview, "Dispute not under review");
        require(!dispute.votes[msg.sender].hasVoted, "Already voted");
        require(block.timestamp <= dispute.timestamp + votingPeriod, "Voting period ended");

        dispute.votes[msg.sender] = Vote({
            hasVoted: true,
            support: _support,
            justification: _justification
        });

        if (_support) {
            dispute.votesFor++;
        } else {
            dispute.votesAgainst++;
        }

        emit DisputeVoteCast(_disputeId, msg.sender, _support);
        updateArbitratorReputation(msg.sender, true);
        checkDisputeResolution(_disputeId);
    }

    function checkDisputeResolution(uint256 _disputeId) internal {
        Dispute storage dispute = disputes[_disputeId];
        uint256 totalVotes = dispute.votesFor + dispute.votesAgainst;

        if (totalVotes >= requiredVotes) {
            if (dispute.votesFor > dispute.votesAgainst) {
                dispute.status = DisputeStatus.Resolved;
            } else {
                dispute.status = DisputeStatus.Rejected;
            }
            emit DisputeResolved(_disputeId, dispute.status);
        }
    }

    function updateArbitratorReputation(address _arbitrator, bool _successful) internal {
        if (_successful) {
            arbitratorReputation[_arbitrator]++;
        } else {
            if (arbitratorReputation[_arbitrator] > 0) {
                arbitratorReputation[_arbitrator]--;
            }
        }
    }

    function getDisputeDetails(uint256 _disputeId)
        external view returns (
            uint256 taskId,
            address initiator,
            string memory reason,
            DisputeStatus status,
            uint256 votesFor,
            uint256 votesAgainst
        )
    {
        Dispute storage dispute = disputes[_disputeId];
        return (
            dispute.taskId,
            dispute.initiator,
            dispute.reason,
            dispute.status,
            dispute.votesFor,
            dispute.votesAgainst
        );
    }
} 