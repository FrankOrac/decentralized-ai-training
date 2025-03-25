import React, { useState, useEffect } from 'react';
import {
  Box,
  Grid,
  VStack,
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
  useToast,
} from '@chakra-ui/react';
import {
  LineChart,
  Line,
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
} from 'recharts';
import { useWeb3 } from '../hooks/useWeb3';

interface HistoricalSnapshot {
  timestamp: number;
  totalProposals: number;
  successRate: number;
  averageParticipation: number;
  activeVoters: number;
}

interface VoterMetrics {
  proposalsVoted: number;
  proposalsCreated: number;
  successfulProposals: number;
  totalGasSpent: number;
  lastActiveBlock: number;
}

export function AnalyticsDashboard() {
  const { contract, account } = useWeb3();
  const toast = useToast();

  const [snapshots, setSnapshots] = useState<HistoricalSnapshot[]>([]);
  const [voterMetrics, setVoterMetrics] = useState<VoterMetrics | null>(null);
  const [loading, setLoading] = useState(true);

  useEffect(() => {
    if (contract) {
      fetchAnalytics();
      const interval = setInterval(fetchAnalytics, 60000); // Update every minute
      return () => clearInterval(interval);
    }
  }, [contract]);

  const fetchAnalytics = async () => {
    try {
      setLoading(true);
      
      // Fetch historical snapshots
      const latestSnapshot = await contract.getLatestSnapshot();
      const snapshotCount = latestSnapshot.timestamp.toNumber();
      const fetchedSnapshots = [];
      
      for (let i = Math.max(0, snapshotCount - 30); i <= snapshotCount; i++) {
        const snapshot = await contract.historicalSnapshots(i);
        fetchedSnapshots.push({
          timestamp: snapshot.timestamp.toNumber(),
          totalProposals: snapshot.totalProposals.toNumber(),
          successRate: snapshot.successRate.toNumber(),
          averageParticipation: snapshot.averageParticipation.toNumber(),
          activeVoters: snapshot.activeVoters.toNumber(),
        });
      }
      
      setSnapshots(fetchedSnapshots);

      // Fetch voter metrics if account is connected
      if (account) {
        const metrics = await contract.getVoterStats(account);
        setVoterMetrics({
          proposalsVoted: metrics.proposalsVoted.toNumber(),
          proposalsCreated: metrics.proposalsCreated.toNumber(),
          successfulProposals: metrics.successfulProposals.toNumber(),
          totalGasSpent: metrics.totalGasSpent.toNumber(),
          lastActiveBlock: metrics.lastActiveBlock.toNumber(),
        });
      }

    } catch (error) {
      console.error('Error fetching analytics:', error);
      toast({
        title: 'Error fetching analytics',
        status: 'error',
        duration: 5000,
      });
    } finally {
      setLoading(false);
    }
  };

  const formatTimestamp = (timestamp: number) => {
    return new Date(timestamp * 1000).toLocaleDateString();
  };

  return (
    <Box p={6}>
      <VStack spacing={6} align="stretch">
        <Heading size="lg">Governance Analytics</Heading>

        <Grid templateColumns="repeat(4, 1fr)" gap={6}>
          <Stat>
            <StatLabel>Total Proposals</StatLabel>
            <StatNumber>
              {snapshots[snapshots.length - 1]?.totalProposals || 0}
            </StatNumber>
            <StatHelpText>
              <StatArrow 
                type={snapshots[snapshots.length - 1]?.totalProposals > 
                      snapshots[snapshots.length - 2]?.totalProposals ? 'increase' : 'decrease'} 
              />
              From last period
            </StatHelpText>
          </Stat>

          <Stat>
            <StatLabel>Success Rate</StatLabel>
            <StatNumber>
              {snapshots[snapshots.length - 1]?.successRate || 0}%
            </StatNumber>
            <StatHelpText>
              <StatArrow 
                type={snapshots[snapshots.length - 1]?.successRate > 
                      snapshots[snapshots.length - 2]?.successRate ? 'increase' : 'decrease'} 
              />
              From last period
            </StatHelpText>
          </Stat>

          <Stat>
            <StatLabel>Average Participation</StatLabel>
            <StatNumber>
              {snapshots[snapshots.length - 1]?.averageParticipation || 0}%
            </StatNumber>
            <StatHelpText>
              <StatArrow 
                type={snapshots[snapshots.length - 1]?.averageParticipation > 
                      snapshots[snapshots.length - 2]?.averageParticipation ? 'increase' : 'decrease'} 
              />
              From last period
            </StatHelpText>
          </Stat>

          <Stat>
            <StatLabel>Active Voters</StatLabel>
            <StatNumber>
              {snapshots[snapshots.length - 1]?.activeVoters || 0}
            </StatNumber>
            <StatHelpText>
              <StatArrow 
                type={snapshots[snapshots.length - 1]?.activeVoters > 
                      snapshots[snapshots.length - 2]?.activeVoters ? 'increase' : 'decrease'} 
              />
              From last period
            </StatHelpText>
          </Stat>
        </Grid>

        <Tabs>
          <TabList>
            <Tab>Proposal Trends</Tab>
            <Tab>Participation Analysis</Tab>
            {account && <Tab>Your Activity</Tab>}
          </TabList>

          <TabPanels>
            <TabPanel>
              <Box height="400px">
                <ResponsiveContainer>
                  <LineChart data={snapshots}>
                    <CartesianGrid strokeDasharray="3 3" />
                    <XAxis 
                      dataKey="timestamp" 
                      tickFormatter={formatTimestamp}
                    />
                    <YAxis />
                    <Tooltip 
                      labelFormatter={formatTimestamp}
                    />
                    <Legend />
                    <Line 
                      type="monotone" 
                      dataKey="totalProposals" 
                      stroke="#8884d8" 
                      name="Total Proposals"
                    />
                    <Line 
                      type="monotone" 
                      dataKey="successRate" 
                      stroke="#82ca9d" 
                      name="Success Rate (%)"
                    />
                  </LineChart>
                </ResponsiveContainer>
              </Box>
            </TabPanel>

            <TabPanel>
              <Box height="400px">
                <ResponsiveContainer>
                  <BarChart data={snapshots}>
                    <CartesianGrid strokeDasharray="3 3" />
                    <XAxis 
                      dataKey="timestamp" 
                      tickFormatter={formatTimestamp}
                    />
                    <YAxis />
                    <Tooltip 
                      labelFormatter={formatTimestamp}
                    />
                    <Legend />
                    <Bar 
                      dataKey="averageParticipation" 
                      fill="#8884d8" 
                      name="Participation (%)"
                    />
                    <Bar 
                      dataKey="activeVoters" 
                      fill="#82ca9d" 
                      name="Active Voters"
                    />
                  </BarChart>
                </ResponsiveContainer>
              </Box>
            </TabPanel>

            {account && (
              <TabPanel>
                {voterMetrics && (
          <Grid templateColumns="repeat(2, 1fr)" gap={6}>
                    <Box height="300px">
                      <ResponsiveContainer>
                        <PieChart>
                          <Pie
                            data={[
                              {
                                name: 'Successful',
                                value: voterMetrics.successfulProposals,
                              },
                              {
                                name: 'Other',
                                value: voterMetrics.proposalsCreated - voterMetrics.successfulProposals,
                              },
                            ]}
                            dataKey="value"
                            nameKey="name"
                            cx="50%"
                            cy="50%"
                            outerRadius={80}
                            fill="#8884d8"
                            label
                          />
                          <Tooltip />
                          <Legend />
                        </PieChart>
                      </ResponsiveContainer>
                    </Box>

                    <VStack align="stretch" spacing={4}>
                      <Stat>
                        <StatLabel>Proposals Voted</StatLabel>
                        <StatNumber>{voterMetrics.proposalsVoted}</StatNumber>
                      </Stat>
            <Stat>
                        <StatLabel>Proposals Created</StatLabel>
                        <StatNumber>{voterMetrics.proposalsCreated}</StatNumber>
            </Stat>
            <Stat>
                        <StatLabel>Total Gas Spent</StatLabel>
              <StatNumber>
                          {(voterMetrics.totalGasSpent / 1e9).toFixed(2)} Gwei
              </StatNumber>
            </Stat>
                    </VStack>
          </Grid>
                )}
              </TabPanel>
            )}
          </TabPanels>
        </Tabs>
      </VStack>
    </Box>
  );
}
