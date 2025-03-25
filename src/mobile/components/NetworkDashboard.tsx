import React, { useEffect, useState, useCallback } from "react";
import {
  View,
  ScrollView,
  RefreshControl,
  StyleSheet,
  Dimensions,
  Platform,
  TouchableOpacity,
} from "react-native";
import {
  Card,
  Title,
  Paragraph,
  List,
  Button,
  Portal,
  Modal,
  ActivityIndicator,
  useTheme,
} from "react-native-paper";
import {
  VictoryChart,
  VictoryLine,
  VictoryAxis,
  VictoryTheme,
} from "victory-native";
import { useAdvancedAnalytics } from "../hooks/useAdvancedAnalytics";
import { NetworkHealthAnalysis, Recommendation } from "../types";
import { formatNumber, formatDate } from "../utils/formatters";

const { width } = Dimensions.get("window");

const NetworkDashboard: React.FC = () => {
  const [refreshing, setRefreshing] = useState(false);
  const [selectedChain, setSelectedChain] = useState<number | null>(null);
  const [showRecommendations, setShowRecommendations] = useState(false);

  const { analytics, loading, error } = useAdvancedAnalytics();
  const theme = useTheme();

  const onRefresh = useCallback(async () => {
    setRefreshing(true);
    await analytics.refreshData();
    setRefreshing(false);
  }, [analytics]);

  if (loading) {
    return (
      <View style={styles.centered}>
        <ActivityIndicator size="large" />
      </View>
    );
  }

  if (error) {
    return (
      <View style={styles.centered}>
        <Title>Error loading data</Title>
        <Button mode="contained" onPress={onRefresh}>
          Retry
        </Button>
      </View>
    );
  }

  const renderHealthScore = () => (
    <Card style={styles.card}>
      <Card.Content>
        <Title>Network Health</Title>
        <View style={styles.scoreContainer}>
          <Title
            style={[
              styles.score,
              { color: getHealthColor(analytics.healthScore) },
            ]}
          >
            {(analytics.healthScore * 100).toFixed(1)}%
          </Title>
          <Paragraph>Overall Health Score</Paragraph>
        </View>
      </Card.Content>
    </Card>
  );

  const renderMetrics = () => (
    <Card style={styles.card}>
      <Card.Content>
        <Title>Key Metrics</Title>
        <List.Section>
          <List.Item
            title="Total Transactions"
            description={formatNumber(analytics.metrics.totalTransactions)}
            left={(props) => <List.Icon {...props} icon="transfer" />}
          />
          <List.Item
            title="Average Latency"
            description={`${analytics.metrics.averageLatency.toFixed(2)}ms`}
            left={(props) => <List.Icon {...props} icon="clock" />}
          />
          <List.Item
            title="Participation Rate"
            description={`${(analytics.metrics.participationRate * 100).toFixed(
              1
            )}%`}
            left={(props) => <List.Icon {...props} icon="account-group" />}
          />
        </List.Section>
      </Card.Content>
    </Card>
  );

  const renderAnomalies = () => (
    <Card style={styles.card}>
      <Card.Content>
        <Title>Detected Anomalies</Title>
        <ScrollView horizontal showsHorizontalScrollIndicator={false}>
          {analytics.anomalies.map((anomaly, index) => (
            <TouchableOpacity
              key={index}
              onPress={() => setSelectedChain(anomaly.chainId)}
            >
              <Card style={styles.anomalyCard}>
                <Card.Content>
                  <Title>Chain {anomaly.chainId}</Title>
                  <Paragraph
                    style={{
                      color: getSeverityColor(anomaly.severity),
                    }}
                  >
                    {anomaly.severity.toUpperCase()}
                  </Paragraph>
                  <Paragraph>
                    {anomaly.transactionAnomalies.length} Transaction Anomalies
                  </Paragraph>
                  <Paragraph>
                    {anomaly.latencyAnomalies.length} Latency Anomalies
                  </Paragraph>
                </Card.Content>
              </Card>
            </TouchableOpacity>
          ))}
        </ScrollView>
      </Card.Content>
    </Card>
  );

  const renderPredictions = () => (
    <Card style={styles.card}>
      <Card.Content>
        <Title>Network Predictions</Title>
        <VictoryChart
          theme={VictoryTheme.material}
          width={width - 40}
          height={200}
        >
          <VictoryLine
            data={analytics.predictions.transactionVolume}
            x="timestamp"
            y="value"
            style={{
              data: { stroke: theme.colors.primary },
            }}
          />
          <VictoryAxis
            tickFormat={(t) => formatDate(t)}
            style={{ tickLabels: { angle: -45 } }}
          />
          <VictoryAxis dependentAxis tickFormat={(t) => formatNumber(t)} />
        </VictoryChart>
      </Card.Content>
    </Card>
  );

  const renderRecommendations = () => (
    <Portal>
      <Modal
        visible={showRecommendations}
        onDismiss={() => setShowRecommendations(false)}
        contentContainerStyle={styles.modal}
      >
        <ScrollView>
          <Title>Recommendations</Title>
          {analytics.recommendations.map((rec, index) => (
            <Card key={index} style={styles.recommendationCard}>
              <Card.Content>
                <Title style={{ color: getPriorityColor(rec.priority) }}>
                  {rec.type.toUpperCase()}
                </Title>
                <Paragraph>{rec.description}</Paragraph>
                <List.Section>
                  {rec.actionItems.map((item, i) => (
                    <List.Item
                      key={i}
                      title={item}
                      left={(props) => (
                        <List.Icon {...props} icon="chevron-right" />
                      )}
                    />
                  ))}
                </List.Section>
              </Card.Content>
            </Card>
          ))}
        </ScrollView>
        <Button
          mode="contained"
          onPress={() => setShowRecommendations(false)}
          style={styles.closeButton}
        >
          Close
        </Button>
      </Modal>
    </Portal>
  );

  return (
    <ScrollView
      style={styles.container}
      refreshControl={
        <RefreshControl refreshing={refreshing} onRefresh={onRefresh} />
      }
    >
      {renderHealthScore()}
      {renderMetrics()}
      {renderAnomalies()}
      {renderPredictions()}
      <Button
        mode="contained"
        onPress={() => setShowRecommendations(true)}
        style={styles.recommendationsButton}
      >
        View Recommendations
      </Button>
      {renderRecommendations()}
    </ScrollView>
  );
};

const styles = StyleSheet.create({
  container: {
    flex: 1,
    backgroundColor: "#f5f5f5",
  },
  centered: {
    flex: 1,
    justifyContent: "center",
    alignItems: "center",
  },
  card: {
    margin: 8,
    elevation: Platform.OS === "android" ? 4 : 0,
    shadowColor: "#000",
    shadowOffset: { width: 0, height: 2 },
    shadowOpacity: 0.25,
    shadowRadius: 3.84,
  },
  scoreContainer: {
    alignItems: "center",
    marginVertical: 16,
  },
  score: {
    fontSize: 48,
    fontWeight: "bold",
  },
  anomalyCard: {
    width: 200,
    marginRight: 8,
  },
  modal: {
    backgroundColor: "white",
    margin: 20,
    padding: 20,
    borderRadius: 8,
    maxHeight: "80%",
  },
  recommendationCard: {
    marginVertical: 8,
  },
  recommendationsButton: {
    margin: 16,
  },
  closeButton: {
    marginTop: 16,
  },
});

export default NetworkDashboard;
