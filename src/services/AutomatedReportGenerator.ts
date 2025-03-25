import { ethers } from "ethers";
import { format } from "date-fns";
import { PDFDocument, rgb } from "pdf-lib";
import { ChartJSNodeCanvas } from "chartjs-node-canvas";
import {
  SecurityMonitor,
  CrossChainGovernance,
  OracleIntegration,
} from "../typechain";
import { sendEmail, uploadToIPFS, notifySlack } from "../utils/notifications";

interface ReportConfig {
  title: string;
  period: "daily" | "weekly" | "monthly";
  recipients: string[];
  includeCharts: boolean;
  notificationChannels: ("email" | "slack" | "ipfs")[];
}

interface ReportMetrics {
  networkHealth: {
    totalChains: number;
    activeChains: number;
    averageLatency: number;
    successRate: number;
  };
  securityMetrics: {
    incidents: number;
    resolvedIncidents: number;
    averageResolutionTime: number;
    threatLevel: "low" | "medium" | "high";
  };
  oracleMetrics: {
    totalRequests: number;
    successfulRequests: number;
    averageResponseTime: number;
    disputeRate: number;
  };
  governanceMetrics: {
    proposals: number;
    votingParticipation: number;
    executedProposals: number;
    crossChainProposals: number;
  };
}

export class AutomatedReportGenerator {
  private securityMonitor: SecurityMonitor;
  private governance: CrossChainGovernance;
  private oracleIntegration: OracleIntegration;
  private chartGenerator: ChartJSNodeCanvas;

  constructor(
    securityMonitor: SecurityMonitor,
    governance: CrossChainGovernance,
    oracleIntegration: OracleIntegration
  ) {
    this.securityMonitor = securityMonitor;
    this.governance = governance;
    this.oracleIntegration = oracleIntegration;
    this.chartGenerator = new ChartJSNodeCanvas({ width: 800, height: 400 });
  }

  async generateReport(config: ReportConfig): Promise<Buffer> {
    const metrics = await this.collectMetrics();
    const pdfDoc = await PDFDocument.create();

    // Add title page
    const titlePage = pdfDoc.addPage();
    const { width, height } = titlePage.getSize();
    titlePage.drawText(config.title, {
      x: 50,
      y: height - 100,
      size: 24,
      color: rgb(0, 0, 0),
    });

    // Add executive summary
    const summaryPage = pdfDoc.addPage();
    await this.addExecutiveSummary(summaryPage, metrics);

    // Add detailed metrics
    const metricsPage = pdfDoc.addPage();
    await this.addDetailedMetrics(metricsPage, metrics);

    // Add charts if configured
    if (config.includeCharts) {
      const chartsPage = pdfDoc.addPage();
      await this.addCharts(chartsPage, metrics);
    }

    // Add recommendations
    const recommendationsPage = pdfDoc.addPage();
    await this.addRecommendations(recommendationsPage, metrics);

    const pdfBytes = await pdfDoc.save();

    // Distribute report
    await this.distributeReport(Buffer.from(pdfBytes), config);

    return Buffer.from(pdfBytes);
  }

  private async collectMetrics(): Promise<ReportMetrics> {
    const [networkMetrics, securityMetrics, oracleMetrics, governanceMetrics] =
      await Promise.all([
        this.collectNetworkMetrics(),
        this.collectSecurityMetrics(),
        this.collectOracleMetrics(),
        this.collectGovernanceMetrics(),
      ]);

    return {
      networkHealth: networkMetrics,
      securityMetrics,
      oracleMetrics,
      governanceMetrics,
    };
  }

  private async collectNetworkMetrics() {
    const chainCount = await this.securityMonitor.getActiveChainCount();
    const healthData = await this.securityMonitor.getNetworkHealthMetrics();

    return {
      totalChains: chainCount.toNumber(),
      activeChains: healthData.activeChains.toNumber(),
      averageLatency: healthData.averageLatency.toNumber(),
      successRate: healthData.successRate.toNumber(),
    };
  }

  private async collectSecurityMetrics() {
    const securityData = await this.securityMonitor.getSecurityMetrics();

    return {
      incidents: securityData.totalIncidents.toNumber(),
      resolvedIncidents: securityData.resolvedIncidents.toNumber(),
      averageResolutionTime: securityData.averageResolutionTime.toNumber(),
      threatLevel: this.calculateThreatLevel(securityData),
    };
  }

  private async collectOracleMetrics() {
    const oracleData = await this.oracleIntegration.getOracleMetrics();

    return {
      totalRequests: oracleData.totalRequests.toNumber(),
      successfulRequests: oracleData.successfulRequests.toNumber(),
      averageResponseTime: oracleData.averageResponseTime.toNumber(),
      disputeRate: oracleData.disputeRate.toNumber(),
    };
  }

  private async collectGovernanceMetrics() {
    const governanceData = await this.governance.getGovernanceMetrics();

    return {
      proposals: governanceData.totalProposals.toNumber(),
      votingParticipation: governanceData.votingParticipation.toNumber(),
      executedProposals: governanceData.executedProposals.toNumber(),
      crossChainProposals: governanceData.crossChainProposals.toNumber(),
    };
  }

  private async addExecutiveSummary(page: PDFPage, metrics: ReportMetrics) {
    const { width, height } = page.getSize();
    let yOffset = height - 100;

    page.drawText("Executive Summary", {
      x: 50,
      y: yOffset,
      size: 18,
      color: rgb(0, 0, 0),
    });

    yOffset -= 40;

    const summaryText = [
      `Network Status: ${this.getNetworkStatus(metrics.networkHealth)}`,
      `Security Status: ${metrics.securityMetrics.threatLevel.toUpperCase()}`,
      `Oracle Performance: ${this.getOraclePerformance(metrics.oracleMetrics)}`,
      `Governance Activity: ${this.getGovernanceActivity(
        metrics.governanceMetrics
      )}`,
    ];

    for (const text of summaryText) {
      page.drawText(text, {
        x: 50,
        y: yOffset,
        size: 12,
        color: rgb(0, 0, 0),
      });
      yOffset -= 20;
    }
  }

  private async addDetailedMetrics(page: PDFPage, metrics: ReportMetrics) {
    // Implementation for detailed metrics visualization
  }

  private async addCharts(page: PDFPage, metrics: ReportMetrics) {
    // Implementation for charts generation and addition
  }

  private async addRecommendations(page: PDFPage, metrics: ReportMetrics) {
    const recommendations = this.generateRecommendations(metrics);
    let yOffset = page.getSize().height - 100;

    page.drawText("Recommendations", {
      x: 50,
      y: yOffset,
      size: 18,
      color: rgb(0, 0, 0),
    });

    yOffset -= 40;

    for (const recommendation of recommendations) {
      page.drawText(`• ${recommendation}`, {
        x: 50,
        y: yOffset,
        size: 12,
        color: rgb(0, 0, 0),
      });
      yOffset -= 20;
    }
  }

  private async distributeReport(report: Buffer, config: ReportConfig) {
    const timestamp = format(new Date(), "yyyy-MM-dd-HH-mm");
    const filename = `report-${timestamp}.pdf`;

    for (const channel of config.notificationChannels) {
      switch (channel) {
        case "email":
          await Promise.all(
            config.recipients.map((recipient) =>
              sendEmail(recipient, "Automated Report", report, filename)
            )
          );
          break;
        case "slack":
          await notifySlack({
            channel: "monitoring",
            text: "New monitoring report available",
            file: report,
            filename,
          });
          break;
        case "ipfs":
          const ipfsHash = await uploadToIPFS(report);
          await notifySlack({
            channel: "monitoring",
            text: `Report available on IPFS: ${ipfsHash}`,
          });
          break;
      }
    }
  }

  private calculateThreatLevel(securityData: any): "low" | "medium" | "high" {
    const incidentRatio =
      securityData.resolvedIncidents / securityData.totalIncidents;
    if (incidentRatio > 0.9) return "low";
    if (incidentRatio > 0.7) return "medium";
    return "high";
  }

  private getNetworkStatus(health: ReportMetrics["networkHealth"]): string {
    const healthRatio = health.activeChains / health.totalChains;
    if (healthRatio > 0.9) return "Excellent";
    if (healthRatio > 0.7) return "Good";
    return "Needs Attention";
  }

  private getOraclePerformance(
    metrics: ReportMetrics["oracleMetrics"]
  ): string {
    const successRate = metrics.successfulRequests / metrics.totalRequests;
    if (successRate > 0.95) return "Excellent";
    if (successRate > 0.8) return "Good";
    return "Needs Improvement";
  }

  private getGovernanceActivity(
    metrics: ReportMetrics["governanceMetrics"]
  ): string {
    const executionRate = metrics.executedProposals / metrics.proposals;
    if (executionRate > 0.8) return "High";
    if (executionRate > 0.5) return "Moderate";
    return "Low";
  }

  private generateRecommendations(metrics: ReportMetrics): string[] {
    const recommendations: string[] = [];

    if (metrics.networkHealth.averageLatency > 5000) {
      recommendations.push(
        "Consider optimizing cross-chain communication to reduce latency"
      );
    }

    if (metrics.securityMetrics.threatLevel === "high") {
      recommendations.push("Immediate security review recommended");
    }

    if (metrics.oracleMetrics.disputeRate > 0.1) {
      recommendations.push("Review oracle configuration and data sources");
    }

    if (metrics.governanceMetrics.votingParticipation < 0.5) {
      recommendations.push(
        "Implement measures to increase governance participation"
      );
    }

    return recommendations;
  }
}
