import React, { useState, useEffect } from "react";
import {
  Box,
  VStack,
  Grid,
  Heading,
  Tabs,
  TabList,
  TabPanels,
  Tab,
  TabPanel,
  Select,
  HStack,
  Button,
  useToast,
  Alert,
  AlertIcon,
  Stat,
  StatLabel,
  StatNumber,
  StatHelpText,
  StatArrow,
} from "@chakra-ui/react";
import {
  LineChart,
  Line,
  AreaChart,
  Area,
  BarChart,
  Bar,
  PieChart,
  Pie,
  XAxis,
  YAxis,
  CartesianGrid,
  Tooltip,
  Legend,
  ResponsiveContainer,
} from "recharts";
import { useWeb3 } from "../hooks/useWeb3";

interface MetricHistory {
  name: string;
  values: number[];
  timestamps: number[];
}

interface ReportSummary {
  totalProposals: number;
  totalVotes: number;
  uniqueVoters: number;
  averageParticipation: number;
  executionSuccess: number;
  timelockedActions: number;
  delegationCount: number;
}

interface Anomaly {
  metricName: string;
  value: number;
  threshold: number;
  timestamp: number;
}

export function ReportingDashboard() {
  const { contract } = useWeb3();
  const toast = useToast();

  const [timeRange, setTimeRange] = useState("7d");
  const [metricHistories, setMetricHistories] = useState<
    Record<string, MetricHistory>
  >({});
  const [latestSummary, setLatestSummary] = useState<ReportSummary | null>(
    null
  );
  const [anomalies, setAnomalies] = useState<Anomaly[]>([]);
  const [loading, setLoading] = useState(true);

  const metricNames = [
    "totalProposals",
    "totalVotes",
    "uniqueVoters",
    "averageParticipation",
    "executionSuccess",
    "timelockedActions",
    "delegationCount",
  ];

  useEffect(() => {
    if (contract) {
      fetchReportingData();
      const interval = setInterval(fetchReportingData, 60000);
      return () => clearInterval(interval);
    }
  }, [contract, timeRange]);

  const fetchReportingData = async () => {
    try {
      setLoading(true);

      // Fetch metric histories
      const histories: Record<string, MetricHistory> = {};
      for (const name of metricNames) {
        const [values, timestamps] = await contract.getMetricHistory(name);
        histories[name] = {
          name,
          values: values.map((v) => v.toNumber()),
          timestamps: timestamps.map((t) => t.toNumber()),
        };
      }
      setMetricHistories(histories);

      // Fetch latest report summary
      const latestReportId = await contract.reportCount();
      if (latestReportId.gt(0)) {
        const summary = await contract.getReportSummary(latestReportId);
        setLatestSummary({
          totalProposals: summary.totalProposals.toNumber(),
          totalVotes: summary.totalVotes.toNumber(),
          uniqueVoters: summary.uniqueVoters.toNumber(),
          averageParticipation: summary.averageParticipation.toNumber(),
          executionSuccess: summary.executionSuccess.toNumber(),
          timelockedActions: summary.timelockedActions.toNumber(),
          delegationCount: summary.delegationCount.toNumber(),
        });
      }

      // Fetch recent anomalies
      const filter = contract.filters.AnomalyDetected();
      const events = await contract.queryFilter(filter);
      setAnomalies(
        events.map((event) => ({
          metricName: event.args?.metricName,
          value: event.args?.value.toNumber(),
          threshold: event.args?.threshold.toNumber(),
          timestamp: event.args?.timestamp.toNumber(),
        }))
      );
    } catch (error) {
      console.error("Error fetching reporting data:", error);
      toast({
        title: "Error fetching reporting data",
        status: "error",
        duration: 5000,
      });
    } finally {
      setLoading(false);
    }
  };

  const formatTimestamp = (timestamp: number) => {
    return new Date(timestamp * 1000).toLocaleString();
  };

  const filterDataByTimeRange = (data: number[], timestamps: number[]) => {
    const now = Math.floor(Date.now() / 1000);
    const ranges = {
      "24h": 86400,
      "7d": 604800,
      "30d": 2592000,
    };
    const cutoff = now - ranges[timeRange as keyof typeof ranges];

    return data.filter((_, index) => timestamps[index] >= cutoff);
  };

  const getMetricChange = (metricName: string) => {
    const history = metricHistories[metricName];
    if (!history || history.values.length < 2) return 0;

    const current = history.values[history.values.length - 1];
    const previous = history.values[history.values.length - 2];
    return ((current - previous) / previous) * 100;
  };

  return (
    <Box p={6}>
      <VStack spacing={6} align="stretch">
        <HStack justify="space-between">
          <Heading size="lg">Governance Reports</Heading>
          <Select
            width="200px"
            value={timeRange}
            onChange={(e) => setTimeRange(e.target.value)}
          >
            <option value="24h">Last 24 Hours</option>
            <option value="7d">Last 7 Days</option>
            <option value="30d">Last 30 Days</option>
          </Select>
        </HStack>

        {anomalies.length > 0 && (
          <Alert status="warning">
            <AlertIcon />
            {anomalies.length} anomalies detected in the selected time range
          </Alert>
        )}

        {latestSummary && (
          <Grid templateColumns="repeat(4, 1fr)" gap={6}>
            <Stat>
              <StatLabel>Total Proposals</StatLabel>
              <StatNumber>{latestSummary.totalProposals}</StatNumber>
              <StatHelpText>
                <StatArrow
                  type={
                    getMetricChange("totalProposals") >= 0
                      ? "increase"
                      : "decrease"
                  }
                />
                {Math.abs(getMetricChange("totalProposals")).toFixed(1)}%
              </StatHelpText>
            </Stat>

            <Stat>
              <StatLabel>Participation Rate</StatLabel>
              <StatNumber>{latestSummary.averageParticipation}%</StatNumber>
              <StatHelpText>
                <StatArrow
                  type={
                    getMetricChange("averageParticipation") >= 0
                      ? "increase"
                      : "decrease"
                  }
                />
                {Math.abs(getMetricChange("averageParticipation")).toFixed(1)}%
              </StatHelpText>
            </Stat>

            <Stat>
              <StatLabel>Success Rate</StatLabel>
              <StatNumber>
                {(
                  (latestSummary.executionSuccess /
                    latestSummary.totalProposals) *
                  100
                ).toFixed(1)}
                %
              </StatNumber>
              <StatHelpText>
                <StatArrow
                  type={
                    getMetricChange("executionSuccess") >= 0
                      ? "increase"
                      : "decrease"
                  }
                />
                {Math.abs(getMetricChange("executionSuccess")).toFixed(1)}%
              </StatHelpText>
            </Stat>

            <Stat>
              <StatLabel>Active Delegations</StatLabel>
              <StatNumber>{latestSummary.delegationCount}</StatNumber>
              <StatHelpText>
                <StatArrow
                  type={
                    getMetricChange("delegationCount") >= 0
                      ? "increase"
                      : "decrease"
                  }
                />
                {Math.abs(getMetricChange("delegationCount")).toFixed(1)}%
              </StatHelpText>
            </Stat>
          </Grid>
        )}

        <Tabs>
          <TabList>
            <Tab>Participation Metrics</Tab>
            <Tab>Execution Metrics</Tab>
            <Tab>Delegation Metrics</Tab>
            <Tab>Anomalies</Tab>
          </TabList>

          <TabPanels>
            <TabPanel>
              <Box height="400px">
                <ResponsiveContainer>
                  <AreaChart
                    data={filterDataByTimeRange(
                      metricHistories.uniqueVoters?.values || [],
                      metricHistories.uniqueVoters?.timestamps || []
                    ).map((value, index) => ({
                      timestamp:
                        metricHistories.uniqueVoters?.timestamps[index],
                      voters: value,
                      participation:
                        metricHistories.averageParticipation?.values[index],
                    }))}
                  >
                    <CartesianGrid strokeDasharray="3 3" />
                    <XAxis
                      dataKey="timestamp"
                      tickFormatter={formatTimestamp}
                    />
                    <YAxis />
                    <Tooltip labelFormatter={formatTimestamp} />
                    <Legend />
                    <Area
                      type="monotone"
                      dataKey="voters"
                      stroke="#8884d8"
                      fill="#8884d8"
                      name="Unique Voters"
                    />
                    <Area
                      type="monotone"
                      dataKey="participation"
                      stroke="#82ca9d"
                      fill="#82ca9d"
                      name="Participation Rate (%)"
                    />
                  </AreaChart>
                </ResponsiveContainer>
              </Box>
            </TabPanel>

            <TabPanel>
              <Box height="400px">
                <ResponsiveContainer>
                  <BarChart
                    data={filterDataByTimeRange(
                      metricHistories.executionSuccess?.values || [],
                      metricHistories.executionSuccess?.timestamps || []
                    ).map((value, index) => ({
                      timestamp:
                        metricHistories.executionSuccess?.timestamps[index],
                      success: value,
                      timelocked:
                        metricHistories.timelockedActions?.values[index],
                    }))}
                  >
                    <CartesianGrid strokeDasharray="3 3" />
                    <XAxis
                      dataKey="timestamp"
                      tickFormatter={formatTimestamp}
                    />
                    <YAxis />
                    <Tooltip labelFormatter={formatTimestamp} />
                    <Legend />
                    <Bar
                      dataKey="success"
                      fill="#8884d8"
                      name="Successful Executions"
                    />
                    <Bar
                      dataKey="timelocked"
                      fill="#82ca9d"
                      name="Timelocked Actions"
                    />
                  </BarChart>
                </ResponsiveContainer>
              </Box>
            </TabPanel>

            <TabPanel>
              <Box height="400px">
                <ResponsiveContainer>
                  <LineChart
                    data={filterDataByTimeRange(
                      metricHistories.delegationCount?.values || [],
                      metricHistories.delegationCount?.timestamps || []
                    ).map((value, index) => ({
                      timestamp:
                        metricHistories.delegationCount?.timestamps[index],
                      count: value,
                    }))}
                  >
                    <CartesianGrid strokeDasharray="3 3" />
                    <XAxis
                      dataKey="timestamp"
                      tickFormatter={formatTimestamp}
                    />
                    <YAxis />
                    <Tooltip labelFormatter={formatTimestamp} />
                    <Legend />
                    <Line
                      type="monotone"
                      dataKey="count"
                      stroke="#8884d8"
                      name="Active Delegations"
                    />
                  </LineChart>
                </ResponsiveContainer>
              </Box>
            </TabPanel>

            <TabPanel>
              <VStack spacing={4} align="stretch">
                {anomalies.map((anomaly, index) => (
                  <Alert key={index} status="warning" borderRadius="md">
                    <AlertIcon />
                    <VStack align="start" spacing={1}>
                      <Box>Metric: {anomaly.metricName}</Box>
                      <Box>
                        Value: {anomaly.value} (Threshold: {anomaly.threshold})
                      </Box>
                      <Box>Detected: {formatTimestamp(anomaly.timestamp)}</Box>
                    </VStack>
                  </Alert>
                ))}
              </VStack>
            </TabPanel>
          </TabPanels>
        </Tabs>
      </VStack>
    </Box>
  );
}
