// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";

contract AdvancedAnalytics is AccessControl, ReentrancyGuard {
    bytes32 public constant ANALYST_ROLE = keccak256("ANALYST_ROLE");

    struct AnalyticsMetric {
        string name;
        uint256[] values;
        uint256[] timestamps;
        MetricType metricType;
        AggregationType aggregationType;
    }

    struct Insight {
        string metricName;
        string description;
        uint256 confidence;
        uint256 timestamp;
        address analyst;
        bool validated;
    }

    struct Correlation {
        string metric1;
        string metric2;
        int256 coefficient;
        uint256 timestamp;
        uint256 sampleSize;
    }

    enum MetricType {
        Performance,
        Resource,
        Training,
        Financial
    }

    enum AggregationType {
        Sum,
        Average,
        Maximum,
        Minimum,
        Weighted
    }

    mapping(string => AnalyticsMetric) public metrics;
    mapping(string => Insight[]) public insights;
    mapping(string => Correlation[]) public correlations;
    mapping(string => mapping(uint256 => uint256)) public aggregatedData;

    uint256 public constant MAX_HISTORY = 1000;
    uint256 public constant MIN_SAMPLE_SIZE = 30;

    event MetricRecorded(
        string indexed name,
        uint256 value,
        MetricType metricType
    );
    event InsightGenerated(
        string indexed metricName,
        string description,
        uint256 confidence
    );
    event CorrelationFound(
        string indexed metric1,
        string indexed metric2,
        int256 coefficient
    );

    constructor() {
        _setupRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _setupRole(ANALYST_ROLE, msg.sender);
    }

    function recordMetric(
        string memory _name,
        uint256 _value,
        MetricType _type,
        AggregationType _aggregationType
    ) external onlyRole(ANALYST_ROLE) {
        AnalyticsMetric storage metric = metrics[_name];
        
        if (metric.values.length == 0) {
            metric.name = _name;
            metric.metricType = _type;
            metric.aggregationType = _aggregationType;
        }

        metric.values.push(_value);
        metric.timestamps.push(block.timestamp);

        // Maintain history limit
        if (metric.values.length > MAX_HISTORY) {
            for (uint i = 0; i < metric.values.length - 1; i++) {
                metric.values[i] = metric.values[i + 1];
                metric.timestamps[i] = metric.timestamps[i + 1];
            }
            metric.values.pop();
            metric.timestamps.pop();
        }

        // Update aggregated data
        updateAggregation(_name, _value);

        emit MetricRecorded(_name, _value, _type);
    }

    function updateAggregation(string memory _name, uint256 _value) internal {
        AnalyticsMetric storage metric = metrics[_name];
        uint256 timeframe = (block.timestamp / 1 days) * 1 days; // Daily aggregation

        if (metric.aggregationType == AggregationType.Sum) {
            aggregatedData[_name][timeframe] += _value;
        } else if (metric.aggregationType == AggregationType.Average) {
            uint256 count = metric.values.length;
            aggregatedData[_name][timeframe] = 
                (aggregatedData[_name][timeframe] * (count - 1) + _value) / count;
        } else if (metric.aggregationType == AggregationType.Maximum) {
            if (_value > aggregatedData[_name][timeframe]) {
                aggregatedData[_name][timeframe] = _value;
            }
        } else if (metric.aggregationType == AggregationType.Minimum) {
            if (aggregatedData[_name][timeframe] == 0 || _value < aggregatedData[_name][timeframe]) {
                aggregatedData[_name][timeframe] = _value;
            }
        }
    }

    function generateInsight(
        string memory _metricName,
        string memory _description,
        uint256 _confidence
    ) external onlyRole(ANALYST_ROLE) {
        require(_confidence <= 100, "Invalid confidence value");
        require(metrics[_metricName].values.length > 0, "Metric not found");

        insights[_metricName].push(Insight({
            metricName: _metricName,
            description: _description,
            confidence: _confidence,
            timestamp: block.timestamp,
            analyst: msg.sender,
            validated: false
        }));

        emit InsightGenerated(_metricName, _description, _confidence);
    }

    function calculateCorrelation(
        string memory _metric1,
        string memory _metric2
    ) external onlyRole(ANALYST_ROLE) {
        AnalyticsMetric storage m1 = metrics[_metric1];
        AnalyticsMetric storage m2 = metrics[_metric2];

        require(
            m1.values.length >= MIN_SAMPLE_SIZE && 
            m2.values.length >= MIN_SAMPLE_SIZE,
            "Insufficient data"
        );

        uint256 sampleSize = min(m1.values.length, m2.values.length);
        int256 coefficient = computePearsonCorrelation(
            m1.values,
            m2.values,
            sampleSize
        );

        correlations[_metric1].push(Correlation({
            metric1: _metric1,
            metric2: _metric2,
            coefficient: coefficient,
            timestamp: block.timestamp,
            sampleSize: sampleSize
        }));

        emit CorrelationFound(_metric1, _metric2, coefficient);
    }

    function computePearsonCorrelation(
        uint256[] storage _values1,
        uint256[] storage _values2,
        uint256 _sampleSize
    ) internal pure returns (int256) {
        // Simplified correlation calculation
        // Returns correlation coefficient multiplied by 1000 for precision
        int256 sum1 = 0;
        int256 sum2 = 0;
        int256 sum1Sq = 0;
        int256 sum2Sq = 0;
        int256 pSum = 0;

        for (uint256 i = 0; i < _sampleSize; i++) {
            int256 val1 = int256(_values1[i]);
            int256 val2 = int256(_values2[i]);
            
            sum1 += val1;
            sum2 += val2;
            sum1Sq += val1 * val1;
            sum2Sq += val2 * val2;
            pSum += val1 * val2;
        }

        int256 num = (int256(_sampleSize) * pSum) - (sum1 * sum2);
        int256 den = sqrt(
            (int256(_sampleSize) * sum1Sq - sum1 * sum1) *
            (int256(_sampleSize) * sum2Sq - sum2 * sum2)
        );

        if (den == 0) return 0;
        return (num * 1000) / den;
    }

    function sqrt(int256 x) internal pure returns (int256) {
        if (x < 0) return 0;
        
        int256 z = (x + 1) / 2;
        int256 y = x;
        
        while (z < y) {
            y = z;
            z = (x / z + z) / 2;
        }
        
        return y;
    }

    function min(uint256 a, uint256 b) internal pure returns (uint256) {
        return a < b ? a : b;
    }

    function getMetricHistory(string memory _name)
        external
        view
        returns (
            uint256[] memory values,
            uint256[] memory timestamps,
            MetricType metricType,
            AggregationType aggregationType
        )
    {
        AnalyticsMetric storage metric = metrics[_name];
        return (
            metric.values,
            metric.timestamps,
            metric.metricType,
            metric.aggregationType
        );
    }

    function getInsights(string memory _metricName)
        external
        view
        returns (Insight[] memory)
    {
        return insights[_metricName];
    }

    function getCorrelations(string memory _metricName)
        external
        view
        returns (Correlation[] memory)
    {
        return correlations[_metricName];
    }

    function getAggregatedData(
        string memory _name,
        uint256 _timeframe
    ) external view returns (uint256) {
        return aggregatedData[_name][_timeframe];
    }
} 