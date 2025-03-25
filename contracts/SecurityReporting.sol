// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@chainlink/contracts/src/v0.8/ChainlinkClient.sol";

contract SecurityReporting is AccessControl, ReentrancyGuard, ChainlinkClient {
    bytes32 public constant REPORTER_ROLE = keccak256("REPORTER_ROLE");
    bytes32 public constant ANALYST_ROLE = keccak256("ANALYST_ROLE");

    struct Report {
        bytes32 id;
        string reportType;
        uint256 timestamp;
        bytes data;
        address generator;
        bool isVerified;
        mapping(address => bool) verifications;
    }

    struct MetricHistory {
        uint256[] timestamps;
        uint256[] values;
        uint256 movingAverage;
        uint256 standardDeviation;
    }

    struct PredictionModel {
        bytes32 id;
        string modelType;
        bytes parameters;
        uint256 accuracy;
        uint256 lastUpdate;
        bool isActive;
    }

    mapping(bytes32 => Report) public reports;
    mapping(string => MetricHistory) public metrics;
    mapping(bytes32 => PredictionModel) public predictionModels;
    
    uint256 public constant MAX_HISTORY_LENGTH = 1000;
    uint256 public constant VERIFICATION_THRESHOLD = 2;

    event ReportGenerated(
        bytes32 indexed reportId,
        string reportType,
        address generator
    );
    event MetricUpdated(
        string indexed metricName,
        uint256 value,
        uint256 movingAverage
    );
    event AnomalyDetected(
        string indexed metricName,
        uint256 value,
        uint256 deviation
    );
    event PredictionModelUpdated(
        bytes32 indexed modelId,
        string modelType,
        uint256 accuracy
    );

    constructor(address _link) {
        setChainlinkToken(_link);
        _setupRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _setupRole(REPORTER_ROLE, msg.sender);
    }

    function generateReport(
        string memory reportType,
        bytes memory data
    ) external onlyRole(REPORTER_ROLE) returns (bytes32) {
        bytes32 reportId = keccak256(
            abi.encodePacked(
                reportType,
                block.timestamp,
                msg.sender
            )
        );

        Report storage report = reports[reportId];
        report.id = reportId;
        report.reportType = reportType;
        report.timestamp = block.timestamp;
        report.data = data;
        report.generator = msg.sender;

        emit ReportGenerated(reportId, reportType, msg.sender);
        return reportId;
    }

    function verifyReport(bytes32 reportId) external onlyRole(ANALYST_ROLE) {
        Report storage report = reports[reportId];
        require(report.id == reportId, "Report not found");
        require(!report.verifications[msg.sender], "Already verified");

        report.verifications[msg.sender] = true;

        uint256 verificationCount = 0;
        for (uint256 i = 0; i < getRoleMemberCount(ANALYST_ROLE); i++) {
            address analyst = getRoleMember(ANALYST_ROLE, i);
            if (report.verifications[analyst]) {
                verificationCount++;
            }
        }

        if (verificationCount >= VERIFICATION_THRESHOLD) {
            report.isVerified = true;
        }
    }

    function updateMetric(
        string memory metricName,
        uint256 value
    ) external onlyRole(REPORTER_ROLE) {
        MetricHistory storage history = metrics[metricName];

        // Update history arrays
        if (history.timestamps.length >= MAX_HISTORY_LENGTH) {
            // Remove oldest entry
            for (uint256 i = 0; i < history.timestamps.length - 1; i++) {
                history.timestamps[i] = history.timestamps[i + 1];
                history.values[i] = history.values[i + 1];
            }
            history.timestamps.pop();
            history.values.pop();
        }

        history.timestamps.push(block.timestamp);
        history.values.push(value);

        // Calculate moving average
        uint256 sum = 0;
        uint256 count = 0;
        for (uint256 i = history.values.length >= 10 ? history.values.length - 10 : 0;
             i < history.values.length;
             i++) {
            sum += history.values[i];
            count++;
        }
        history.movingAverage = sum / count;

        // Calculate standard deviation
        uint256 squaredDiffSum = 0;
        for (uint256 i = history.values.length >= 10 ? history.values.length - 10 : 0;
             i < history.values.length;
             i++) {
            if (history.values[i] > history.movingAverage) {
                squaredDiffSum += (history.values[i] - history.movingAverage) ** 2;
            } else {
                squaredDiffSum += (history.movingAverage - history.values[i]) ** 2;
            }
        }
        history.standardDeviation = sqrt(squaredDiffSum / count);

        emit MetricUpdated(metricName, value, history.movingAverage);

        // Check for anomalies
        uint256 deviation = value > history.movingAverage ?
            value - history.movingAverage :
            history.movingAverage - value;

        if (deviation > history.standardDeviation * 2) {
            emit AnomalyDetected(metricName, value, deviation);
        }
    }

    function updatePredictionModel(
        string memory modelType,
        bytes memory parameters,
        uint256 accuracy
    ) external onlyRole(ANALYST_ROLE) returns (bytes32) {
        bytes32 modelId = keccak256(
            abi.encodePacked(
                modelType,
                block.timestamp
            )
        );

        predictionModels[modelId] = PredictionModel({
            id: modelId,
            modelType: modelType,
            parameters: parameters,
            accuracy: accuracy,
            lastUpdate: block.timestamp,
            isActive: true
        });

        emit PredictionModelUpdated(modelId, modelType, accuracy);
        return modelId;
    }

    function getMetricHistory(string memory metricName)
        external
        view
        returns (
            uint256[] memory timestamps,
            uint256[] memory values,
            uint256 movingAverage,
            uint256 standardDeviation
        )
    {
        MetricHistory storage history = metrics[metricName];
        return (
            history.timestamps,
            history.values,
            history.movingAverage,
            history.standardDeviation
        );
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