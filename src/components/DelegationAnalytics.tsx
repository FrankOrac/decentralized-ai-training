import React, { useState, useEffect } from "react";
import {
  Box,
  VStack,
  Grid,
  Stat,
  StatLabel,
  StatNumber,
  StatHelpText,
  StatArrow,
  Table,
  Thead,
  Tbody,
  Tr,
  Th,
  Td,
  useToast,
  Heading,
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
import { useWeb3 } from "../hooks/useWeb3";

interface DelegationStats {
  totalDelegations: number;
  activeDelegations: number;
  uniqueDelegators: number;
  uniqueDelegates: number;
  averageDelegationDuration: number;
  topDelegates: Array<{
    address: string;
    votingPower: number;
    delegatorCount: number;
  }>;
}

export function DelegationAnalytics() {
  const { contract } = useWeb3();
  const toast = useToast();

  const [stats, setStats] = useState<DelegationStats | null>(null);
  const [historicalData, setHistoricalData] = useState<any[]>([]);
  const [loading, setLoading] = useState(true);

  useEffect(() => {
    if (contract) {
      fetchAnalytics();
      const interval = setInterval(fetchAnalytics, 60000);
      return () => clearInterval(interval);
    }
  }, [contract]);

  const fetchAnalytics = async () => {
    try {
      setLoading(true);

      // Fetch current statistics
      const [
        totalDelegations,
        activeDelegations,
        uniqueDelegators,
        uniqueDelegates,
        avgDuration,
      ] = await contract.getDelegationStats();

      // Fetch top delegates
      const topDelegates = await contract.getTopDelegates(10);

      setStats({
        totalDelegations: totalDelegations.toNumber(),
        activeDelegations: activeDelegations.toNumber(),
        uniqueDelegators: uniqueDelegators.toNumber(),
        uniqueDelegates: uniqueDelegates.toNumber(),
        averageDelegationDuration: avgDuration.toNumber(),
        topDelegates: topDelegates.map((d: any) => ({
          address: d.delegate,
          votingPower: d.votingPower.toNumber(),
          delegatorCount: d.delegatorCount.toNumber(),
        })),
      });

      // Fetch historical data
      const history = await contract.getDelegationHistory();
      setHistoricalData(
        history.map((h: any) => ({
          timestamp: new Date(
            h.timestamp.toNumber() * 1000
          ).toLocaleDateString(),
          activeDelegations: h.activeDelegations.toNumber(),
          votingPower: h.totalVotingPower.toNumber(),
        }))
      );
    } catch (error) {
      console.error("Error fetching delegation analytics:", error);
      toast({
        title: "Error fetching analytics",
        status: "error",
        duration: 5000,
      });
    } finally {
      setLoading(false);
    }
  };

  if (!stats) return null;

  return (
    <Box p={6}>
      <VStack spacing={6} align="stretch">
        <Heading size="lg">Delegation Analytics</Heading>

        <Grid templateColumns="repeat(4, 1fr)" gap={6}>
          <Stat>
            <StatLabel>Total Delegations</StatLabel>
            <StatNumber>{stats.totalDelegations}</StatNumber>
            <StatHelpText>
              <StatArrow type="increase" />
              {(
                (stats.activeDelegations / stats.totalDelegations) *
                100
              ).toFixed(1)}
              % Active
            </StatHelpText>
          </Stat>

          <Stat>
            <StatLabel>Unique Delegators</StatLabel>
            <StatNumber>{stats.uniqueDelegators}</StatNumber>
          </Stat>

          <Stat>
            <StatLabel>Unique Delegates</StatLabel>
            <StatNumber>{stats.uniqueDelegates}</StatNumber>
          </Stat>

          <Stat>
            <StatLabel>Avg. Duration</StatLabel>
            <StatNumber>
              {(stats.averageDelegationDuration / 86400).toFixed(1)} days
            </StatNumber>
          </Stat>
        </Grid>

        <Box height="400px">
          <Heading size="md" mb={4}>
            Delegation Activity
          </Heading>
          <ResponsiveContainer>
            <LineChart data={historicalData}>
              <CartesianGrid strokeDasharray="3 3" />
              <XAxis dataKey="timestamp" />
              <YAxis />
              <Tooltip />
              <Legend />
              <Line
                type="monotone"
                dataKey="activeDelegations"
                stroke="#8884d8"
                name="Active Delegations"
              />
              <Line
                type="monotone"
                dataKey="votingPower"
                stroke="#82ca9d"
                name="Total Voting Power"
              />
            </LineChart>
          </ResponsiveContainer>
        </Box>

        <Box>
          <Heading size="md" mb={4}>
            Top Delegates
          </Heading>
          <Table variant="simple">
            <Thead>
              <Tr>
                <Th>Delegate</Th>
                <Th isNumeric>Voting Power</Th>
                <Th isNumeric>Delegators</Th>
                <Th isNumeric>Share (%)</Th>
              </Tr>
            </Thead>
            <Tbody>
              {stats.topDelegates.map((delegate) => (
                <Tr key={delegate.address}>
                  <Td>{`${delegate.address.slice(
                    0,
                    6
                  )}...${delegate.address.slice(-4)}`}</Td>
                  <Td isNumeric>{delegate.votingPower}</Td>
                  <Td isNumeric>{delegate.delegatorCount}</Td>
                  <Td isNumeric>
                    {(
                      (delegate.votingPower / stats.totalDelegations) *
                      100
                    ).toFixed(2)}
                    %
                  </Td>
                </Tr>
              ))}
            </Tbody>
          </Table>
        </Box>

        <Box height="300px">
          <Heading size="md" mb={4}>
            Voting Power Distribution
          </Heading>
          <ResponsiveContainer>
            <BarChart data={stats.topDelegates}>
              <CartesianGrid strokeDasharray="3 3" />
              <XAxis
                dataKey="address"
                tickFormatter={(value) => `${value.slice(0, 6)}...`}
              />
              <YAxis />
              <Tooltip />
              <Legend />
              <Bar dataKey="votingPower" fill="#8884d8" name="Voting Power" />
              <Bar
                dataKey="delegatorCount"
                fill="#82ca9d"
                name="Delegator Count"
              />
            </BarChart>
          </ResponsiveContainer>
        </Box>
      </VStack>
    </Box>
  );
}
