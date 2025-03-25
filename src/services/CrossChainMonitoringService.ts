import { ethers } from "ethers";
import { Subject, interval } from "rxjs";
import { Web3Provider } from "@ethersproject/providers";
import { CrossChainGovernance } from "../typechain/CrossChainGovernance";

export interface ChainStatus {
  chainId: number;
  lastBlock: number;
  lastUpdate: number;
  latency: number;
  isHealthy: boolean;
}

export interface ProposalStatus {
  id: string;
  sourceChain: number;
  targetChains: number[];
  status: "pending" | "voting" | "executed" | "failed";
  votingProgress: number;
  timeRemaining?: number;
}

export interface NetworkAlert {
  id: string;
  timestamp: number;
  chainId: number;
  type: "latency" | "participation" | "security" | "consensus";
  severity: "low" | "medium" | "high";
  message: string;
  acknowledged: boolean;
}

export class CrossChainMonitoringService {
  private providers: Map<number, Web3Provider> = new Map();
  private contracts: Map<number, CrossChainGovernance> = new Map();
  private alertsSubject = new Subject<NetworkAlert>();
  private statusSubject = new Subject<ChainStatus>();
  private readonly healthCheckInterval = 30000; // 30 seconds
  private readonly latencyThreshold = 5000; // 5 seconds
  private readonly participationThreshold = 0.4; // 40%

  constructor() {
    this.startHealthCheck();
  }

  public addChain(
    chainId: number,
    provider: Web3Provider,
    contract: CrossChainGovernance
  ) {
    this.providers.set(chainId, provider);
    this.contracts.set(chainId, contract);
  }

  public get alerts$() {
    return this.alertsSubject.asObservable();
  }

  public get status$() {
    return this.statusSubject.asObservable();
  }

  private startHealthCheck() {
    interval(this.healthCheckInterval).subscribe(async () => {
      for (const [chainId, provider] of this.providers) {
        try {
          const startTime = Date.now();
          const blockNumber = await provider.getBlockNumber();
          const latency = Date.now() - startTime;

          const status: ChainStatus = {
            chainId,
            lastBlock: blockNumber,
            lastUpdate: Date.now(),
            latency,
            isHealthy: latency < this.latencyThreshold,
          };

          this.statusSubject.next(status);

          if (latency > this.latencyThreshold) {
            this.emitAlert({
              id: `latency-${chainId}-${Date.now()}`,
              timestamp: Date.now(),
              chainId,
              type: "latency",
              severity: "medium",
              message: `High latency detected on chain ${chainId}: ${latency}ms`,
              acknowledged: false,
            });
          }

          await this.checkParticipation(chainId);
          await this.checkConsensus(chainId);
        } catch (error) {
          console.error(`Error monitoring chain ${chainId}:`, error);
          this.emitAlert({
            id: `error-${chainId}-${Date.now()}`,
            timestamp: Date.now(),
            chainId,
            type: "security",
            severity: "high",
            message: `Connection error on chain ${chainId}: ${error.message}`,
            acknowledged: false,
          });
        }
      }
    });
  }

  private async checkParticipation(chainId: number) {
    const contract = this.contracts.get(chainId);
    if (!contract) return;

    try {
      const events = await contract.queryFilter(
        contract.filters.CrossChainProposalCreated(),
        -1000
      );

      for (const event of events) {
        const proposal = await contract.proposals(event.args?.proposalId);
        const totalVotes = await this.calculateTotalVotes(proposal);
        const participation =
          totalVotes / (await this.getTotalVotingPower(chainId));

        if (participation < this.participationThreshold) {
          this.emitAlert({
            id: `participation-${chainId}-${event.args?.proposalId}`,
            timestamp: Date.now(),
            chainId,
            type: "participation",
            severity: "medium",
            message: `Low participation (${(participation * 100).toFixed(
              2
            )}%) for proposal ${event.args?.proposalId}`,
            acknowledged: false,
          });
        }
      }
    } catch (error) {
      console.error(
        `Error checking participation for chain ${chainId}:`,
        error
      );
    }
  }

  private async checkConsensus(chainId: number) {
    const contract = this.contracts.get(chainId);
    if (!contract) return;

    try {
      const events = await contract.queryFilter(
        contract.filters.CrossChainVoteReceived(),
        -1000
      );

      const votesByProposal = new Map<string, Map<number, number>>();
      for (const event of events) {
        const proposalId = event.args?.proposalId;
        const sourceChain = event.args?.sourceChain.toNumber();
        const votes = event.args?.votes.toNumber();

        if (!votesByProposal.has(proposalId)) {
          votesByProposal.set(proposalId, new Map());
        }
        votesByProposal.get(proposalId)?.set(sourceChain, votes);
      }

      for (const [proposalId, votes] of votesByProposal) {
        const divergence = this.calculateVoteDivergence(votes);
        if (divergence > 0.3) {
          // 30% divergence threshold
          this.emitAlert({
            id: `consensus-${chainId}-${proposalId}`,
            timestamp: Date.now(),
            chainId,
            type: "consensus",
            severity: "high",
            message: `High vote divergence (${(divergence * 100).toFixed(
              2
            )}%) detected for proposal ${proposalId}`,
            acknowledged: false,
          });
        }
      }
    } catch (error) {
      console.error(`Error checking consensus for chain ${chainId}:`, error);
    }
  }

  private calculateVoteDivergence(votes: Map<number, number>): number {
    const values = Array.from(votes.values());
    if (values.length < 2) return 0;

    const mean = values.reduce((a, b) => a + b, 0) / values.length;
    const variance =
      values.reduce((acc, val) => acc + Math.pow(val - mean, 2), 0) /
      values.length;
    return Math.sqrt(variance) / mean;
  }

  private async calculateTotalVotes(proposal: any): Promise<number> {
    // Implementation depends on your contract structure
    return 0;
  }

  private async getTotalVotingPower(chainId: number): Promise<number> {
    // Implementation depends on your contract structure
    return 1000000;
  }

  private emitAlert(alert: NetworkAlert) {
    this.alertsSubject.next(alert);
  }

  public async getProposalStatus(proposalId: string): Promise<ProposalStatus> {
    const statuses = await Promise.all(
      Array.from(this.contracts.entries()).map(async ([chainId, contract]) => {
        try {
          const proposal = await contract.proposals(proposalId);
          return {
            chainId,
            status: this.determineProposalStatus(proposal),
            votes: await this.calculateTotalVotes(proposal),
          };
        } catch (error) {
          console.error(
            `Error getting proposal status for chain ${chainId}:`,
            error
          );
          return null;
        }
      })
    );

    const validStatuses = statuses.filter((s) => s !== null);
    const sourceChain = validStatuses[0]?.chainId || 0;
    const targetChains = validStatuses.map((s) => s!.chainId);
    const totalVotes = validStatuses.reduce(
      (sum, s) => sum + (s?.votes || 0),
      0
    );
    const maxVotes = await this.getTotalVotingPower(sourceChain);

    return {
      id: proposalId,
      sourceChain,
      targetChains,
      status: this.aggregateProposalStatus(validStatuses.map((s) => s!.status)),
      votingProgress: totalVotes / maxVotes,
      timeRemaining: await this.calculateTimeRemaining(proposalId, sourceChain),
    };
  }

  private determineProposalStatus(
    proposal: any
  ): "pending" | "voting" | "executed" | "failed" {
    // Implementation depends on your contract structure
    return "pending";
  }

  private aggregateProposalStatus(
    statuses: Array<"pending" | "voting" | "executed" | "failed">
  ): "pending" | "voting" | "executed" | "failed" {
    if (statuses.every((s) => s === "executed")) return "executed";
    if (statuses.some((s) => s === "failed")) return "failed";
    if (statuses.some((s) => s === "voting")) return "voting";
    return "pending";
  }

  private async calculateTimeRemaining(
    proposalId: string,
    chainId: number
  ): Promise<number | undefined> {
    const contract = this.contracts.get(chainId);
    if (!contract) return undefined;

    try {
      const proposal = await contract.proposals(proposalId);
      const now = Math.floor(Date.now() / 1000);
      return Math.max(0, proposal.endTime.toNumber() - now);
    } catch (error) {
      console.error(`Error calculating time remaining:`, error);
      return undefined;
    }
  }
}
