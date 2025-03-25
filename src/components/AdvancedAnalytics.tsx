import {
  Box,
  Grid,
  Heading,
  Stack,
  Text,
  Select,
  Stat,
  StatLabel,
  StatNumber,
  StatHelpText,
  LineChart,
  BarChart,
  Tooltip,
} from "@chakra-ui/react";
import { useState, useEffect } from "react";
import { useWeb3 } from "../context/Web3Context";
import { AnalyticsService } from "../services/AnalyticsService";

export function AdvancedAnalytics() {
  const { contract, provider } = useWeb3();
  const [timeRange, setTimeRange] = useState("24h");
  const [metrics, setMetrics] = useState<any>(null);
  const [loading, setLoading] = useState(true);

  useEffect(() => {
    if (contract && provider) {
      const analytics = new AnalyticsService(contract, provider);
      fetchMetrics(analytics);
    }
  }, [contract, provider, timeRange]);

  const fetchMetrics = async (analytics: AnalyticsService) => {
    try {
      const [networkStats, taskMetrics, contributorMetrics] = await Promise.all(
        [
          analytics.getNetworkStats(),
          analytics.getTaskMetrics(),
          analytics.getContributorMetrics(),
        ]
      );

      setMetrics({
        network: networkStats,
        tasks: taskMetrics,
        contributors: contributorMetrics,
      });
    } catch (error) {
      console.error("Error fetching metrics:", error);
    } finally {
      setLoading(false);
    }
  };

  if (loading) return <Text>Loading analytics...</Text>;

  return (
    <Box p={6}>
      <Stack spacing={8}>
        <Box>
          <Heading size="lg">Advanced Analytics</Heading>
          <Select
            mt={4}
            width="200px"
            value={timeRange}
            onChange={(e) => setTimeRange(e.target.value)}
          >
            <option value="24h">Last 24 Hours</option>
            <option value="7d">Last 7 Days</option>
            <option value="30d">Last 30 Days</option>
            <option value="all">All Time</option>
          </Select>
        </Box>

        <Grid templateColumns="repeat(3, 1fr)" gap={6}>
          <Stat>
            <StatLabel>Network Status</StatLabel>
            <StatNumber>Block #{metrics.network.latestBlock}</StatNumber>
            <StatHelpText>
              Gas Price: {metrics.network.gasPrice} Gwei
            </StatHelpText>
          </Stat>

          <Stat>
            <StatLabel>Task Completion Rate</StatLabel>
            <StatNumber>{metrics.tasks.completionRate.toFixed(1)}%</StatNumber>
            <StatHelpText>
              {metrics.tasks.completed} / {metrics.tasks.total} Tasks
            </StatHelpText>
          </Stat>

          <Stat>
            <StatLabel>Average Reward</StatLabel>
            <StatNumber>
              {metrics.tasks.averageReward.toFixed(2)} ETH
            </StatNumber>
            <StatHelpText>Per Completed Task</StatHelpText>
          </Stat>
        </Grid>

        <Box>
          <Heading size="md" mb={4}>
            Model Type Distribution
          </Heading>
          <BarChart
            data={metrics.tasks.modelTypeDistribution}
            width={600}
            height={300}
          />
        </Box>

        <Box>
          <Heading size="md" mb={4}>
            Top Contributors
          </Heading>
          <Grid templateColumns="repeat(2, 1fr)" gap={6}>
            {metrics.contributors.topContributors.map((contributor: any) => (
              <Box
                key={contributor.address}
                p={4}
                borderWidth={1}
                borderRadius="md"
              >
                <Text fontWeight="bold">
                  {contributor.address.slice(0, 6)}...
                  {contributor.address.slice(-4)}
                </Text>
                <Text>Tasks: {contributor.tasksCompleted}</Text>
                <Text>Earnings: {contributor.earnings} ETH</Text>
                <Text>Reputation: {contributor.reputation}</Text>
              </Box>
            ))}
          </Grid>
        </Box>

        <Box>
          <Heading size="md" mb={4}>
            Reputation Distribution
          </Heading>
          <BarChart
            data={metrics.contributors.reputationDistribution}
            width={600}
            height={300}
          />
        </Box>
      </Stack>
    </Box>
  );
}
