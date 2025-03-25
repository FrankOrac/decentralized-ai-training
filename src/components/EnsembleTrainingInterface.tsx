import {
  Box,
  Button,
  FormControl,
  FormLabel,
  Input,
  Stack,
  NumberInput,
  NumberInputField,
  Select,
  Table,
  Thead,
  Tbody,
  Tr,
  Th,
  Td,
  Badge,
  useToast,
  Modal,
  ModalOverlay,
  ModalContent,
  ModalHeader,
  ModalBody,
  ModalCloseButton,
  useDisclosure,
} from "@chakra-ui/react";
import { useState, useEffect } from "react";
import { useWeb3 } from "../context/Web3Context";

export function EnsembleTrainingInterface() {
  const { contract } = useWeb3();
  const [ensembles, setEnsembles] = useState([]);
  const { isOpen, onOpen, onClose } = useDisclosure();
  const toast = useToast();

  const [newEnsemble, setNewEnsemble] = useState({
    baseModels: [""],
    weights: [""],
    strategy: "weighted_average",
    threshold: 80,
  });

  useEffect(() => {
    if (contract) {
      fetchEnsembles();
    }
  }, [contract]);

  const fetchEnsembles = async () => {
    try {
      const count = await contract.ensembleCount();
      const fetchedEnsembles = [];

      for (let i = 1; i <= count; i++) {
        const ensemble = await contract.getEnsembleDetails(i);
        fetchedEnsembles.push({
          id: i,
          ...ensemble,
        });
      }

      setEnsembles(fetchedEnsembles);
    } catch (error) {
      console.error("Error fetching ensembles:", error);
    }
  };

  const addModelInput = () => {
    setNewEnsemble({
      ...newEnsemble,
      baseModels: [...newEnsemble.baseModels, ""],
      weights: [...newEnsemble.weights, ""],
    });
  };

  const handleCreateEnsemble = async () => {
    try {
      const tx = await contract.createEnsemble(
        newEnsemble.baseModels,
        newEnsemble.weights,
        newEnsemble.strategy,
        newEnsemble.threshold
      );
      await tx.wait();

      toast({
        title: "Ensemble Created",
        description: "Your ensemble training task has been created",
        status: "success",
      });

      onClose();
      fetchEnsembles();
    } catch (error: any) {
      toast({
        title: "Error",
        description: error.message,
        status: "error",
      });
    }
  };

  const handleValidate = async (ensembleId: number, approved: boolean) => {
    try {
      const tx = await contract.submitValidation(
        ensembleId,
        approved,
        85, // Example performance score
        approved ? "Good performance" : "Needs improvement"
      );
      await tx.wait();

      toast({
        title: "Validation Submitted",
        description: "Your validation has been recorded",
        status: "success",
      });

      fetchEnsembles();
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
        <Button colorScheme="blue" onClick={onOpen}>
          Create Ensemble
        </Button>

        <Table variant="simple">
          <Thead>
            <Tr>
              <Th>ID</Th>
              <Th>Models</Th>
              <Th>Strategy</Th>
              <Th>Status</Th>
              <Th>Validations</Th>
              <Th>Actions</Th>
            </Tr>
          </Thead>
          <Tbody>
            {ensembles.map((ensemble: any) => (
              <Tr key={ensemble.id}>
                <Td>{ensemble.id}</Td>
                <Td>{ensemble.baseModels.length}</Td>
                <Td>{ensemble.strategy}</Td>
                <Td>
                  <Badge
                    colorScheme={
                      ensemble.status === 3
                        ? "green"
                        : ensemble.status === 4
                        ? "red"
                        : "yellow"
                    }
                  >
                    {
                      [
                        "Created",
                        "Training",
                        "Validating",
                        "Completed",
                        "Failed",
                      ][ensemble.status]
                    }
                  </Badge>
                </Td>
                <Td>{ensemble.validationCount.toString()}</Td>
                <Td>
                  {ensemble.status === 2 && (
                    <Stack direction="row" spacing={2}>
                      <Button
                        size="sm"
                        colorScheme="green"
                        onClick={() => handleValidate(ensemble.id, true)}
                      >
                        Approve
                      </Button>
                      <Button
                        size="sm"
                        colorScheme="red"
                        onClick={() => handleValidate(ensemble.id, false)}
                      >
                        Reject
                      </Button>
                    </Stack>
                  )}
                </Td>
              </Tr>
            ))}
          </Tbody>
        </Table>

        <Modal isOpen={isOpen} onClose={onClose}>
          <ModalOverlay />
          <ModalContent>
            <ModalHeader>Create Ensemble</ModalHeader>
            <ModalCloseButton />
            <ModalBody>
              <Stack spacing={4}>
                {newEnsemble.baseModels.map((_, index) => (
                  <Stack key={index} direction="row" spacing={2}>
                    <FormControl>
                      <FormLabel>Model Hash {index + 1}</FormLabel>
                      <Input
                        value={newEnsemble.baseModels[index]}
                        onChange={(e) => {
                          const updated = [...newEnsemble.baseModels];
                          updated[index] = e.target.value;
                          setNewEnsemble({
                            ...newEnsemble,
                            baseModels: updated,
                          });
                        }}
                      />
                    </FormControl>
                    <FormControl>
                      <FormLabel>Weight {index + 1}</FormLabel>
                      <Input
                        value={newEnsemble.weights[index]}
                        onChange={(e) => {
                          const updated = [...newEnsemble.weights];
                          updated[index] = e.target.value;
                          setNewEnsemble({
                            ...newEnsemble,
                            weights: updated,
                          });
                        }}
                      />
                    </FormControl>
                  </Stack>
                ))}

                <Button size="sm" onClick={addModelInput}>
                  Add Model
                </Button>

                <FormControl>
                  <FormLabel>Aggregation Strategy</FormLabel>
                  <Select
                    value={newEnsemble.strategy}
                    onChange={(e) =>
                      setNewEnsemble({
                        ...newEnsemble,
                        strategy: e.target.value,
                      })
                    }
                  >
                    <option value="weighted_average">Weighted Average</option>
                    <option value="majority_voting">Majority Voting</option>
                    <option value="stacking">Stacking</option>
                  </Select>
                </FormControl>

                <FormControl>
                  <FormLabel>Performance Threshold</FormLabel>
                  <NumberInput
                    value={newEnsemble.threshold}
                    onChange={(value) =>
                      setNewEnsemble({
                        ...newEnsemble,
                        threshold: parseInt(value),
                      })
                    }
                    min={0}
                    max={100}
                  >
                    <NumberInputField />
                  </NumberInput>
                </FormControl>

                <Button colorScheme="blue" onClick={handleCreateEnsemble}>
                  Create Ensemble
                </Button>
              </Stack>
            </ModalBody>
          </ModalContent>
        </Modal>
      </Stack>
    </Box>
  );
}
