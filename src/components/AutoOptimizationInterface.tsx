import {
  Box,
  Button,
  FormControl,
  FormLabel,
  Input,
  Stack,
  NumberInput,
  NumberInputField,
  NumberInputStepper,
  NumberIncrementStepper,
  NumberDecrementStepper,
  Progress,
  Text,
  Table,
  Thead,
  Tbody,
  Tr,
  Th,
  Td,
  useToast,
} from "@chakra-ui/react";
import { useState, useEffect } from "react";
import { useWeb3 } from "../context/Web3Context";

export function AutoOptimizationInterface() {
  const { contract } = useWeb3();
  const [tasks, setTasks] = useState([]);
  const [newTask, setNewTask] = useState({
    modelHash: "",
    hyperparameters: "",
    targetMetric: 0,
    maxIterations: 10,
  });
  const toast = useToast();

  useEffect(() => {
    if (contract) {
      fetchTasks();
    }
  }, [contract]);

  const fetchTasks = async () => {
    try {
      const taskCount = await contract.taskCount();
      const fetchedTasks = [];

      for (let i = 1; i <= taskCount; i++) {
        const task = await contract.tasks(i);
        fetchedTasks.push({
          id: i,
          ...task,
          progress: (task.iterationsCompleted / task.maxIterations) * 100,
        });
      }

      setTasks(fetchedTasks);
    } catch (error) {
      console.error("Error fetching tasks:", error);
    }
  };

  const handleCreateTask = async () => {
    try {
      const tx = await contract.createOptimizationTask(
        newTask.modelHash,
        newTask.hyperparameters,
        newTask.targetMetric,
        newTask.maxIterations
      );
      await tx.wait();

      toast({
        title: "Optimization Task Created",
        description: "Your model optimization task has started",
        status: "success",
      });

      fetchTasks();
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
        <Box>
          <Stack spacing={4}>
            <FormControl>
              <FormLabel>Model Hash</FormLabel>
              <Input
                value={newTask.modelHash}
                onChange={(e) =>
                  setNewTask({
                    ...newTask,
                    modelHash: e.target.value,
                  })
                }
              />
            </FormControl>

            <FormControl>
              <FormLabel>Hyperparameters</FormLabel>
              <Input
                value={newTask.hyperparameters}
                onChange={(e) =>
                  setNewTask({
                    ...newTask,
                    hyperparameters: e.target.value,
                  })
                }
              />
            </FormControl>

            <FormControl>
              <FormLabel>Target Metric</FormLabel>
              <NumberInput
                value={newTask.targetMetric}
                onChange={(value) =>
                  setNewTask({
                    ...newTask,
                    targetMetric: parseInt(value),
                  })
                }
              >
                <NumberInputField />
                <NumberInputStepper>
                  <NumberIncrementStepper />
                  <NumberDecrementStepper />
                </NumberInputStepper>
              </NumberInput>
            </FormControl>

            <FormControl>
              <FormLabel>Max Iterations</FormLabel>
              <NumberInput
                value={newTask.maxIterations}
                onChange={(value) =>
                  setNewTask({
                    ...newTask,
                    maxIterations: parseInt(value),
                  })
                }
              >
                <NumberInputField />
                <NumberInputStepper>
                  <NumberIncrementStepper />
                  <NumberDecrementStepper />
                </NumberInputStepper>
              </NumberInput>
            </FormControl>

            <Button colorScheme="blue" onClick={handleCreateTask}>
              Create Optimization Task
            </Button>
          </Stack>
        </Box>

        <Table variant="simple">
          <Thead>
            <Tr>
              <Th>ID</Th>
              <Th>Model</Th>
              <Th>Progress</Th>
              <Th>Best Metric</Th>
              <Th>Status</Th>
            </Tr>
          </Thead>
          <Tbody>
            {tasks.map((task: any) => (
              <Tr key={task.id}>
                <Td>{task.id}</Td>
                <Td>{task.modelHash}</Td>
                <Td>
                  <Progress
                    value={task.progress}
                    size="sm"
                    colorScheme="blue"
                  />
                </Td>
                <Td>{task.currentBestMetric.toString()}</Td>
                <Td>
                  {["Pending", "Running", "Completed", "Failed"][task.status]}
                </Td>
              </Tr>
            ))}
          </Tbody>
        </Table>
      </Stack>
    </Box>
  );
}
