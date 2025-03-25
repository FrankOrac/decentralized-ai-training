// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/utils/math/SafeMath.sol";

contract AdvancedAnalytics is AccessControl, ReentrancyGuard {
    using SafeMath for uint256;

    bytes32 public constant ANALYZER_ROLE = keccak256("ANALYZER_ROLE");

    struct AnalyticsMetric {
        string name;
        uint256[] values;
        uint256[] timestamps;
        uint256 movingAverage;
        uint256 standardDeviation;
        uint256 lastUpdateBlock;
    }

    struct ProposalAnalytics {
        uint256 proposalId;
        uint256 votingDuration;
        uint256 participationRate;
        uint256 approvalRate;
        uint256 executionGas;
        uint256 voterCount;
        mapping(address => VoterBehavior) voterBehavior;
    }

    struct VoterBehavior {
        uint256 totalVotes;
        uint256 approvalVotes;
        uint256 averageVotingDelay;
        uint256 lastVoteTimestamp;
    }

    struct PredictionModel {
        uint256 confidenceScore;
        uint256 historicalAccuracy;
        uint256[] predictions;
        uint256[] actuals;
    }

    mapping(bytes32 => AnalyticsMetric) public metrics;
    mapping(uint256 => ProposalAnalytics) public proposalAnalytics;
    mapping(address => PredictionModel) public predictionModels;
    
    uint256 public constant ANALYSIS_WINDOW = 30 days;
    uint256 public constant MIN_DATA_POINTS = 10;

    event MetricUpdated(
        bytes32 indexed metricId,
        string name,
        uint256 value,
        uint256 movingAverage
    );
    event AnomalyDetected(
        bytes32 indexed metricId,
        uint256 value,
        uint256 threshold,
        string anomalyType
    );
    event PredictionMade(
        address indexed model,
        uint256 prediction,
        uint256 confidence
    );

    constructor() {
        _setupRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _setupRole(ANALYZER_ROLE, msg.sender);
    }

    function recordMetric(
        string memory name,
        uint256 value
    ) external onlyRole(ANALYZER_ROLE) {
        bytes32 metricId = keccak256(abi.encodePacked(name));
        AnalyticsMetric storage metric = metrics[metricId];
        
        if (metric.values.length == 0) {
            metric.name = name;
        }

        metric.values.push(value);
        metric.timestamps.push(block.timestamp);
        metric.lastUpdateBlock = block.number;

        // Update moving average
        if (metric.values.length >= MIN_DATA_POINTS) {
            metric.movingAverage = calculateMovingAverage(metric.values);
            metric.standardDeviation = calculateStandardDeviation(
                metric.values,
                metric.movingAverage
            );

            // Check for anomalies
            if (value > metric.movingAverage.add(metric.standardDeviation.mul(2))) {
                emit AnomalyDetected(
                    metricId,
                    value,
                    metric.movingAverage.add(metric.standardDeviation.mul(2)),
                    "ABOVE_THRESHOLD"
                );
            }
        }

        emit MetricUpdated(metricId, name, value, metric.movingAverage);
    }

    function recordProposalAnalytics(
        uint256 proposalId,
        uint256 votingDuration,
        uint256 participationRate,
        uint256 approvalRate,
        uint256 executionGas,
        uint256 voterCount
    ) external onlyRole(ANALYZER_ROLE) {
        ProposalAnalytics storage analytics = proposalAnalytics[proposalId];
        analytics.proposalId = proposalId;
        analytics.votingDuration = votingDuration;
        analytics.participationRate = participationRate;
        analytics.approvalRate = approvalRate;
        analytics.executionGas = executionGas;
        analytics.voterCount = voterCount;
    }

    function updateVoterBehavior(
        uint256 proposalId,
        address voter,
        bool approved,
        uint256 votingDelay
    ) external onlyRole(ANALYZER_ROLE) {
        ProposalAnalytics storage analytics = proposalAnalytics[proposalId];
        VoterBehavior storage behavior = analytics.voterBehavior[voter];
        
        behavior.totalVotes = behavior.totalVotes.add(1);
        if (approved) {
            behavior.approvalVotes = behavior.approvalVotes.add(1);
        }
        
        if (behavior.lastVoteTimestamp > 0) {
            behavior.averageVotingDelay = behavior.averageVotingDelay
                .mul(behavior.totalVotes.sub(1))
                .add(votingDelay)
                .div(behavior.totalVotes);
        } else {
            behavior.averageVotingDelay = votingDelay;
        }
        
        behavior.lastVoteTimestamp = block.timestamp;
    }

    function makePrediction(
        address modelAddress,
        uint256 prediction,
        uint256 confidence
    ) external onlyRole(ANALYZER_ROLE) {
        PredictionModel storage model = predictionModels[modelAddress];
        model.predictions.push(prediction);
        model.confidenceScore = confidence;
        
        emit PredictionMade(modelAddress, prediction, confidence);
    }

    function updatePredictionAccuracy(
        address modelAddress,
        uint256 actual
    ) external onlyRole(ANALYZER_ROLE) {
        PredictionModel storage model = predictionModels[modelAddress];
        require(model.predictions.length > model.actuals.length, "No prediction to validate");
        
        model.actuals.push(actual);
        uint256 latestPrediction = model.predictions[model.predictions.length - 1];
        
        // Update historical accuracy
        uint256 accuracy = calculatePredictionAccuracy(latestPrediction, actual);
        model.historicalAccuracy = model.historicalAccuracy > 0 ?
            model.historicalAccuracy.add(accuracy).div(2) :
            accuracy;
    }

    function getMetricStats(bytes32 metricId)
        external
        view
        returns (
            uint256[] memory values,
            uint256[] memory timestamps,
            uint256 movingAverage,
            uint256 standardDeviation
        )
    {
        AnalyticsMetric storage metric = metrics[metricId];
        return (
            metric.values,
            metric.timestamps,
            metric.movingAverage,
            metric.standardDeviation
        );
    }

    function getVoterStats(uint256 proposalId, address voter)
        external
        view
        returns (
            uint256 totalVotes,
            uint256 approvalVotes,
            uint256 averageVotingDelay,
            uint256 lastVoteTimestamp
        )
    {
        VoterBehavior storage behavior = proposalAnalytics[proposalId].voterBehavior[voter];
        return (
            behavior.totalVotes,
            behavior.approvalVotes,
            behavior.averageVotingDelay,
            behavior.lastVoteTimestamp
        );
    }

    function calculateMovingAverage(uint256[] memory values)
        internal
        pure
        returns (uint256)
    {
        require(values.length > 0, "No values provided");
        uint256 sum = 0;
        uint256 count = 0;
        
        for (uint256 i = 0; i < values.length; i++) {
            sum = sum.add(values[i]);
            count = count.add(1);
        }
        
        return sum.div(count);
    }

    function calculateStandardDeviation(
        uint256[] memory values,
        uint256 mean
    ) internal pure returns (uint256) {
        require(values.length > 0, "No values provided");
        uint256 sumSquaredDiff = 0;
        
        for (uint256 i = 0; i < values.length; i++) {
            if (values[i] > mean) {
                sumSquaredDiff = sumSquaredDiff.add(
                    (values[i].sub(mean)).mul(values[i].sub(mean))
                );
            } else {
                sumSquaredDiff = sumSquaredDiff.add(
                    (mean.sub(values[i])).mul(mean.sub(values[i]))
                );
            }
        }
        
        return sqrt(sumSquaredDiff.div(values.length));
    }

    function calculatePredictionAccuracy(
        uint256 predicted,
        uint256 actual
    ) internal pure returns (uint256) {
        if (predicted > actual) {
            return uint256(100).sub(
                predicted.sub(actual).mul(100).div(predicted)
            );
        } else {
            return uint256(100).sub(
                actual.sub(predicted).mul(100).div(actual)
            );
        }
    }

    function sqrt(uint256 x) internal pure returns (uint256) {
        if (x == 0) return 0;
        uint256 z = (x + 1) / 2;
        uint256 y = x;
        while (z < y) {
            y = z;
            z = (x / z + z) / 2;
        }
        return y;
    }
} 