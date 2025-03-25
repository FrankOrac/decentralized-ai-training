import React, { useState, useEffect } from "react";
import {
  Box,
  VStack,
  HStack,
  Button,
  Table,
  Thead,
  Tbody,
  Tr,
  Th,
  Td,
  Badge,
  Modal,
  ModalOverlay,
  ModalContent,
  ModalHeader,
  ModalBody,
  ModalCloseButton,
  FormControl,
  FormLabel,
  Input,
  NumberInput,
  NumberInputField,
  useDisclosure,
  useToast,
  Text,
  Heading,
  Tooltip,
  Progress,
} from "@chakra-ui/react";
import { ethers } from "ethers";
import { useWeb3 } from "../hooks/useWeb3";

interface TimelockOperation {
  id: string;
  targets: string[];
  values: string[];
  calldatas: string[];
  predecessor: string;
  salt: string;
  delay: number;
  scheduledAt: number;
  executed: boolean;
  canceled: boolean;
}

export function TimelockManager() {
  const { contract, account } = useWeb3();
  const toast = useToast();
  const { isOpen, onOpen, onClose } = useDisclosure();

  const [operations, setOperations] = useState<TimelockOperation[]>([]);
  const [loading, setLoading] = useState(false);
  const [newOperation, setNewOperation] = useState({
    targets: [""],
    values: ["0"],
    calldatas: ["0x"],
    predecessor: ethers.constants.HashZero,
    salt: ethers.utils.randomBytes(32),
    delay: 86400, // 24 hours in seconds
  });

  useEffect(() => {
    if (contract) {
      fetchOperations();
      const interval = setInterval(fetchOperations, 30000);
      return () => clearInterval(interval);
    }
  }, [contract]);

  const fetchOperations = async () => {
    try {
      const filter = contract.filters.OperationScheduled();
      const events = await contract.queryFilter(filter);

      const operationsData = await Promise.all(
        events.map(async (event) => {
          const operation = await contract.operations(event.args.id);
          return {
            id: event.args.id,
            targets: operation.targets,
            values: operation.values.map((v: any) =>
              ethers.utils.formatEther(v)
            ),
            calldatas: operation.calldatas,
            predecessor: operation.predecessor,
            salt: operation.salt,
            delay: operation.delay.toNumber(),
            scheduledAt: operation.scheduledAt.toNumber(),
            executed: operation.executed,
            canceled: operation.canceled,
          };
        })
      );

      setOperations(operationsData);
    } catch (error) {
      console.error("Error fetching operations:", error);
    }
  };

  const handleScheduleOperation = async () => {
    try {
      setLoading(true);
      const tx = await contract.schedule(
        newOperation.targets,
        newOperation.values.map((v) => ethers.utils.parseEther(v)),
        newOperation.calldatas,
        newOperation.predecessor,
        newOperation.salt,
        newOperation.delay
      );
      await tx.wait();

      toast({
        title: "Operation scheduled successfully",
        status: "success",
        duration: 5000,
      });

      onClose();
      fetchOperations();
    } catch (error) {
      console.error("Error scheduling operation:", error);
      toast({
        title: "Error scheduling operation",
        description: error.message,
        status: "error",
        duration: 5000,
      });
    } finally {
      setLoading(false);
    }
  };

  const handleExecuteOperation = async (operation: TimelockOperation) => {
    try {
      setLoading(true);
      const tx = await contract.execute(
        operation.targets,
        operation.values.map((v) => ethers.utils.parseEther(v)),
        operation.calldatas,
        operation.predecessor,
        operation.salt
      );
      await tx.wait();

      toast({
        title: "Operation executed successfully",
        status: "success",
        duration: 5000,
      });

      fetchOperations();
    } catch (error) {
      console.error("Error executing operation:", error);
      toast({
        title: "Error executing operation",
        description: error.message,
        status: "error",
        duration: 5000,
      });
    } finally {
      setLoading(false);
    }
  };

  const handleCancelOperation = async (operationId: string) => {
    try {
      setLoading(true);
      const tx = await contract.cancel(operationId);
      await tx.wait();

      toast({
        title: "Operation canceled successfully",
        status: "success",
        duration: 5000,
      });

      fetchOperations();
    } catch (error) {
      console.error("Error canceling operation:", error);
      toast({
        title: "Error canceling operation",
        description: error.message,
        status: "error",
        duration: 5000,
      });
    } finally {
      setLoading(false);
    }
  };

  const getOperationStatus = (operation: TimelockOperation) => {
    if (operation.canceled) return "Canceled";
    if (operation.executed) return "Executed";

    const now = Math.floor(Date.now() / 1000);
    const readyTime = operation.scheduledAt + operation.delay;

    if (now < readyTime) return "Pending";
    return "Ready";
  };

  const getTimeRemaining = (operation: TimelockOperation) => {
    const now = Math.floor(Date.now() / 1000);
    const readyTime = operation.scheduledAt + operation.delay;
    const remaining = readyTime - now;

    if (remaining <= 0) return "0";

    const hours = Math.floor(remaining / 3600);
    const minutes = Math.floor((remaining % 3600) / 60);
    return `${hours}h ${minutes}m`;
  };

  const getProgressValue = (operation: TimelockOperation) => {
    const now = Math.floor(Date.now() / 1000);
    const elapsed = now - operation.scheduledAt;
    const progress = (elapsed / operation.delay) * 100;
    return Math.min(Math.max(progress, 0), 100);
  };

  return (
    <Box p={6}>
      <VStack spacing={6} align="stretch">
        <HStack justify="space-between">
          <Heading size="lg">Timelock Manager</Heading>
          <Button colorScheme="blue" onClick={onOpen}>
            Schedule Operation
          </Button>
        </HStack>

        <Table variant="simple">
          <Thead>
            <Tr>
              <Th>Operation ID</Th>
              <Th>Status</Th>
              <Th>Progress</Th>
              <Th>Time Remaining</Th>
              <Th>Actions</Th>
            </Tr>
          </Thead>
          <Tbody>
            {operations.map((operation) => {
              const status = getOperationStatus(operation);
              return (
                <Tr key={operation.id}>
                  <Td>
                    <Tooltip label={operation.id}>
                      <Text>{`${operation.id.slice(
                        0,
                        6
                      )}...${operation.id.slice(-4)}`}</Text>
                    </Tooltip>
                  </Td>
                  <Td>
                    <Badge
                      colorScheme={
                        status === "Executed"
                          ? "green"
                          : status === "Ready"
                          ? "yellow"
                          : status === "Canceled"
                          ? "red"
                          : "blue"
                      }
                    >
                      {status}
                    </Badge>
                  </Td>
                  <Td>
                    <Progress
                      value={getProgressValue(operation)}
                      size="sm"
                      colorScheme={status === "Ready" ? "green" : "blue"}
                    />
                  </Td>
                  <Td>{getTimeRemaining(operation)}</Td>
                  <Td>
                    <HStack spacing={2}>
                      {status === "Ready" && (
                        <Button
                          size="sm"
                          colorScheme="green"
                          onClick={() => handleExecuteOperation(operation)}
                          isLoading={loading}
                        >
                          Execute
                        </Button>
                      )}
                      {(status === "Pending" || status === "Ready") && (
                        <Button
                          size="sm"
                          colorScheme="red"
                          onClick={() => handleCancelOperation(operation.id)}
                          isLoading={loading}
                        >
                          Cancel
                        </Button>
                      )}
                    </HStack>
                  </Td>
                </Tr>
              );
            })}
          </Tbody>
        </Table>

        <Modal isOpen={isOpen} onClose={onClose}>
          <ModalOverlay />
          <ModalContent>
            <ModalHeader>Schedule Operation</ModalHeader>
            <ModalCloseButton />
            <ModalBody pb={6}>
              <VStack spacing={4}>
                <FormControl>
                  <FormLabel>Target Address</FormLabel>
                  <Input
                    value={newOperation.targets[0]}
                    onChange={(e) =>
                      setNewOperation({
                        ...newOperation,
                        targets: [e.target.value],
                      })
                    }
                  />
                </FormControl>

                <FormControl>
                  <FormLabel>Value (ETH)</FormLabel>
                  <NumberInput
                    value={newOperation.values[0]}
                    onChange={(value) =>
                      setNewOperation({
                        ...newOperation,
                        values: [value],
                      })
                    }
                  >
                    <NumberInputField />
                  </NumberInput>
                </FormControl>

                <FormControl>
                  <FormLabel>Calldata</FormLabel>
                  <Input
                    value={newOperation.calldatas[0]}
                    onChange={(e) =>
                      setNewOperation({
                        ...newOperation,
                        calldatas: [e.target.value],
                      })
                    }
                  />
                </FormControl>

                <FormControl>
                  <FormLabel>Delay (seconds)</FormLabel>
                  <NumberInput
                    value={newOperation.delay}
                    onChange={(value) =>
                      setNewOperation({
                        ...newOperation,
                        delay: parseInt(value),
                      })
                    }
                  >
                    <NumberInputField />
                  </NumberInput>
                </FormControl>

                <Button
                  colorScheme="blue"
                  width="full"
                  onClick={handleScheduleOperation}
                  isLoading={loading}
                >
                  Schedule Operation
                </Button>
              </VStack>
            </ModalBody>
          </ModalContent>
        </Modal>
      </VStack>
    </Box>
  );
}
