import React, { useEffect, useState, useMemo } from "react";
import {
  Box,
  Grid,
  Heading,
  VStack,
  useColorModeValue,
  Tabs,
  TabList,
  TabPanels,
  Tab,
  TabPanel,
} from "@chakra-ui/react";
import {
  ResponsiveContainer,
  LineChart,
  Line,
  AreaChart,
  Area,
  BarChart,
  Bar,
  XAxis,
  YAxis,
  CartesianGrid,
  Tooltip,
  Legend,
  Sankey,
  RadialBarChart,
  RadialBar,
} from "recharts";
import { ForceGraph3D } from "react-force-graph-3d";
import { useOracleData } from "../hooks/useOracleData";
import { useChainData } from "../hooks/useChainData";
import { NetworkMetrics, ChainMetrics } from "../types/metrics";
import { formatEther } from "ethers/lib/utils";
import { ThreeJSRenderer } from "./ThreeJSRenderer";

interface ChainNode {
  id: string;
  name: string;
  value: number;
  color: string;
}

interface ChainLink {
  source: string;
  target: string;
  value: number;
}

const AdvancedDashboard: React.FC = () => {
  const [networkMetrics, setNetworkMetrics] = useState<NetworkMetrics | null>(
    null
  );
  const [chainMetrics, setChainMetrics] = useState<ChainMetrics[]>([]);
  const [graphData, setGraphData] = useState<{
    nodes: ChainNode[];
    links: ChainLink[];
  }>({ nodes: [], links: [] });

  const { oracleData, loading: oracleLoading } = useOracleData();
  const { chainData, loading: chainLoading } = useChainData();

  const bgColor = useColorModeValue("white", "gray.800");
  const textColor = useColorModeValue("gray.800", "white");

  useEffect(() => {
    if (chainData && oracleData) {
      processData();
    }
  }, [chainData, oracleData]);

  const processData = () => {
    // Process chain data into graph format
    const nodes: ChainNode[] = chainData.map((chain) => ({
      id: chain.id.toString(),
      name: `Chain ${chain.id}`,
      value: chain.trustScore,
      color: getTrustScoreColor(chain.trustScore),
    }));

    const links: ChainLink[] = chainData.flatMap((chain) =>
      chain.connections.map((conn) => ({
        source: chain.id.toString(),
        target: conn.targetChain.toString(),
        value: conn.interactionCount,
      }))
    );

    setGraphData({ nodes, links });
  };

  const getTrustScoreColor = (score: number): string => {
    if (score >= 80) return "#4CAF50";
    if (score >= 60) return "#FFC107";
    return "#F44336";
  };

  const renderNetworkMetrics = () => (
    <Box p={4} bg={bgColor} borderRadius="lg" shadow="md">
      <Heading size="md" mb={4}>
        Network Performance
      </Heading>
      <ResponsiveContainer width="100%" height={300}>
        <AreaChart data={networkMetrics?.timeSeriesData}>
          <CartesianGrid strokeDasharray="3 3" />
          <XAxis dataKey="timestamp" />
          <YAxis />
          <Tooltip />
          <Legend />
          <Area
            type="monotone"
            dataKey="throughput"
            stroke="#8884d8"
            fill="#8884d8"
            fillOpacity={0.3}
          />
          <Area
            type="monotone"
            dataKey="latency"
            stroke="#82ca9d"
            fill="#82ca9d"
            fillOpacity={0.3}
          />
        </AreaChart>
      </ResponsiveContainer>
    </Box>
  );

  const renderOracleMetrics = () => (
    <Box p={4} bg={bgColor} borderRadius="lg" shadow="md">
      <Heading size="md" mb={4}>
        Oracle Performance
      </Heading>
      <ResponsiveContainer width="100%" height={300}>
        <RadialBarChart
          innerRadius="30%"
          outerRadius="80%"
          data={oracleData?.performanceMetrics}
        >
          <RadialBar minAngle={15} background clockWise dataKey="accuracy" />
          <Legend />
          <Tooltip />
        </RadialBarChart>
      </ResponsiveContainer>
    </Box>
  );

  const renderChainInteractions = () => (
    <Box p={4} bg={bgColor} borderRadius="lg" shadow="md">
      <Heading size="md" mb={4}>
        Chain Interactions
      </Heading>
      <Box height="600px">
        <ForceGraph3D
          graphData={graphData}
          nodeLabel="name"
          nodeColor="color"
          linkWidth={(link) => Math.sqrt(link.value)}
          nodeRelSize={6}
          linkOpacity={0.5}
          linkDirectionalParticles={2}
          linkDirectionalParticleSpeed={(d) => d.value * 0.001}
        />
      </Box>
    </Box>
  );

  const renderSecurityMetrics = () => (
    <Box p={4} bg={bgColor} borderRadius="lg" shadow="md">
      <Heading size="md" mb={4}>
        Security Metrics
      </Heading>
      <ResponsiveContainer width="100%" height={300}>
        <Sankey
          data={networkMetrics?.securityData}
          nodeWidth={15}
          nodePadding={10}
          margin={{ top: 20, right: 20, bottom: 20, left: 20 }}
        >
          <Tooltip />
        </Sankey>
      </ResponsiveContainer>
    </Box>
  );

  return (
    <VStack spacing={4} w="full" p={4}>
      <Tabs isFitted variant="soft-rounded" colorScheme="blue" w="full">
        <TabList mb={4}>
          <Tab>Overview</Tab>
          <Tab>Network</Tab>
          <Tab>Oracles</Tab>
          <Tab>Security</Tab>
        </TabList>

        <TabPanels>
          <TabPanel>
            <Grid templateColumns="repeat(2, 1fr)" gap={4}>
              {renderNetworkMetrics()}
              {renderOracleMetrics()}
            </Grid>
          </TabPanel>

          <TabPanel>{renderChainInteractions()}</TabPanel>

          <TabPanel>
            <Grid templateColumns="repeat(2, 1fr)" gap={4}>
              {renderOracleMetrics()}
              <ThreeJSRenderer data={oracleData?.visualizationData} />
            </Grid>
          </TabPanel>

          <TabPanel>{renderSecurityMetrics()}</TabPanel>
        </TabPanels>
      </Tabs>
    </VStack>
  );
};

export default AdvancedDashboard;
