import {
  Box,
  Button,
  Stack,
  Table,
  Thead,
  Tbody,
  Tr,
  Th,
  Td,
  Badge,
  Alert,
  AlertIcon,
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
  useToast,
} from "@chakra-ui/react";
import { useState, useEffect } from "react";
import { useWeb3 } from "../context/Web3Context";

export function SecurityDashboard() {
  const { contract } = useWeb3();
  const [incidents, setIncidents] = useState([]);
  const [systemStatus, setSystemStatus] = useState({
    isPaused: false,
    rateLimitExceeded: false,
  });
  const { isOpen, onOpen, onClose } = useDisclosure();
  const toast = useToast();

  const [newIncident, setNewIncident] = useState({
    description: "",
    severity: "Low",
  });

  useEffect(() => {
    if (contract) {
      fetchIncidents();
      checkSystemStatus();
    }
  }, [contract]);

  const fetchIncidents = async () => {
    try {
      const count = await contract.incidentCount();
      const fetchedIncidents = [];

      for (let i = 1; i <= count; i++) {
        const incident = await contract.getIncidentDetails(i);
        fetchedIncidents.push({
          id: i,
          ...incident,
        });
      }

      setIncidents(fetchedIncidents);
    } catch (error) {
      console.error("Error fetching incidents:", error);
    }
  };

  const checkSystemStatus = async () => {
    try {
      const paused = await contract.paused();
      setSystemStatus((prev) => ({ ...prev, isPaused: paused }));
    } catch (error) {
      console.error("Error checking system status:", error);
    }
  };

  const handleReportIncident = async () => {
    try {
      const tx = await contract.reportIncident(
        newIncident.description,
        ["Low", "Medium", "High", "Critical"].indexOf(newIncident.severity)
      );
      await tx.wait();

      toast({
        title: "Incident Reported",
        description: "Security incident has been reported successfully",
        status: "success",
      });

      onClose();
      fetchIncidents();
    } catch (error: any) {
      toast({
        title: "Error",
        description: error.message,
        status: "error",
      });
    }
  };

  const handleUpdateStatus = async (incidentId: number, status: number) => {
    try {
      const tx = await contract.updateIncidentStatus(incidentId, status, "");
      await tx.wait();

      toast({
        title: "Status Updated",
        description: "Incident status has been updated",
        status: "success",
      });

      fetchIncidents();
    } catch (error: any) {
      toast({
        title: "Error",
        description: error.message,
        status: "error",
      });
    }
  };

  return (
    <Box p={6}>
      <Stack spacing={6}>
        {systemStatus.isPaused && (
          <Alert status="error">
            <AlertIcon />
            System is currently paused due to security concerns
          </Alert>
        )}

        <Button colorScheme="blue" onClick={onOpen}>
          Report Security Incident
        </Button>

        <Table variant="simple">
          <Thead>
            <Tr>
              <Th>ID</Th>
              <Th>Reporter</Th>
              <Th>Severity</Th>
              <Th>Status</Th>
              <Th>Timestamp</Th>
              <Th>Actions</Th>
            </Tr>
          </Thead>
          <Tbody>
            {incidents.map((incident: any) => (
              <Tr key={incident.id}>
                <Td>{incident.id}</Td>
                <Td>{`${incident.reporter.slice(
                  0,
                  6
                )}...${incident.reporter.slice(-4)}`}</Td>
                <Td>
                  <Badge
                    colorScheme={
                      incident.severity === 3
                        ? "red"
                        : incident.severity === 2
                        ? "orange"
                        : incident.severity === 1
                        ? "yellow"
                        : "green"
                    }
                  >
                    {["Low", "Medium", "High", "Critical"][incident.severity]}
                  </Badge>
                </Td>
                <Td>
                  <Badge
                    colorScheme={
                      incident.status === 2
                        ? "green"
                        : incident.status === 3
                        ? "red"
                        : "yellow"
                    }
                  >
                    {
                      ["Reported", "Investigating", "Resolved", "Dismissed"][
                        incident.status
                      ]
                    }
                  </Badge>
                </Td>
                <Td>{new Date(incident.timestamp * 1000).toLocaleString()}</Td>
                <Td>
                  <Stack direction="row" spacing={2}>
                    <Button
                      size="sm"
                      colorScheme="green"
                      onClick={() => handleUpdateStatus(incident.id, 2)}
                    >
                      Resolve
                    </Button>
                    <Button
                      size="sm"
                      colorScheme="red"
                      onClick={() => handleUpdateStatus(incident.id, 3)}
                    >
                      Dismiss
                    </Button>
                  </Stack>
                </Td>
              </Tr>
            ))}
          </Tbody>
        </Table>

        <Modal isOpen={isOpen} onClose={onClose}>
          <ModalOverlay />
          <ModalContent>
            <ModalHeader>Report Security Incident</ModalHeader>
            <ModalCloseButton />
            <ModalBody>
              <Stack spacing={4}>
                <FormControl>
                  <FormLabel>Description</FormLabel>
                  <Input
                    value={newIncident.description}
                    onChange={(e) =>
                      setNewIncident({
                        ...newIncident,
                        description: e.target.value,
                      })
                    }
                  />
                </FormControl>

                <FormControl>
                  <FormLabel>Severity</FormLabel>
                  <Select
                    value={newIncident.severity}
                    onChange={(e) =>
                      setNewIncident({
                        ...newIncident,
                        severity: e.target.value,
                      })
                    }
                  >
                    <option value="Low">Low</option>
                    <option value="Medium">Medium</option>
                    <option value="High">High</option>
                    <option value="Critical">Critical</option>
                  </Select>
                </FormControl>

                <Button colorScheme="blue" onClick={handleReportIncident}>
                  Submit Report
                </Button>
              </Stack>
            </ModalBody>
          </ModalContent>
        </Modal>
      </Stack>
    </Box>
  );
}
