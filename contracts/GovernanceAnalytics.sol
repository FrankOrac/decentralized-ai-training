// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/utils/math/SafeMath.sol";

contract GovernanceAnalytics is AccessControl, ReentrancyGuard {
    using SafeMath for uint256;

    bytes32 public constant ANALYZER_ROLE = keccak256("ANALYZER_ROLE");

    struct ProposalMetrics {
        uint256 voterParticipation;
        uint256 executionGasUsed;
        uint256 timeToFinalization;
        uint256 voterCount;
        mapping(address => bool) uniqueVoters;
        uint256 quorumReachedBlock;
        bool wasSuccessful;
    }

    struct VoterMetrics {
        uint256 proposalsVoted;
        uint256 proposalsCreated;
        uint256 successfulProposals;
        uint256 totalGasSpent;
        uint256 lastActiveBlock;
    }

    struct HistoricalSnapshot {
        uint256 timestamp;
        uint256 totalProposals;
        uint256 successRate;
        uint256 averageParticipation;
        uint256 activeVoters;
    }

    mapping(uint256 => ProposalMetrics) public proposalMetrics;
    mapping(address => VoterMetrics) public voterMetrics;
    HistoricalSnapshot[] public historicalSnapshots;
    
    uint256 public constant SNAPSHOT_PERIOD = 7 days;
    uint256 public lastSnapshotTimestamp;

    event MetricsUpdated(
        uint256 indexed proposalId,
        uint256 participation,
        bool successful
    );
    event VoterActivityRecorded(
        address indexed voter,
        uint256 indexed proposalId,
        uint256 gasUsed
    );
    event SnapshotCreated(
        uint256 indexed timestamp,
        uint256 totalProposals,
        uint256 successRate
    );
    event AnomalyDetected(
        uint256 indexed proposalId,
        string anomalyType,
        string description
    );

    constructor() {
        _setupRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _setupRole(ANALYZER_ROLE, msg.sender);
        lastSnapshotTimestamp = block.timestamp;
    }

    function recordProposalMetrics(
        uint256 proposalId,
        uint256 voterParticipation,
        uint256 gasUsed,
        uint256 startBlock,
        bool successful
    ) external onlyRole(ANALYZER_ROLE) {
        ProposalMetrics storage metrics = proposalMetrics[proposalId];
        metrics.voterParticipation = voterParticipation;
        metrics.executionGasUsed = gasUsed;
        metrics.timeToFinalization = block.number.sub(startBlock);
        metrics.wasSuccessful = successful;

        emit MetricsUpdated(proposalId, voterParticipation, successful);

        _checkForAnomalies(proposalId);
    }

    function recordVoterActivity(
        address voter,
        uint256 proposalId,
        uint256 gasUsed,
        bool isProposalCreator
    ) external onlyRole(ANALYZER_ROLE) {
        VoterMetrics storage metrics = voterMetrics[voter];
        metrics.proposalsVoted = metrics.proposalsVoted.add(1);
        metrics.totalGasSpent = metrics.totalGasSpent.add(gasUsed);
        metrics.lastActiveBlock = block.number;

        if (isProposalCreator) {
            metrics.proposalsCreated = metrics.proposalsCreated.add(1);
        }

        ProposalMetrics storage proposal = proposalMetrics[proposalId];
        if (!proposal.uniqueVoters[voter]) {
            proposal.uniqueVoters[voter] = true;
            proposal.voterCount = proposal.voterCount.add(1);
        }

        emit VoterActivityRecorded(voter, proposalId, gasUsed);
    }

    function createSnapshot() external {
        require(
            block.timestamp >= lastSnapshotTimestamp.add(SNAPSHOT_PERIOD),
            "Too early for new snapshot"
        );

        uint256 totalProposals = 0;
        uint256 successfulProposals = 0;
        uint256 totalParticipation = 0;
        uint256 activeVoters = 0;

        // Calculate metrics for the snapshot period
        for (uint256 i = historicalSnapshots.length; i > 0; i--) {
            if (block.timestamp.sub(historicalSnapshots[i-1].timestamp) <= SNAPSHOT_PERIOD) {
                totalProposals = totalProposals.add(1);
                if (proposalMetrics[i].wasSuccessful) {
                    successfulProposals = successfulProposals.add(1);
                }
                totalParticipation = totalParticipation.add(proposalMetrics[i].voterParticipation);
                activeVoters = activeVoters.add(proposalMetrics[i].voterCount);
            }
        }

        uint256 successRate = totalProposals > 0 ? 
            successfulProposals.mul(100).div(totalProposals) : 0;
        uint256 averageParticipation = totalProposals > 0 ? 
            totalParticipation.div(totalProposals) : 0;

        historicalSnapshots.push(HistoricalSnapshot({
            timestamp: block.timestamp,
            totalProposals: totalProposals,
            successRate: successRate,
            averageParticipation: averageParticipation,
            activeVoters: activeVoters
        }));

        lastSnapshotTimestamp = block.timestamp;

        emit SnapshotCreated(block.timestamp, totalProposals, successRate);
    }

    function _checkForAnomalies(uint256 proposalId) internal {
        ProposalMetrics storage metrics = proposalMetrics[proposalId];

        // Check for unusually low participation
        if (metrics.voterParticipation < getAverageParticipation().div(2)) {
            emit AnomalyDetected(
                proposalId,
                "LOW_PARTICIPATION",
                "Voter participation significantly below average"
            );
        }

        // Check for unusually high gas usage
        if (metrics.executionGasUsed > getAverageGasUsage().mul(2)) {
            emit AnomalyDetected(
                proposalId,
                "HIGH_GAS_USAGE",
                "Execution gas usage significantly above average"
            );
        }

        // Check for unusual voting patterns
        if (metrics.timeToFinalization < getAverageFinalizationTime().div(2)) {
            emit AnomalyDetected(
                proposalId,
                "RAPID_FINALIZATION",
                "Proposal finalized unusually quickly"
            );
        }
    }

    function getAverageParticipation() public view returns (uint256) {
        if (historicalSnapshots.length == 0) return 0;
        return historicalSnapshots[historicalSnapshots.length - 1].averageParticipation;
    }

    function getAverageGasUsage() public view returns (uint256) {
        uint256 totalGas = 0;
        uint256 count = 0;
        
        for (uint256 i = 0; i < historicalSnapshots.length; i++) {
            if (block.timestamp.sub(historicalSnapshots[i].timestamp) <= SNAPSHOT_PERIOD) {
                totalGas = totalGas.add(proposalMetrics[i].executionGasUsed);
                count = count.add(1);
            }
        }
        
        return count > 0 ? totalGas.div(count) : 0;
    }

    function getAverageFinalizationTime() public view returns (uint256) {
        uint256 totalTime = 0;
        uint256 count = 0;
        
        for (uint256 i = 0; i < historicalSnapshots.length; i++) {
            if (block.timestamp.sub(historicalSnapshots[i].timestamp) <= SNAPSHOT_PERIOD) {
                totalTime = totalTime.add(proposalMetrics[i].timeToFinalization);
                count = count.add(1);
            }
        }
        
        return count > 0 ? totalTime.div(count) : 0;
    }

    function getVoterStats(address voter) external view returns (
        uint256 proposalsVoted,
        uint256 proposalsCreated,
        uint256 successfulProposals,
        uint256 totalGasSpent,
        uint256 lastActiveBlock
    ) {
        VoterMetrics storage metrics = voterMetrics[voter];
        return (
            metrics.proposalsVoted,
            metrics.proposalsCreated,
            metrics.successfulProposals,
            metrics.totalGasSpent,
            metrics.lastActiveBlock
        );
    }

    function getLatestSnapshot() external view returns (HistoricalSnapshot memory) {
        require(historicalSnapshots.length > 0, "No snapshots available");
        return historicalSnapshots[historicalSnapshots.length - 1];
    }
} 