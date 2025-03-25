import { ethers } from 'ethers';
import { createClient } from '@supabase/supabase-js';

export class AnalyticsService {
  private supabase;

  constructor(
    private contract: ethers.Contract,
    private provider: ethers.providers.Web3Provider
  ) {
    this.supabase = createClient(
      process.env.NEXT_PUBLIC_SUPABASE_URL!,
      process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY!
    );
  }

  async getNetworkStats() {
    const blockNumber = await this.provider.getBlockNumber();
    const block = await this.provider.getBlock(blockNumber);

    return {
      latestBlock: blockNumber,
      timestamp: block.timestamp,
      gasPrice: ethers.utils.formatUnits(
        await this.provider.getGasPrice(),
        'gwei'
      ),
    };
  }

  async getTaskMetrics() {
    const taskCount = await this.contract.taskCount();
    const tasks = await this.fetchAllTasks(taskCount);
    
    return {
      total: tasks.length,
      completed: tasks.filter(t => t.status === 2).length,
      active: tasks.filter(t => t.status === 1).length,
      averageReward: this.calculateAverageReward(tasks),
      completionRate: this.calculateCompletionRate(tasks),
      modelTypeDistribution: this.calculateModelTypeDistribution(tasks),
    };
  }

  async getContributorMetrics() {
    const filter = this.contract.filters.TaskCompleted();
    const events = await this.contract.queryFilter(filter);
    const contributors = new Set(events.map(e => e.args?.contributor));

    const metrics = await Promise.all(
      Array.from(contributors).map(async (address) => {
        const stats = await this.contract.contributors(address);
        return {
          address,
          tasksCompleted: stats.tasksCompleted.toNumber(),
          reputation: stats.reputation.toNumber(),
          earnings: ethers.utils.formatEther(stats.earnings),
        };
      })
    );

    return {
      totalContributors: contributors.size,
      topContributors: metrics.sort((a, b) => b.tasksCompleted - a.tasksCompleted).slice(0, 10),
      averageEarnings: this.calculateAverageEarnings(metrics),
      reputationDistribution: this.calculateReputationDistribution(metrics),
    };
  }

  async trackEvent(eventType: string, data: any) {
    await this.supabase
      .from('analytics_events')
      .insert([
        {
          event_type: eventType,
          data,
          timestamp: new Date(),
        },
      ]);
  }

  private calculateAverageReward(tasks: any[]) {
    const rewards = tasks.map(t => parseFloat(ethers.utils.formatEther(t.reward)));
    return rewards.reduce((a, b) => a + b, 0) / rewards.length;
  }

  private calculateCompletionRate(tasks: any[]) {
    const completed = tasks.filter(t => t.status === 2).length;
    return (completed / tasks.length) * 100;
  }

  private calculateModelTypeDistribution(tasks: any[]) {
    const distribution = tasks.reduce((acc: any, task) => {
      acc[task.modelTypeId] = (acc[task.modelTypeId] || 0) + 1;
      return acc;
    }, {});

    return Object.entries(distribution).map(([type, count]) => ({
      type,
      count,
      percentage: (Number(count) / tasks.length) * 100,
    }));
  }

  private calculateReputationDistribution(contributors: any[]) {
    const ranges = [
      { min: 0, max: 10 },
      { min: 11, max: 50 },
      { min: 51, max: 100 },
      { min: 101, max: Infinity },
    ];

    return ranges.map(range => ({
      range: `${range.min}-${range.max === Infinity ? '∞' : range.max}`,
      count: contributors.filter(c => 
        c.reputation >= range.min && c.reputation <= range.max
      ).length,
    }));
  }

  private calculateAverageEarnings(contributors: any[]) {
    const earnings = contributors.map(c => parseFloat(c.earnings));
    return earnings.reduce((a, b) => a + b, 0) / earnings.length;
  }
} 