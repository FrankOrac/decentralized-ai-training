import React, { useState } from "react";
import {
  Box,
  VStack,
  HStack,
  Text,
  Tabs,
  TabList,
  TabPanels,
  Tab,
  TabPanel,
  Code,
  Link,
  ListItem,
  UnorderedList,
  Heading,
  Accordion,
  AccordionItem,
  AccordionButton,
  AccordionPanel,
  AccordionIcon,
} from "@chakra-ui/react";
import { ExternalLinkIcon } from "@chakra-ui/icons";
import ReactMarkdown from "react-markdown";
import { Prism as SyntaxHighlighter } from "react-syntax-highlighter";
import { tomorrow } from "react-syntax-highlighter/dist/esm/styles/prism";

const technicalDocs = `
# Technical Documentation

## Architecture Overview

The system consists of several key components:

### Smart Contracts
- \`FederatedLearning.sol\`: Manages federated learning rounds and updates
- \`RewardDistributor.sol\`: Handles reward distribution and scoring
- \`SecurityMonitor.sol\`: Monitors security incidents and threats
- \`CrossChainIncidentCoordinator.sol\`: Coordinates security across chains
- \`AutomatedWorkflow.sol\`: Manages automated response workflows
- \`SecurityReporting.sol\`: Handles security reporting and analytics

### Frontend Components
- SecurityDashboard: Real-time security monitoring
- WorkflowVisualizer: Workflow management interface
- AdvancedAnalytics: Security analytics and reporting
- SecurityPredictor: ML-based prediction interface

### Integration Layer
- Oracle Network Integration
- External Security Services
- Cross-chain Communication

## Security Features

### Incident Response
\`\`\`solidity
function handleSecurityIncident(bytes32 incidentId) external {
    // Incident handling logic
}
\`\`\`

### Cross-chain Security
\`\`\`solidity
function propagateAlert(uint16 destChain, bytes memory payload) external {
    // Cross-chain alert propagation
}
\`\`\`

## Deployment Guide

1. Deploy core contracts
2. Configure oracle networks
3. Set up cross-chain communication
4. Deploy frontend components
`;

const userGuide = `
# User Guide

## Getting Started

### Connecting Your Wallet
1. Click "Connect Wallet" in the top right
2. Select your preferred wallet provider
3. Approve the connection request

### Monitoring Security
1. Navigate to the Security Dashboard
2. View real-time security metrics
3. Set up custom alerts

### Managing Workflows
1. Access the Workflow Visualizer
2. Create or modify workflows
3. Monitor workflow execution

## Features

### Security Dashboard
- Real-time monitoring
- Incident tracking
- Analytics visualization

### Workflow Management
- Create automated workflows
- Monitor execution status
- Configure response actions

### Analytics
- View security metrics
- Generate reports
- Analyze trends
`;

const apiDocs = `
# API Documentation

## Smart Contract APIs

### SecurityMonitor

\`\`\`solidity
interface ISecurityMonitor {
    function reportIncident(
        string memory incidentType,
        uint256 severity,
        bytes memory evidence
    ) external returns (bytes32);

    function getIncidentDetails(bytes32 incidentId)
        external
        view
        returns (IncidentDetails memory);
}
\`\`\`

### WorkflowManager

\`\`\`solidity
interface IWorkflowManager {
    function createWorkflow(
        string memory name,
        bytes32[] memory steps
    ) external returns (bytes32);

    function executeWorkflow(bytes32 workflowId)
        external
        returns (bool);
}
\`\`\`

## Frontend Integration

### React Hooks

\`\`\`typescript
const useSecurityMonitor = () => {
    // Hook implementation
};

const useWorkflowManager = () => {
    // Hook implementation
};
\`\`\`

### API Endpoints

\`\`\`typescript
const API_ENDPOINTS = {
    incidents: '/api/incidents',
    workflows: '/api/workflows',
    analytics: '/api/analytics'
};
\`\`\`
`;

export const Documentation: React.FC = () => {
  const [searchTerm, setSearchTerm] = useState("");

  const renderMarkdown = (content: string) => (
    <ReactMarkdown
      components={{
        code: ({ node, inline, className, children, ...props }) => {
          const match = /language-(\w+)/.exec(className || "");
          return !inline && match ? (
            <SyntaxHighlighter
              style={tomorrow}
              language={match[1]}
              PreTag="div"
              {...props}
            >
              {String(children).replace(/\n$/, "")}
            </SyntaxHighlighter>
          ) : (
            <Code {...props}>{children}</Code>
          );
        },
      }}
    >
      {content}
    </ReactMarkdown>
  );

  return (
    <Box p={6}>
      <VStack spacing={6} align="stretch">
        <Heading size="lg">Documentation</Heading>

        <Tabs>
          <TabList>
            <Tab>Technical Docs</Tab>
            <Tab>User Guide</Tab>
            <Tab>API Reference</Tab>
            <Tab>Architecture</Tab>
          </TabList>

          <TabPanels>
            <TabPanel>
              <Box overflowY="auto" maxHeight="800px">
                {renderMarkdown(technicalDocs)}
              </Box>
            </TabPanel>

            <TabPanel>
              <Box overflowY="auto" maxHeight="800px">
                {renderMarkdown(userGuide)}
              </Box>
            </TabPanel>

            <TabPanel>
              <Box overflowY="auto" maxHeight="800px">
                {renderMarkdown(apiDocs)}
              </Box>
            </TabPanel>

            <TabPanel>
              <VStack spacing={4} align="stretch">
                <Heading size="md">System Architecture</Heading>

                <Accordion allowMultiple>
                  <AccordionItem>
                    <h2>
                      <AccordionButton>
                        <Box flex="1" textAlign="left">
                          Smart Contracts
                        </Box>
                        <AccordionIcon />
                      </AccordionButton>
                    </h2>
                    <AccordionPanel>
                      <UnorderedList>
                        <ListItem>FederatedLearning Contract</ListItem>
                        <ListItem>RewardDistributor Contract</ListItem>
                        <ListItem>SecurityMonitor Contract</ListItem>
                        <ListItem>CrossChainIncidentCoordinator</ListItem>
                        <ListItem>AutomatedWorkflow Contract</ListItem>
                        <ListItem>SecurityReporting Contract</ListItem>
                      </UnorderedList>
                    </AccordionPanel>
                  </AccordionItem>

                  <AccordionItem>
                    <h2>
                      <AccordionButton>
                        <Box flex="1" textAlign="left">
                          Frontend Components
                        </Box>
                        <AccordionIcon />
                      </AccordionButton>
                    </h2>
                    <AccordionPanel>
                      <UnorderedList>
                        <ListItem>SecurityDashboard</ListItem>
                        <ListItem>WorkflowVisualizer</ListItem>
                        <ListItem>AdvancedAnalytics</ListItem>
                        <ListItem>SecurityPredictor</ListItem>
                        <ListItem>RealTimeAlerts</ListItem>
                      </UnorderedList>
                    </AccordionPanel>
                  </AccordionItem>

                  <AccordionItem>
                    <h2>
                      <AccordionButton>
                        <Box flex="1" textAlign="left">
                          Integration Layer
                        </Box>
                        <AccordionIcon />
                      </AccordionButton>
                    </h2>
                    <AccordionPanel>
                      <UnorderedList>
                        <ListItem>Oracle Network Integration</ListItem>
                        <ListItem>External Security Services</ListItem>
                        <ListItem>Cross-chain Communication</ListItem>
                        <ListItem>Data Validation and Aggregation</ListItem>
                      </UnorderedList>
                    </AccordionPanel>
                  </AccordionItem>
                </Accordion>

                <Box mt={4}>
                  <Heading size="sm" mb={2}>
                    External Resources
                  </Heading>
                  <UnorderedList>
                    <ListItem>
                      <Link href="https://docs.chain.link" isExternal>
                        Chainlink Documentation <ExternalLinkIcon mx="2px" />
                      </Link>
                    </ListItem>
                    <ListItem>
                      <Link href="https://layerzero.network/docs" isExternal>
                        LayerZero Documentation <ExternalLinkIcon mx="2px" />
                      </Link>
                    </ListItem>
                  </UnorderedList>
                </Box>
              </VStack>
            </TabPanel>
          </TabPanels>
        </Tabs>
      </VStack>
    </Box>
  );
};
