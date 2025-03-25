import { ethers } from "ethers";
import * as tf from "@tensorflow/tfjs";
import { SecurityMetrics, ChainData, TransactionData } from "../types";
import { anomalyDetection, predictTrends } from "../utils/mlUtils";

export class AdvancedAnalytics {
  private model: tf.LayersModel | null = null;
  private readonly historyWindow = 24; // hours
  private readonly predictionHorizon = 6; // hours

  async initialize() {
    this.model = await this.buildModel();
    await this.loadTrainingData();
  }

  private async buildModel(): Promise<tf.LayersModel> {
    const model = tf.sequential();

    model.add(
      tf.layers.lstm({
        units: 64,
        returnSequences: true,
        inputShape: [this.historyWindow, 5], // features: transactions, volume, latency, security score, participation
      })
    );

    model.add(tf.layers.dropout({ rate: 0.2 }));
    model.add(tf.layers.lstm({ units: 32 }));
    model.add(tf.layers.dense({ units: 5 }));

    model.compile({
      optimizer: tf.train.adam(0.001),
      loss: "meanSquaredError",
    });

    return model;
  }

  async analyzeNetworkHealth(
    chainData: ChainData[],
    timeframe: number
  ): Promise<NetworkHealthAnalysis> {
    const metrics = this.calculateNetworkMetrics(chainData);
    const anomalies = await this.detectAnomalies(chainData);
    const predictions = await this.generatePredictions(chainData);

    return {
      currentHealth: metrics,
      anomalies,
      predictions,
      recommendations: this.generateRecommendations(metrics, anomalies),
    };
  }

  private calculateNetworkMetrics(chainData: ChainData[]): NetworkMetrics {
    const totalTransactions = chainData.reduce(
      (sum, chain) => sum + chain.transactionCount,
      0
    );
    const averageLatency =
      chainData.reduce((sum, chain) => sum + chain.latency, 0) /
      chainData.length;

    const participationRate =
      chainData.reduce((sum, chain) => sum + chain.participationRate, 0) /
      chainData.length;

    return {
      totalTransactions,
      averageLatency,
      participationRate,
      healthScore: this.calculateHealthScore(chainData),
      crossChainInteractions: this.analyzeCrossChainInteractions(chainData),
    };
  }

  private async detectAnomalies(
    chainData: ChainData[]
  ): Promise<AnomalyReport[]> {
    const anomalies: AnomalyReport[] = [];

    for (const chain of chainData) {
      // Analyze transaction patterns
      const txAnomalies = await anomalyDetection(
        chain.transactionHistory,
        "transactions"
      );

      // Analyze latency patterns
      const latencyAnomalies = await anomalyDetection(
        chain.latencyHistory,
        "latency"
      );

      // Analyze security incidents
      const securityAnomalies = this.analyzeSecurityPatterns(
        chain.securityIncidents
      );

      anomalies.push({
        chainId: chain.id,
        transactionAnomalies: txAnomalies,
        latencyAnomalies: latencyAnomalies,
        securityAnomalies: securityAnomalies,
        severity: this.calculateAnomalySeverity(
          txAnomalies,
          latencyAnomalies,
          securityAnomalies
        ),
      });
    }

    return anomalies;
  }

  private async generatePredictions(
    chainData: ChainData[]
  ): Promise<NetworkPredictions> {
    const features = this.prepareFeatures(chainData);
    const predictions = (await this.model!.predict(features)) as tf.Tensor;

    return {
      transactionVolume: this.processPredictions(
        predictions.slice([0, 0], [-1, 1])
      ),
      latency: this.processPredictions(predictions.slice([0, 1], [-1, 2])),
      securityScore: this.processPredictions(
        predictions.slice([0, 2], [-1, 3])
      ),
      confidence: this.calculatePredictionConfidence(predictions),
    };
  }

  private prepareFeatures(chainData: ChainData[]): tf.Tensor {
    const features = chainData.map((chain) => [
      chain.transactionCount,
      chain.latency,
      chain.securityScore,
      chain.participationRate,
      chain.crossChainVolume,
    ]);

    return tf.tensor3d([features], [1, features.length, 5]);
  }

  private analyzeCrossChainInteractions(
    chainData: ChainData[]
  ): CrossChainAnalysis {
    const interactions: Record<string, number> = {};
    const patterns: InteractionPattern[] = [];

    // Analyze interaction patterns
    for (const chain of chainData) {
      for (const interaction of chain.crossChainInteractions) {
        const key = `${chain.id}-${interaction.targetChain}`;
        interactions[key] = (interactions[key] || 0) + interaction.volume;

        patterns.push({
          sourceChain: chain.id,
          targetChain: interaction.targetChain,
          volume: interaction.volume,
          latency: interaction.latency,
          success: interaction.success,
        });
      }
    }

    return {
      totalInteractions: Object.values(interactions).reduce((a, b) => a + b, 0),
      interactionMatrix: interactions,
      patterns: this.analyzeInteractionPatterns(patterns),
      bottlenecks: this.identifyBottlenecks(patterns),
    };
  }

  private analyzeInteractionPatterns(
    patterns: InteractionPattern[]
  ): PatternAnalysis {
    const timeBasedPatterns = this.analyzeTimeBasedPatterns(patterns);
    const volumePatterns = this.analyzeVolumePatterns(patterns);
    const successPatterns = this.analyzeSuccessPatterns(patterns);

    return {
      timeBasedPatterns,
      volumePatterns,
      successPatterns,
      recommendations: this.generatePatternRecommendations(
        timeBasedPatterns,
        volumePatterns,
        successPatterns
      ),
    };
  }

  private identifyBottlenecks(patterns: InteractionPattern[]): Bottleneck[] {
    const bottlenecks: Bottleneck[] = [];
    const chainLatencies = new Map<number, number[]>();

    // Collect latencies by chain
    for (const pattern of patterns) {
      if (!chainLatencies.has(pattern.targetChain)) {
        chainLatencies.set(pattern.targetChain, []);
      }
      chainLatencies.get(pattern.targetChain)!.push(pattern.latency);
    }

    // Analyze latencies for bottlenecks
    for (const [chainId, latencies] of chainLatencies) {
      const avgLatency =
        latencies.reduce((a, b) => a + b, 0) / latencies.length;
      const stdDev = this.calculateStandardDeviation(latencies);

      if (avgLatency > 5000 || stdDev > avgLatency * 0.5) {
        bottlenecks.push({
          chainId,
          averageLatency: avgLatency,
          standardDeviation: stdDev,
          impactScore: this.calculateBottleneckImpact(avgLatency, stdDev),
          recommendations: this.generateBottleneckRecommendations(
            avgLatency,
            stdDev
          ),
        });
      }
    }

    return bottlenecks.sort((a, b) => b.impactScore - a.impactScore);
  }

  private generateRecommendations(
    metrics: NetworkMetrics,
    anomalies: AnomalyReport[]
  ): Recommendation[] {
    const recommendations: Recommendation[] = [];

    // Performance recommendations
    if (metrics.averageLatency > 3000) {
      recommendations.push({
        type: "performance",
        priority: "high",
        description:
          "High network latency detected. Consider optimizing cross-chain communication.",
        actionItems: [
          "Review chain connection configurations",
          "Optimize message serialization",
          "Consider implementing caching mechanisms",
        ],
      });
    }

    // Security recommendations
    const criticalAnomalies = anomalies.filter((a) => a.severity === "high");
    if (criticalAnomalies.length > 0) {
      recommendations.push({
        type: "security",
        priority: "critical",
        description: "Critical security anomalies detected.",
        actionItems: criticalAnomalies.map(
          (a) => `Investigate anomalies on chain ${a.chainId}`
        ),
      });
    }

    // Scalability recommendations
    if (metrics.totalTransactions > metrics.previousPeriodTransactions * 1.5) {
      recommendations.push({
        type: "scalability",
        priority: "medium",
        description: "Significant increase in transaction volume detected.",
        actionItems: [
          "Review resource allocation",
          "Consider implementing sharding",
          "Optimize transaction batching",
        ],
      });
    }

    return recommendations;
  }

  private calculateHealthScore(chainData: ChainData[]): number {
    const weights = {
      latency: 0.3,
      security: 0.3,
      participation: 0.2,
      transactions: 0.2,
    };

    return (
      chainData.reduce((score, chain) => {
        const latencyScore = Math.max(0, 1 - chain.latency / 5000);
        const securityScore = chain.securityScore / 100;
        const participationScore = chain.participationRate;
        const transactionScore = Math.min(
          1,
          chain.transactionCount / chain.expectedTransactions
        );

        return (
          score +
          (latencyScore * weights.latency +
            securityScore * weights.security +
            participationScore * weights.participation +
            transactionScore * weights.transactions)
        );
      }, 0) / chainData.length
    );
  }

  private calculateStandardDeviation(values: number[]): number {
    const avg = values.reduce((a, b) => a + b, 0) / values.length;
    const squareDiffs = values.map((value) => Math.pow(value - avg, 2));
    return Math.sqrt(
      squareDiffs.reduce((a, b) => a + b, 0) / squareDiffs.length
    );
  }

  private calculateBottleneckImpact(
    avgLatency: number,
    stdDev: number
  ): number {
    return (avgLatency * 0.7 + stdDev * 0.3) / 1000;
  }
}
