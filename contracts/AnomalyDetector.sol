// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@chainlink/contracts/src/v0.8/ChainlinkClient.sol";

contract AnomalyDetector is AccessControl, ReentrancyGuard, ChainlinkClient {
    using Chainlink for Chainlink.Request;

    bytes32 public constant DETECTOR_ROLE = keccak256("DETECTOR_ROLE");
    bytes32 public constant ML_ORACLE_ROLE = keccak256("ML_ORACLE_ROLE");

    struct AnomalyModel {
        string modelType;
        bytes parameters;
        uint256 threshold;
        uint256 confidence;
        uint256 lastUpdate;
        bool isActive;
    }

    struct DetectionResult {
        bytes32 id;
        string modelType;
        uint256 timestamp;
        uint256 score;
        bool isAnomaly;
        bytes evidence;
    }

    struct ModelMetrics {
        uint256 totalDetections;
        uint256 confirmedAnomalies;
        uint256 falsePositives;
        uint256 avgConfidence;
    }

    mapping(string => AnomalyModel) public models;
    mapping(bytes32 => DetectionResult) public detectionResults;
    mapping(string => ModelMetrics) public modelMetrics;
    mapping(bytes32 => bytes32[]) public batchDetections;

    event ModelUpdated(
        string indexed modelType,
        uint256 threshold,
        uint256 confidence
    );
    event AnomalyDetected(
        bytes32 indexed detectionId,
        string modelType,
        uint256 score,
        bool isAnomaly
    );
    event ModelMetricsUpdated(
        string indexed modelType,
        uint256 confirmedAnomalies,
        uint256 falsePositives
    );

    constructor(address _link) {
        setChainlinkToken(_link);
        _setupRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _setupRole(DETECTOR_ROLE, msg.sender);
    }

    function updateModel(
        string memory modelType,
        bytes memory parameters,
        uint256 threshold,
        uint256 confidence
    ) external onlyRole(DEFAULT_ADMIN_ROLE) {
        require(threshold > 0 && threshold <= 100, "Invalid threshold");
        require(confidence > 0 && confidence <= 100, "Invalid confidence");

        models[modelType] = AnomalyModel({
            modelType: modelType,
            parameters: parameters,
            threshold: threshold,
            confidence: confidence,
            lastUpdate: block.timestamp,
            isActive: true
        });

        emit ModelUpdated(modelType, threshold, confidence);
    }

    function detectAnomaly(
        string memory modelType,
        bytes memory data
    ) external onlyRole(DETECTOR_ROLE) returns (bytes32) {
        require(models[modelType].isActive, "Model not active");

        bytes32 detectionId = keccak256(
            abi.encodePacked(
                modelType,
                data,
                block.timestamp
            )
        );

        // Request ML model inference from oracle
        Chainlink.Request memory req = buildChainlinkRequest(
            keccak256(abi.encodePacked(modelType)),
            address(this),
            this.fulfillAnomalyDetection.selector
        );

        req.add("modelType", modelType);
        req.addBytes("data", data);
        req.add("threshold", uint256ToString(models[modelType].threshold));

        bytes32 requestId = sendChainlinkRequestTo(
            getRoleMember(ML_ORACLE_ROLE, 0),
            req,
            0.1 * 10**18 // 0.1 LINK
        );

        batchDetections[requestId].push(detectionId);

        return detectionId;
    }

    function fulfillAnomalyDetection(
        bytes32 _requestId,
        uint256 _score
    ) external recordChainlinkFulfillment(_requestId) {
        bytes32[] storage detectionIds = batchDetections[_requestId];
        require(detectionIds.length > 0, "No detection found");

        for (uint256 i = 0; i < detectionIds.length; i++) {
            bytes32 detectionId = detectionIds[i];
            DetectionResult storage result = detectionResults[detectionId];
            
            string memory modelType = result.modelType;
            AnomalyModel storage model = models[modelType];

            bool isAnomaly = _score >= model.threshold;

            result.score = _score;
            result.isAnomaly = isAnomaly;
            result.timestamp = block.timestamp;

            // Update model metrics
            ModelMetrics storage metrics = modelMetrics[modelType];
            metrics.totalDetections++;
            if (isAnomaly) {
                metrics.confirmedAnomalies++;
            }
            metrics.avgConfidence = (metrics.avgConfidence * (metrics.totalDetections - 1) + _score) / metrics.totalDetections;

            emit AnomalyDetected(detectionId, modelType, _score, isAnomaly);
        }

        delete batchDetections[_requestId];
    }

    function reportFalsePositive(
        bytes32 detectionId
    ) external onlyRole(DETECTOR_ROLE) {
        DetectionResult storage result = detectionResults[detectionId];
        require(result.isAnomaly, "Not marked as anomaly");

        ModelMetrics storage metrics = modelMetrics[result.modelType];
        metrics.falsePositives++;
        metrics.confirmedAnomalies--;

        emit ModelMetricsUpdated(
            result.modelType,
            metrics.confirmedAnomalies,
            metrics.falsePositives
        );
    }

    function getModelPerformance(string memory modelType)
        external
        view
        returns (
            uint256 accuracy,
            uint256 precision,
            uint256 recall
        )
    {
        ModelMetrics storage metrics = modelMetrics[modelType];
        
        if (metrics.totalDetections == 0) return (0, 0, 0);

        uint256 truePositives = metrics.confirmedAnomalies;
        uint256 falsePositives = metrics.falsePositives;
        uint256 total = metrics.totalDetections;

        accuracy = (total - falsePositives) * 100 / total;
        precision = truePositives * 100 / (truePositives + falsePositives);
        recall = truePositives * 100 / total;
    }

    function uint256ToString(uint256 value) internal pure returns (string memory) {
        if (value == 0) {
            return "0";
        }
        uint256 temp = value;
        uint256 digits;
        while (temp != 0) {
            digits++;
            temp /= 10;
        }
        bytes memory buffer = new bytes(digits);
        while (value != 0) {
            digits -= 1;
            buffer[digits] = bytes1(uint8(48 + uint256(value % 10)));
            value /= 10;
        }
        return string(buffer);
    }
} 