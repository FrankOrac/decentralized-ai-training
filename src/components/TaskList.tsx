import { Box, SimpleGrid, Text, Heading } from "@chakra-ui/react";
import { useEffect, useState } from "react";
import { useWeb3 } from "../context/Web3Context";
import { TaskCard } from "./TaskCard";
import { Task } from "../types/contracts";

export function TaskList() {
  const { contract } = useWeb3();
  const [tasks, setTasks] = useState<Task[]>([]);
  const [loading, setLoading] = useState(true);

  useEffect(() => {
    if (contract) {
      fetchTasks();
    }
  }, [contract]);

  const fetchTasks = async () => {
    try {
      const taskCount = await contract?.taskCount();
      const fetchedTasks = [];

      for (let i = 1; i <= taskCount.toNumber(); i++) {
        const task = await contract?.tasks(i);
        fetchedTasks.push({
          id: i,
          modelHash: task.modelHash,
          reward: task.reward,
          creator: task.creator,
          status: task.status,
          deadline: task.deadline.toNumber(),
        });
      }

      setTasks(fetchedTasks);
    } catch (error) {
      console.error("Error fetching tasks:", error);
    } finally {
      setLoading(false);
    }
  };

  if (loading) {
    return <Text>Loading tasks...</Text>;
  }

  return (
    <Box py={8}>
      <Heading mb={6}>Available Tasks</Heading>
      <SimpleGrid columns={{ base: 1, md: 2, lg: 3 }} spacing={6}>
        {tasks.map((task) => (
          <TaskCard key={task.id} task={task} onUpdate={fetchTasks} />
        ))}
      </SimpleGrid>
    </Box>
  );
}
