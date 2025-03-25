import React, { useState, useEffect, useCallback } from 'react';
import {
  Box,
  VStack,
  HStack,
  Text,
  Select,
  Button,
  Grid,
  Stat,
  StatLabel,
  StatNumber,
  StatHelpText,
  StatArrow,
  useToast,
  Tabs,
  TabList,
  TabPanels,
  Tab,
  TabPanel,
} from '@chakra-ui/react';
import {
  ResponsiveContainer,
  ComposedChart,
  LineChart,
  Line,
  BarChart,
  Bar,
  ScatterChart,
  Scatter,
  XAxis,
  YAxis,
  ZAxis,
  CartesianGrid,
  Tooltip,
  Legend,
  Sankey,
  Network,
} from 'recharts';
import { format } from 'date-fns';
import { useContract } from '../hooks/useContract';
import { ForceGraph2D } from 'react-force-graph';

interface AnalyticsData {
  crossChainIncidents: any[];
  correlations: any[];
  chainMetrics: any[];
  temporalPatterns: any[];
}

export const AdvancedAnalytics: React.FC = () => {
  const [timeRange, setTimeRange] = useState<string>('24h');
  const [analyticsData, setAnalyticsData] = useState<AnalyticsData>({
    crossChainIncidents: [],
    correlations: [],
    chainMetrics: [],
    temporalPatterns: [],
  });
  const [loading, setLoading] = useState(true);

  const toast = useToast();
  const { contract: coordinator } = useContract('CrossChainIncidentCoordinator');

  const fetchAnalyticsData = useCallback(async () => {
    try {
      setLoading(true);

      // Fetch cross-chain incidents
      const incidentFilter = coordinator.filters.CrossChainIncidentReported();
      const correlationFilter = coordinator.filters.IncidentCorrelated();
      const resolutionFilter = coordinator.filters.CrossChainIncidentResolved();

      const [incidentEvents, correlationEvents, resolutionEvents] = await Promise.all([
        coordinator.queryFilter(incidentFilter, -10000),
        coordinator.queryFilter(correlationFilter, -10000),
        coordinator.queryFilter(resolutionFilter, -10000),
      ]);

      // Process incidents and build correlation network
      const incidents = await Promise.all(
        incidentEvents.map(async (event) => {
          const incident = await coordinator.crossChainIncidents(event.args.incidentId);
          return {
            id: event.args.incidentId,
            chains: event.args.chains,
            severity: event.args.severity.toNumber(),
            timestamp: incident.timestamp.toNumber(),
            isResolved: incident.isResolved,
          };
        })
      );

      // Build correlation network
      const nodes = new Set();
      const links = [];
      
      correlationEvents.forEach(event => {
        nodes.add(event.args.incidentId);
        nodes.add(event.args.correlatedIncidentId);
        links.push({
          source: event.args.incidentId,
          target: event.args.correlatedIncidentId,
          value: event.args.correlationScore.toNumber(),
        });
      });

      // Calculate chain-specific metrics
      const chainMetrics = new Map();
      incidents.forEach(incident => {
        incident.chains.forEach(chainId => {
          const metrics = chainMetrics.get(chainId) || {
            chainId,
            totalIncidents: 0,
            resolvedIncidents: 0,
            avgResolutionTime: 0,
            severity: {
              low: 0,
              medium: 0,
              high: 0,
              critical: 0,
            },
          };

          metrics.totalIncidents++;
          if (incident.isResolved) {
            metrics.resolvedIncidents++;
            const resolutionEvent = resolutionEvents.find(
              e => e.args.incidentId === incident.id
            );
            if (resolutionEvent) {
              const resolutionTime = resolutionEvent.args.resolutionTime.toNumber();
              metrics.avgResolutionTime = (
                metrics.avgResolutionTime * (metrics.resolvedIncidents - 1) +
                resolutionTime
              ) / metrics.resolvedIncidents;
            }
          }

          if (incident.severity <= 3) metrics.severity.low++;
          else if (incident.severity <= 6) metrics.severity.medium++;
          else if (incident.severity <= 8) metrics.severity.high++;
          else metrics.severity.critical++;

          chainMetrics.set(chainId, metrics);
        });
      });

      // Analyze temporal patterns
      const timeSeriesData = new Map();
      incidents.forEach(incident => {
        const day = Math.floor(incident.timestamp / 86400) * 86400;
        const data = timeSeriesData.get(day) || {
          timestamp: day,
          incidents: 0,
          avgSeverity: 0,
          correlations: 0,
        };

        data.incidents++;
        data.avgSeverity = (
          data.avgSeverity * (data.incidents - 1) +
          incident.severity
        ) / data.incidents;

        const incidentCorrelations = correlationEvents.filter(
          e => e.args.incidentId === incident.id ||
               e.args.correlatedIncidentId === incident.id
        );
        data.correlations += incidentCorrelations.length;

        timeSeriesData.set(day, data);
      });

      setAnalyticsData({
        crossChainIncidents: incidents,
        correlations: {
          nodes: Array.from(nodes).map(id => ({ id })),
          links,
        },
        chainMetrics: Array.from(chainMetrics.values()),
        temporalPatterns: Array.from(timeSeriesData.values())
          .sort((a, b) => a.timestamp - b.timestamp),
      });

      setLoading(false);
    } catch (error) {
      console.error('Error fetching analytics data:', error);
      toast({
        title: 'Error',
        description: 'Failed to fetch analytics data',
        status: 'error',
        duration: 5000,
      });
      setLoading(false);
    }
  }, [coordinator, toast]);

  useEffect(() => {
    fetchAnalyticsData();
    const interval = setInterval(fetchAnalyticsData, 60000);
    return () => clearInterval(interval);
  }, [fetchAnalyticsData]);

  return (
    <Box p={6}>
      <VStack spacing={6} align="stretch">
        <HStack justify="space-between">
          <Text fontSize="2xl" fontWeight="bold">Advanced Security Analytics</Text>
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
              onClick={fetchAnalyticsData}
              isLoading={loading}
            >
              Refresh
            </Button>
          </HStack>
        </HStack>

        <Tabs>
          <TabList>
            <Tab>Overview</Tab>
            <Tab>Correlation Network</Tab>
            <Tab>Chain Analysis</Tab>
            <Tab>Temporal Patterns</Tab>
          </TabList>

          <TabPanels>
            <TabPanel>
              <Grid templateColumns="repeat(4, 1fr)" gap={6} mb={6}>
                {analyticsData.chainMetrics.map((metric) => (
                  <Stat
                    key={metric.chainId}
                    p={4}
                    shadow="md"
                    borderWidth={1}
                    borderRadius="md"
                  >
                    <StatLabel>Chain {metric.chainId}</StatLabel>
                    <StatNumber>
                      {metric.resolvedIncidents}/{metric.totalIncidents}
                    </StatNumber>
            <StatHelpText>
                      <StatArrow
                        type={metric.avgResolutionTime < 3600 ? 'decrease' : 'increase'}
                      />
                      Avg Resolution: {(metric.avgResolutionTime / 3600).toFixed(1)}h
            </StatHelpText>
          </Stat>
                ))}
        </Grid>

              <Box h="400px" mb={6}>
                <ResponsiveContainer>
                  <ComposedChart data={analyticsData.temporalPatterns}>
                    <CartesianGrid strokeDasharray="3 3" />
                    <XAxis
                      dataKey="timestamp"
                      tickFormatter={(ts) => format(ts * 1000, 'MM/dd HH:mm')}
                    />
                    <YAxis yAxisId="left" />
                    <YAxis yAxisId="right" orientation="right" />
                    <Tooltip
                      labelFormatter={(ts) => format(ts * 1000, 'yyyy-MM-dd HH:mm')}
                    />
                    <Legend />
                    <Bar
                      yAxisId="left"
                      dataKey="incidents"
                      fill="#8884d8"
                      name="Incidents"
                    />
                    <Line
                      yAxisId="right"
                      type="monotone"
                      dataKey="avgSeverity"
                      stroke="#82ca9d"
                      name="Avg Severity"
                    />
                  </ComposedChart>
                </ResponsiveContainer>
              </Box>
            </TabPanel>

            <TabPanel>
              <Box h="600px">
                <ForceGraph2D
                  graphData={analyticsData.correlations}
                  nodeLabel="id"
                  linkDirectionalParticles={2}
                  linkDirectionalParticleSpeed={d => d.value * 0.001}
                  nodeAutoColorBy="id"
                  linkWidth={1}
                  linkColor={() => "#999"}
          />
        </Box>
            </TabPanel>

            <TabPanel>
              <Grid templateColumns="1fr 1fr" gap={6}>
                <Box h="400px">
                  <ResponsiveContainer>
                    <BarChart data={analyticsData.chainMetrics}>
                      <CartesianGrid strokeDasharray="3 3" />
                      <XAxis dataKey="chainId" />
                      <YAxis />
                      <Tooltip />
                      <Legend />
                      <Bar dataKey="severity.low" stackId="severity" fill="#82ca9d" name="Low" />
                      <Bar dataKey="severity.medium" stackId="severity" fill="#8884d8" name="Medium" />
                      <Bar dataKey="severity.high" stackId="severity" fill="#ffc658" name="High" />
                      <Bar dataKey="severity.critical" stackId="severity" fill="#ff8042" name="Critical" />
                    </BarChart>
                  </ResponsiveContainer>
        </Box>

                <Box h="400px">
                  <ResponsiveContainer>
                    <ScatterChart>
                      <CartesianGrid strokeDasharray="3 3" />
                      <XAxis
                        dataKey="totalIncidents"
                        name="Total Incidents"
                      />
                      <YAxis
                        dataKey="avgResolutionTime"
                        name="Avg Resolution Time (h)"
                      />
                      <ZAxis
                        dataKey="resolvedIncidents"
                        range={[50, 400]}
                        name="Resolved Incidents"
                      />
                      <Tooltip cursor={{ strokeDasharray: '3 3' }} />
                      <Legend />
                      <Scatter
                        name="Chain Metrics"
                        data={analyticsData.chainMetrics}
                        fill="#8884d8"
                      />
                    </ScatterChart>
                  </ResponsiveContainer>
                </Box>
              </Grid>
            </TabPanel>

            <TabPanel>
              <Box h="500px">
                <ResponsiveContainer>
                  <LineChart data={analyticsData.temporalPatterns}>
                    <CartesianGrid strokeDasharray="3 3" />
                    <XAxis
                      dataKey="timestamp"
                      tickFormatter={(ts) => format(ts * 1000, 'MM/dd HH:mm')}
                    />
                    <YAxis />
                    <Tooltip
                      labelFormatter={(ts) => format(ts * 1000, 'yyyy-MM-dd HH:mm')}
                    />
                    <Legend />
                    <Line
                      type="monotone"
                      dataKey="incidents"
                      stroke="#8884d8"
                      name="Incidents"
                    />
                    <Line
                      type="monotone"
                      dataKey="correlations"
                      stroke="#82ca9d"
                      name="Correlations"
                    />
                  </LineChart>
                </ResponsiveContainer>
        </Box>
            </TabPanel>
          </TabPanels>
        </Tabs>
      </VStack>
    </Box>
  );
};
