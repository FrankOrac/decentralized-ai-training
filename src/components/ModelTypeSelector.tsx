import {
  Box,
  Select,
  FormControl,
  FormLabel,
  Stack,
  Text,
  Badge,
} from "@chakra-ui/react";
import { useState, useEffect } from "react";
import { useWeb3 } from "../context/Web3Context";

interface ModelType {
  id: number;
  name: string;
  description: string;
  baseComputeScore: number;
  minReputation: number;
  isActive: boolean;
}

export function ModelTypeSelector({
  onSelect,
}: {
  onSelect: (modelType: ModelType) => void;
}) {
  const { contract } = useWeb3();
  const [modelTypes, setModelTypes] = useState<ModelType[]>([]);
  const [selectedType, setSelectedType] = useState<ModelType | null>(null);

  useEffect(() => {
    if (contract) {
      fetchModelTypes();
    }
  }, [contract]);

  const fetchModelTypes = async () => {
    try {
      const count = await contract.modelTypeCount();
      const types = [];

      for (let i = 1; i <= count; i++) {
        const modelType = await contract.modelTypes(i);
        types.push({
          id: i,
          name: modelType.name,
          description: modelType.description,
          baseComputeScore: modelType.baseComputeScore.toNumber(),
          minReputation: modelType.minReputation.toNumber(),
          isActive: modelType.isActive,
        });
      }

      setModelTypes(types);
    } catch (error) {
      console.error("Error fetching model types:", error);
    }
  };

  const handleSelect = (typeId: string) => {
    const selected = modelTypes.find((t) => t.id === parseInt(typeId));
    if (selected) {
      setSelectedType(selected);
      onSelect(selected);
    }
  };

  return (
    <Stack spacing={4}>
      <FormControl>
        <FormLabel>Model Type</FormLabel>
        <Select
          placeholder="Select model type"
          onChange={(e) => handleSelect(e.target.value)}
        >
          {modelTypes.map((type) => (
            <option key={type.id} value={type.id}>
              {type.name}
            </option>
          ))}
        </Select>
      </FormControl>

      {selectedType && (
        <Box p={4} borderWidth={1} borderRadius="md">
          <Stack spacing={2}>
            <Text fontWeight="bold">{selectedType.name}</Text>
            <Text fontSize="sm">{selectedType.description}</Text>
            <Stack direction="row" spacing={2}>
              <Badge colorScheme="blue">
                Base Score: {selectedType.baseComputeScore}
              </Badge>
              <Badge colorScheme="green">
                Min Reputation: {selectedType.minReputation}
              </Badge>
            </Stack>
          </Stack>
        </Box>
      )}
    </Stack>
  );
}
