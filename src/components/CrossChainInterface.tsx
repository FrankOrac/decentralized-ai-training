import {
  Box,
  Button,
  FormControl,
  FormLabel,
  Input,
  Stack,
  Select,
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
import { ethers } from "ethers";

const SUPPORTED_CHAINS = {
  1: "Ethereum",
  137: "Polygon",
  43114: "Avalanche",
  56: "BSC",
};

export function CrossChainInterface() {
  const { contract, account } = useWeb3();
  const [models, setModels] = useState([]);
  const [newShare, setNewShare] = useState({
    modelHash: "",
    targetChain: "",
  });
  const toast = useToast();

  useEffect(() => {
    if (contract) {
      fetchModels();
    }
  }, [contract]);

  const fetchModels = async () => {
    try {
      const modelCount = await contract.modelCount();
      const fetchedModels = [];

      for (let i = 1; i <= modelCount; i++) {
        const model = await contract.getModel(i);
        fetchedModels.push({
          id: i,
          ...model,
        });
      }

      setModels(fetchedModels);
    } catch (error) {
      console.error("Error fetching models:", error);
    }
  };

  const handleShareModel = async () => {
    try {
      const tx = await contract.shareModel(
        newShare.modelHash,
        parseInt(newShare.targetChain),
        {
          value: ethers.utils.parseEther("0.1"), // Example fee
        }
      );
      await tx.wait();

      toast({
        title: "Model Shared",
        description: "Your model has been shared across chains successfully",
        status: "success",
      });

      fetchModels();
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
        <Stack spacing={4}>
          <FormControl>
            <FormLabel>Model Hash</FormLabel>
            <Input
              value={newShare.modelHash}
              onChange={(e) =>
                setNewShare({
                  ...newShare,
                  modelHash: e.target.value,
                })
              }
              placeholder="Enter IPFS hash of the model"
            />
          </FormControl>

          <FormControl>
            <FormLabel>Target Chain</FormLabel>
            <Select
              value={newShare.targetChain}
              onChange={(e) =>
                setNewShare({
                  ...newShare,
                  targetChain: e.target.value,
                })
              }
            >
              <option value="">Select chain</option>
              {Object.entries(SUPPORTED_CHAINS).map(([id, name]) => (
                <option key={id} value={id}>
                  {name}
                </option>
              ))}
            </Select>
          </FormControl>

          <Button colorScheme="blue" onClick={handleShareModel}>
            Share Model
          </Button>
        </Stack>

        <Table variant="simple">
          <Thead>
            <Tr>
              <Th>ID</Th>
              <Th>Model Hash</Th>
              <Th>Source Chain</Th>
              <Th>Creator</Th>
              <Th>Status</Th>
            </Tr>
          </Thead>
          <Tbody>
            {models.map((model: any) => (
              <Tr key={model.id}>
                <Td>{model.id}</Td>
                <Td>{model.modelHash}</Td>
                <Td>
                  {SUPPORTED_CHAINS[model.sourceChainId] || model.sourceChainId}
                </Td>
                <Td>{`${model.creator.slice(0, 6)}...${model.creator.slice(
                  -4
                )}`}</Td>
                <Td>
                  <Badge colorScheme={model.isVerified ? "green" : "yellow"}>
                    {model.isVerified ? "Verified" : "Pending"}
                  </Badge>
                </Td>
              </Tr>
            ))}
          </Tbody>
        </Table>
      </Stack>
    </Box>
  );
}
