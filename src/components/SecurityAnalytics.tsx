import React, { useState, useEffect, useCallback } from "react";
import {
  Box,
  Grid,
  Heading,
  VStack,
  HStack,
  Text,
  Select,
  Button,
  useToast,
  Spinner,
} from "@chakra-ui/react";
import {
  ResponsiveContainer,
  ComposedChart,
  Line,
  Bar,
  Area,
  XAxis,
  YAxis,
  CartesianGrid,
  Tooltip,
  Legend,
  Scatter,
  RadarChart,
  PolarGrid,
  PolarAngleAxis,
  PolarRadiusAxis,
  Radar,
} from "recharts";
import { format } from "date-fns";
import { useContract } from "../hooks/useContract";
import { ethers } from "ethers";

interface AnalyticsData {
  timestamp: number;
  totalAlerts: number;
  verifiedAlerts: number;
  falsePositives: number;
  avgSeverity: number;
  responseTime: number;
  consensusRate: number;
}

interface ChainMetrics {
  chainId: number;
  alertCount: number;
  verifiedCount: number;
  falsePositives: number;
  avgResponseTime: number;
  healthScore: number;
}

interface AlertDistribution {
  type: string;
  count: number;
  severity: number;
  verificationRate: number;
}

export const SecurityAnalytics: React.FC = () => {
  const [timeRange, setTimeRange] = useState<string>("24h");
  const [analyticsData, setAnalyticsData] = useState<AnalyticsData[]>([]);
  const [chainMetrics, setChainMetrics] = useState<ChainMetrics[]>([]);
  const [alertDistribution, setAlertDistribution] = useState<
    AlertDistribution[]
  >([]);
  const [loading, setLoading] = useState<boolean>(true);
  const [selectedMetric, setSelectedMetric] = useState<string>("alerts");

  const toast = useToast();
  const { contract: monitorContract } = useContract(
    "CrossChainSecurityMonitor"
  );
  const { contract: oracleContract } = useContract("SecurityOracle");

  const fetchAnalyticsData = useCallback(async () => {
    try {
      setLoading(true);

      // Fetch historical data based on time range
      const endBlock = await ethers.provider.getBlockNumber();
      const blocksPerDay = 6500; // Approximate
      const blockRange = {
        "24h": blocksPerDay,
        "7d": blocksPerDay * 7,
        "30d": blocksPerDay * 30,
      }[timeRange];

      const startBlock = endBlock - blockRange;

      // Fetch alerts
      const alertFilter = monitorContract.filters.SecurityAlertRaised();
      const alerts = await monitorContract.queryFilter(
        alertFilter,
        startBlock,
        endBlock
      );

      // Fetch verifications
      const verificationFilter = monitorContract.filters.AlertVerified();
      const verifications = await monitorContract.queryFilter(
        verificationFilter,
        startBlock,
        endBlock
      );

      // Process data into time series
      const timeSeriesData = processTimeSeriesData(
        alerts,
        verifications,
        timeRange
      );
      setAnalyticsData(timeSeriesData);

      // Fetch chain metrics
      const chains = [1, 2, 3]; // Mainnet, Arbitrum, Optimism
      const metricsPromises = chains.map(async (chainId) => {
        const metrics = await monitorContract.getChainMetrics(chainId);
        return {
          chainId,
          alertCount: metrics.alertCount.toNumber(),
          verifiedCount: metrics.verifiedAlerts.toNumber(),
          falsePositives: metrics.falsePositives.toNumber(),
          avgResponseTime: metrics.avgResponseTime.toNumber(),
          healthScore: calculateHealthScore(metrics),
        };
      });

      const chainMetricsData = await Promise.all(metricsPromises);
      setChainMetrics(chainMetricsData);

      // Process alert distribution
      const distributionData = processAlertDistribution(alerts, verifications);
      setAlertDistribution(distributionData);

      setLoading(false);
    } catch (error) {
      toast({
        title: "Error fetching analytics data",
        description: error.message,
        status: "error",
        duration: 5000,
      });
      setLoading(false);
    }
  }, [monitorContract, oracleContract, timeRange, toast]);

  useEffect(() => {
    fetchAnalyticsData();
    const interval = setInterval(fetchAnalyticsData, 60000); // Refresh every minute
    return () => clearInterval(interval);
  }, [fetchAnalyticsData]);

  const processTimeSeriesData = (
    alerts: any[],
    verifications: any[],
    timeRange: string
  ): AnalyticsData[] => {
    const timeSeriesData: AnalyticsData[] = [];
    const interval = {
      "24h": 3600, // 1 hour
      "7d": 86400, // 1 day
      "30d": 86400 * 3, // 3 days
    }[timeRange];

    // Group data by time intervals
    const groupedData = new Map<number, any>();

    alerts.forEach((alert) => {
      const timestamp =
        Math.floor(alert.args.timestamp.toNumber() / interval) * interval;
      const existing = groupedData.get(timestamp) || {
        timestamp,
        totalAlerts: 0,
        verifiedAlerts: 0,
        falsePositives: 0,
        avgSeverity: 0,
        responseTime: 0,
        consensusRate: 0,
      };

      existing.totalAlerts++;
      existing.avgSeverity =
        (existing.avgSeverity * (existing.totalAlerts - 1) +
          alert.args.severity) /
        existing.totalAlerts;

      groupedData.set(timestamp, existing);
    });

    verifications.forEach((verification) => {
      const timestamp =
        Math.floor(verification.args.timestamp.toNumber() / interval) *
        interval;
      const existing = groupedData.get(timestamp);
      if (existing) {
        existing.verifiedAlerts++;
        existing.consensusRate = existing.verifiedAlerts / existing.totalAlerts;
      }
    });

    return Array.from(groupedData.values()).sort(
      (a, b) => a.timestamp - b.timestamp
    );
  };

  const calculateHealthScore = (metrics: any): number => {
    const verificationRate = metrics.verifiedAlerts / metrics.alertCount;
    const falsePositiveRate = metrics.falsePositives / metrics.alertCount;
    const responseScore = Math.max(0, 1 - metrics.avgResponseTime / 3600); // Normalize to 1 hour

    return Math.round(
      (verificationRate * 0.4 +
        (1 - falsePositiveRate) * 0.4 +
        responseScore * 0.2) *
        100
    );
  };

  const processAlertDistribution = (
    alerts: any[],
    verifications: any[]
  ): AlertDistribution[] => {
    const distribution = new Map<string, AlertDistribution>();

    alerts.forEach((alert) => {
      const type = alert.args.alertType;
      const existing = distribution.get(type) || {
        type,
        count: 0,
        severity: 0,
        verificationRate: 0,
      };

      existing.count++;
      existing.severity =
        (existing.severity * (existing.count - 1) + alert.args.severity) /
        existing.count;

      distribution.set(type, existing);
    });

    verifications.forEach((verification) => {
      const alert = alerts.find(
        (a) => a.args.alertId === verification.args.alertId
      );
      if (alert) {
        const type = alert.args.alertType;
        const existing = distribution.get(type);
        if (existing) {
          existing.verificationRate =
            (existing.verificationRate * (existing.count - 1) + 1) /
            existing.count;
        }
      }
    });

    return Array.from(distribution.values());
  };

  return (
    <Box p={6}>
      <VStack spacing={6} align="stretch">
        <HStack justify="space-between">
          <Heading size="lg">Security Analytics Dashboard</Heading>
          <HStack>
            <Select
              value={timeRange}
              onChange={(e) => setTimeRange(e.target.value)}
              w="150px"
            >
              <option value="24h">Last 24 Hours</option>
              <option value="7d">Last 7 Days</option>
              <option value="30d">Last 30 Days</option>
            </Select>
            <Select
              value={selectedMetric}
              onChange={(e) => setSelectedMetric(e.target.value)}
              w="200px"
            >
              <option value="alerts">Alert Metrics</option>
              <option value="response">Response Times</option>
              <option value="consensus">Consensus Rates</option>
            </Select>
            <Button onClick={fetchAnalyticsData} isLoading={loading}>
              Refresh
            </Button>
          </HStack>
        </HStack>

        {loading ? (
          <Box textAlign="center" py={10}>
            <Spinner size="xl" />
          </Box>
        ) : (
          <Grid templateColumns="repeat(2, 1fr)" gap={6}>
            {/* Time Series Chart */}
            <Box p={4} borderRadius="lg" borderWidth={1} h="400px">
              <ResponsiveContainer>
                <ComposedChart data={analyticsData}>
                  <CartesianGrid strokeDasharray="3 3" />
                  <XAxis
                    dataKey="timestamp"
                    tickFormatter={(timestamp) =>
                      format(new Date(timestamp * 1000), "MM/dd HH:mm")
                    }
                  />
                  <YAxis />
                  <Tooltip
                    labelFormatter={(timestamp) =>
                      format(new Date(timestamp * 1000), "yyyy-MM-dd HH:mm")
                    }
                  />
                  <Legend />
                  <Area
                    type="monotone"
                    dataKey="totalAlerts"
                    fill="#8884d8"
                    stroke="#8884d8"
                    name="Total Alerts"
                  />
                  <Bar
                    dataKey="verifiedAlerts"
                    fill="#82ca9d"
                    name="Verified Alerts"
                  />
                  <Line
                    type="monotone"
                    dataKey="avgSeverity"
                    stroke="#ff7300"
                    name="Avg Severity"
                  />
                </ComposedChart>
              </ResponsiveContainer>
            </Box>

            {/* Radar Chart for Chain Metrics */}
            <Box p={4} borderRadius="lg" borderWidth={1} h="400px">
              <ResponsiveContainer>
                <RadarChart data={chainMetrics}>
                  <PolarGrid />
                  <PolarAngleAxis dataKey="chainId" />
                  <PolarRadiusAxis />
                  <Radar
                    name="Alert Count"
                    dataKey="alertCount"
                    stroke="#8884d8"
                    fill="#8884d8"
                    fillOpacity={0.6}
                  />
                  <Radar
                    name="Health Score"
                    dataKey="healthScore"
                    stroke="#82ca9d"
                    fill="#82ca9d"
                    fillOpacity={0.6}
                  />
                  <Legend />
                </RadarChart>
              </ResponsiveContainer>
            </Box>

            {/* Alert Distribution Scatter Plot */}
            <Box p={4} borderRadius="lg" borderWidth={1} h="400px">
              <ResponsiveContainer>
                <ComposedChart data={alertDistribution}>
                  <CartesianGrid strokeDasharray="3 3" />
                  <XAxis dataKey="type" />
                  <YAxis />
                  <Tooltip />
                  <Legend />
                  <Scatter
                    name="Alert Distribution"
                    data={alertDistribution}
                    fill="#8884d8"
                  />
                  <Line
                    type="monotone"
                    dataKey="verificationRate"
                    stroke="#82ca9d"
                    name="Verification Rate"
                  />
                </ComposedChart>
              </ResponsiveContainer>
            </Box>
          </Grid>
        )}
      </VStack>
    </Box>
  );
};
