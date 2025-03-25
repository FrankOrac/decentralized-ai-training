import { ethers } from 'ethers';
import { Web3Provider } from '@ethersproject/providers';
import { CrossChainGovernance } from '../typechain/CrossChainGovernance';
import { formatEther, parseEther } from 'ethers/lib/utils';

export interface ChainMetrics {
  chainId: number;
  trustScore: number;
  proposalCount: number;
  totalVotes: number;
  averageParticipation: number;
  successRate: number;
}

export interface ProposalMetrics {
  id: string;
  title: string;
  sourceChain: number;
  participationRate: number;
  voteDistribution: Record<number, number>;
  executionTime?: number;
  status: 'active' | 'executed' | 'canceled';
}

export interface NetworkMetrics {
  totalProposals: number;
  activeProposals: number;
  executedProposals: number;
  averageExecutionTime: number;
  participationTrend: Array<{ timestamp: number; participation: number }>;
  chainInteractions: Array<{ source: number; target: number; weight: number }>;
}

export class AnalyticsService {
  private contract: CrossChainGovernance;
  private provider: Web3Provider;

  constructor(contract: CrossChainGovernance, provider: Web3Provider) {
    this.contract = contract;
    this.provider = provider;
  }

  async getChainMetrics(): Promise<ChainMetrics[]> {
    const metrics: ChainMetrics[] = [];
    const events = await this.contract.queryFilter(
      this.contract.filters.CrossChainProposalCreated(),
      0,
      'latest'
    );

    for (let chainId = 0; chainId < 65535; chainId++) {
      const config = await this.contract.chainConfigs(chainId);
      if (!config.isActive) continue;

      const chainProposals = events.filter(
        e => e.args?.sourceChain === chainId
      );

      const voteEvents = await this.contract.queryFilter(
        this.contract.filters.CrossChainVoteReceived(null, chainId),
        0,
        'latest'
      );

      const totalVotes = voteEvents.reduce(
        (sum, event) => sum + parseFloat(formatEther(event.args?.votes || 0)),
        0
      );

      const executedProposals = await Promise.all(
        chainProposals.map(p => this.contract.proposals(p.args?.proposalId))
      );

      metrics.push({
        chainId,
        trustScore: config.trustScore.toNumber(),
        proposalCount: chainProposals.length,
        totalVotes,
        averageParticipation: chainProposals.length > 0 ?
          totalVotes / chainProposals.length : 0,
        successRate: chainProposals.length > 0 ?
          executedProposals.filter(p => p.executed).length / chainProposals.length : 0
      });
    }

    return metrics;
  }

  async getProposalMetrics(): Promise<ProposalMetrics[]> {
    const metrics: ProposalMetrics[] = [];
    const events = await this.contract.queryFilter(
      this.contract.filters.CrossChainProposalCreated(),
      0,
      'latest'
    );

    for (const event of events) {
      const proposal = await this.contract.proposals(event.args?.proposalId);
      const voteEvents = await this.contract.queryFilter(
        this.contract.filters.CrossChainVoteReceived(event.args?.proposalId),
        0,
        'latest'
      );

      const voteDistribution: Record<number, number> = {};
      let totalVotes = 0;

      for (const voteEvent of voteEvents) {
        const chainId = voteEvent.args?.sourceChain.toNumber() || 0;
        const votes = parseFloat(formatEther(voteEvent.args?.votes || 0));
        voteDistribution[chainId] = votes;
        totalVotes += votes;
      }

      const executionEvent = await this.contract.queryFilter(
        this.contract.filters.ProposalExecuted(event.args?.proposalId),
        0,
        'latest'
      );

      metrics.push({
        id: event.args?.proposalId,
        title: proposal.title,
        sourceChain: proposal.sourceChain.toNumber(),
        participationRate: totalVotes / (await this.getTotalVotingPower()),
        voteDistribution,
        executionTime: executionEvent[0]?.blockNumber ?
          (await this.provider.getBlock(executionEvent[0].blockNumber)).timestamp -
          proposal.startTime.toNumber() : undefined,
        status: proposal.executed ? 'executed' :
                proposal.canceled ? 'canceled' : 'active'
      });
    }

    return metrics;
  }

  async getNetworkMetrics(): Promise<NetworkMetrics> {
    const proposals = await this.getProposalMetrics();
    const now = Math.floor(Date.now() / 1000);
    const thirtyDaysAgo = now - 30 * 24 * 60 * 60;

    // Calculate participation trend
    const participationTrend: Array<{ timestamp: number; participation: number }> = [];
    for (let t = thirtyDaysAgo; t <= now; t += 24 * 60 * 60) {
      const relevantProposals = proposals.filter(
        p => p.executionTime && p.executionTime <= t
      );
      participationTrend.push({
        timestamp: t,
        participation: relevantProposals.reduce(
          (sum, p) => sum + p.participationRate,
          0
        ) / (relevantProposals.length || 1)
      });
    }

    // Calculate chain interactions
    const chainInteractions: Array<{ source: number; target: number; weight: number }> = [];
    proposals.forEach(proposal => {
      Object.entries(proposal.voteDistribution).forEach(([chainId, votes]) => {
        chainInteractions.push({
          source: proposal.sourceChain,
          target: parseInt(chainId),
          weight: votes
        });
      });
    });

    const executedProposals = proposals.filter(p => p.status === 'executed');

    return {
      totalProposals: proposals.length,
      activeProposals: proposals.filter(p => p.status === 'active').length,
      executedProposals: executedProposals.length,
      averageExecutionTime: executedProposals.reduce(
        (sum, p) => sum + (p.executionTime || 0),
        0
      ) / (executedProposals.length || 1),
      participationTrend,
      chainInteractions
    };
  }

  private async getTotalVotingPower(): Promise<number> {
    // Implementation depends on your voting power calculation logic
    return parseFloat(formatEther(parseEther('1000000'))); // Example value
  }
} 