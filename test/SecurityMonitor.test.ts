import { expect } from "chai";
import { ethers } from "hardhat";
import { SignerWithAddress } from "@nomiclabs/hardhat-ethers/signers";
import {
  CrossChainSecurityMonitor,
  SecurityOracle,
  MockLZEndpoint,
  MockChainlinkOracle,
  SecurityMonitor,
  MockProtectedContract,
} from "../typechain-types";

describe("Security Monitoring System", () => {
  let securityMonitor: CrossChainSecurityMonitor;
  let securityOracle: SecurityOracle;
  let mockLZEndpoint: MockLZEndpoint;
  let mockChainlinkOracle: MockChainlinkOracle;
  let protectedContract: MockProtectedContract;
  let owner: SignerWithAddress;
  let monitor: SignerWithAddress;
  let validator: SignerWithAddress;
  let guardian: SignerWithAddress;
  let users: SignerWithAddress[];

  beforeEach(async () => {
    [owner, monitor, validator, guardian, ...users] = await ethers.getSigners();

    // Deploy mock contracts
    const MockLZEndpoint = await ethers.getContractFactory("MockLZEndpoint");
    mockLZEndpoint = await MockLZEndpoint.deploy();

    const MockChainlinkOracle = await ethers.getContractFactory(
      "MockChainlinkOracle"
    );
    mockChainlinkOracle = await MockChainlinkOracle.deploy();

    // Deploy main contracts
    const SecurityMonitor = await ethers.getContractFactory(
      "CrossChainSecurityMonitor"
    );
    securityMonitor = await SecurityMonitor.deploy(mockLZEndpoint.address);

    const SecurityOracle = await ethers.getContractFactory("SecurityOracle");
    securityOracle = await SecurityOracle.deploy(mockChainlinkOracle.address);

    // Setup roles
    await securityMonitor.grantRole(
      await securityMonitor.MONITOR_ROLE(),
      monitor.address
    );
    await securityMonitor.grantRole(
      await securityMonitor.VALIDATOR_ROLE(),
      validator.address
    );
    await securityOracle.grantRole(
      await securityOracle.ORACLE_ROLE(),
      monitor.address
    );
    await securityOracle.grantRole(
      await securityOracle.VALIDATOR_ROLE(),
      validator.address
    );

    const MockProtectedContract = await ethers.getContractFactory("MockProtectedContract");
    protectedContract = await MockProtectedContract.deploy();

    await securityMonitor.grantRole(await securityMonitor.GUARDIAN_ROLE(), guardian.address);

    // Configure protection
    const restrictedFunctions = [
      ethers.utils.id("riskyFunction()").slice(0, 10)
    ];

    const threshold = {
      maxGasPerTx: ethers.utils.parseEther("0.1"),
      maxTxPerBlock: 10,
      maxValuePerTx: ethers.utils.parseEther("1"),
      cooldownPeriod: 3600,
      requiredConfirmations: 2
    };

    await securityMonitor.connect(guardian).enableContractProtection(
      protectedContract.address,
      restrictedFunctions,
      threshold
    );
  });

  describe("Security Alert Management", () => {
    it("should raise security alert with correct parameters", async () => {
      const alertType = "SUSPICIOUS_ACTIVITY";
      const severity = 2;
      const evidence = ethers.utils.defaultAbiCoder.encode(
        ["string", "uint256"],
        ["Unusual transaction pattern", 1234567890]
      );

      await expect(
        securityMonitor
          .connect(monitor)
          .raiseSecurityAlert(alertType, severity, evidence)
      )
        .to.emit(securityMonitor, "SecurityAlertRaised")
        .withArgs(
          expect.any(String), // alertId
          await securityMonitor.getChainId(),
          alertType,
          severity
        );
    });

    it("should properly verify alerts with sufficient validations", async () => {
      // Create alert
      const tx = await securityMonitor
        .connect(monitor)
        .raiseSecurityAlert("SUSPICIOUS_ACTIVITY", 2, "0x");
      const receipt = await tx.wait();
      const alertId = receipt.events?.[0].args?.alertId;

      // Verify alert
      await expect(
        securityMonitor.connect(validator).verifyAlert(alertId, true)
      )
        .to.emit(securityMonitor, "AlertVerified")
        .withArgs(alertId, await securityMonitor.getChainId(), true);

      const alert = await securityMonitor.alerts(alertId);
      expect(alert.verifications).to.equal(1);
    });
  });

  describe("Cross-Chain Communication", () => {
    it("should propagate alerts to other chains", async () => {
      const alertType = "SUSPICIOUS_ACTIVITY";
      const severity = 2;
      const evidence = "0x";

      // Mock destination chains
      const destChains = [2, 3]; // Arbitrum and Optimism
      await mockLZEndpoint.setDestinationChains(destChains);

      // Raise alert
      await securityMonitor
        .connect(monitor)
        .raiseSecurityAlert(alertType, severity, evidence);

      // Verify cross-chain messages
      const messages = await mockLZEndpoint.getMessages();
      expect(messages.length).to.equal(destChains.length);
    });
  });

  describe("Oracle Integration", () => {
    it("should configure oracle with correct parameters", async () => {
      const checkType = "TRANSACTION_ANALYSIS";
      const jobId = ethers.utils.formatBytes32String("abc123");
      const fee = ethers.utils.parseEther("0.1");

      await expect(
        securityOracle
          .connect(owner)
          .configureOracle(checkType, mockChainlinkOracle.address, jobId, fee)
      )
        .to.emit(securityOracle, "OracleConfigured")
        .withArgs(checkType, mockChainlinkOracle.address, jobId);

      const config = await securityOracle.oracleConfigs(checkType);
      expect(config.oracle).to.equal(mockChainlinkOracle.address);
      expect(config.jobId).to.equal(jobId);
      expect(config.fee).to.equal(fee);
      expect(config.isActive).to.be.true;
    });

    it("should initiate security check and process oracle response", async () => {
      // Configure oracle
      const checkType = "TRANSACTION_ANALYSIS";
      const jobId = ethers.utils.formatBytes32String("abc123");
      await securityOracle.configureOracle(
        checkType,
        mockChainlinkOracle.address,
        jobId,
        ethers.utils.parseEther("0.1")
      );

      // Initiate check
      const data = ethers.utils.defaultAbiCoder.encode(
        ["address", "uint256"],
        [users[0].address, 1234567890]
      );

      const tx = await securityOracle
        .connect(monitor)
        .initiateSecurityCheck(checkType, data);
      const receipt = await tx.wait();
      const checkId = receipt.events?.[0].args?.checkId;

      // Mock oracle response
      await mockChainlinkOracle.fulfillSecurityCheck(
        checkId,
        1 // Result indicating suspicious activity
      );

      const check = await securityOracle.getSecurityCheckStatus(checkId);
      expect(check.isComplete).to.be.true;
      expect(check.result).to.equal(1);
    });
  });

  describe("Validation Thresholds", () => {
    it("should enforce correct validation thresholds", async () => {
      const checkType = "TRANSACTION_ANALYSIS";
      const minResponses = 2;
      const consensusPercentage = 75;

      await securityOracle.setValidationThreshold(
        checkType,
        minResponses,
        consensusPercentage
      );

      const threshold = await securityOracle.validationThresholds(checkType);
      expect(threshold.minResponses).to.equal(minResponses);
      expect(threshold.consensusPercentage).to.equal(consensusPercentage);
    });
  });

  describe("Contract Protection", () => {
    it("should correctly enable protection for a contract", async () => {
      const guard = await securityMonitor.protectedContracts(protectedContract.address);
      expect(guard.isProtected).to.be.true;
    });

    it("should validate transactions according to thresholds", async () => {
      const functionSig = ethers.utils.id("safeFunction()").slice(0, 10);
      const isValid = await securityMonitor.validateTransaction(
        protectedContract.address,
        functionSig,
        21000,
        ethers.utils.parseEther("0.5")
      );
      expect(isValid).to.be.true;
    });

    it("should reject transactions exceeding thresholds", async () => {
      const functionSig = ethers.utils.id("safeFunction()").slice(0, 10);
      const isValid = await securityMonitor.validateTransaction(
        protectedContract.address,
        functionSig,
        21000,
        ethers.utils.parseEther("2")
      );
      expect(isValid).to.be.false;
    });

    it("should reject restricted functions", async () => {
      const functionSig = ethers.utils.id("riskyFunction()").slice(0, 10);
      const isValid = await securityMonitor.validateTransaction(
        protectedContract.address,
        functionSig,
        21000,
        0
      );
      expect(isValid).to.be.false;
    });
  });

  describe("Incident Reporting", () => {
    it("should allow monitors to report incidents", async () => {
      const tx = await securityMonitor.connect(monitor).reportSecurityIncident(
        "SUSPICIOUS_ACTIVITY",
        protectedContract.address,
        5,
        "0x"
      );

      const receipt = await tx.wait();
      const event = receipt.events?.find(e => e.event === "SecurityIncidentReported");
      expect(event).to.not.be.undefined;
      expect(event?.args?.incidentType).to.equal("SUSPICIOUS_ACTIVITY");
    });

    it("should trigger emergency response for high severity incidents", async () => {
      const tx = await securityMonitor.connect(monitor).reportSecurityIncident(
        "CRITICAL_VULNERABILITY",
        protectedContract.address,
        8,
        "0x"
      );

      const receipt = await tx.wait();
      const event = receipt.events?.find(e => e.event === "EmergencyShutdown");
      expect(event).to.not.be.undefined;
    });

    it("should require multiple guardian approvals for resolution", async () => {
      // Report incident
      const tx = await securityMonitor.connect(monitor).reportSecurityIncident(
        "SUSPICIOUS_ACTIVITY",
        protectedContract.address,
        5,
        "0x"
      );
      const receipt = await tx.wait();
      const incidentId = receipt.events?.[0].args?.incidentId;

      // First guardian approval
      await securityMonitor.connect(guardian).approveIncidentResolution(incidentId);
      
      let incident = await securityMonitor.incidents(incidentId);
      expect(incident.isResolved).to.be.false;

      // Grant guardian role to another user and approve
      await securityMonitor.grantRole(await securityMonitor.GUARDIAN_ROLE(), users[0].address);
      await securityMonitor.connect(users[0]).approveIncidentResolution(incidentId);

      incident = await securityMonitor.incidents(incidentId);
      expect(incident.isResolved).to.be.true;
    });
  });

  describe("Guardian Management", () => {
    it("should allow adding and removing guardians", async () => {
      await securityMonitor.grantRole(await securityMonitor.GUARDIAN_ROLE(), users[0].address);
      expect(await securityMonitor.hasRole(await securityMonitor.GUARDIAN_ROLE(), users[0].address)).to.be.true;

      await securityMonitor.revokeRole(await securityMonitor.GUARDIAN_ROLE(), users[0].address);
      expect(await securityMonitor.hasRole(await securityMonitor.GUARDIAN_ROLE(), users[0].address)).to.be.false;
    });
  });

  describe("Threshold Management", () => {
    it("should allow updating security thresholds", async () => {
      const newThreshold = {
        maxGasPerTx: ethers.utils.parseEther("0.2"),
        maxTxPerBlock: 20,
        maxValuePerTx: ethers.utils.parseEther("2"),
        cooldownPeriod: 7200,
        requiredConfirmations: 3
      };

      await securityMonitor.connect(guardian).enableContractProtection(
        protectedContract.address,
        [],
        newThreshold
      );

      const threshold = await securityMonitor.thresholds(protectedContract.address);
      expect(threshold.maxGasPerTx).to.equal(newThreshold.maxGasPerTx);
      expect(threshold.maxTxPerBlock).to.equal(newThreshold.maxTxPerBlock);
    });
  });
});
