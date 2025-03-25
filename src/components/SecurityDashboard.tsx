import React, { useState, useEffect, useCallback } from 'react';
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
  Progress,
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
  PieChart,
  Pie,
  Cell,
} from 'recharts';
import { useWeb3 } from '../hooks/useWeb3';
import { format } from 'date-fns';
import { useContract } from '../hooks/useContract';
import { ethers } from 'ethers';

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

interface SecurityIncident {
  id: string;
  type: string;
  target: string;
  severity: number;
  timestamp: number;
  isResolved: boolean;
  approvals: number;
  evidence: string;
}

interface ContractMetrics {
  address: string;
  name: string;
  totalIncidents: number;
  activeIncidents: number;
  avgResponseTime: number;
  riskScore: number;
}

const SEVERITY_COLORS = {
  low: 'green',
  medium: 'yellow',
  high: 'orange',
  critical: 'red',
};

export function SecurityDashboard() {
  const { contract } = useWeb3();
  const toast = useToast();
  const { isOpen, onOpen, onClose } = useDisclosure();

  const [metrics, setMetrics] = useState<SecurityMetrics | null>(null);
  const [threats, setThreats] = useState<ThreatAlert[]>([]);
  const [audits, setAudits] = useState<SecurityAudit[]>([]);
  const [loading, setLoading] = useState(true);
  const [selectedContract, setSelectedContract] = useState<string>('');
  const [incidents, setIncidents] = useState<SecurityIncident[]>([]);
  const [selectedIncident, setSelectedIncident] = useState<SecurityIncident | null>(null);
  const [timeRange, setTimeRange] = useState<string>('24h');

  const { contract: securityMonitor } = useContract('SecurityMonitor');

  useEffect(() => {
    if (contract) {
      fetchSecurityData();
      const interval = setInterval(fetchSecurityData, 30000);
      return () => clearInterval(interval);
    }
  }, [contract, selectedContract]);

  const fetchSecurityData = useCallback(async () => {
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

      // Fetch incidents
      const filter = securityMonitor.filters.SecurityIncidentReported();
      const events = await securityMonitor.queryFilter(filter, -10000);

      const incidentData = await Promise.all(
        events.map(async (event) => {
          const incident = await securityMonitor.incidents(event.args.incidentId);
          const approvals = await securityMonitor.getApprovalCount(event.args.incidentId);
          
          return {
            id: event.args.incidentId,
            type: event.args.incidentType,
            target: incident.target,
            severity: incident.severity.toNumber(),
            timestamp: incident.timestamp.toNumber(),
            isResolved: incident.isResolved,
            approvals: approvals.toNumber(),
            evidence: ethers.utils.toUtf8String(incident.evidence),
          };
        })
      );

      setIncidents(incidentData);

      // Process metrics
      const contractMap = new Map<string, ContractMetrics>();
      incidentData.forEach(incident => {
        const existing = contractMap.get(incident.target) || {
          address: incident.target,
          name: 'Unknown Contract',
          totalIncidents: 0,
          activeIncidents: 0,
          avgResponseTime: 0,
          riskScore: 0,
        };

        existing.totalIncidents++;
        if (!incident.isResolved) {
          existing.activeIncidents++;
        }

        // Calculate risk score based on incident severity and resolution time
        const responseTime = incident.isResolved ? 
          (Date.now() / 1000 - incident.timestamp) : 0;
        existing.avgResponseTime = existing.avgResponseTime ?
          (existing.avgResponseTime + responseTime) / 2 : responseTime;
        
        const severityWeight = incident.severity / 10;
        const timeWeight = Math.min(responseTime / 86400, 1); // Normalize to 1 day
        existing.riskScore = (existing.riskScore + (severityWeight * (1 + timeWeight))) / 2;

        contractMap.set(incident.target, existing);
      });

      setMetrics(Array.from(contractMap.values()));
      setLoading(false);
    } catch (error) {
      console.error('Error fetching security data:', error);
      toast({
        title: 'Error',
        description: 'Failed to fetch security data',
        status: 'error',
        duration: 5000,
      });
      setLoading(false);
    }
  }, [contract, securityMonitor, toast]);

  useEffect(() => {
    fetchSecurityData();
    const interval = setInterval(fetchSecurityData, 30000);
    return () => clearInterval(interval);
  }, [fetchSecurityData]);

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

  const getSeverityLevel = (severity: number) => {
    if (severity <= 3) return 'low';
    if (severity <= 6) return 'medium';
    if (severity <= 8) return 'high';
    return 'critical';
  };

  const handleIncidentClick = (incident: SecurityIncident) => {
    setSelectedIncident(incident);
    onOpen();
  };

  const handleApproveResolution = async (incidentId: string) => {
    try {
      await securityMonitor.approveIncidentResolution(incidentId);
      toast({
        title: 'Success',
        description: 'Resolution approval submitted',
        status: 'success',
        duration: 5000,
      });
      await fetchSecurityData();
    } catch (error) {
      console.error('Error approving resolution:', error);
      toast({
        title: 'Error',
        description: 'Failed to approve resolution',
        status: 'error',
        duration: 5000,
      });
    }
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

        <Grid templateColumns="repeat(4, 1fr)" gap={6}>
          {metrics.map((metric) => (
            <Stat
              key={metric.address}
              p={4}
              shadow="md"
              borderWidth={1}
              borderRadius="md"
            >
              <StatLabel>{metric.name}</StatLabel>
              <StatNumber>{metric.activeIncidents}/{metric.totalIncidents}</StatNumber>
              <StatHelpText>
                <StatArrow
                  type={metric.riskScore < 0.5 ? 'decrease' : 'increase'}
                />
                Risk Score: {(metric.riskScore * 100).toFixed(1)}%
              </StatHelpText>
              <Progress
                value={metric.riskScore * 100}
                colorScheme={metric.riskScore < 0.3 ? 'green' : 
                           metric.riskScore < 0.7 ? 'yellow' : 'red'}
                size="sm"
                mt={2}
              />
            </Stat>
          ))}
        </Grid>

        <Grid templateColumns="1fr 1fr" gap={6}>
          <Box h="300px">
            <ResponsiveContainer>
              <LineChart data={incidents}>
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
                <Line
                  type="monotone"
                  dataKey="severity"
                  stroke="#8884d8"
                  name="Incident Severity"
                />
              </LineChart>
            </ResponsiveContainer>
          </Box>

          <Box h="300px">
            <ResponsiveContainer>
              <PieChart>
                <Pie
                  data={metrics}
                  dataKey="activeIncidents"
                  nameKey="name"
                  cx="50%"
                  cy="50%"
                  outerRadius={100}
                  label
                >
                  {metrics.map((entry, index) => (
                    <Cell
                      key={`cell-${index}`}
                      fill={entry.riskScore < 0.3 ? '#48BB78' :
                            entry.riskScore < 0.7 ? '#ECC94B' : '#E53E3E'}
                    />
                  ))}
                </Pie>
                <Tooltip />
                <Legend />
              </PieChart>
            </ResponsiveContainer>
          </Box>
        </Grid>

        <Table variant="simple">
          <Thead>
            <Tr>
              <Th>Time</Th>
              <Th>Type</Th>
              <Th>Target</Th>
              <Th>Severity</Th>
              <Th>Status</Th>
              <Th>Actions</Th>
            </Tr>
          </Thead>
          <Tbody>
            {incidents.map((incident) => (
              <Tr
                key={incident.id}
                cursor="pointer"
                onClick={() => handleIncidentClick(incident)}
              >
                <Td>{format(incident.timestamp * 1000, 'yyyy-MM-dd HH:mm:ss')}</Td>
                <Td>{incident.type}</Td>
                <Td>{incident.target}</Td>
                <Td>
                  <Badge
                    colorScheme={SEVERITY_COLORS[getSeverityLevel(incident.severity)]}
                  >
                    {getSeverityLevel(incident.severity).toUpperCase()}
                  </Badge>
                </Td>
                <Td>
                  <Badge
                    colorScheme={incident.isResolved ? 'green' : 'yellow'}
                  >
                    {incident.isResolved ? 'Resolved' : `${incident.approvals} Approvals`}
                  </Badge>
                </Td>
                <Td>
                  <Button
                    size="sm"
                    colorScheme="blue"
                    onClick={(e) => {
                      e.stopPropagation();
                      handleApproveResolution(incident.id);
                    }}
                    isDisabled={incident.isResolved}
                  >
                    Approve Resolution
                  </Button>
                </Td>
              </Tr>
            ))}
          </Tbody>
        </Table>

        <Modal isOpen={isOpen} onClose={onClose} size="xl">
          <ModalOverlay />
          <ModalContent>
            <ModalHeader>Incident Details</ModalHeader>
            <ModalCloseButton />
            <ModalBody>
              {selectedIncident && (
                <VStack align="stretch" spacing={4}>
                  <Text><strong>Type:</strong> {selectedIncident.type}</Text>
                  <Text><strong>Target:</strong> {selectedIncident.target}</Text>
                  <Text><strong>Severity:</strong> {selectedIncident.severity}</Text>
                  <Text><strong>Time:</strong> {format(selectedIncident.timestamp * 1000, 'yyyy-MM-dd HH:mm:ss')}</Text>
                  <Text><strong>Status:</strong> {selectedIncident.isResolved ? 'Resolved' : 'Active'}</Text>
                  <Text><strong>Approvals:</strong> {selectedIncident.approvals}</Text>
                  <Box>
                    <Text><strong>Evidence:</strong></Text>
                    <Box
                      p={4}
                      bg="gray.50"
                      borderRadius="md"
                      whiteSpace="pre-wrap"
                    >
                      {selectedIncident.evidence}
                    </Box>
                  </Box>
                </VStack>
              )}
            </ModalBody>
          </ModalContent>
        </Modal>
      </VStack>
    </Box>
  );
}
