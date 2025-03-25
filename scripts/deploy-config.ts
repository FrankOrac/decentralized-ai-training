export interface NetworkConfig {
  votingPeriod: number;
  votingDelay: number;
  proposalThreshold: string;
  quorumPercentage: number;
  executionDelay: number;
  verifyContract: boolean;
}

export const configs: Record<string, NetworkConfig> = {
  mainnet: {
    votingPeriod: 40320, // ~7 days
    votingDelay: 1,
    proposalThreshold: "100.0", // 100 ETH
    quorumPercentage: 4,
    executionDelay: 2,
    verifyContract: true
  },
  polygon: {
    votingPeriod: 302400, // ~7 days
    votingDelay: 1,
    proposalThreshold: "100000.0", // 100,000 MATIC
    quorumPercentage: 4,
    executionDelay: 2,
    verifyContract: true
  },
  arbitrum: {
    votingPeriod: 302400, // ~7 days
    votingDelay: 1,
    proposalThreshold: "100.0", // 100 ETH
    quorumPercentage: 4,
    executionDelay: 2,
    verifyContract: true
  },
  localhost: {
    votingPeriod: 50,
    votingDelay: 1,
    proposalThreshold: "1.0",
    quorumPercentage: 4,
    executionDelay: 2,
    verifyContract: false
  }
}; 