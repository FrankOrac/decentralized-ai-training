import {
  Box,
  Grid,
  Heading,
  Stack,
  Text,
  Button,
  Input,
  useToast,
  Modal,
  ModalOverlay,
  ModalContent,
  ModalHeader,
  ModalBody,
  ModalCloseButton,
  useDisclosure,
  FormControl,
  FormLabel,
} from "@chakra-ui/react";
import { useState, useEffect } from "react";
import { useWeb3 } from "../context/Web3Context";
import { ethers } from "ethers";

interface MarketplaceTask {
  id: number;
  modelHash: string;
  totalReward: string;
  minContributors: number;
  maxContributors: number;
  currentContributors: number;
  highestBid: string;
  bidEndTime: number;
  status: number;
}

export function TaskMarketplace() {
  const { contract, account } = useWeb3();
  const [tasks, setTasks] = useState<MarketplaceTask[]>([]);
  const [selectedTask, setSelectedTask] = useState<MarketplaceTask | null>(
    null
  );
  const [bidAmount, setBidAmount] = useState("");
  const { isOpen, onOpen, onClose } = useDisclosure();
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
        const task = await contract.distributedTasks(i);
        if (task.status === 0) {
          // Open tasks only
          fetchedTasks.push({
            id: i,
            modelHash: task.modelHash,
            totalReward: ethers.utils.formatEther(task.totalReward),
            minContributors: task.minContributors.toNumber(),
            maxContributors: task.maxContributors.toNumber(),
            currentContributors: task.currentContributors.toNumber(),
            highestBid: ethers.utils.formatEther(task.highestBid),
            bidEndTime: task.bidEndTime.toNumber(),
            status: task.status,
          });
        }
      }

      setTasks(fetchedTasks);
    } catch (error) {
      console.error("Error fetching tasks:", error);
    }
  };

  const handleBid = async () => {
    if (!selectedTask) return;

    try {
      const bidInWei = ethers.utils.parseEther(bidAmount);
      const tx = await contract.placeBid(selectedTask.id, bidInWei);
      await tx.wait();

      toast({
        title: "Bid Placed",
        description: `Successfully bid ${bidAmount} ETH on task #${selectedTask.id}`,
        status: "success",
      });

      onClose();
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
        <Heading size="lg">Task Marketplace</Heading>

        <Grid templateColumns="repeat(auto-fill, minmax(300px, 1fr))" gap={6}>
          {tasks.map((task) => (
            <Box
              key={task.id}
              p={5}
              borderWidth={1}
              borderRadius="lg"
              bg="white"
              shadow="md"
            >
              <Stack spacing={4}>
                <Heading size="md">Task #{task.id}</Heading>
                <Text>Reward: {task.totalReward} ETH</Text>
                <Text>
                  Contributors: {task.currentContributors}/
                  {task.maxContributors}
                </Text>
                <Text>Current Highest Bid: {task.highestBid} ETH</Text>
                <Text>
                  Bid Ends: {new Date(task.bidEndTime * 1000).toLocaleString()}
                </Text>

                <Button
                  colorScheme="blue"
                  onClick={() => {
                    setSelectedTask(task);
                    onOpen();
                  }}
                >
                  Place Bid
                </Button>
              </Stack>
            </Box>
          ))}
        </Grid>

        <Modal isOpen={isOpen} onClose={onClose}>
          <ModalOverlay />
          <ModalContent>
            <ModalHeader>Place Bid</ModalHeader>
            <ModalCloseButton />
            <ModalBody pb={6}>
              <FormControl>
                <FormLabel>Bid Amount (ETH)</FormLabel>
                <Input
                  type="number"
                  value={bidAmount}
                  onChange={(e) => setBidAmount(e.target.value)}
                  placeholder="0.0"
                  step="0.01"
                />
              </FormControl>

              <Button colorScheme="blue" mr={3} mt={4} onClick={handleBid}>
                Submit Bid
              </Button>
            </ModalBody>
          </ModalContent>
        </Modal>
      </Stack>
    </Box>
  );
}
