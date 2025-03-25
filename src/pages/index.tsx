import { Box, Container, Heading, Text, Stack, Button, Tabs, TabList, TabPanels, Tab, TabPanel } from '@chakra-ui/react';
import { Web3Provider } from '../context/Web3Context';
import { TaskCreation } from '../components/TaskCreation';
import { TaskList } from '../components/TaskList';
import { ContributorDashboard } from '../components/ContributorDashboard';
import { useWeb3 } from '../context/Web3Context';
import { AnalyticsDashboard } from '../components/AnalyticsDashboard';
import { TaskMarketplace } from '../components/TaskMarketplace';
import { GovernanceInterface } from '../components/GovernanceInterface';
import { AdvancedAnalytics } from '../components/AdvancedAnalytics';

function HomePage() {
  const { account, connectWallet } = useWeb3();

  return (
    <Container maxW="container.xl" py={10}>
      <Stack spacing={8}>
        <Box textAlign="center">
          <Heading as="h1" size="2xl">
            Decentralized AI Training Network
          </Heading>
          <Text mt={4} fontSize="xl">
            Contribute computational power, earn tokens
          </Text>
          
          {!account && (
            <Button
              mt={6}
              colorScheme="blue"
              onClick={connectWallet}
            >
              Connect Wallet
            </Button>
          )}
        </Box>

        {account && (
          <Tabs isFitted variant="enclosed">
            <TabList mb="1em">
              <Tab>Available Tasks</Tab>
              <Tab>Create Task</Tab>
              <Tab>Contributor Dashboard</Tab>
              <Tab>Analytics</Tab>
              <Tab>Marketplace</Tab>
              <Tab>Governance</Tab>
              <Tab>Advanced Analytics</Tab>
            </TabList>

            <TabPanels>
              <TabPanel>
                <TaskList />
              </TabPanel>
              <TabPanel>
                <TaskCreation />
              </TabPanel>
              <TabPanel>
                <ContributorDashboard />
              </TabPanel>
              <TabPanel>
                <AnalyticsDashboard />
              </TabPanel>
              <TabPanel>
                <TaskMarketplace />
              </TabPanel>
              <TabPanel>
                <GovernanceInterface />
              </TabPanel>
              <TabPanel>
                <AdvancedAnalytics />
              </TabPanel>
            </TabPanels>
          </Tabs>
        )}
      </Stack>
    </Container>
  );
}

export default function App() {
  return (
    <Web3Provider>
      <HomePage />
    </Web3Provider>
  );
} 