import React, { useState } from "react";
import {
  Box,
  Button,
  VStack,
  FormControl,
  FormLabel,
  Input,
  Textarea,
  Alert,
  AlertIcon,
  Code,
  Heading,
  Text,
  useToast,
  Spinner,
  Table,
  Tbody,
  Tr,
  Td,
  Modal,
  ModalOverlay,
  ModalContent,
  ModalHeader,
  ModalBody,
  ModalCloseButton,
  useDisclosure,
  NumberInput,
  NumberInputField,
  Select,
  Badge,
} from "@chakra-ui/react";
import { ethers } from "ethers";
import { useWeb3 } from "../hooks/useWeb3";

interface SimulationConfig {
  blockNumber: number;
  timestamp: number;
  sender: string;
  value: string;
  revertOnFailure: boolean;
}

interface SimulationResult {
  id: string;
  success: boolean;
  gasUsed: number;
  error: string;
  impactedContracts: string[];
  stateDiffs: Record<string, string>;
}

export function ProposalSimulator() {
  const { contract } = useWeb3();
  const toast = useToast();
  const { isOpen, onOpen, onClose } = useDisclosure();

  const [loading, setLoading] = useState(false);
  const [proposal, setProposal] = useState({
    targets: [""],
    values: ["0"],
    calldatas: ["0x"],
  });
  const [config, setConfig] = useState<SimulationConfig>({
    blockNumber: 0,
    timestamp: Math.floor(Date.now() / 1000),
    sender: "",
    value: "0",
    revertOnFailure: true,
  });
  const [simulationResult, setSimulationResult] = useState<SimulationResult | null>(null);

  const handleSimulation = async () => {
    try {
      setLoading(true);

      const tx = await contract.simulateProposal(
        proposal.targets,
        proposal.values.map((v) => ethers.utils.parseEther(v)),
        proposal.calldatas,
        config
      );
      const receipt = await tx.wait();

      const simulationId = receipt.events?.find(
        (e) => e.event === "SimulationStarted"
      )?.args?.simulationId;

      const result = await contract.getSimulationResult(simulationId);

      // Fetch state diffs for each impacted contract
      const stateDiffs: Record<string, string> = {};
      for (const contractAddr of result.impactedContracts) {
        const diff = await contract.getStateDiff(simulationId, contractAddr);
        stateDiffs[contractAddr] = diff;
      }

      setSimulationResult({
        id: simulationId,
        success: result.success,
        gasUsed: result.gasUsed.toNumber(),
        error: result.error,
        impactedContracts: result.impactedContracts,
        stateDiffs,
      });

      toast({
        title: "Simulation completed",
        status: result.success ? "success" : "warning",
        duration: 5000,
      });
    } catch (error) {
      console.error("Simulation error:", error);
      toast({
        title: "Simulation failed",
        description: error.message,
        status: "error",
        duration: 5000,
      });
    } finally {
      setLoading(false);
    }
  };

  const addAction = () => {
    setProposal((prev) => ({
      targets: [...prev.targets, ""],
      values: [...prev.values, "0"],
      calldatas: [...prev.calldatas, "0x"],
    }));
  };

  const removeAction = (index: number) => {
    setProposal((prev) => ({
      targets: prev.targets.filter((_, i) => i !== index),
      values: prev.values.filter((_, i) => i !== index),
      calldatas: prev.calldatas.filter((_, i) => i !== index),
    }));
  };

  return (
    <Box p={6}>
      <VStack spacing={6} align="stretch">
        <Heading size="lg">Proposal Simulator</Heading>

        {proposal.targets.map((_, index) => (
          <Box key={index} p={4} borderWidth={1} borderRadius="lg">
            <VStack spacing={4}>
              <FormControl>
                <FormLabel>Target Contract {index + 1}</FormLabel>
                <Input
                  value={proposal.targets[index]}
                  onChange={(e) => {
                    const newTargets = [...proposal.targets];
                    newTargets[index] = e.target.value;
                    setProposal((prev) => ({ ...prev, targets: newTargets }));
                  }}
                />
              </FormControl>

              <FormControl>
                <FormLabel>Value (ETH) {index + 1}</FormLabel>
                <NumberInput
                  value={proposal.values[index]}
                  onChange={(value) => {
                    const newValues = [...proposal.values];
                    newValues[index] = value;
                    setProposal((prev) => ({ ...prev, values: newValues }));
                  }}
                >
                  <NumberInputField />
                </NumberInput>
              </FormControl>

              <FormControl>
                <FormLabel>Calldata {index + 1}</FormLabel>
                <Input
                  value={proposal.calldatas[index]}
                  onChange={(e) => {
                    const newCalldatas = [...proposal.calldatas];
                    newCalldatas[index] = e.target.value;
                    setProposal((prev) => ({
                      ...prev,
                      calldatas: newCalldatas,
                    }));
                  }}
                />
              </FormControl>

              {index > 0 && (
                <Button colorScheme="red" onClick={() => removeAction(index)}>
                  Remove Action
                </Button>
              )}
            </VStack>
          </Box>
        ))}

        <Button onClick={addAction}>Add Action</Button>

        <Button
          colorScheme="blue"
          onClick={handleSimulation}
          isLoading={loading}
        >
          Run Simulation
        </Button>

        {simulationResult && (
          <Box borderWidth={1} borderRadius="lg" p={4}>
            <VStack spacing={4} align="stretch">
              <HStack justify="space-between">
                <Heading size="md">Simulation Results</Heading>
                <Badge
                  colorScheme={simulationResult.success ? "green" : "red"}
                  fontSize="md"
                >
                  {simulationResult.success ? "Success" : "Failed"}
                </Badge>
              </HStack>

              <Text>
                Gas Used: {simulationResult.gasUsed.toLocaleString()} units
              </Text>

              {simulationResult.error && (
                <Alert status="error">
                  <AlertIcon />
                  {simulationResult.error}
                </Alert>
              )}

              <Box>
                <Heading size="sm" mb={2}>Impacted Contracts</Heading>
                <Table variant="simple">
                  <Thead>
                    <Tr>
                      <Th>Contract</Th>
                      <Th>State Changes</Th>
                    </Tr>
                  </Thead>
                  <Tbody>
                    {simulationResult.impactedContracts.map((contract) => (
                      <Tr key={contract}>
                        <Td>{contract}</Td>
                        <Td>
                          <Code>{simulationResult.stateDiffs[contract]}</Code>
                        </Td>
                      </Tr>
                    ))}
                  </Tbody>
                </Table>
              </Box>
            </VStack>
          </Box>
        )}

        <Modal isOpen={isOpen} onClose={onClose}>
          <ModalOverlay />
          <ModalContent>
            <ModalHeader>Simulation Configuration</ModalHeader>
            <ModalCloseButton />
            <ModalBody pb={6}>
              <VStack spacing={4}>
                <FormControl>
                  <FormLabel>Block Number</FormLabel>
                  <NumberInput
                    value={config.blockNumber}
                    onChange={(value) => setConfig({
                      ...config,
                      blockNumber: parseInt(value)
                    })}
                  >
                    <NumberInputField />
                  </NumberInput>
                </FormControl>

                <FormControl>
                  <FormLabel>Timestamp</FormLabel>
                  <NumberInput
                    value={config.timestamp}
                    onChange={(value) => setConfig({
                      ...config,
                      timestamp: parseInt(value)
                    })}
                  >
                    <NumberInputField />
                  </NumberInput>
                </FormControl>

                <FormControl>
                  <FormLabel>Sender Address</FormLabel>
                  <Input
                    value={config.sender}
                    onChange={(e) => setConfig({
                      ...config,
                      sender: e.target.value
                    })}
                  />
                </FormControl>

                <FormControl>
                  <FormLabel>Value (ETH)</FormLabel>
                  <NumberInput
                    value={config.value}
                    onChange={(value) => setConfig({
                      ...config,
                      value: value
                    })}
                  >
                    <NumberInputField />
                  </NumberInput>
                </FormControl>

                <FormControl>
                  <FormLabel>Revert on Failure</FormLabel>
                  <Select
                    value={config.revertOnFailure ? "true" : "false"}
                    onChange={(e) => setConfig({
                      ...config,
                      revertOnFailure: e.target.value === "true"
                    })}
                  >
                    <option value="true">Yes</option>
                    <option value="false">No</option>
                  </Select>
                </FormControl>
              </VStack>
            </ModalBody>
          </ModalContent>
        </Modal>
      </VStack>
    </Box>
  );
}
