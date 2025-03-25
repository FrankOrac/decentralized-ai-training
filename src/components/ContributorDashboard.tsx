import {
  Box,
  Heading,
  Stack,
  Grid,
  Stat,
  StatLabel,
  StatNumber,
  Button,
  useToast,
  Text,
  Progress,
  Badge,
} from "@chakra-ui/react";
import { useState, useEffect, useRef } from "react";
import { useWeb3 } from "../context/Web3Context";
import { TrainingCoordinator } from "../services/TrainingCoordinator";
import { ethers } from "ethers";

interface ContributorStats {
  tasksCompleted: number;
  totalEarnings: string;
  activeTask: number | null;
  reputation: number;
}

export function ContributorDashboard() {
  const { contract, account } = useWeb3();
  const [stats, setStats] = useState<ContributorStats>({
    tasksCompleted: 0,
    totalEarnings: "0",
    activeTask: null,
    reputation: 0,
  });
  const [trainingProgress, setTrainingProgress] = useState(0);
  const [isTraining, setIsTraining] = useState(false);
  const coordinatorRef = useRef<TrainingCoordinator | null>(null);
  const toast = useToast();

  useEffect(() => {
    if (contract && account) {
      coordinatorRef.current = new TrainingCoordinator(contract, account);
      fetchStats();
    }

    return () => {
      if (coordinatorRef.current) {
        coordinatorRef.current.stop();
      }
    };
  }, [contract, account]);

  const fetchStats = async () => {
    if (!contract || !account) return;

    try {
      const contributorData = await contract.contributors(account);
      setStats({
        tasksCompleted: contributorData.tasksCompleted.toNumber(),
        totalEarnings: ethers.utils.formatEther(contributorData.earnings || 0),
        activeTask: contributorData.activeTask.toNumber() || null,
        reputation: contributorData.reputation.toNumber(),
      });
    } catch (error) {
      console.error("Error fetching stats:", error);
    }
  };

  const handleStartTraining = async (taskId: number) => {
    try {
      setIsTraining(true);
      
      // First register as contributor if not already registered
      const isRegistered = await contract.contributors(account);
      if (!isRegistered.isRegistered) {
        const tx = await contract.registerContributor();
        await tx.wait();
      }

      // Start the task on the contract
      const tx = await contract.startTask(taskId);
      await tx.wait();

      // Start the training process
      await coordinatorRef.current?.startTask(taskId, (progress) => {
        setTrainingProgress(progress);
      });

      toast({
        title: "Training Started",
        description: "AI model training has begun",
        status: "success",
      });
    } catch (error: any) {
      toast({
        title: "Error",
        description: error.message,
        status: "error",
      });
      setIsTraining(false);
    }
  };

  if (!contract || !account) {
    return <Text>Loading dashboard...</Text>;
  }

  return (
    <Box p={6} borderWidth={1} borderRadius="lg" bg="white" shadow="md">
      <Stack spacing={6}>
        <Heading size="lg">Contributor Dashboard</Heading>

        <Grid templateColumns="repeat(4, 1fr)" gap={6}>
          <Stat>
            <StatLabel>Tasks Completed</StatLabel>
            <StatNumber>{stats.tasksCompleted}</StatNumber>
          </Stat>
          <Stat>
            <StatLabel>Total Earnings</StatLabel>
            <StatNumber>{stats.totalEarnings} ETH</StatNumber>
          </Stat>
          <Stat>
            <StatLabel>Reputation Score</StatLabel>
            <StatNumber>{stats.reputation}</StatNumber>
          </Stat>
          <Stat>
            <StatLabel>Status</StatLabel>
            <StatNumber>
              <Badge colorScheme={isTraining ? 'green' : 'gray'}>
                {isTraining ? 'Training' : 'Idle'}
              </Badge>
            </StatNumber>
          </Stat>
        </Grid>

        {isTraining && (
          <Box>
            <Text mb={2}>Training Progress</Text>
            <Progress value={trainingProgress} colorScheme="blue" />
            <Text mt={2} fontSize="sm" color="gray.600">
              {trainingProgress.toFixed(1)}% Complete
            </Text>
          </Box>
        )}

        <Button
          colorScheme="blue"
          onClick={() => handleStartTraining(1)}
          isDisabled={isTraining}
          isLoading={isTraining}
          loadingText="Training in Progress"
        >
          Start New Training Task
        </Button>
      </Stack>
    </Box>
  );
}
