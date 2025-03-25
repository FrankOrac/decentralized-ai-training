import { expect } from "chai";
import { ethers, network } from "hardhat";
import { SignerWithAddress } from "@nomiclabs/hardhat-ethers/signers";
import {
  SecurityMonitor,
  CrossChainGovernance,
  OracleIntegration,
  AutomatedReportGenerator,
} from "../../typechain";
import { deployMockSystem, MockSystemConfig } from "../helpers/deployMocks";
import { increaseTime, mineBlocks } from "../helpers/timeManipulation";

describe("Cross-Chain System Integration", () => {
  let owner: SignerWithAddress;
  let admin: SignerWithAddress;
  let validators: SignerWithAddress[];
  let users: SignerWithAddress[];

  let securityMonitor: SecurityMonitor;
  let governance: CrossChainGovernance;
  let oracleIntegration: OracleIntegration;
  let reportGenerator: AutomatedReportGenerator;

  const mockConfig: MockSystemConfig = {
    chainIds: [1, 137, 56], // Ethereum, Polygon, BSC
    oracleTypes: ["chainlink", "api3", "uma"],
    validatorCount: 3,
    minValidations: 2,
    votingPeriod: 86400, // 1 day
    executionDelay: 43200, // 12 hours
  };

  beforeEach(async () => {
    [owner, admin, ...users] = await ethers.getSigners();
    validators = users.slice(0, mockConfig.validatorCount);
    users = users.slice(mockConfig.validatorCount);

    // Deploy and configure the entire system
    const deployment = await deployMockSystem(mockConfig);
    securityMonitor = deployment.securityMonitor;
    governance = deployment.governance;
    oracleIntegration = deployment.oracleIntegration;
    reportGenerator = deployment.reportGenerator;

    // Setup initial chain configurations
    for (const chainId of mockConfig.chainIds) {
      await securityMonitor.connect(admin).configureChain(
        chainId,
        ethers.utils.parseEther("0.1"), // threshold
        86400, // update period
        mockConfig.minValidations
      );
    }
  });

  describe("Cross-Chain Security Monitoring", () => {
    it("should detect and handle security incidents across chains", async () => {
      // Simulate security incident on chain 1
      const incidentType = "SUSPICIOUS_ACTIVITY";
      const severity = 80;

      await securityMonitor
        .connect(validators[0])
        .reportIncident(
          mockConfig.chainIds[0],
          incidentType,
          "Suspicious transaction pattern detected",
          severity
        );

      // Validate incident
      for (const validator of validators.slice(0, mockConfig.minValidations)) {
        await securityMonitor.connect(validator).validateIncident(1, true);
      }

      // Check system response
      const incident = await securityMonitor.incidents(1);
      expect(incident.validated).to.be.true;
      expect(incident.severity).to.equal(severity);

      // Verify cross-chain notification
      for (const chainId of mockConfig.chainIds) {
        const chainStatus = await securityMonitor.getChainStatus(chainId);
        expect(chainStatus.alertLevel).to.be.gt(0);
      }
    });

    it("should maintain chain health metrics over time", async () => {
      // Simulate chain activities over time
      for (let i = 0; i < 5; i++) {
        // Update chain metrics
        for (const chainId of mockConfig.chainIds) {
          await securityMonitor.connect(admin).updateChainMetrics(
            chainId,
            95 - i, // decreasing health
            100 - i * 10, // decreasing performance
            true // isActive
          );
        }

        // Move time forward
        await increaseTime(3600); // 1 hour
        await mineBlocks(1);
      }

      // Verify health tracking
      const healthReport = await securityMonitor.getNetworkHealthReport();
      expect(healthReport.averageHealth).to.be.lt(95);
      expect(healthReport.degradingChains.length).to.be.gt(0);
    });
  });

  describe("Cross-Chain Governance Integration", () => {
    it("should handle cross-chain proposal lifecycle", async () => {
      // Create cross-chain proposal
      const proposalData = {
        title: "Cross-chain Update",
        description: "Update security parameters across chains",
        actions: mockConfig.chainIds.map((chainId) => ({
          target: securityMonitor.address,
          value: 0,
          data: securityMonitor.interface.encodeFunctionData(
            "updateSecurityParams",
            [chainId, ethers.utils.parseEther("0.2"), 43200]
          ),
        })),
      };

      await governance.connect(users[0]).createProposal(
        proposalData.title,
        proposalData.description,
        proposalData.actions.map((a) => a.target),
        proposalData.actions.map((a) => a.value),
        proposalData.actions.map((a) => a.data)
      );

      // Vote on proposal
      const proposalId = 1;
      for (const user of users.slice(0, 5)) {
        await governance.connect(user).castVote(proposalId, true);
      }

      // Move time forward past voting period
      await increaseTime(mockConfig.votingPeriod + 1);
      await mineBlocks(1);

      // Execute proposal
      await governance.connect(admin).executeProposal(proposalId);

      // Verify changes across chains
      for (const chainId of mockConfig.chainIds) {
        const params = await securityMonitor.getSecurityParams(chainId);
        expect(params.threshold).to.equal(ethers.utils.parseEther("0.2"));
        expect(params.updatePeriod).to.equal(43200);
      }
    });
  });

  describe("Oracle Integration", () => {
    it("should handle multi-oracle data requests and responses", async () => {
      // Request data from multiple oracles
      const dataTypes = mockConfig.oracleTypes;
      const requests = await Promise.all(
        dataTypes.map((type) =>
          oracleIntegration
            .connect(users[0])
            .requestData(
              type,
              ethers.utils.defaultAbiCoder.encode(["string"], ["TEST_DATA"])
            )
        )
      );

      // Simulate oracle responses
      for (let i = 0; i < requests.length; i++) {
        await oracleIntegration
          .connect(admin)
          .mockOracleResponse(
            requests[i],
            ethers.utils.defaultAbiCoder.encode(["uint256"], [100 + i])
          );
      }

      // Verify data aggregation
      const aggregatedData = await oracleIntegration.getAggregatedData(
        dataTypes[0]
      );
      expect(aggregatedData.responseCount).to.be.gt(0);
      expect(aggregatedData.isValid).to.be.true;
    });
  });

  describe("System Recovery", () => {
    it("should handle and recover from system-wide incidents", async () => {
      // Simulate critical security incident
      await securityMonitor
        .connect(validators[0])
        .reportIncident(
          mockConfig.chainIds[0],
          "CRITICAL_BREACH",
          "System-wide security breach detected",
          100
        );

      // Verify system pause
      expect(await securityMonitor.paused()).to.be.true;
      expect(await governance.paused()).to.be.true;

      // Validate and resolve incident
      for (const validator of validators) {
        await securityMonitor.connect(validator).validateIncident(1, true);
      }
      await securityMonitor.connect(admin).resolveIncident(1);

      // Verify system recovery
      expect(await securityMonitor.paused()).to.be.false;
      expect(await governance.paused()).to.be.false;

      // Verify incident recording
      const report = await reportGenerator.generateIncidentReport(1);
      expect(report.resolutionTime).to.be.gt(0);
      expect(report.systemImpact).to.equal("HIGH");
    });
  });

  describe("Performance Under Load", () => {
    it("should maintain performance under high transaction volume", async () => {
      // Generate high volume of transactions
      const txCount = 100;
      const txPromises = [];

      for (let i = 0; i < txCount; i++) {
        txPromises.push(
          securityMonitor
            .connect(users[i % users.length])
            .updateChainMetrics(
              mockConfig.chainIds[i % mockConfig.chainIds.length],
              90,
              95,
              true
            )
        );
      }

      // Execute transactions in parallel
      await Promise.all(txPromises);

      // Verify system stability
      const healthReport = await securityMonitor.getNetworkHealthReport();
      expect(healthReport.systemStable).to.be.true;
      expect(healthReport.performanceMetrics.averageLatency).to.be.lt(5000);
    });
  });

  describe("Data Consistency", () => {
    it("should maintain data consistency across chains", async () => {
      // Update data on multiple chains
      for (const chainId of mockConfig.chainIds) {
        await securityMonitor
          .connect(admin)
          .updateChainData(
            chainId,
            ethers.utils.defaultAbiCoder.encode(
              ["string", "uint256"],
              ["TEST_DATA", 100]
            )
          );
      }

      // Verify data consistency
      const dataHashes = await Promise.all(
        mockConfig.chainIds.map((chainId) =>
          securityMonitor.getChainDataHash(chainId)
        )
      );

      // All hashes should match
      const referenceHash = dataHashes[0];
      dataHashes.forEach((hash) => expect(hash).to.equal(referenceHash));
    });
  });
});
