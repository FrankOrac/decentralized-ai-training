import {
  Box,
  Button,
  FormControl,
  FormLabel,
  Input,
  Stack,
  Textarea,
  NumberInput,
  NumberInputField,
  NumberInputStepper,
  NumberIncrementStepper,
  NumberDecrementStepper,
  Table,
  Thead,
  Tbody,
  Tr,
  Th,
  Td,
  Badge,
  useToast,
} from "@chakra-ui/react";
import { useState, useEffect } from "react";
import { useWeb3 } from "../context/Web3Context";

export function ValidationInterface() {
  const { contract, account } = useWeb3();
  const [validations, setValidations] = useState([]);
  const [taskId, setTaskId] = useState("");
  const [score, setScore] = useState(0);
  const [comments, setComments] = useState("");
  const [resultHash, setResultHash] = useState("");
  const toast = useToast();

  useEffect(() => {
    if (contract && taskId) {
      fetchValidations();
    }
  }, [contract, taskId]);

  const fetchValidations = async () => {
    try {
      const taskValidations = await contract.getTaskValidations(taskId);
      setValidations(taskValidations);
    } catch (error) {
      console.error("Error fetching validations:", error);
    }
  };

  const handleSubmitValidation = async () => {
    try {
      const tx = await contract.submitValidation(
        taskId,
        score,
        resultHash,
        comments
      );
      await tx.wait();

      toast({
        title: "Validation Submitted",
        description: "Your validation has been recorded successfully",
        status: "success",
      });

      fetchValidations();
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
        <FormControl>
          <FormLabel>Task ID</FormLabel>
          <Input
            value={taskId}
            onChange={(e) => setTaskId(e.target.value)}
            placeholder="Enter task ID"
          />
        </FormControl>

        <FormControl>
          <FormLabel>Validation Score (0-100)</FormLabel>
          <NumberInput
            value={score}
            onChange={(value) => setScore(parseInt(value))}
            min={0}
            max={100}
          >
            <NumberInputField />
            <NumberInputStepper>
              <NumberIncrementStepper />
              <NumberDecrementStepper />
            </NumberInputStepper>
          </NumberInput>
        </FormControl>

        <FormControl>
          <FormLabel>Result Hash</FormLabel>
          <Input
            value={resultHash}
            onChange={(e) => setResultHash(e.target.value)}
            placeholder="Enter IPFS hash of validation results"
          />
        </FormControl>

        <FormControl>
          <FormLabel>Comments</FormLabel>
          <Textarea
            value={comments}
            onChange={(e) => setComments(e.target.value)}
            placeholder="Enter validation comments"
          />
        </FormControl>

        <Button colorScheme="blue" onClick={handleSubmitValidation}>
          Submit Validation
        </Button>

        {validations.length > 0 && (
          <Table variant="simple">
            <Thead>
              <Tr>
                <Th>Validator</Th>
                <Th>Score</Th>
                <Th>Status</Th>
                <Th>Timestamp</Th>
              </Tr>
            </Thead>
            <Tbody>
              {validations.map((validation: any, index: number) => (
                <Tr key={index}>
                  <Td>{validation.validator}</Td>
                  <Td>{validation.score.toString()}</Td>
                  <Td>
                    <Badge
                      colorScheme={validation.isApproved ? "green" : "red"}
                    >
                      {validation.isApproved ? "Approved" : "Rejected"}
                    </Badge>
                  </Td>
                  <Td>
                    {new Date(validation.timestamp * 1000).toLocaleString()}
                  </Td>
                </Tr>
              ))}
            </Tbody>
          </Table>
        )}
      </Stack>
    </Box>
  );
}
