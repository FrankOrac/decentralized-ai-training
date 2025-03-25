import { ethers } from "ethers";
import { SecurityMonitor } from "../typechain/SecurityMonitor";
import { CrossChainGovernance } from "../typechain/CrossChainGovernance";
import { formatEther } from "ethers/lib/utils";
import {
  sendEmail,
  sendSlackNotification,
  generatePDF,
} from "../utils/notifications";

export interface SecurityReport {
  timestamp: number;
  networkHealth: {
    totalChains: number;
    healthyChains: number;
    averageTrustScore: number;
    averageLatency: number;
    averageParticipation: number;
  };
  incidents: {
    total: number;
    critical: number;
    resolved: number;
    averageResolutionTime: number;
  };
  governance: {
    totalProposals: number;
    activeProposals: number;
    executedProposals: number;
    participationRate: number;
  };
  recommendations: string[];
}

export class AutomatedReportingService {
  private securityMonitor: SecurityMonitor;
  private governance: CrossChainGovernance;
  private reportingInterval: NodeJS.Timeout | null = null;
  private readonly reportRecipients: string[];

  constructor(
    securityMonitor: SecurityMonitor,
    governance: CrossChainGovernance,
    reportRecipients: string[]
  ) {
    this.securityMonitor = securityMonitor;
    this.governance = governance;
    this.reportRecipients = reportRecipients;
  }

  public startAutomatedReporting(intervalHours: number = 24) {
    if (this.reportingInterval) {
      clearInterval(this.reportingInterval);
    }

    this.reportingInterval = setInterval(async () => {
      try {
        const report = await this.generateSecurityReport();
        await this.distributeReport(report);
      } catch (error) {
        console.error("Error generating/distributing report:", error);
      }
    }, intervalHours * 60 * 60 * 1000);
  }

  public stopAutomatedReporting() {
    if (this.reportingInterval) {
      clearInterval(this.reportingInterval);
      this.reportingInterval = null;
    }
  }

  private async generateSecurityReport(): Promise<SecurityReport> {
    const [networkHealth, incidentMetrics, governanceMetrics] =
      await Promise.all([
        this.getNetworkHealth(),
        this.getIncidentMetrics(),
        this.getGovernanceMetrics(),
      ]);

    const recommendations = this.generateRecommendations(
      networkHealth,
      incidentMetrics,
      governanceMetrics
    );

    return {
      timestamp: Date.now(),
      networkHealth,
      incidents: incidentMetrics,
      governance: governanceMetrics,
      recommendations,
    };
  }

  private async getNetworkHealth() {
    const chainIds = await this.getActiveChainIds();
    const healthData = await Promise.all(
      chainIds.map((chainId) => this.securityMonitor.chainHealth(chainId))
    );

    const healthyChains = healthData.filter(
      (health) => health.isHealthy
    ).length;
    const totalTrustScore = healthData.reduce(
      (sum, health) => sum + health.trustScore.toNumber(),
      0
    );
    const totalLatency = healthData.reduce(
      (sum, health) => sum + health.latency.toNumber(),
      0
    );
    const totalParticipation = healthData.reduce(
      (sum, health) => sum + health.participation.toNumber(),
      0
    );

    return {
      totalChains: chainIds.length,
      healthyChains,
      averageTrustScore: totalTrustScore / chainIds.length,
      averageLatency: totalLatency / chainIds.length,
      averageParticipation: totalParticipation / chainIds.length,
    };
  }

  private async getIncidentMetrics() {
    const filter = this.securityMonitor.filters.SecurityIncidentReported();
    const events = await this.securityMonitor.queryFilter(filter, -10000);

    const incidents = await Promise.all(
      events.map(async (event) => {
        const incident = await this.securityMonitor.incidents(
          event.args?.incidentId
        );
        return {
          ...incident,
          resolutionTime: incident.resolved
            ? incident.resolvedAt.sub(incident.timestamp).toNumber()
            : null,
        };
      })
    );

    const criticalIncidents = incidents.filter(
      (i) => i.severity.toNumber() >= 80
    );
    const resolvedIncidents = incidents.filter((i) => i.resolved);
    const resolutionTimes = resolvedIncidents
      .map((i) => i.resolutionTime)
      .filter((time) => time !== null);

    return {
      total: incidents.length,
      critical: criticalIncidents.length,
      resolved: resolvedIncidents.length,
      averageResolutionTime:
        resolutionTimes.length > 0
          ? resolutionTimes.reduce((a, b) => a + b, 0) / resolutionTimes.length
          : 0,
    };
  }

  private async getGovernanceMetrics() {
    const filter = this.governance.filters.CrossChainProposalCreated();
    const events = await this.governance.queryFilter(filter, -10000);

    const proposals = await Promise.all(
      events.map((event) => this.governance.proposals(event.args?.proposalId))
    );

    const activeProposals = proposals.filter((p) => !p.executed && !p.canceled);
    const executedProposals = proposals.filter((p) => p.executed);

    const totalVotes = await Promise.all(
      proposals.map((p) => this.calculateTotalVotes(p))
    );
    const totalVotingPower = await this.getTotalVotingPower();
    const participationRate =
      totalVotes.reduce((a, b) => a + b, 0) /
      (proposals.length * totalVotingPower);

    return {
      totalProposals: proposals.length,
      activeProposals: activeProposals.length,
      executedProposals: executedProposals.length,
      participationRate,
    };
  }

  private generateRecommendations(
    networkHealth: SecurityReport["networkHealth"],
    incidents: SecurityReport["incidents"],
    governance: SecurityReport["governance"]
  ): string[] {
    const recommendations: string[] = [];

    // Network health recommendations
    if (networkHealth.healthyChains < networkHealth.totalChains) {
      recommendations.push(
        `Investigate unhealthy chains (${
          networkHealth.totalChains - networkHealth.healthyChains
        } chains)`
      );
    }
    if (networkHealth.averageTrustScore < 80) {
      recommendations.push("Review and improve trust score mechanisms");
    }
    if (networkHealth.averageLatency > 5000) {
      recommendations.push(
        "Optimize cross-chain communication to reduce latency"
      );
    }

    // Incident-related recommendations
    if (incidents.critical > 0) {
      recommendations.push(
        `Address ${incidents.critical} critical security incidents`
      );
    }
    if (incidents.averageResolutionTime > 86400) {
      recommendations.push(
        "Improve incident response time (currently > 24 hours)"
      );
    }

    // Governance recommendations
    if (governance.participationRate < 0.5) {
      recommendations.push(
        "Implement measures to increase governance participation"
      );
    }

    return recommendations;
  }

  private async distributeReport(report: SecurityReport) {
    const pdfReport = await generatePDF(report);

    // Send email to all recipients
    await Promise.all(
      this.reportRecipients.map((recipient) =>
        sendEmail(recipient, "Security Report", pdfReport)
      )
    );

    // Send Slack notification
    await sendSlackNotification({
      channel: "security-monitoring",
      text: "New security report available",
      attachments: [
        {
          title: "Security Report Summary",
          fields: [
            {
              title: "Network Health",
              value: `${report.networkHealth.healthyChains}/${report.networkHealth.totalChains} chains healthy`,
              short: true,
            },
            {
              title: "Critical Incidents",
              value: report.incidents.critical.toString(),
              short: true,
            },
            {
              title: "Governance Participation",
              value: `${(report.governance.participationRate * 100).toFixed(
                1
              )}%`,
              short: true,
            },
          ],
        },
      ],
    });
  }

  private async getActiveChainIds(): Promise<number[]> {
    // Implementation depends on your contract structure
    return [1, 56, 137]; // Example chain IDs
  }

  private async calculateTotalVotes(proposal: any): Promise<number> {
    // Implementation depends on your contract structure
    return 0;
  }

  private async getTotalVotingPower(): Promise<number> {
    // Implementation depends on your contract structure
    return 1000000;
  }
}
