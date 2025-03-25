import { ethers } from "ethers";

export interface PlatformMetrics {
  totalTasks: number;
  completedTasks: number;
  activeContributors: number;
  totalRewardsDistributed: string;
  averageCompletionTime: number;
  successRate: number;
}

export interface ContributorMetrics {
  tasksCompleted: number;
  successRate: number;
  averageTime: number;
  totalEarnings: string;
  reputation: number;
  ranking: number;
}

export class AnalyticsService {
  constructor(private contract: ethers.Contract) {}

  async getPlatformMetrics(): Promise<PlatformMetrics> {
    const taskCount = await this.contract.taskCount();
    const tasks = await this.fetchAllTasks(taskCount.toNumber());
    const completedTasks = tasks.filter((t) => t.status === 2);

    return {
      totalTasks: taskCount.toNumber(),
      completedTasks: completedTasks.length,
      activeContributors: await this.getActiveContributorsCount(),
      totalRewardsDistributed: ethers.utils.formatEther(
        await this.contract.totalRewardsDistributed()
      ),
      averageCompletionTime:
        this.calculateAverageCompletionTime(completedTasks),
      successRate: (completedTasks.length / taskCount.toNumber()) * 100,
    };
  }

  async getContributorMetrics(address: string): Promise<ContributorMetrics> {
    const contributor = await this.contract.contributors(address);
    const ranking = await this.calculateContributorRanking(address);

    return {
      tasksCompleted: contributor.tasksCompleted.toNumber(),
      successRate: await this.calculateContributorSuccessRate(address),
      averageTime: await this.calculateContributorAverageTime(address),
      totalEarnings: ethers.utils.formatEther(contributor.earnings),
      reputation: contributor.reputation.toNumber(),
      ranking,
    };
  }

  private async fetchAllTasks(count: number) {
    const tasks = [];
    for (let i = 1; i <= count; i++) {
      const task = await this.contract.tasks(i);
      tasks.push(task);
    }
    return tasks;
  }

  private async getActiveContributorsCount(): Promise<number> {
    // Implementation depends on contract events
    const filter = this.contract.filters.TaskStarted();
    const events = await this.contract.queryFilter(filter, -10000);
    const uniqueContributors = new Set(events.map((e) => e.args?.contributor));
    return uniqueContributors.size;
  }

  private calculateAverageCompletionTime(tasks: any[]): number {
    const completionTimes = tasks.map(
      (t) => t.completedAt.toNumber() - t.startTime.toNumber()
    );
    return completionTimes.reduce((a, b) => a + b, 0) / completionTimes.length;
  }

  private async calculateContributorSuccessRate(
    address: string
  ): Promise<number> {
    const filter = this.contract.filters.TaskCompleted(null, address);
    const completedEvents = await this.contract.queryFilter(filter, -10000);
    const startedFilter = this.contract.filters.TaskStarted(null, address);
    const startedEvents = await this.contract.queryFilter(
      startedFilter,
      -10000
    );

    return (completedEvents.length / startedEvents.length) * 100;
  }

  private async calculateContributorRanking(address: string): Promise<number> {
    // Implementation would sort all contributors by reputation
    return 1; // Placeholder
  }

  private async calculateContributorAverageTime(
    address: string
  ): Promise<number> {
    // Implementation would calculate average task completion time
    return 0; // Placeholder
  }
}
