import {
  Box,
  Button,
  Text,
  Stack,
  Badge,
  Flex,
  useToast,
} from "@chakra-ui/react";
import { ethers } from "ethers";
import { useWeb3 } from "../context/Web3Context";
import { Task } from "../types/contracts";

interface TaskCardProps {
  task: Task;
  onUpdate: () => void;
}

export function TaskCard({ task, onUpdate }: TaskCardProps) {
  const { contract, account } = useWeb3();
  const toast = useToast();

  const getStatusColor = (status: number) => {
    switch (status) {
      case 0:
        return "green";
      case 1:
        return "yellow";
      case 2:
        return "blue";
      case 3:
        return "red";
      default:
        return "gray";
    }
  };

  const getStatusText = (status: number) => {
    switch (status) {
      case 0:
        return "Open";
      case 1:
        return "In Progress";
      case 2:
        return "Completed";
      case 3:
        return "Failed";
      default:
        return "Unknown";
    }
  };

  const formatDeadline = (timestamp: number) => {
    return new Date(timestamp * 1000).toLocaleString();
  };

  const handleContribute = async () => {
    try {
      // Implementation will come later with the contributor logic
      toast({
        title: "Coming Soon",
        description: "Contribution feature is under development",
        status: "info",
      });
    } catch (error: any) {
      toast({
        title: "Error",
        description: error.message,
        status: "error",
      });
    }
  };

  return (
    <Box p={5} borderWidth={1} borderRadius="lg" bg="white" shadow="md">
      <Stack spacing={4}>
        <Flex justify="space-between" align="center">
          <Text fontWeight="bold">Task #{task.id}</Text>
          <Badge colorScheme={getStatusColor(task.status)}>
            {getStatusText(task.status)}
          </Badge>
        </Flex>

        <Text noOfLines={1}>Model: {task.modelHash}</Text>
        <Text>Reward: {ethers.utils.formatEther(task.reward)} ETH</Text>
        <Text>Deadline: {formatDeadline(task.deadline)}</Text>

        {task.status === 0 && task.creator !== account && (
          <Button colorScheme="blue" onClick={handleContribute}>
            Contribute
          </Button>
        )}
      </Stack>
    </Box>
  );
}
