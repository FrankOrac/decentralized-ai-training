import { ethers } from "ethers";
import { Subject, interval, merge } from "rxjs";
import { map, filter, debounceTime } from "rxjs/operators";
import { ChainConfig, MonitoringMetrics, AlertConfig } from "../types";

export class CrossChainMonitor {
  private providers: Map<number, ethers.providers.Provider> = new Map();
  private metrics: Map<number, MonitoringMetrics> = new Map();
  private alertConfigs: AlertConfig[] = [];
  private readonly metricsSubject = new Subject<MonitoringMetrics>();
  private readonly alertSubject = new Subject<Alert>();

  constructor(private readonly configs: ChainConfig[]) {
    this.initializeProviders();
    this.startMonitoring();
  }

  private initializeProviders() {
    for (const config of this.configs) {
      this.providers.set(
        config.chainId,
        new ethers.providers.JsonRpcProvider(config.rpcUrl)
      );
    }
  }

  private startMonitoring() {
    // Monitor block production
    this.monitorBlockProduction();

    // Monitor transaction metrics
    this.monitorTransactionMetrics();

    // Monitor cross-chain messages
    this.monitorCrossChainMessages();

    // Monitor network health
    this.monitorNetworkHealth();
  }

  private monitorBlockProduction() {
    for (const [chainId, provider] of this.providers) {
      provider.on("block", async (blockNumber) => {
        try {
          const block = await provider.getBlock(blockNumber);
          const metrics = this.getOrCreateMetrics(chainId);

          metrics.lastBlockTime = block.timestamp;
          metrics.blockInterval = this.calculateBlockInterval(chainId, block);

          this.updateMetrics(chainId, metrics);
          this.checkBlockProductionAlerts(chainId, metrics);
        } catch (error) {
          console.error(`Error monitoring blocks for chain ${chainId}:`, error);
        }
      });
    }
  }

  private monitorTransactionMetrics() {
    for (const [chainId, provider] of this.providers) {
      provider.on("block", async (blockNumber) => {
        try {
          const block = await provider.getBlock(blockNumber, true);
          const metrics = this.getOrCreateMetrics(chainId);

          metrics.transactionCount = block.transactions.length;
          metrics.gasUsed = block.gasUsed.toNumber();
          metrics.averageGasPrice = await this.calculateAverageGasPrice(
            provider
          );

          this.updateMetrics(chainId, metrics);
          this.checkTransactionAlerts(chainId, metrics);
        } catch (error) {
          console.error(
            `Error monitoring transactions for chain ${chainId}:`,
            error
          );
        }
      });
    }
  }

  private monitorCrossChainMessages() {
    for (const config of this.configs) {
      const contract = new ethers.Contract(
        config.bridgeAddress,
        config.bridgeAbi,
        this.providers.get(config.chainId)
      );

      contract.on(
        "MessageSent",
        async (sourceChain, targetChain, sequence, payload) => {
          try {
            const metrics = this.getOrCreateMetrics(config.chainId);
            metrics.outgoingMessages++;

            this.trackMessageLatency(
              sourceChain,
              targetChain,
              sequence,
              payload
            );

            this.updateMetrics(config.chainId, metrics);
          } catch (error) {
            console.error(
              `Error monitoring messages for chain ${config.chainId}:`,
              error
            );
          }
        }
      );

      contract.on("MessageReceived", async (sourceChain, sequence, payload) => {
        try {
          const metrics = this.getOrCreateMetrics(config.chainId);
          metrics.incomingMessages++;

          this.updateMessageLatency(sourceChain, config.chainId, sequence);

          this.updateMetrics(config.chainId, metrics);
        } catch (error) {
          console.error(
            `Error monitoring messages for chain ${config.chainId}:`,
            error
          );
        }
      });
    }
  }

  private monitorNetworkHealth() {
    interval(60000).subscribe(async () => {
      for (const [chainId, provider] of this.providers) {
        try {
          const metrics = this.getOrCreateMetrics(chainId);

          metrics.peerCount = await this.getPeerCount(provider);
          metrics.syncStatus = await this.getSyncStatus(provider);
          metrics.networkLatency = await this.measureNetworkLatency(provider);

          this.updateMetrics(chainId, metrics);
          this.checkNetworkHealthAlerts(chainId, metrics);
        } catch (error) {
          console.error(
            `Error monitoring network health for chain ${chainId}:`,
            error
          );
        }
      }
    });
  }

  private async trackMessageLatency(
    sourceChain: number,
    targetChain: number,
    sequence: number,
    payload: string
  ) {
    const messageKey = `${sourceChain}-${targetChain}-${sequence}`;
    const timestamp = Date.now();

    await this.messageStore.set(messageKey, {
      timestamp,
      payload,
      delivered: false,
    });
  }

  private async updateMessageLatency(
    sourceChain: number,
    targetChain: number,
    sequence: number
  ) {
    const messageKey = `${sourceChain}-${targetChain}-${sequence}`;
    const message = await this.messageStore.get(messageKey);

    if (message) {
      const latency = Date.now() - message.timestamp;
      const metrics = this.getOrCreateMetrics(targetChain);

      metrics.messageLatencies.push(latency);
      metrics.averageMessageLatency = this.calculateAverageLatency(
        metrics.messageLatencies
      );

      this.updateMetrics(targetChain, metrics);
      this.checkMessageLatencyAlerts(targetChain, metrics);
    }
  }

  private async calculateAverageGasPrice(
    provider: ethers.providers.Provider
  ): Promise<number> {
    const gasPrice = await provider.getGasPrice();
    return gasPrice.toNumber();
  }

  private async getPeerCount(
    provider: ethers.providers.Provider
  ): Promise<number> {
    const peerCount = await provider.send("net_peerCount", []);
    return parseInt(peerCount, 16);
  }

  private async getSyncStatus(
    provider: ethers.providers.Provider
  ): Promise<boolean> {
    const syncStatus = await provider.send("eth_syncing", []);
    return !syncStatus;
  }

  private async measureNetworkLatency(
    provider: ethers.providers.Provider
  ): Promise<number> {
    const start = Date.now();
    await provider.getBlockNumber();
    return Date.now() - start;
  }

  private getOrCreateMetrics(chainId: number): MonitoringMetrics {
    if (!this.metrics.has(chainId)) {
      this.metrics.set(chainId, {
        chainId,
        lastBlockTime: 0,
        blockInterval: 0,
        transactionCount: 0,
        gasUsed: 0,
        averageGasPrice: 0,
        outgoingMessages: 0,
        incomingMessages: 0,
        messageLatencies: [],
        averageMessageLatency: 0,
        peerCount: 0,
        syncStatus: true,
        networkLatency: 0,
      });
    }
    return this.metrics.get(chainId)!;
  }

  private updateMetrics(chainId: number, metrics: MonitoringMetrics) {
    this.metrics.set(chainId, metrics);
    this.metricsSubject.next(metrics);
  }

  private checkBlockProductionAlerts(
    chainId: number,
    metrics: MonitoringMetrics
  ) {
    const config = this.alertConfigs.find(
      (c) => c.chainId === chainId && c.type === "BLOCK_PRODUCTION"
    );

    if (config && metrics.blockInterval > config.threshold) {
      this.alertSubject.next({
        chainId,
        type: "BLOCK_PRODUCTION",
        severity: "HIGH",
        message: `Block production delayed on chain ${chainId}. Interval: ${metrics.blockInterval}s`,
      });
    }
  }

  private checkTransactionAlerts(chainId: number, metrics: MonitoringMetrics) {
    const config = this.alertConfigs.find(
      (c) => c.chainId === chainId && c.type === "TRANSACTION_VOLUME"
    );

    if (config && metrics.transactionCount > config.threshold) {
      this.alertSubject.next({
        chainId,
        type: "TRANSACTION_VOLUME",
        severity: "MEDIUM",
        message: `High transaction volume on chain ${chainId}. Count: ${metrics.transactionCount}`,
      });
    }
  }

  private checkMessageLatencyAlerts(
    chainId: number,
    metrics: MonitoringMetrics
  ) {
    const config = this.alertConfigs.find(
      (c) => c.chainId === chainId && c.type === "MESSAGE_LATENCY"
    );

    if (config && metrics.averageMessageLatency > config.threshold) {
      this.alertSubject.next({
        chainId,
        type: "MESSAGE_LATENCY",
        severity: "HIGH",
        message: `High message latency on chain ${chainId}. Average: ${metrics.averageMessageLatency}ms`,
      });
    }
  }

  private checkNetworkHealthAlerts(
    chainId: number,
    metrics: MonitoringMetrics
  ) {
    if (!metrics.syncStatus) {
      this.alertSubject.next({
        chainId,
        type: "SYNC_STATUS",
        severity: "CRITICAL",
        message: `Chain ${chainId} is not in sync`,
      });
    }

    if (metrics.peerCount < 3) {
      this.alertSubject.next({
        chainId,
        type: "PEER_COUNT",
        severity: "HIGH",
        message: `Low peer count on chain ${chainId}. Count: ${metrics.peerCount}`,
      });
    }
  }

  public getMetrics(chainId: number): MonitoringMetrics | undefined {
    return this.metrics.get(chainId);
  }

  public getAllMetrics(): MonitoringMetrics[] {
    return Array.from(this.metrics.values());
  }

  public onMetrics(callback: (metrics: MonitoringMetrics) => void) {
    return this.metricsSubject.pipe(debounceTime(1000)).subscribe(callback);
  }

  public onAlerts(callback: (alert: Alert) => void) {
    return this.alertSubject.subscribe(callback);
  }

  public setAlertConfig(config: AlertConfig) {
    const index = this.alertConfigs.findIndex(
      (c) => c.chainId === config.chainId && c.type === config.type
    );

    if (index >= 0) {
      this.alertConfigs[index] = config;
    } else {
      this.alertConfigs.push(config);
    }
  }

  public removeAlertConfig(chainId: number, type: string) {
    this.alertConfigs = this.alertConfigs.filter(
      (c) => !(c.chainId === chainId && c.type === type)
    );
  }
}
