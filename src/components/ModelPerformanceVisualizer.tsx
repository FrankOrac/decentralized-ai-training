import React, { useEffect, useState } from "react";
import {
  Box,
  Select,
  Stack,
  Heading,
  Grid,
  Text,
  Spinner,
  Button,
  useToast,
} from "@chakra-ui/react";
import {
  LineChart,
  Line,
  XAxis,
  YAxis,
  CartesianGrid,
  Tooltip,
  Legend,
  ResponsiveContainer,
  BarChart,
  Bar,
} from "recharts";
import { useWeb3 } from "../context/Web3Context";

export function ModelPerformanceVisualizer() {
  const { contract } = useWeb3();
  const [selectedModel, setSelectedModel] = useState("");
  const [models, setModels] = useState([]);
  const [metrics, setMetrics] = useState({
    accuracy: [],
    latency: [],
    resourceUsage: [],
    convergence: [],
  });
  const [isLoading, setIsLoading] = useState(false);
  const toast = useToast();

  useEffect(() => {
    fetchModels();
  }, [contract]);

  useEffect(() => {
    if (selectedModel) {
      fetchMetrics();
    }
  }, [selectedModel]);

  const fetchModels = async () => {
    try {
      const modelCount = await contract.getModelCount();
      const modelList = [];

      for (let i = 0; i < modelCount; i++) {
        const model = await contract.getModelDetails(i);
        modelList.push({
          id: i,
          hash: model.modelHash,
          name: model.name,
        });
      }

      setModels(modelList);
    } catch (error) {
      console.error("Error fetching models:", error);
      toast({
        title: "Error",
        description: "Failed to fetch models",
        status: "error",
      });
    }
  };

  const fetchMetrics = async () => {
    setIsLoading(true);
    try {
      const [accuracy, latency, resourceUsage, convergence] = await Promise.all(
        [
          contract.getMetricHistory(selectedModel, "accuracy"),
          contract.getMetricHistory(selectedModel, "latency"),
          contract.getMetricHistory(selectedModel, "resourceUsage"),
          contract.getMetricHistory(selectedModel, "convergence"),
        ]
      );

      setMetrics({
        accuracy: formatMetricData(accuracy),
        latency: formatMetricData(latency),
        resourceUsage: formatMetricData(resourceUsage),
        convergence: formatMetricData(convergence),
      });
    } catch (error) {
      console.error("Error fetching metrics:", error);
      toast({
        title: "Error",
        description: "Failed to fetch metrics",
        status: "error",
      });
    } finally {
      setIsLoading(false);
    }
  };

  const formatMetricData = (data) => {
    return data.map((point, index) => ({
      timestamp: new Date(point.timestamp * 1000).toLocaleString(),
      value: parseFloat(point.value),
      iteration: index + 1,
    }));
  };

  const refreshData = () => {
    if (selectedModel) {
      fetchMetrics();
    }
  };

  return (
    <Box p={6}>
      <Stack spacing={6}>
        <Heading size="lg">Model Performance Visualization</Heading>

        <Stack direction="row" spacing={4} align="center">
          <Select
            placeholder="Select Model"
            value={selectedModel}
            onChange={(e) => setSelectedModel(e.target.value)}
            maxW="300px"
          >
            {models.map((model) => (
              <option key={model.id} value={model.hash}>
                {model.name}
              </option>
            ))}
          </Select>

          <Button
            colorScheme="blue"
            onClick={refreshData}
            isDisabled={!selectedModel}
          >
            Refresh Data
          </Button>
        </Stack>

        {isLoading ? (
          <Box textAlign="center" py={10}>
            <Spinner size="xl" />
          </Box>
        ) : selectedModel ? (
          <Grid templateColumns="repeat(2, 1fr)" gap={6}>
            {/* Accuracy Chart */}
            <Box p={4} borderWidth={1} borderRadius="lg">
              <Text fontSize="lg" mb={4}>
                Accuracy Over Time
              </Text>
              <ResponsiveContainer width="100%" height={300}>
                <LineChart data={metrics.accuracy}>
                  <CartesianGrid strokeDasharray="3 3" />
                  <XAxis dataKey="iteration" />
                  <YAxis domain={[0, 100]} />
                  <Tooltip />
                  <Legend />
                  <Line
                    type="monotone"
                    dataKey="value"
                    stroke="#3182ce"
                    name="Accuracy %"
                  />
                </LineChart>
              </ResponsiveContainer>
            </Box>

            {/* Latency Chart */}
            <Box p={4} borderWidth={1} borderRadius="lg">
              <Text fontSize="lg" mb={4}>
                Latency Distribution
              </Text>
              <ResponsiveContainer width="100%" height={300}>
                <BarChart data={metrics.latency}>
                  <CartesianGrid strokeDasharray="3 3" />
                  <XAxis dataKey="iteration" />
                  <YAxis />
                  <Tooltip />
                  <Legend />
                  <Bar dataKey="value" fill="#38a169" name="Latency (ms)" />
                </BarChart>
              </ResponsiveContainer>
            </Box>

            {/* Resource Usage Chart */}
            <Box p={4} borderWidth={1} borderRadius="lg">
              <Text fontSize="lg" mb={4}>
                Resource Usage
              </Text>
              <ResponsiveContainer width="100%" height={300}>
                <LineChart data={metrics.resourceUsage}>
                  <CartesianGrid strokeDasharray="3 3" />
                  <XAxis dataKey="iteration" />
                  <YAxis />
                  <Tooltip />
                  <Legend />
                  <Line
                    type="monotone"
                    dataKey="value"
                    stroke="#dd6b20"
                    name="Resource Usage %"
                  />
                </LineChart>
              </ResponsiveContainer>
            </Box>

            {/* Convergence Chart */}
            <Box p={4} borderWidth={1} borderRadius="lg">
              <Text fontSize="lg" mb={4}>
                Convergence Rate
              </Text>
              <ResponsiveContainer width="100%" height={300}>
                <LineChart data={metrics.convergence}>
                  <CartesianGrid strokeDasharray="3 3" />
                  <XAxis dataKey="iteration" />
                  <YAxis />
                  <Tooltip />
                  <Legend />
                  <Line
                    type="monotone"
                    dataKey="value"
                    stroke="#805ad5"
                    name="Convergence Rate"
                  />
                </LineChart>
              </ResponsiveContainer>
            </Box>
          </Grid>
        ) : (
          <Box textAlign="center" py={10}>
            <Text color="gray.500">
              Select a model to view performance metrics
            </Text>
          </Box>
        )}
      </Stack>
    </Box>
  );
}
