// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/utils/math/SafeMath.sol";

contract GovernanceReporting is AccessControl, ReentrancyGuard {
    using SafeMath for uint256;

    bytes32 public constant REPORTER_ROLE = keccak256("REPORTER_ROLE");

    struct Report {
        uint256 id;
        string reportType;
        uint256 timestamp;
        bytes data;
        mapping(string => uint256) metrics;
        mapping(string => string) metadata;
    }

    struct ReportSummary {
        uint256 totalProposals;
        uint256 totalVotes;
        uint256 uniqueVoters;
        uint256 averageParticipation;
        uint256 executionSuccess;
        uint256 timelockedActions;
        uint256 delegationCount;
    }

    struct MetricHistory {
        string name;
        uint256[] values;
        uint256[] timestamps;
    }

    mapping(uint256 => Report) public reports;
    mapping(string => MetricHistory) public metricHistories;
    uint256 public reportCount;
    uint256 public constant REPORT_RETENTION = 365 days;

    event ReportGenerated(
        uint256 indexed id,
        string reportType,
        uint256 timestamp
    );
    event MetricUpdated(
        string indexed name,
        uint256 value,
        uint256 timestamp
    );
    event AnomalyDetected(
        string metricName,
        uint256 value,
        uint256 threshold,
        uint256 timestamp
    );

    constructor() {
        _setupRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _setupRole(REPORTER_ROLE, msg.sender);
    }

    function generateReport(
        string memory reportType,
        bytes memory data,
        string[] memory metricNames,
        uint256[] memory metricValues,
        string[] memory metadataKeys,
        string[] memory metadataValues
    ) external onlyRole(REPORTER_ROLE) returns (uint256) {
        require(
            metricNames.length == metricValues.length,
            "Metrics length mismatch"
        );
        require(
            metadataKeys.length == metadataValues.length,
            "Metadata length mismatch"
        );

        reportCount++;
        Report storage newReport = reports[reportCount];
        newReport.id = reportCount;
        newReport.reportType = reportType;
        newReport.timestamp = block.timestamp;
        newReport.data = data;

        for (uint256 i = 0; i < metricNames.length; i++) {
            newReport.metrics[metricNames[i]] = metricValues[i];
            updateMetricHistory(metricNames[i], metricValues[i]);
        }

        for (uint256 i = 0; i < metadataKeys.length; i++) {
            newReport.metadata[metadataKeys[i]] = metadataValues[i];
        }

        emit ReportGenerated(reportCount, reportType, block.timestamp);
        return reportCount;
    }

    function updateMetricHistory(string memory name, uint256 value) internal {
        MetricHistory storage history = metricHistories[name];
        if (history.values.length == 0) {
            history.name = name;
        }
        history.values.push(value);
        history.timestamps.push(block.timestamp);

        // Check for anomalies
        if (history.values.length > 1) {
            uint256 average = calculateMovingAverage(name, 5);
            uint256 threshold = average.mul(120).div(100); // 20% deviation threshold
            if (value > threshold) {
                emit AnomalyDetected(name, value, threshold, block.timestamp);
            }
        }

        emit MetricUpdated(name, value, block.timestamp);
    }

    function calculateMovingAverage(string memory metricName, uint256 periods)
        public
        view
        returns (uint256)
    {
        MetricHistory storage history = metricHistories[metricName];
        require(history.values.length > 0, "No history available");

        uint256 startIndex = history.values.length >= periods ?
            history.values.length - periods :
            0;
        uint256 sum = 0;
        uint256 count = 0;

        for (uint256 i = startIndex; i < history.values.length; i++) {
            sum = sum.add(history.values[i]);
            count++;
        }

        return sum.div(count);
    }

    function getReportSummary(uint256 reportId)
        external
        view
        returns (ReportSummary memory)
    {
        Report storage report = reports[reportId];
        return ReportSummary({
            totalProposals: report.metrics["totalProposals"],
            totalVotes: report.metrics["totalVotes"],
            uniqueVoters: report.metrics["uniqueVoters"],
            averageParticipation: report.metrics["averageParticipation"],
            executionSuccess: report.metrics["executionSuccess"],
            timelockedActions: report.metrics["timelockedActions"],
            delegationCount: report.metrics["delegationCount"]
        });
    }

    function getMetricHistory(string memory metricName)
        external
        view
        returns (uint256[] memory values, uint256[] memory timestamps)
    {
        MetricHistory storage history = metricHistories[metricName];
        return (history.values, history.timestamps);
    }

    function cleanupOldReports() external onlyRole(REPORTER_ROLE) {
        uint256 cutoffTime = block.timestamp.sub(REPORT_RETENTION);
        for (uint256 i = 1; i <= reportCount; i++) {
            if (reports[i].timestamp < cutoffTime) {
                delete reports[i];
            }
        }
    }
} 