import React, { useEffect, useState, useMemo } from "react";
import {
  Box,
  Flex,
  Heading,
  Text,
  useColorModeValue,
  Stat,
  StatLabel,
  StatNumber,
  StatGroup,
  Tab,
  TabList,
  TabPanel,
  TabPanels,
  Tabs,
  Tooltip,
} from "@chakra-ui/react";
import {
  ResponsiveContainer,
  BarChart,
  Bar,
  XAxis,
  YAxis,
  CartesianGrid,
  Tooltip as RechartsTooltip,
  Legend,
  Sankey,
  Network,
} from "recharts";
import { ForceGraph2D } from "react-force-graph";
import { useContract } from "../hooks/useContract";
import { useWeb3 } from "../hooks/useWeb3";

interface ChainData {
  chainId: number;
  name: string;
  trustScore: number;
  activeProposals: number;
  totalVotes: number;
}

interface ProposalData {
  id: string;
  title: string;
  sourceChain: number;
  votes: Record<number, number>;
  status: "active" | "executed" | "canceled";
  startTime: number;
  endTime: number;
}

interface NetworkNode {
  id: string;
  name: string;
  value: number;
  color: string;
}

interface NetworkLink {
  source: string;
  target: string;
  value: number;
}

export const GovernanceVisualizer: React.FC = () => {
  const [chainData, setChainData] = useState<ChainData[]>([]);
  const [proposals, setProposals] = useState<ProposalData[]>([]);
  const [networkData, setNetworkData] = useState<{
    nodes: NetworkNode[];
    links: NetworkLink[];
  }>({ nodes: [], links: [] });

  const { contract } = useContract("CrossChainGovernance");
  const { web3 } = useWeb3();

  const bgColor = useColorModeValue("white", "gray.800");
  const textColor = useColorModeValue("gray.800", "white");

  useEffect(() => {
    const fetchData = async () => {
      if (!contract) return;

      try {
        // Fetch chain configurations
        const chains: ChainData[] = [];
        for (let chainId = 0; chainId < 65535; chainId++) {
          const config = await contract.methods.chainConfigs(chainId).call();
          if (config.isActive) {
            chains.push({
              chainId,
              name: getChainName(chainId),
              trustScore: Number(config.trustScore),
              activeProposals: 0,
              totalVotes: 0,
            });
          }
        }
        setChainData(chains);

        // Fetch proposals
        const proposalCount = await contract.methods.getProposalCount().call();
        const proposalData: ProposalData[] = [];

        for (let i = 0; i < proposalCount; i++) {
          const proposal = await contract.methods.proposals(i).call();
          proposalData.push({
            id: proposal.id,
            title: proposal.title,
            sourceChain: Number(proposal.sourceChain),
            votes: proposal.chainVotes,
            status: getProposalStatus(proposal),
            startTime: Number(proposal.startTime),
            endTime: Number(proposal.endTime),
          });
        }
        setProposals(proposalData);

        // Generate network data
        generateNetworkData(chains, proposalData);
      } catch (error) {
        console.error("Error fetching governance data:", error);
      }
    };

    fetchData();
    const interval = setInterval(fetchData, 30000);
    return () => clearInterval(interval);
  }, [contract]);

  const generateNetworkData = (
    chains: ChainData[],
    proposals: ProposalData[]
  ) => {
    const nodes: NetworkNode[] = chains.map((chain) => ({
      id: chain.chainId.toString(),
      name: chain.name,
      value: chain.trustScore,
      color: getChainColor(chain.trustScore),
    }));

    const links: NetworkLink[] = [];
    proposals.forEach((proposal) => {
      Object.entries(proposal.votes).forEach(([chainId, votes]) => {
        links.push({
          source: proposal.sourceChain.toString(),
          target: chainId,
          value: Number(votes),
        });
      });
    });

    setNetworkData({ nodes, links });
  };

  const votingStatistics = useMemo(() => {
    return proposals.reduce(
      (stats, proposal) => {
        const totalVotes = Object.values(proposal.votes).reduce(
          (sum, votes) => sum + Number(votes),
          0
        );
        return {
          totalProposals: stats.totalProposals + 1,
          totalVotes: stats.totalVotes + totalVotes,
          activeProposals:
            stats.activeProposals + (proposal.status === "active" ? 1 : 0),
          executedProposals:
            stats.executedProposals + (proposal.status === "executed" ? 1 : 0),
        };
      },
      {
        totalProposals: 0,
        totalVotes: 0,
        activeProposals: 0,
        executedProposals: 0,
      }
    );
  }, [proposals]);

  return (
    <Box p={4} bg={bgColor} borderRadius="lg" shadow="base">
      <Heading size="lg" mb={6} color={textColor}>
        Cross-Chain Governance Analytics
      </Heading>

      <StatGroup mb={8}>
        <Stat>
          <StatLabel>Total Proposals</StatLabel>
          <StatNumber>{votingStatistics.totalProposals}</StatNumber>
        </Stat>
        <Stat>
          <StatLabel>Active Proposals</StatLabel>
          <StatNumber>{votingStatistics.activeProposals}</StatNumber>
        </Stat>
        <Stat>
          <StatLabel>Executed Proposals</StatLabel>
          <StatNumber>{votingStatistics.executedProposals}</StatNumber>
        </Stat>
        <Stat>
          <StatLabel>Total Votes</StatLabel>
          <StatNumber>{votingStatistics.totalVotes}</StatNumber>
        </Stat>
      </StatGroup>

      <Tabs variant="soft-rounded" colorScheme="blue">
        <TabList mb={4}>
          <Tab>Chain Activity</Tab>
          <Tab>Proposal Distribution</Tab>
          <Tab>Network Graph</Tab>
        </TabList>

        <TabPanels>
          <TabPanel>
            <Box height="400px">
              <ResponsiveContainer width="100%" height="100%">
                <BarChart data={chainData}>
                  <CartesianGrid strokeDasharray="3 3" />
                  <XAxis dataKey="name" />
                  <YAxis yAxisId="left" />
                  <YAxis yAxisId="right" orientation="right" />
                  <RechartsTooltip />
                  <Legend />
                  <Bar
                    yAxisId="left"
                    dataKey="activeProposals"
                    fill="#8884d8"
                    name="Active Proposals"
                  />
                  <Bar
                    yAxisId="right"
                    dataKey="trustScore"
                    fill="#82ca9d"
                    name="Trust Score"
                  />
                </BarChart>
              </ResponsiveContainer>
            </Box>
          </TabPanel>

          <TabPanel>
            <Box height="400px">
              <ResponsiveContainer width="100%" height="100%">
                <Sankey
                  data={networkData}
                  nodeWidth={15}
                  nodePadding={10}
                  margin={{ top: 20, right: 20, bottom: 20, left: 20 }}
                >
                  <RechartsTooltip />
                </Sankey>
              </ResponsiveContainer>
            </Box>
          </TabPanel>

          <TabPanel>
            <Box height="600px">
              <ForceGraph2D
                graphData={networkData}
                nodeLabel="name"
                nodeColor="color"
                linkWidth={(link) => Math.sqrt(link.value)}
                nodeCanvasObject={(node, ctx, globalScale) => {
                  const label = node.name;
                  const fontSize = 12 / globalScale;
                  ctx.font = `${fontSize}px Sans-Serif`;
                  ctx.textAlign = "center";
                  ctx.textBaseline = "middle";
                  ctx.fillStyle = node.color;
                  ctx.fillText(label, node.x, node.y);
                }}
              />
            </Box>
          </TabPanel>
        </TabPanels>
      </Tabs>
    </Box>
  );
};

function getChainName(chainId: number): string {
  const chainNames: Record<number, string> = {
    1: "Ethereum",
    56: "BSC",
    137: "Polygon",
    // Add more chains as needed
  };
  return chainNames[chainId] || `Chain ${chainId}`;
}

function getChainColor(trustScore: number): string {
  if (trustScore >= 80) return "#4CAF50";
  if (trustScore >= 60) return "#FFC107";
  return "#F44336";
}

function getProposalStatus(proposal: any): "active" | "executed" | "canceled" {
  if (proposal.canceled) return "canceled";
  if (proposal.executed) return "executed";
  return "active";
}
