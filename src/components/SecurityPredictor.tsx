import React, { useState, useEffect, useCallback } from "react";
import {
  Box,
  VStack,
  HStack,
  Text,
  Select,
  Button,
  Table,
  Thead,
  Tbody,
  Tr,
  Th,
  Td,
  useToast,
  Progress,
  Badge,
  Stat,
  StatLabel,
  StatNumber,
  StatHelpText,
  StatArrow,
} from "@chakra-ui/react";
import {
  ResponsiveContainer,
  LineChart,
  Line,
  XAxis,
  YAxis,
  CartesianGrid,
  Tooltip,
  Legend,
  ScatterChart,
  Scatter,
} from "recharts";
import { format } from "date-fns";
import { useContract } from "../hooks/useContract";
import * as tf from "@tensorflow/tfjs";

interface PredictionData {
  timestamp: number;
  actual: number;
  predicted: number;
  confidence: number;
}

interface ModelMetrics {
  accuracy: number;
  precision: number;
  recall: number;
  f1Score: number;
}

export const SecurityPredictor: React.FC = () => {
  const [predictions, setPredictions] = useState<PredictionData[]>([]);
  const [modelMetrics, setModelMetrics] = useState<ModelMetrics | null>(null);
  const [selectedMetric, setSelectedMetric] = useState<string>("incidents");
  const [loading, setLoading] = useState(true);
  const [model, setModel] = useState<tf.LayersModel | null>(null);

  const toast = useToast();
  const { contract: reporting } = useContract("SecurityReporting");

  const initializeModel = useCallback(async () => {
    // Create a simple LSTM model for time series prediction
    const model = tf.sequential();

    model.add(
      tf.layers.lstm({
        units: 50,
        returnSequences: true,
        inputShape: [10, 1], // 10 time steps, 1 feature
      })
    );

    model.add(
      tf.layers.lstm({
        units: 30,
        returnSequences: false,
      })
    );

    model.add(
      tf.layers.dense({
        units: 1,
        activation: "linear",
      })
    );

    model.compile({
      optimizer: tf.train.adam(0.001),
      loss: "meanSquaredError",
      metrics: ["accuracy"],
    });

    setModel(model);
  }, []);

  const preprocessData = (data: number[]) => {
    const sequences = [];
    const labels = [];

    for (let i = 0; i < data.length - 10; i++) {
      sequences.push(data.slice(i, i + 10));
      labels.push(data[i + 10]);
    }

    return {
      sequences: tf.tensor3d(sequences, [sequences.length, 10, 1]),
      labels: tf.tensor2d(labels, [labels.length, 1]),
    };
  };

  const trainModel = async (historicalData: number[]) => {
    if (!model) return;

    const { sequences, labels } = preprocessData(historicalData);

    await model.fit(sequences, labels, {
      epochs: 50,
      batchSize: 32,
      validationSplit: 0.2,
      callbacks: {
        onEpochEnd: (epoch, logs) => {
          console.log(`Epoch ${epoch}: loss = ${logs?.loss}`);
        },
      },
    });
  };

  const makePrediction = async (historicalData: number[]) => {
    if (!model) return null;

    const input = tf.tensor3d([historicalData.slice(-10)], [1, 10, 1]);
    const prediction = model.predict(input) as tf.Tensor;
    const value = await prediction.data();

    return value[0];
  };

  const fetchData = useCallback(async () => {
    try {
      setLoading(true);

      // Fetch metric history
      const history = await reporting.getMetricHistory(selectedMetric);
      const values = history.values.map((v) => v.toNumber());
      const timestamps = history.timestamps.map((t) => t.toNumber());

      if (!model) {
        await initializeModel();
      }

      // Train model if we have enough data
      if (values.length >= 20) {
        await trainModel(values);

        // Make predictions
        const predictionData: PredictionData[] = [];
        for (let i = 10; i < values.length; i++) {
          const historicalData = values.slice(i - 10, i);
          const predicted = await makePrediction(historicalData);

          if (predicted !== null) {
            predictionData.push({
              timestamp: timestamps[i],
              actual: values[i],
              predicted,
              confidence: calculateConfidence(values[i], predicted),
            });
          }
        }

        setPredictions(predictionData);

        // Calculate model metrics
        const metrics = calculateModelMetrics(predictionData);
        setModelMetrics(metrics);
      }

      setLoading(false);
    } catch (error) {
      console.error("Error fetching data:", error);
      toast({
        title: "Error",
        description: "Failed to fetch and process data",
        status: "error",
        duration: 5000,
      });
      setLoading(false);
    }
  }, [reporting, selectedMetric, model, initializeModel, toast]);

  useEffect(() => {
    fetchData();
    const interval = setInterval(fetchData, 300000); // Refresh every 5 minutes
    return () => clearInterval(interval);
  }, [fetchData]);

  const calculateConfidence = (actual: number, predicted: number): number => {
    const error = Math.abs(actual - predicted) / actual;
    return Math.max(0, 100 * (1 - error));
  };

  const calculateModelMetrics = (
    predictions: PredictionData[]
  ): ModelMetrics => {
    let truePositives = 0;
    let falsePositives = 0;
    let falseNegatives = 0;
    let totalError = 0;

    predictions.forEach((pred) => {
      const error = Math.abs(pred.actual - pred.predicted);
      totalError += error;

      // Consider a prediction "correct" if within 10% of actual value
      const threshold = pred.actual * 0.1;
      if (error <= threshold) {
        truePositives++;
      } else if (pred.predicted > pred.actual) {
        falsePositives++;
      } else {
        falseNegatives++;
      }
    });

    const accuracy = truePositives / predictions.length;
    const precision = truePositives / (truePositives + falsePositives);
    const recall = truePositives / (truePositives + falseNegatives);
    const f1Score = (2 * (precision * recall)) / (precision + recall);

    return { accuracy, precision, recall, f1Score };
  };

  return (
    <Box p={6}>
      <VStack spacing={6} align="stretch">
        <HStack justify="space-between">
          <Text fontSize="2xl" fontWeight="bold">
            Security Predictor
          </Text>
          <HStack>
            <Select
              value={selectedMetric}
              onChange={(e) => setSelectedMetric(e.target.value)}
              w="200px"
            >
              <option value="incidents">Security Incidents</option>
              <option value="alerts">Alert Frequency</option>
              <option value="response">Response Time</option>
            </Select>
            <Button onClick={fetchData} isLoading={loading}>
              Refresh
            </Button>
          </HStack>
        </HStack>

        {modelMetrics && (
          <Grid templateColumns="repeat(4, 1fr)" gap={6}>
            <Stat>
              <StatLabel>Model Accuracy</StatLabel>
              <StatNumber>
                {(modelMetrics.accuracy * 100).toFixed(1)}%
              </StatNumber>
              <StatHelpText>
                <StatArrow
                  type={modelMetrics.accuracy > 0.8 ? "increase" : "decrease"}
                />
                Based on historical predictions
              </StatHelpText>
            </Stat>
            <Stat>
              <StatLabel>Precision</StatLabel>
              <StatNumber>
                {(modelMetrics.precision * 100).toFixed(1)}%
              </StatNumber>
            </Stat>
            <Stat>
              <StatLabel>Recall</StatLabel>
              <StatNumber>{(modelMetrics.recall * 100).toFixed(1)}%</StatNumber>
            </Stat>
            <Stat>
              <StatLabel>F1 Score</StatLabel>
              <StatNumber>
                {(modelMetrics.f1Score * 100).toFixed(1)}%
              </StatNumber>
            </Stat>
          </Grid>
        )}

        <Box h="400px">
          <ResponsiveContainer>
            <LineChart data={predictions}>
              <CartesianGrid strokeDasharray="3 3" />
              <XAxis
                dataKey="timestamp"
                tickFormatter={(ts) => format(ts * 1000, "MM/dd HH:mm")}
              />
              <YAxis />
              <Tooltip
                labelFormatter={(ts) => format(ts * 1000, "yyyy-MM-dd HH:mm")}
              />
              <Legend />
              <Line
                type="monotone"
                dataKey="actual"
                stroke="#8884d8"
                name="Actual"
                dot={false}
              />
              <Line
                type="monotone"
                dataKey="predicted"
                stroke="#82ca9d"
                name="Predicted"
                strokeDasharray="5 5"
              />
            </LineChart>
          </ResponsiveContainer>
        </Box>

        <Box h="300px">
          <ResponsiveContainer>
            <ScatterChart>
              <CartesianGrid strokeDasharray="3 3" />
              <XAxis dataKey="actual" name="Actual Value" />
              <YAxis dataKey="predicted" name="Predicted Value" />
              <Tooltip cursor={{ strokeDasharray: "3 3" }} />
              <Legend />
              <Scatter name="Predictions" data={predictions} fill="#8884d8" />
            </ScatterChart>
          </ResponsiveContainer>
        </Box>

        <Table variant="simple">
          <Thead>
            <Tr>
              <Th>Time</Th>
              <Th>Actual</Th>
              <Th>Predicted</Th>
              <Th>Confidence</Th>
              <Th>Error</Th>
            </Tr>
          </Thead>
          <Tbody>
            {predictions.slice(-10).map((pred, index) => (
              <Tr key={index}>
                <Td>{format(pred.timestamp * 1000, "yyyy-MM-dd HH:mm:ss")}</Td>
                <Td>{pred.actual.toFixed(2)}</Td>
                <Td>{pred.predicted.toFixed(2)}</Td>
                <Td>
                  <Badge
                    colorScheme={
                      pred.confidence >= 90
                        ? "green"
                        : pred.confidence >= 70
                        ? "yellow"
                        : "red"
                    }
                  >
                    {pred.confidence.toFixed(1)}%
                  </Badge>
                </Td>
                <Td>
                  {Math.abs(pred.actual - pred.predicted).toFixed(2)}
                  <Progress
                    size="xs"
                    mt={1}
                    value={
                      100 -
                      (Math.abs(pred.actual - pred.predicted) / pred.actual) *
                        100
                    }
                    colorScheme={
                      pred.confidence >= 90
                        ? "green"
                        : pred.confidence >= 70
                        ? "yellow"
                        : "red"
                    }
                  />
                </Td>
              </Tr>
            ))}
          </Tbody>
        </Table>
      </VStack>
    </Box>
  );
};
