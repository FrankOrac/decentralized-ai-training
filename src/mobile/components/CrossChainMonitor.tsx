import React, { useEffect, useState, useCallback } from "react";
import {
  View,
  RefreshControl,
  ScrollView,
  StyleSheet,
  Platform,
  useWindowDimensions,
} from "react-native";
import {
  VictoryChart,
  VictoryLine,
  VictoryTheme,
  VictoryAxis,
  VictoryTooltip,
} from "victory-native";
import {
  Card,
  Title,
  Paragraph,
  List,
  Badge,
  Button,
  Portal,
  Modal,
  ActivityIndicator,
} from "react-native-paper";
import { useWalletConnect } from "@walletconnect/react-native-dapp";
import { ethers } from "ethers";
import {
  AnalyticsService,
  NetworkMetrics,
  ChainMetrics,
} from "../services/AnalyticsService";

interface AlertConfig {
  chainId: number;
  threshold: number;
  type: "participation" | "trustScore" | "latency";
}

const CrossChainMonitor: React.FC = () => {
  const [networkMetrics, setNetworkMetrics] = useState<NetworkMetrics | null>(
    null
  );
  const [chainMetrics, setChainMetrics] = useState<ChainMetrics[]>([]);
  const [alerts, setAlerts] = useState<string[]>([]);
  const [refreshing, setRefreshing] = useState(false);
  const [modalVisible, setModalVisible] = useState(false);
  const [selectedChain, setSelectedChain] = useState<ChainMetrics | null>(null);
  const [alertConfigs, setAlertConfigs] = useState<AlertConfig[]>([]);

  const connector = useWalletConnect();
  const { width } = useWindowDimensions();

  const analyticsService = new AnalyticsService(
    // Initialize with contract and provider
    null as any,
    null as any
  );

  const fetchData = useCallback(async () => {
    try {
      const [network, chains] = await Promise.all([
        analyticsService.getNetworkMetrics(),
        analyticsService.getChainMetrics(),
      ]);

      setNetworkMetrics(network);
      setChainMetrics(chains);

      // Check for alerts
      const newAlerts = [];
      for (const config of alertConfigs) {
        const chain = chains.find((c) => c.chainId === config.chainId);
        if (chain) {
          switch (config.type) {
            case "participation":
              if (chain.averageParticipation < config.threshold) {
                newAlerts.push(
                  `Low participation on chain ${
                    chain.chainId
                  }: ${chain.averageParticipation.toFixed(2)}%`
                );
              }
              break;
            case "trustScore":
              if (chain.trustScore < config.threshold) {
                newAlerts.push(
                  `Low trust score on chain ${chain.chainId}: ${chain.trustScore}`
                );
              }
              break;
          }
        }
      }
      setAlerts(newAlerts);
    } catch (error) {
      console.error("Error fetching data:", error);
    }
  }, [alertConfigs]);

  useEffect(() => {
    fetchData();
    const interval = setInterval(fetchData, 30000);
    return () => clearInterval(interval);
  }, [fetchData]);

  const onRefresh = useCallback(async () => {
    setRefreshing(true);
    await fetchData();
    setRefreshing(false);
  }, [fetchData]);

  const showChainDetails = (chain: ChainMetrics) => {
    setSelectedChain(chain);
    setModalVisible(true);
  };

  return (
    <ScrollView
      style={styles.container}
      refreshControl={
        <RefreshControl refreshing={refreshing} onRefresh={onRefresh} />
      }
    >
      {/* Network Overview Card */}
      <Card style={styles.card}>
        <Card.Content>
          <Title>Network Overview</Title>
          <View style={styles.metricsGrid}>
            <View style={styles.metric}>
              <Paragraph>Total Proposals</Paragraph>
              <Title>{networkMetrics?.totalProposals || 0}</Title>
            </View>
            <View style={styles.metric}>
              <Paragraph>Active Proposals</Paragraph>
              <Title>{networkMetrics?.activeProposals || 0}</Title>
            </View>
            <View style={styles.metric}>
              <Paragraph>Success Rate</Paragraph>
              <Title>
                {networkMetrics
                  ? (
                      (networkMetrics.executedProposals /
                        networkMetrics.totalProposals) *
                      100
                    ).toFixed(1)
                  : 0}
                %
              </Title>
            </View>
          </View>
        </Card.Content>
      </Card>

      {/* Participation Trend Chart */}
      <Card style={styles.card}>
        <Card.Content>
          <Title>Participation Trend</Title>
          {networkMetrics?.participationTrend && (
            <VictoryChart
              theme={VictoryTheme.material}
              width={width - 40}
              height={200}
            >
              <VictoryLine
                data={networkMetrics.participationTrend}
                x="timestamp"
                y="participation"
                labels={({ datum }) => `${datum.participation.toFixed(2)}%`}
                labelComponent={<VictoryTooltip />}
              />
              <VictoryAxis
                tickFormat={(t) => new Date(t * 1000).toLocaleDateString()}
                style={{ tickLabels: { angle: -45 } }}
              />
              <VictoryAxis dependentAxis />
            </VictoryChart>
          )}
        </Card.Content>
      </Card>

      {/* Alerts Section */}
      {alerts.length > 0 && (
        <Card style={[styles.card, styles.alertCard]}>
          <Card.Content>
            <Title>Active Alerts</Title>
            <List.Section>
              {alerts.map((alert, index) => (
                <List.Item
                  key={index}
                  title={alert}
                  left={() => <List.Icon icon="alert" />}
                  right={() => <Badge>New</Badge>}
                />
              ))}
            </List.Section>
          </Card.Content>
        </Card>
      )}

      {/* Chain List */}
      <Card style={styles.card}>
        <Card.Content>
          <Title>Connected Chains</Title>
          <List.Section>
            {chainMetrics.map((chain) => (
              <List.Item
                key={chain.chainId}
                title={`Chain ${chain.chainId}`}
                description={`Trust Score: ${chain.trustScore}`}
                right={() => (
                  <Button
                    mode="contained"
                    onPress={() => showChainDetails(chain)}
                    style={styles.detailsButton}
                  >
                    Details
                  </Button>
                )}
              />
            ))}
          </List.Section>
        </Card.Content>
      </Card>

      {/* Chain Details Modal */}
      <Portal>
        <Modal
          visible={modalVisible}
          onDismiss={() => setModalVisible(false)}
          contentContainerStyle={styles.modalContent}
        >
          {selectedChain && (
            <View>
              <Title>Chain {selectedChain.chainId} Details</Title>
              <List.Section>
                <List.Item
                  title="Trust Score"
                  description={selectedChain.trustScore}
                />
                <List.Item
                  title="Proposal Count"
                  description={selectedChain.proposalCount}
                />
                <List.Item
                  title="Average Participation"
                  description={`${selectedChain.averageParticipation.toFixed(
                    2
                  )}%`}
                />
                <List.Item
                  title="Success Rate"
                  description={`${(selectedChain.successRate * 100).toFixed(
                    1
                  )}%`}
                />
              </List.Section>
              <Button
                mode="contained"
                onPress={() => setModalVisible(false)}
                style={styles.closeButton}
              >
                Close
              </Button>
            </View>
          )}
        </Modal>
      </Portal>
    </ScrollView>
  );
};

const styles = StyleSheet.create({
  container: {
    flex: 1,
    backgroundColor: "#f5f5f5",
  },
  card: {
    margin: 8,
    elevation: 4,
  },
  alertCard: {
    backgroundColor: "#fff3e0",
  },
  metricsGrid: {
    flexDirection: "row",
    justifyContent: "space-between",
    marginTop: 16,
  },
  metric: {
    alignItems: "center",
  },
  detailsButton: {
    marginVertical: 4,
  },
  modalContent: {
    backgroundColor: "white",
    padding: 20,
    margin: 20,
    borderRadius: 8,
  },
  closeButton: {
    marginTop: 16,
  },
});

export default CrossChainMonitor;
