import React, { useState, useEffect, useCallback } from "react";
import {
  Box,
  Grid,
  Heading,
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
  Table,
  Thead,
  Tbody,
  Tr,
  Th,
  Td,
  Badge,
  useToast,
  Flex,
  Select,
} from "@chakra-ui/react";
import {
  LineChart,
  Line,
  BarChart,
  Bar,
  XAxis,
  YAxis,
  CartesianGrid,
  Tooltip,
  Legend,
  ResponsiveContainer,
} from "recharts";
import { useContract } from "../hooks/useContract";
import { formatDistance } from "date-fns";

interface SecurityMetrics {
  alertCount: number;
  verifiedAlerts: number;
  falsePositives: number;
  lastUpdateTimestamp: number;
  chainId: number;
}

interface Alert {
  id: string;
  sourceChainId: number;
  alertType: string;
  severity: number;
  timestamp: number;
  isVerified: boolean;
  verifications: number;
}

interface ChainActivity {
  timestamp: number;
  alerts: number;
  verifications: number;
}

export const SecurityMonitorDashboard: React.FC = () => {
  const [selectedChain, setSelectedChain] = useState<number>(1);
  const [metrics, setMetrics] = useState<SecurityMetrics[]>([]);
  const [alerts, setAlerts] = useState<Alert[]>([]);
  const [chainActivity, setChainActivity] = useState<ChainActivity[]>([]);
  const [loading, setLoading] = useState<boolean>(true);

  const toast = useToast();
  const { contract } = useContract("CrossChainSecurityMonitor");

  const fetchMetrics = useCallback(async () => {
    try {
      const supportedChains = [1, 2, 3]; // Mainnet, Arbitrum, Optimism
      const metricsData = await Promise.all(
        supportedChains.map(async (chainId) => {
          const data = await contract.getChainMetrics(chainId);
          return {
            chainId,
            alertCount: data.alertCount.toNumber(),
            verifiedAlerts: data.verifiedAlerts.toNumber(),
            falsePositives: data.falsePositives.toNumber(),
            lastUpdateTimestamp: data.lastUpdateTimestamp.toNumber(),
          };
        })
      );
      setMetrics(metricsData);
    } catch (error) {
      toast({
        title: "Error fetching metrics",
        description: error.message,
        status: "error",
        duration: 5000,
      });
    }
  }, [contract, toast]);

  const fetchAlerts = useCallback(async () => {
    try {
      const filter = contract.filters.SecurityAlertRaised();
      const events = await contract.queryFilter(filter, -10000);

      const alertsData = await Promise.all(
        events.map(async (event) => {
          const alert = await contract.alerts(event.args.alertId);
          const verifications = await contract.getAlertVerifications(
            event.args.alertId
          );

          return {
            id: event.args.alertId,
            sourceChainId: alert.sourceChainId.toNumber(),
            alertType: alert.alertType,
            severity: alert.severity.toNumber(),
            timestamp: alert.timestamp.toNumber(),
            isVerified: alert.isVerified,
            verifications: verifications.toNumber(),
          };
        })
      );

      setAlerts(alertsData);
    } catch (error) {
      toast({
        title: "Error fetching alerts",
        description: error.message,
        status: "error",
        duration: 5000,
      });
    }
  }, [contract, toast]);

  const fetchChainActivity = useCallback(async () => {
    try {
      const filter = contract.filters.SecurityAlertRaised(null, selectedChain);
      const events = await contract.queryFilter(filter, -10000);

      const activityMap = new Map<number, ChainActivity>();

      events.forEach((event) => {
        const day = Math.floor(event.args.timestamp.toNumber() / 86400) * 86400;
        const existing = activityMap.get(day) || {
          timestamp: day,
          alerts: 0,
          verifications: 0,
        };

        existing.alerts++;
        activityMap.set(day, existing);
      });

      setChainActivity(Array.from(activityMap.values()));
    } catch (error) {
      toast({
        title: "Error fetching chain activity",
        description: error.message,
        status: "error",
        duration: 5000,
      });
    }
  }, [contract, selectedChain, toast]);

  useEffect(() => {
    const init = async () => {
      setLoading(true);
      await Promise.all([fetchMetrics(), fetchAlerts(), fetchChainActivity()]);
      setLoading(false);
    };

    init();

    const interval = setInterval(init, 30000); // Refresh every 30 seconds
    return () => clearInterval(interval);
  }, [fetchMetrics, fetchAlerts, fetchChainActivity]);

  const getSeverityColor = (severity: number) => {
    switch (severity) {
      case 1:
        return "yellow";
      case 2:
        return "orange";
      case 3:
        return "red";
      default:
        return "gray";
    }
  };

  const formatTime = (timestamp: number) => {
    return formatDistance(new Date(timestamp * 1000), new Date(), {
      addSuffix: true,
    });
  };

  return (
    <Box p={6}>
      <Flex justify="space-between" align="center" mb={6}>
        <Heading size="lg">Security Monitor Dashboard</Heading>
        <Select
          w="200px"
          value={selectedChain}
          onChange={(e) => setSelectedChain(Number(e.target.value))}
        >
          <option value={1}>Mainnet</option>
          <option value={2}>Arbitrum</option>
          <option value={3}>Optimism</option>
        </Select>
      </Flex>

      <Grid templateColumns="repeat(4, 1fr)" gap={6} mb={8}>
        {metrics.map((metric) => (
          <Stat key={metric.chainId} p={4} shadow="md" borderRadius="md">
            <StatLabel>Chain {metric.chainId}</StatLabel>
            <StatNumber>{metric.alertCount}</StatNumber>
            <StatHelpText>
              <StatArrow
                type={metric.falsePositives === 0 ? "increase" : "decrease"}
              />
              {((metric.verifiedAlerts / metric.alertCount) * 100).toFixed(1)}%
              verified
            </StatHelpText>
          </Stat>
        ))}
      </Grid>

      <Tabs>
        <TabList>
          <Tab>Recent Alerts</Tab>
          <Tab>Chain Activity</Tab>
          <Tab>Alert Distribution</Tab>
        </TabList>

        <TabPanels>
          <TabPanel>
            <Table variant="simple">
              <Thead>
                <Tr>
                  <Th>Type</Th>
                  <Th>Severity</Th>
                  <Th>Chain</Th>
                  <Th>Time</Th>
                  <Th>Status</Th>
                </Tr>
              </Thead>
              <Tbody>
                {alerts.map((alert) => (
                  <Tr key={alert.id}>
                    <Td>{alert.alertType}</Td>
                    <Td>
                      <Badge colorScheme={getSeverityColor(alert.severity)}>
                        Level {alert.severity}
                      </Badge>
                    </Td>
                    <Td>Chain {alert.sourceChainId}</Td>
                    <Td>{formatTime(alert.timestamp)}</Td>
                    <Td>
                      <Badge colorScheme={alert.isVerified ? "green" : "gray"}>
                        {alert.isVerified
                          ? "Verified"
                          : `${alert.verifications} verifications`}
                      </Badge>
                    </Td>
                  </Tr>
                ))}
              </Tbody>
            </Table>
          </TabPanel>

          <TabPanel>
            <Box h="400px">
              <ResponsiveContainer>
                <LineChart data={chainActivity}>
                  <CartesianGrid strokeDasharray="3 3" />
                  <XAxis
                    dataKey="timestamp"
                    tickFormatter={(timestamp) =>
                      new Date(timestamp * 1000).toLocaleDateString()
                    }
                  />
                  <YAxis />
                  <Tooltip
                    labelFormatter={(timestamp) =>
                      new Date(timestamp * 1000).toLocaleString()
                    }
                  />
                  <Legend />
                  <Line type="monotone" dataKey="alerts" stroke="#8884d8" />
                  <Line
                    type="monotone"
                    dataKey="verifications"
                    stroke="#82ca9d"
                  />
                </LineChart>
              </ResponsiveContainer>
            </Box>
          </TabPanel>

          <TabPanel>
            <Box h="400px">
              <ResponsiveContainer>
                <BarChart data={metrics}>
                  <CartesianGrid strokeDasharray="3 3" />
                  <XAxis dataKey="chainId" />
                  <YAxis />
                  <Tooltip />
                  <Legend />
                  <Bar
                    dataKey="alertCount"
                    fill="#8884d8"
                    name="Total Alerts"
                  />
                  <Bar
                    dataKey="verifiedAlerts"
                    fill="#82ca9d"
                    name="Verified Alerts"
                  />
                  <Bar
                    dataKey="falsePositives"
                    fill="#ff8042"
                    name="False Positives"
                  />
                </BarChart>
              </ResponsiveContainer>
            </Box>
          </TabPanel>
        </TabPanels>
      </Tabs>
    </Box>
  );
};
