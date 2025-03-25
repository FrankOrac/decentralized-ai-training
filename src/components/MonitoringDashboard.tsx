import React, { useState, useEffect } from 'react';
import {
  Box,
  Grid,
  Heading,
  VStack,
  HStack,
  Text,
  Table,
  Thead,
  Tbody,
  Tr,
  Th,
  Td,
  Badge,
  Select,
  Button,
  useToast,
  Stat,
  StatLabel,
  StatNumber,
  StatHelpText,
  StatArrow,
} from '@chakra-ui/react';
import {
  LineChart,
  Line,
  XAxis,
  YAxis,
  CartesianGrid,
  Tooltip,
  Legend,
  ResponsiveContainer,
} from 'recharts';
import { useWeb3 } from '../hooks/useWeb3';
import { formatDistance } from 'date-fns';

interface MetricData {
  name: string;
  lastValue: number;
  average: number;
  minimum: number;
  maximum: number;
  values: number[];
  timestamps: number[];
}

interface Alert {
  alertId: string;
  metricName: string;
  threshold: number;
  alertType: string;
  isActive: boolean;
  lastTriggered: number;
  triggerCount: number;
}

interface HealthStatus {
  component: string;
  isHealthy: boolean;
  lastCheck: number;
  uptime: number;
  downtime: number;
  lastIncident: number;
}

export function MonitoringDashboard() {
  const { contract } = useWeb3();
  const toast = useToast();
  const [metrics, setMetrics] = useState<Record<string, MetricData>>({});
  const [alerts, setAlerts] = useState<Alert[]>([]);
  const [healthStatus, setHealthStatus] = useState<Record<string, HealthStatus>>({});
  const [selectedMetric, setSelectedMetric] = useState<string>('');
  const [timeRange, setTimeRange] = useState<string>('1h');

  useEffect(() => {
    if (contract) {
      fetchMetrics();
      fetchAlerts();
      fetchHealthStatus();
      const interval = setInterval(fetchMetrics, 30000); // Update every 30 seconds
      return () => clearInterval(interval);
    }
  }, [contract]);

  const fetchMetrics = async () => {
    try {
      const metricNames = await contract.getMetricNames();
      const metricsData: Record<string, MetricData> = {};

      for (const name of metricNames) {
        const stats = await contract.getMetricStats(name);
        metricsData[name] = {
          name,
          lastValue: stats.lastValue.toNumber(),
          average: stats.average.toNumber(),
          minimum: stats.minimum.toNumber(),
          maximum: stats.maximum.toNumber(),
          values: stats.values.map(v => v.toNumber()),
          timestamps: stats.timestamps.map(t => t.toNumber()),
        };
      }

      setMetrics(metricsData);
      if (!selectedMetric && metricNames.length > 0) {
        setSelectedMetric(metricNames[0]);
      }
    } catch (error) {
      console.error('Error fetching metrics:', error);
      toast({
        title: 'Error fetching metrics',
        status: 'error',
        duration: 5000,
      });
    }
  };

  const fetchAlerts = async () => {
    try {
      const alertsData = await contract.getActiveAlerts();
      setAlerts(alertsData);
    } catch (error) {
      console.error('Error fetching alerts:', error);
    }
  };

  const fetchHealthStatus = async () => {
    try {
      const components = await contract.getComponents();
      const healthData: Record<string, HealthStatus> = {};

      for (const component of components) {
        const status = await contract.getHealthStats(component);
        healthData[component] = {
          component,
          isHealthy: status.isHealthy,
          lastCheck: status.lastCheck.toNumber(),
          uptime: status.uptime.toNumber(),
          downtime: status.downtime.toNumber(),
          lastIncident: status.lastIncident.toNumber(),
        };
      }

      setHealthStatus(healthData);
    } catch (error) {
      console.error('Error fetching health status:', error);
    }
  };

  const formatChartData = (metric: MetricData) => {
    const now = Date.now() / 1000;
    const timeRangeSeconds = {
      '1h': 3600,
      '24h': 86400,
      '7d': 604800,
    }[timeRange];

    return metric.values
      .map((value, index) => ({
        timestamp: metric.timestamps[index],
        value,
      }))
      .filter(point => now - point.timestamp <= timeRangeSeconds);
  };

  const calculateChangePercentage = (current: number, average: number) => {
    if (average === 0) return 0;
    return ((current - average) / average) * 100;
  };

  return (
    <Box p={6}>
      <VStack spacing={6} align="stretch">
        <HStack justify="space-between">
          <Heading size="lg">System Monitoring</Heading>
          <Select
            value={timeRange}
            onChange={(e) => setTimeRange(e.target.value)}
            width="200px"
          >
            <option value="1h">Last Hour</option>
            <option value="24h">Last 24 Hours</option>
            <option value="7d">Last 7 Days</option>
          </Select>
        </HStack>

        {/* Health Status Overview */}
        <Grid templateColumns="repeat(auto-fit, minmax(200px, 1fr))" gap={6}>
          {Object.values(healthStatus).map((status) => (
            <Box
              key={status.component}
              p={4}
              borderWidth={1}
              borderRadius="lg"
              bg={status.isHealthy ? 'green.50' : 'red.50'}
            >
              <Stat>
                <StatLabel>{status.component}</StatLabel>
                <StatNumber>
                  <Badge colorScheme={status.isHealthy ? 'green' : 'red'}>
                    {status.isHealthy ? 'Healthy' : 'Unhealthy'}
                  </Badge>
                </StatNumber>
                <StatHelpText>
                  Uptime: {((status.uptime / (status.uptime + status.downtime)) * 100).toFixed(2)}%
                </StatHelpText>
              </Stat>
            </Box>
          ))}
        </Grid>

        {/* Metrics Chart */}
        <Box borderWidth={1} borderRadius="lg" p={4}>
          <HStack mb={4}>
            <Select
              value={selectedMetric}
              onChange={(e) => setSelectedMetric(e.target.value)}
              width="200px"
            >
              {Object.keys(metrics).map((name) => (
                <option key={name} value={name}>{name}</option>
              ))}
            </Select>
          </HStack>

          {selectedMetric && metrics[selectedMetric] && (
            <>
              <Grid templateColumns="repeat(4, 1fr)" gap={4} mb={4}>
                <Stat>
                  <StatLabel>Current Value</StatLabel>
                  <StatNumber>{metrics[selectedMetric].lastValue}</StatNumber>
                  <StatHelpText>
                    <StatArrow
                      type={metrics[selectedMetric].lastValue > metrics[selectedMetric].average ? 'increase' : 'decrease'}
                    />
                    {calculateChangePercentage(
                      metrics[selectedMetric].lastValue,
                      metrics[selectedMetric].average
                    ).toFixed(2)}%
                  </StatHelpText>
                </Stat>
                <Stat>
                  <StatLabel>Average</StatLabel>
                  <StatNumber>{metrics[selectedMetric].average}</StatNumber>
                </Stat>
                <Stat>
                  <StatLabel>Minimum</StatLabel>
                  <StatNumber>{metrics[selectedMetric].minimum}</StatNumber>
                </Stat>
                <Stat>
                  <StatLabel>Maximum</StatLabel>
                  <StatNumber>{metrics[selectedMetric].maximum}</StatNumber>
                </Stat>
              </Grid>

              <Box height="400px">
                <ResponsiveContainer>
                  <LineChart data={formatChartData(metrics[selectedMetric])}>
                    <CartesianGrid strokeDasharray="3 3" />
                    <XAxis
                      dataKey="timestamp"
                      tickFormatter={(timestamp) => new Date(timestamp * 1000).toLocaleTimeString()}
                    />
                    <YAxis />
                    <Tooltip
                      labelFormatter={(timestamp) => new Date(timestamp * 1000).toLocaleString()}
                    />
                    <Legend />
                    <Line
                      type="monotone"
                      dataKey="value"
                      stroke="#3182ce"
                      name={selectedMetric}
                    />
                  </LineChart>
                </ResponsiveContainer>
              </Box>
            </>
          )}
        </Box>

        {/* Active Alerts */}
        <Box borderWidth={1} borderRadius="lg" p={4}>
          <Heading size="md" mb={4}>Active Alerts</Heading>
          <Table variant="simple">
            <Thead>
              <Tr>
                <Th>Metric</Th>
                <Th>Type</Th>
                <Th>Threshold</Th>
                <Th>Last Triggered</Th>
                <Th>Count</Th>
              </Tr>
            </Thead>
            <Tbody>
              {alerts.map((alert) => (
                <Tr key={alert.alertId}>
                  <Td>{alert.metricName}</Td>
                  <Td>{alert.alertType}</Td>
                  <Td>{alert.threshold}</Td>
                  <Td>
                    {alert.lastTriggered > 0
                      ? formatDistance(new Date(alert.lastTriggered * 1000), new Date(), { addSuffix: true })
                      : 'Never'}
                  </Td>
                  <Td>{alert.triggerCount}</Td>
                </Tr>
              ))}
            </Tbody>
          </Table>
        </Box>
      </VStack>
    </Box>
  );
}
