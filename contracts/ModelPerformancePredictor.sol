// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";

contract ModelPerformancePredictor is AccessControl, ReentrancyGuard {
    bytes32 public constant PREDICTOR_ROLE = keccak256("PREDICTOR_ROLE");
    bytes32 public constant ORACLE_ROLE = keccak256("ORACLE_ROLE");

    struct Prediction {
        bytes32 predictionId;
        string modelHash;
        uint256 predictedAccuracy;
        uint256 predictedLatency;
        uint256 predictedResourceUsage;
        uint256 confidence;
        address predictor;
        uint256 timestamp;
        bool isVerified;
        bool wasAccurate;
    }

    struct ModelMetrics {
        uint256[] accuracyHistory;
        uint256[] latencyHistory;
        uint256[] resourceUsageHistory;
        mapping(address => PredictorScore) predictorScores;
        uint256 totalPredictions;
        uint256 accuratePredictions;
    }

    struct PredictorScore {
        uint256 totalPredictions;
        uint256 accuratePredictions;
        uint256 averageConfidence;
        uint256 reputation;
    }

    struct PerformanceThresholds {
        uint256 accuracyTolerance;
        uint256 latencyTolerance;
        uint256 resourceTolerance;
        uint256 minConfidence;
    }

    mapping(bytes32 => Prediction) public predictions;
    mapping(string => ModelMetrics) public modelMetrics;
    mapping(address => uint256) public predictorReputations;
    
    PerformanceThresholds public thresholds;
    uint256 public predictionReward;
    uint256 public penaltyAmount;

    event PredictionSubmitted(
        bytes32 indexed predictionId,
        string modelHash,
        uint256 predictedAccuracy,
        uint256 confidence
    );
    event PredictionVerified(
        bytes32 indexed predictionId,
        bool wasAccurate,
        uint256 actualAccuracy
    );
    event PredictorReputationUpdated(
        address indexed predictor,
        uint256 newReputation,
        bool wasAccurate
    );

    constructor(
        uint256 _accuracyTolerance,
        uint256 _latencyTolerance,
        uint256 _resourceTolerance,
        uint256 _minConfidence,
        uint256 _predictionReward,
        uint256 _penaltyAmount
    ) {
        _setupRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _setupRole(PREDICTOR_ROLE, msg.sender);
        _setupRole(ORACLE_ROLE, msg.sender);

        thresholds = PerformanceThresholds({
            accuracyTolerance: _accuracyTolerance,
            latencyTolerance: _latencyTolerance,
            resourceTolerance: _resourceTolerance,
            minConfidence: _minConfidence
        });

        predictionReward = _predictionReward;
        penaltyAmount = _penaltyAmount;
    }

    function submitPrediction(
        string memory _modelHash,
        uint256 _predictedAccuracy,
        uint256 _predictedLatency,
        uint256 _predictedResourceUsage,
        uint256 _confidence
    ) external onlyRole(PREDICTOR_ROLE) returns (bytes32) {
        require(_confidence >= thresholds.minConfidence, "Confidence too low");
        require(_predictedAccuracy <= 100, "Invalid accuracy");

        bytes32 predictionId = keccak256(abi.encodePacked(
            _modelHash,
            block.timestamp,
            msg.sender
        ));

        predictions[predictionId] = Prediction({
            predictionId: predictionId,
            modelHash: _modelHash,
            predictedAccuracy: _predictedAccuracy,
            predictedLatency: _predictedLatency,
            predictedResourceUsage: _predictedResourceUsage,
            confidence: _confidence,
            predictor: msg.sender,
            timestamp: block.timestamp,
            isVerified: false,
            wasAccurate: false
        });

        modelMetrics[_modelHash].totalPredictions++;

        emit PredictionSubmitted(
            predictionId,
            _modelHash,
            _predictedAccuracy,
            _confidence
        );

        return predictionId;
    }

    function verifyPrediction(
        bytes32 _predictionId,
        uint256 _actualAccuracy,
        uint256 _actualLatency,
        uint256 _actualResourceUsage
    ) external onlyRole(ORACLE_ROLE) nonReentrant {
        Prediction storage prediction = predictions[_predictionId];
        require(!prediction.isVerified, "Already verified");
        require(_actualAccuracy <= 100, "Invalid accuracy");

        bool isAccurate = isPredictionAccurate(
            prediction.predictedAccuracy,
            prediction.predictedLatency,
            prediction.predictedResourceUsage,
            _actualAccuracy,
            _actualLatency,
            _actualResourceUsage
        );

        prediction.isVerified = true;
        prediction.wasAccurate = isAccurate;

        ModelMetrics storage metrics = modelMetrics[prediction.modelHash];
        metrics.accuracyHistory.push(_actualAccuracy);
        metrics.latencyHistory.push(_actualLatency);
        metrics.resourceUsageHistory.push(_actualResourceUsage);

        if (isAccurate) {
            metrics.accuratePredictions++;
            predictorReputations[prediction.predictor] += predictionReward;
            payable(prediction.predictor).transfer(predictionReward);
        } else {
            predictorReputations[prediction.predictor] = predictorReputations[prediction.predictor] > penaltyAmount ?
                predictorReputations[prediction.predictor] - penaltyAmount : 0;
        }

        // Update predictor score
        PredictorScore storage score = metrics.predictorScores[prediction.predictor];
        score.totalPredictions++;
        if (isAccurate) score.accuratePredictions++;
        score.averageConfidence = (score.averageConfidence * (score.totalPredictions - 1) + prediction.confidence) / score.totalPredictions;
        score.reputation = predictorReputations[prediction.predictor];

        emit PredictionVerified(_predictionId, isAccurate, _actualAccuracy);
        emit PredictorReputationUpdated(
            prediction.predictor,
            predictorReputations[prediction.predictor],
            isAccurate
        );
    }

    function isPredictionAccurate(
        uint256 _predictedAccuracy,
        uint256 _predictedLatency,
        uint256 _predictedResourceUsage,
        uint256 _actualAccuracy,
        uint256 _actualLatency,
        uint256 _actualResourceUsage
    ) internal view returns (bool) {
        bool accuracyMatch = abs(int256(_predictedAccuracy) - int256(_actualAccuracy)) <= int256(thresholds.accuracyTolerance);
        bool latencyMatch = abs(int256(_predictedLatency) - int256(_actualLatency)) <= int256(thresholds.latencyTolerance);
        bool resourceMatch = abs(int256(_predictedResourceUsage) - int256(_actualResourceUsage)) <= int256(thresholds.resourceTolerance);

        return accuracyMatch && latencyMatch && resourceMatch;
    }

    function abs(int256 x) internal pure returns (int256) {
        return x >= 0 ? x : -x;
    }

    function getPredictionDetails(bytes32 _predictionId)
        external
        view
        returns (
            string memory modelHash,
            uint256 predictedAccuracy,
            uint256 predictedLatency,
            uint256 predictedResourceUsage,
            uint256 confidence,
            address predictor,
            uint256 timestamp,
            bool isVerified,
            bool wasAccurate
        )
    {
        Prediction storage prediction = predictions[_predictionId];
        return (
            prediction.modelHash,
            prediction.predictedAccuracy,
            prediction.predictedLatency,
            prediction.predictedResourceUsage,
            prediction.confidence,
            prediction.predictor,
            prediction.timestamp,
            prediction.isVerified,
            prediction.wasAccurate
        );
    }

    function getModelPerformanceHistory(string memory _modelHash)
        external
        view
        returns (
            uint256[] memory accuracyHistory,
            uint256[] memory latencyHistory,
            uint256[] memory resourceUsageHistory,
            uint256 totalPredictions,
            uint256 accuratePredictions
        )
    {
        ModelMetrics storage metrics = modelMetrics[_modelHash];
        return (
            metrics.accuracyHistory,
            metrics.latencyHistory,
            metrics.resourceUsageHistory,
            metrics.totalPredictions,
            metrics.accuratePredictions
        );
    }

    function getPredictorScore(
        string memory _modelHash,
        address _predictor
    ) external view returns (
        uint256 totalPredictions,
        uint256 accuratePredictions,
        uint256 averageConfidence,
        uint256 reputation
    ) {
        PredictorScore storage score = modelMetrics[_modelHash].predictorScores[_predictor];
        return (
            score.totalPredictions,
            score.accuratePredictions,
            score.averageConfidence,
            score.reputation
        );
    }

    function updateThresholds(
        uint256 _accuracyTolerance,
        uint256 _latencyTolerance,
        uint256 _resourceTolerance,
        uint256 _minConfidence
    ) external onlyRole(DEFAULT_ADMIN_ROLE) {
        thresholds = PerformanceThresholds({
            accuracyTolerance: _accuracyTolerance,
            latencyTolerance: _latencyTolerance,
            resourceTolerance: _resourceTolerance,
            minConfidence: _minConfidence
        });
    }

    function updateRewards(
        uint256 _predictionReward,
        uint256 _penaltyAmount
    ) external onlyRole(DEFAULT_ADMIN_ROLE) {
        predictionReward = _predictionReward;
        penaltyAmount = _penaltyAmount;
    }
} 