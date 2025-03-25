import React, { useState, useEffect } from "react";
import {
  Box,
  VStack,
  HStack,
  Text,
  Badge,
  Button,
  Table,
  Thead,
  Tbody,
  Tr,
  Th,
  Td,
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
} from "@chakra-ui/react";
import { useWeb3 } from "../hooks/useWeb3";

interface Alert {
  id: number;
  alertType: string;
  description: string;
  severity: number;
  timestamp: number;
  isActive: boolean;
  reporter: string;
}

interface MonitoringRule {
  id: number;
  name: string;
  condition: string;
  threshold: number;
  severity: number;
  isActive: boolean;
}

export function AlertSystem() {
  const { contract, account } = useWeb3();
  const toast = useToast();
  const { isOpen, onOpen, onClose } = useDisclosure();

  const [alerts, setAlerts] = useState<Alert[]>([]);
  const [rules, setRules] = useState<MonitoringRule[]>([]);
  const [loading, setLoading] = useState(false);
  const [newRule, setNewRule] = useState({
    name: "",
    condition: "",
    threshold: 0,
    severity: 1,
  });

  useEffect(() => {
    if (contract) {
      fetchAlerts();
      fetchRules();
      const interval = setInterval(fetchAlerts, 30000); // Update every 30 seconds
      return () => clearInterval(interval);
    }
  }, [contract]);

  const fetchAlerts = async () => {
    try {
      const activeAlerts = await contract.getActiveAlerts();
      setAlerts(activeAlerts);
    } catch (error) {
      console.error("Error fetching alerts:", error);
    }
  };

  const fetchRules = async () => {
    try {
      const activeRules = await contract.getActiveRules();
      setRules(activeRules);
    } catch (error) {
      console.error("Error fetching rules:", error);
    }
  };

  const handleResolveAlert = async (alertId: number) => {
    try {
      setLoading(true);
      const tx = await contract.resolveAlert(alertId);
      await tx.wait();

      toast({
        title: "Alert resolved successfully",
        status: "success",
        duration: 5000,
      });

      fetchAlerts();
    } catch (error) {
      console.error("Error resolving alert:", error);
      toast({
        title: "Error resolving alert",
        status: "error",
        duration: 5000,
      });
    } finally {
      setLoading(false);
    }
  };

  const handleCreateRule = async () => {
    try {
      setLoading(true);
      const tx = await contract.createMonitoringRule(
        newRule.name,
        newRule.condition,
        newRule.threshold,
        newRule.severity
      );
      await tx.wait();

      toast({
        title: "Rule created successfully",
        status: "success",
        duration: 5000,
      });

      onClose();
      fetchRules();
    } catch (error) {
      console.error("Error creating rule:", error);
      toast({
        title: "Error creating rule",
        status: "error",
        duration: 5000,
      });
    } finally {
      setLoading(false);
    }
  };

  const getSeverityColor = (severity: number) => {
    switch (severity) {
      case 3:
        return "red";
      case 2:
        return "orange";
      case 1:
        return "yellow";
      default:
        return "gray";
    }
  };

  return (
    <Box p={6}>
      <VStack spacing={6} align="stretch">
        <HStack justify="space-between">
          <Text fontSize="2xl">Alert System</Text>
          <Button colorScheme="blue" onClick={onOpen}>
            Create Rule
          </Button>
        </HStack>

        <Box>
          <Text fontSize="xl" mb={4}>
            Active Alerts
          </Text>
          <Table variant="simple">
            <Thead>
              <Tr>
                <Th>Type</Th>
                <Th>Description</Th>
                <Th>Severity</Th>
                <Th>Time</Th>
                <Th>Actions</Th>
              </Tr>
            </Thead>
            <Tbody>
              {alerts.map((alert) => (
                <Tr key={alert.id}>
                  <Td>{alert.alertType}</Td>
                  <Td>{alert.description}</Td>
                  <Td>
                    <Badge colorScheme={getSeverityColor(alert.severity)}>
                      {alert.severity === 3
                        ? "High"
                        : alert.severity === 2
                        ? "Medium"
                        : "Low"}
                    </Badge>
                  </Td>
                  <Td>{new Date(alert.timestamp * 1000).toLocaleString()}</Td>
                  <Td>
                    <Button
                      size="sm"
                      colorScheme="green"
                      onClick={() => handleResolveAlert(alert.id)}
                      isLoading={loading}
                    >
                      Resolve
                    </Button>
                  </Td>
                </Tr>
              ))}
            </Tbody>
          </Table>
        </Box>

        <Box>
          <Text fontSize="xl" mb={4}>
            Monitoring Rules
          </Text>
          <Table variant="simple">
            <Thead>
              <Tr>
                <Th>Name</Th>
                <Th>Condition</Th>
                <Th>Threshold</Th>
                <Th>Severity</Th>
                <Th>Status</Th>
              </Tr>
            </Thead>
            <Tbody>
              {rules.map((rule) => (
                <Tr key={rule.id}>
                  <Td>{rule.name}</Td>
                  <Td>{rule.condition}</Td>
                  <Td>{rule.threshold}</Td>
                  <Td>
                    <Badge colorScheme={getSeverityColor(rule.severity)}>
                      {rule.severity === 3
                        ? "High"
                        : rule.severity === 2
                        ? "Medium"
                        : "Low"}
                    </Badge>
                  </Td>
                  <Td>
                    <Badge colorScheme={rule.isActive ? "green" : "red"}>
                      {rule.isActive ? "Active" : "Inactive"}
                    </Badge>
                  </Td>
                </Tr>
              ))}
            </Tbody>
          </Table>
        </Box>

        <Modal isOpen={isOpen} onClose={onClose}>
          <ModalOverlay />
          <ModalContent>
            <ModalHeader>Create Monitoring Rule</ModalHeader>
            <ModalCloseButton />
            <ModalBody pb={6}>
              <VStack spacing={4}>
                <FormControl>
                  <FormLabel>Rule Name</FormLabel>
                  <Input
                    value={newRule.name}
                    onChange={(e) =>
                      setNewRule({
                        ...newRule,
                        name: e.target.value,
                      })
                    }
                  />
                </FormControl>

                <FormControl>
                  <FormLabel>Condition</FormLabel>
                  <Input
                    value={newRule.condition}
                    onChange={(e) =>
                      setNewRule({
                        ...newRule,
                        condition: e.target.value,
                      })
                    }
                  />
                </FormControl>

                <FormControl>
                  <FormLabel>Threshold</FormLabel>
                  <Input
                    type="number"
                    value={newRule.threshold}
                    onChange={(e) =>
                      setNewRule({
                        ...newRule,
                        threshold: parseInt(e.target.value),
                      })
                    }
                  />
                </FormControl>

                <FormControl>
                  <FormLabel>Severity</FormLabel>
                  <Select
                    value={newRule.severity}
                    onChange={(e) =>
                      setNewRule({
                        ...newRule,
                        severity: parseInt(e.target.value),
                      })
                    }
                  >
                    <option value={1}>Low</option>
                    <option value={2}>Medium</option>
                    <option value={3}>High</option>
                  </Select>
                </FormControl>

                <Button
                  colorScheme="blue"
                  width="full"
                  onClick={handleCreateRule}
                  isLoading={loading}
                >
                  Create Rule
                </Button>
              </VStack>
            </ModalBody>
          </ModalContent>
        </Modal>
      </VStack>
    </Box>
  );
}
