import React, { useState, useEffect, useCallback } from 'react';
import {
  Box,
  Grid,
  VStack,
  HStack,
  Text,
  Select,
  Button,
  Stat,
  StatLabel,
  StatNumber,
  StatHelpText,
  StatArrow,
  Tabs,
  TabList,
  TabPanels,
  Tab,
  TabPanel,
  useToast,
  Spinner,
} from '@chakra-ui/react';
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
  PieChart,
  Pie,
  Cell,
  Scatter,
} from 'recharts';
import { format } from 'date-fns';
import { useContract } from '../hooks/useContract';
import { ethers } from 'ethers';

interface ChainMetrics {
  chainId: number;
  totalWorkflows: number;
  completedWorkflows: number;
  averageCompletionTime: number;
  successRate: number;
}

interface TimeSeriesData {
  timestamp: number;
  initiatedWorkflows: number;
  completedWorkflows: number;
  averageGasUsed: number;
  crossChainLatency: number;
}

interface ChainLatency {
  sourceChain: number;
  targetChain: number;
  averageLatency: number;
  messageCount: number;
}

export const AnalyticsDashboard: React.FC = () => {
  const [timeRange, setTimeRange] = useState<string>('24h');
  const [selectedChain, setSelectedChain] = useState<number>(1);
  const [chainMetrics, setChainMetrics] = useState<ChainMetrics[]>([]);
  const [timeSeriesData, setTimeSeriesData] = useState<TimeSeriesData[]>([]);
  const [chainLatencies, setChainLatencies] = useState<ChainLatency[]>([]);
  const [loading, setLoading] = useState(true);

  const toast = useToast();
  const { contract: coordinator } = useContract('CrossChainWorkflowCoordinator');

  const fetchAnalytics = useCallback(async () => {
    try {
      setLoading(true);

      // Calculate block range based on time range
      const blocksPerDay = 6500;
      const blockRange = {
        '24h': blocksPerDay,
        '7d': blocksPerDay * 7,
        '30d': blocksPerDay * 30,
      }[timeRange];

      const endBlock = await ethers.provider.getBlockNumber();
      const startBlock = endBlock - blockRange;

      // Fetch workflow events
      const initiatedFilter = coordinator.filters.CrossChainWorkflowInitiated();
      const completedFilter = coordinator.filters.CrossChainWorkflowCompleted();
      const chainCompletedFilter = coordinator.filters.ChainWorkflowCompleted();

      const [initiatedEvents, completedEvents, chainCompletedEvents] = await Promise.all([
        coordinator.queryFilter(initiatedFilter, startBlock, endBlock),
        coordinator.queryFilter(completedFilter, startBlock, endBlock),
        coordinator.queryFilter(chainCompletedFilter, startBlock, endBlock),
      ]);

      // Process chain metrics
      const metrics = new Map<number, ChainMetrics>();
      const chains = new Set<number>();

      initiatedEvents.forEach(event => {
        event.args.chains.forEach((chainId: number) => {
          chains.add(chainId);
          if (!metrics.has(chainId)) {
            metrics.set(chainId, {
              chainId,
              totalWorkflows: 0,
              completedWorkflows: 0,
              averageCompletionTime: 0,
              successRate: 0,
            });
          }
          const chainMetric = metrics.get(chainId)!;
          chainMetric.totalWorkflows++;
        });
      });

      chainCompletedEvents.forEach(event => {
        const chainId = event.args.chainId;
        const chainMetric = metrics.get(chainId);
        if (chainMetric) {
          chainMetric.completedWorkflows++;
        }
      });

      // Calculate success rates and average completion times
      metrics.forEach(metric => {
        metric.successRate = (metric.completedWorkflows / metric.totalWorkflows) * 100;
        
        const completionTimes = completedEvents
          .filter(event => {
            const workflow = crossChainWorkflows[event.args.workflowId];
            return workflow.involvedChains.includes(metric.chainId);
          })
          .map(event => {
            const workflow = crossChainWorkflows[event.args.workflowId];
            return workflow.completionTime - workflow.startTime;
          });

        metric.averageCompletionTime = completionTimes.length > 0
          ? completionTimes.reduce((a, b) => a + b, 0) / completionTimes.length
          : 0;
      });

      setChainMetrics(Array.from(metrics.values()));

      // Process time series data
      const timeSeriesMap = new Map<number, TimeSeriesData>();
      const interval = {
        '24h': 3600,
        '7d': 86400,
        '30d': 86400 * 3,
      }[timeRange];

      initiatedEvents.forEach(event => {
        const timestamp = Math.floor(event.args.timestamp / interval) * interval;
        if (!timeSeriesMap.has(timestamp)) {
          timeSeriesMap.set(timestamp, {
            timestamp,
            initiatedWorkflows: 0,
            completedWorkflows: 0,
            averageGasUsed: 0,
            crossChainLatency: 0,
          });
        }
        const data = timeSeriesMap.get(timestamp)!;
        data.initiatedWorkflows++;
      });

      completedEvents.forEach(event => {
        const timestamp = Math.floor(event.args.timestamp / interval) * interval;
        if (timeSeriesMap.has(timestamp)) {
          const data = timeSeriesMap.get(timestamp)!;
          data.completedWorkflows++;
        }
      });

      setTimeSeriesData(Array.from(timeSeriesMap.values()).sort((a, b) => a.timestamp - b.timestamp));

      // Process chain latencies
      const latencyMap = new Map<string, ChainLatency>();
      chainCompletedEvents.forEach(event => {
        const workflow = crossChainWorkflows[event.args.workflowId];
        workflow.involvedChains.forEach(sourceChain => {
          if (sourceChain !== event.args.chainId) {
            const key = `${sourceChain}-${event.args.chainId}`;
            if (!latencyMap.has(key)) {
              latencyMap.set(key, {
                sourceChain,
                targetChain: event.args.chainId,
                averageLatency: 0,
                messageCount: 0,
              });
            }
            const latency = latencyMap.get(key)!;
            const messageLatency = event.args.timestamp - workflow.startTime;
            latency.averageLatency = (latency.averageLatency * latency.messageCount + messageLatency) / (latency.messageCount + 1);
            latency.messageCount++;
          }
        });
      });

      setChainLatencies(Array.from(latencyMap.values()));
      setLoading(false);
    } catch (error) {
      console.error('Error fetching analytics:', error);
      toast({
        title: 'Error',
        description: 'Failed to fetch analytics data',
        status: 'error',
        duration: 5000,
      });
      setLoading(false);
    }
  }, [coordinator, timeRange, toast]);

  useEffect(() => {
    fetchAnalytics();
    const interval = setInterval(fetchAnalytics, 60000);
    return () => clearInterval(interval);
  }, [fetchAnalytics]);

  const COLORS = ['#0088FE', '#00C49F', '#FFBB28', '#FF8042'];

  return (
    <Box p={6}>
      <VStack spacing={6} align="stretch">
        <HStack justify="space-between">
          <Text fontSize="2xl" fontWeight="bold">Cross-Chain Analytics Dashboard</Text>
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
            <Button
              onClick={fetchAnalytics}
              isLoading={loading}
            >
              Refresh
            </Button>
          </HStack>
        </HStack>

        {loading ? (
          <Box textAlign="center" py={10}>
            <Spinner size="xl" />
          </Box>
        ) : (
          <Tabs>
            <TabList>
              <Tab>Overview</Tab>
              <Tab>Chain Performance</Tab>
              <Tab>Latency Analysis</Tab>
            </TabList>

            <TabPanels>
              <TabPanel>
                <Grid templateColumns="repeat(4, 1fr)" gap={6} mb={6}>
                  {chainMetrics.map((metric) => (
                    <Stat
                      key={metric.chainId}
                      p={4}
                      shadow="md"
                      borderWidth={1}
                      borderRadius="md"
                    >
                      <StatLabel>Chain {metric.chainId}</StatLabel>
                      <StatNumber>{metric.completedWorkflows}/{metric.totalWorkflows}</StatNumber>
                      <StatHelpText>
                        <StatArrow type={metric.successRate >= 95 ? 'increase' : 'decrease'} />
                        {metric.successRate.toFixed(1)}% Success Rate
                      </StatHelpText>
                    </Stat>
                  ))}
                </Grid>

                <Box h="400px" mb={6}>
                  <ResponsiveContainer>
                    <ComposedChart data={timeSeriesData}>
                      <CartesianGrid strokeDasharray="3 3" />
                      <XAxis
                        dataKey="timestamp"
                        tickFormatter={(timestamp) => format(timestamp * 1000, 'MM/dd HH:mm')}
                      />
                      <YAxis />
                      <Tooltip
                        labelFormatter={(timestamp) => format(timestamp * 1000, 'yyyy-MM-dd HH:mm')}
                      />
                      <Legend />
                      <Area
                        type="monotone"
                        dataKey="initiatedWorkflows"
                        fill="#8884d8"
                        stroke="#8884d8"
                        name="Initiated Workflows"
                      />
                      <Line
                        type="monotone"
                        dataKey="completedWorkflows"
                        stroke="#82ca9d"
                        name="Completed Workflows"
                      />
                    </ComposedChart>
                  </ResponsiveContainer>
                </Box>
              </TabPanel>

              <TabPanel>
                <Grid templateColumns="1fr 1fr" gap={6}>
                  <Box h="400px">
                    <ResponsiveContainer>
                      <PieChart>
                        <Pie
                          data={chainMetrics}
                          dataKey="totalWorkflows"
                          nameKey="chainId"
                          cx="50%"
                          cy="50%"
                          outerRadius={150}
                          label
                        >
                          {chainMetrics.map((entry, index) => (
                            <Cell key={`cell-${index}`} fill={COLORS[index % COLORS.length]} />
                          ))}
                        </Pie>
                        <Tooltip />
                        <Legend />
                      </PieChart>
                    </ResponsiveContainer>
                  </Box>

                  <Box h="400px">
                    <ResponsiveContainer>
                      <ComposedChart data={chainMetrics}>
                        <CartesianGrid strokeDasharray="3 3" />
                        <XAxis dataKey="chainId" />
                        <YAxis />
                        <Tooltip />
                        <Legend />
                        <Bar
                          dataKey="averageCompletionTime"
                          fill="#8884d8"
                          name="Avg Completion Time (s)"
                        />
                        <Line
                          type="monotone"
                          dataKey="successRate"
                          stroke="#82ca9d"
                          name="Success Rate (%)"
                        />
                      </ComposedChart>
                    </ResponsiveContainer>
                  </Box>
                </Grid>
              </TabPanel>

              <TabPanel>
                <Box h="500px">
                  <ResponsiveContainer>
                    <Scatter data={chainLatencies}>
                      <CartesianGrid strokeDasharray="3 3" />
                      <XAxis
                        dataKey="sourceChain"
                        name="Source Chain"
                        type="number"
                      />
                      <YAxis
                        dataKey="targetChain"
                        name="Target Chain"
                        type="number"
                      />
                      <Tooltip
                        cursor={{ strokeDasharray: '3 3' }}
                        content={({ payload }) => {
                          if (payload && payload.length) {
                            const data = payload[0].payload;
                            return (
                              <Box bg="white" p={2} shadow="md" borderRadius="md">
                                <Text>Source Chain: {data.sourceChain}</Text>
                                <Text>Target Chain: {data.targetChain}</Text>
                                <Text>Avg Latency: {data.averageLatency.toFixed(2)}s</Text>
                                <Text>Messages: {data.messageCount}</Text>
                              </Box>
                            );
                          }
                          return null;
                        }}
                      />
                      <Scatter
                        name="Chain Latency"
                        data={chainLatencies}
                        fill="#8884d8"
                      />
                    </Scatter>
                  </ResponsiveContainer>
                </Box>
              </TabPanel>
            </TabPanels>
          </Tabs>
        )}
      </VStack>
    </Box>
  );
};
