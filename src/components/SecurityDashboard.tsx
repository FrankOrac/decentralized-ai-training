import React, { useState, useEffect } from 'react';
import {
  Box,
  VStack,
  HStack,
  Grid,
  Heading,
  Text,
  Table,
  Thead,
  Tbody,
  Tr,
  Th,
  Td,
  Badge,
  Button,
  Alert,
  AlertIcon,
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
  Modal,
  ModalOverlay,
  ModalContent,
  ModalHeader,
  ModalBody,
  ModalCloseButton,
  FormControl,
  FormLabel,
  Input,
  Select,
  useDisclosure,
} from '@chakra-ui/react';
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
} from 'recharts';
import { useWeb3 } from '../hooks/useWeb3';

interface SecurityMetrics {
  totalAudits: number;
  passedAudits: number;
  activeThreats: number;
  resolvedThreats: number;
  averageAuditScore: number;
  lastUpdateTimestamp: number;
}

interface ThreatAlert {
  id: string;
  alertType: string;
  severity: number;
  description: string;
  timestamp: number;
  isResolved: boolean;
}

interface SecurityAudit {
  id: string;
  auditType: string;
  contractAddress: string;
  timestamp: number;
  score: number;
  findings: string;
  passed: boolean;
}

export function SecurityDashboard() {
  const { contract } = useWeb3();
  const toast = useToast();
  const { isOpen, onOpen, onClose } = useDisclosure();

  const [metrics, setMetrics] = useState<SecurityMetrics | null>(null);
  const [threats, setThreats] = useState<ThreatAlert[]>([]);
  const [audits, setAudits] = useState<SecurityAudit[]>([]);
  const [loading, setLoading] = useState(true);
  const [selectedContract, setSelectedContract] = useState<string>('');

  useEffect(() => {
    if (contract) {
      fetchSecurityData();
      const interval = setInterval(fetchSecurityData, 30000);
      return () => clearInterval(interval);
    }
  }, [contract, selectedContract]);

  const fetchSecurityData = async () => {
    try {
      setLoading(true);

      // Fetch security metrics
      if (selectedContract) {
        const contractMetrics = await contract.contractMetrics(selectedContract);
        setMetrics({
          totalAudits: contractMetrics.totalAudits.toNumber(),
          passedAudits: contractMetrics.passedAudits.toNumber(),
          activeThreats: contractMetrics.activeThreats.toNumber(),
          resolvedThreats: contractMetrics.resolvedThreats.toNumber(),
          averageAuditScore: contractMetrics.averageAuditScore.toNumber(),
          lastUpdateTimestamp: contractMetrics.lastUpdateTimestamp.toNumber()
        });
      }

      // Fetch recent threats
      const threatFilter = contract.filters.ThreatDetected();
      const threatEvents = await contract.queryFilter(threatFilter);
      const threatData = await Promise.all(
        threatEvents.map(async (event) => {
          const threat = await contract.threats(event.args?.threatId);
          return {
            id: event.args?.threatId,
            alertType: threat.alertType,
            severity: threat.severity.toNumber(),
            description: threat.description,
            timestamp: threat.timestamp.toNumber(),
            isResolved: threat.isResolved
          };
        })
      );
      setThreats(threatData);

      // Fetch recent audits
      const auditFilter = contract.filters.AuditCompleted();
      const auditEvents = await contract.queryFilter(auditFilter);
      const auditData = await Promise.all(
        auditEvents.map(async (event) => {
          const audit = await contract.audits(event.args?.auditId);
          return {
            id: event.args?.auditId,
            auditType: audit.auditType,
            contractAddress: audit.contractAddress,
            timestamp: audit.timestamp.toNumber(),
            score: audit.score.toNumber(),
            findings: audit.findings,
            passed: audit.passed
          };
        })
      );
      setAudits(auditData);

    } catch (error) {
      console.error('Error fetching security data:', error);
      toast({
        title: 'Error fetching security data',
        status: 'error',
        duration: 5000
      });
    } finally {
      setLoading(false);
    }
  };

  const getSeverityColor = (severity: number) => {
    switch (severity) {
      case 3: return 'red';
      case 2: return 'orange';
      case 1: return 'yellow';
      default: return 'gray';
    }
  };

  const formatTimestamp = (timestamp: number) => {
    return new Date(timestamp * 1000).toLocaleString();
  };

  return (
    <Box p={6}>
      <VStack spacing={6} align="stretch">
        <HStack justify="space-between">
          <Heading size="lg">Security Monitor</Heading>
          <Select
            placeholder="Select Contract"
            value={selectedContract}
            onChange={(e) => setSelectedContract(e.target.value)}
            width="300px"
          >
            {/* Add contract options */}
          </Select>
        </HStack>

        {metrics && (
          <Grid templateColumns="repeat(4, 1fr)" gap={6}>
            <Stat>
              <StatLabel>Security Score</StatLabel>
              <StatNumber>{metrics.averageAuditScore}%</StatNumber>
              <StatHelpText>
                <StatArrow type="increase" />
                From last audit
              </StatHelpText>
            </Stat>

            <Stat>
              <StatLabel>Active Threats</StatLabel>
              <StatNumber>{metrics.activeThreats}</StatNumber>
              <StatHelpText>
                {metrics.resolvedThreats} resolved
              </StatHelpText>
            </Stat>

            <Stat>
              <StatLabel>Audit Success Rate</StatLabel>
              <StatNumber>
                {(metrics.passedAudits / metrics.totalAudits * 100).toFixed(1)}%
              </StatNumber>
              <StatHelpText>
                {metrics.totalAudits} total audits
              </StatHelpText>
            </Stat>

            <Stat>
              <StatLabel>Last Update</StatLabel>
              <StatNumber>
                {formatTimestamp(metrics.lastUpdateTimestamp)}
              </StatNumber>
            </Stat>
          </Grid>
        )}

        <Tabs>
          <TabList>
            <Tab>Active Threats</Tab>
            <Tab>Audit History</Tab>
            <Tab>Security Metrics</Tab>
          </TabList>

          <TabPanels>
            <TabPanel>
              <Table variant="simple">
                <Thead>
                  <Tr>
                    <Th>Type</Th>
                    <Th>Severity</Th>
                    <Th>Description</Th>
                    <Th>Detected</Th>
                    <Th>Status</Th>
                  </Tr>
                </Thead>
                <Tbody>
                  {threats.map((threat) => (
                    <Tr key={threat.id}>
                      <Td>{threat.alertType}</Td>
                      <Td>
                        <Badge colorScheme={getSeverityColor(threat.severity)}>
                          {threat.severity === 3 ? 'Critical' :
                           threat.severity === 2 ? 'High' : 'Medium'}
                        </Badge>
                      </Td>
                      <Td>{threat.description}</Td>
                      <Td>{formatTimestamp(threat.timestamp)}</Td>
                      <Td>
                        <Badge
                          colorScheme={threat.isResolved ? 'green' : 'red'}
                        >
                          {threat.isResolved ? 'Resolved' : 'Active'}
                        </Badge>
                      </Td>
                    </Tr>
                  ))}
                </Tbody>
              </Table>
            </TabPanel>

            <TabPanel>
              <Table variant="simple">
                <Thead>
                  <Tr>
                    <Th>Contract</Th>
                    <Th>Type</Th>
                    <Th>Score</Th>
                    <Th>Result</Th>
                    <Th>Date</Th>
                  </Tr>
                </Thead>
                <Tbody>
                  {audits.map((audit) => (
                    <Tr key={audit.id}>
                      <Td>{`${audit.contractAddress.slice(0, 6)}...${audit.contractAddress.slice(-4)}`}</Td>
                      <Td>{audit.auditType}</Td>
                      <Td>{audit.score}%</Td>
                      <Td>
                        <Badge
                          colorScheme={audit.passed ? 'green' : 'red'}
                        >
                          {audit.passed ? 'Passed' : 'Failed'}
                        </Badge>
                      </Td>
                      <Td>{formatTimestamp(audit.timestamp)}</Td>
                    </Tr>
                  ))}
                </Tbody>
              </Table>
            </TabPanel>

            <TabPanel>
              <Box height="400px">
                <ResponsiveContainer>
                  <LineChart
                    data={audits.map((audit) => ({
                      timestamp: audit.timestamp,
                      score: audit.score
                    }))}
                  >
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
                      dataKey="score"
                      stroke="#8884d8"
                      name="Security Score"
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
}
