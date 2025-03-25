import {
  Box,
  Button,
  FormControl,
  FormLabel,
  Input,
  Stack,
  useToast,
  NumberInput,
  NumberInputField,
} from "@chakra-ui/react";
import { useState } from "react";
import { useWeb3 } from "../context/Web3Context";
import { ethers } from "ethers";
import { ModelTypeSelector } from './ModelTypeSelector';

export function TaskCreation() {
  const { contract } = useWeb3();
  const toast = useToast();
  const [loading, setLoading] = useState(false);
  const [formData, setFormData] = useState({
    modelHash: "",
    reward: "",
    deadline: "",
  });
  const [selectedModelType, setSelectedModelType] = useState(null);

  const handleSubmit = async (e: React.FormEvent) => {
    e.preventDefault();
    setLoading(true);

    try {
      const rewardInWei = ethers.utils.parseEther(formData.reward);
      const deadlineTimestamp = Math.floor(
        new Date(formData.deadline).getTime() / 1000
      );

      const tx = await contract?.createTask(
        formData.modelHash,
        rewardInWei,
        deadlineTimestamp,
        selectedModelType.id
      );
      await tx.wait();

      toast({
        title: "Task Created",
        description: "Your AI training task has been created successfully",
        status: "success",
        duration: 5000,
      });

      setFormData({ modelHash: "", reward: "", deadline: "" });
    } catch (error: any) {
      toast({
        title: "Error",
        description: error.message || "Failed to create task",
        status: "error",
        duration: 5000,
      });
    } finally {
      setLoading(false);
    }
  };

  return (
    <Box p={6} borderWidth={1} borderRadius="lg" bg="white" shadow="md">
      <form onSubmit={handleSubmit}>
        <Stack spacing={4}>
          <ModelTypeSelector
            onSelect={(modelType) => setSelectedModelType(modelType)}
          />
          <FormControl isRequired>
            <FormLabel>Model Hash (IPFS)</FormLabel>
            <Input
              value={formData.modelHash}
              onChange={(e) =>
                setFormData({ ...formData, modelHash: e.target.value })
              }
              placeholder="QmX..."
            />
          </FormControl>

          <FormControl isRequired>
            <FormLabel>Reward (ETH)</FormLabel>
            <NumberInput min={0}>
              <NumberInputField
                value={formData.reward}
                onChange={(e) =>
                  setFormData({ ...formData, reward: e.target.value })
                }
                placeholder="0.1"
              />
            </NumberInput>
          </FormControl>

          <FormControl isRequired>
            <FormLabel>Deadline</FormLabel>
            <Input
              type="datetime-local"
              value={formData.deadline}
              onChange={(e) =>
                setFormData({ ...formData, deadline: e.target.value })
              }
              min={new Date().toISOString().slice(0, 16)}
            />
          </FormControl>

          <Button
            type="submit"
            colorScheme="blue"
            isLoading={loading}
            loadingText="Creating..."
          >
            Create Task
          </Button>
        </Stack>
      </form>
    </Box>
  );
}
