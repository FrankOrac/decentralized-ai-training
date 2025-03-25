import { expect } from "chai";
import { ethers } from "hardhat";
import { SignerWithAddress } from "@nomiclabs/hardhat-ethers/signers";
import {
  GovernanceTimelock,
  ProposalDelegation,
  GovernanceReporting,
} from "../../typechain-types";

describe("Governance Integration Tests", function () {
  let timelock: GovernanceTimelock;
  let delegation: ProposalDelegation;
  let reporting: GovernanceReporting;
  let admin: SignerWithAddress;
  let proposer: SignerWithAddress;
  let executor: SignerWithAddress;
  let delegator1: SignerWithAddress;
  let delegator2: SignerWithAddress;
  let delegate1: SignerWithAddress;
  let delegate2: SignerWithAddress;

  beforeEach(async function () {
    [admin, proposer, executor, delegator1, delegator2, delegate1, delegate2] =
      await ethers.getSigners();

    // Deploy contracts
    const TimelockFactory = await ethers.getContractFactory(
      "GovernanceTimelock"
    );
    timelock = await TimelockFactory.deploy(
      3600, // minDelay
      86400, // maxDelay
      1800 // gracePeriod
    );
    await timelock.deployed();

    const DelegationFactory = await ethers.getContractFactory(
      "ProposalDelegation"
    );
    delegation = await DelegationFactory.deploy();
    await delegation.deployed();

    const ReportingFactory = await ethers.getContractFactory(
      "GovernanceReporting"
    );
    reporting = await ReportingFactory.deploy();
    await reporting.deployed();

    // Setup roles
    await timelock.grantRole(await timelock.PROPOSER_ROLE(), proposer.address);
    await timelock.grantRole(await timelock.EXECUTOR_ROLE(), executor.address);
    await reporting.grantRole(await reporting.REPORTER_ROLE(), admin.address);
  });

  describe("End-to-end Governance Flow", function () {
    it("should handle complete governance lifecycle", async function () {
      // 1. Setup delegations
      await delegation.connect(delegator1).delegate(
        delegate1.address,
        86400, // 1 day
        0 // Full delegation
      );
      await delegation
        .connect(delegator2)
        .delegate(delegate2.address, 86400, 0);

      // 2. Schedule timelock operation
      const targets = [delegation.address];
      const values = [0];
      const calldatas = [
        delegation.interface.encodeFunctionData("cleanupExpiredDelegations"),
      ];
      const salt = ethers.utils.randomBytes(32);

      const tx = await timelock
        .connect(proposer)
        .schedule(
          targets,
          values,
          calldatas,
          ethers.constants.HashZero,
          salt,
          3600
        );
      const receipt = await tx.wait();
      const event = receipt.events?.find(
        (e) => e.event === "OperationScheduled"
      );
      const operationId = event?.args?.id;

      // 3. Generate governance report
      const metricNames = [
        "totalProposals",
        "totalVotes",
        "uniqueVoters",
        "delegationCount",
      ];
      const metricValues = [1, 2, 2, 2];
      const metadataKeys = ["proposalType", "status"];
      const metadataValues = ["cleanup", "scheduled"];

      await reporting.generateReport(
        "governance_status",
        "0x",
        metricNames,
        metricValues,
        metadataKeys,
        metadataValues
      );

      // 4. Verify timelock operation
      const operation = await timelock.operations(operationId);
      expect(operation.executed).to.be.false;
      expect(operation.canceled).to.be.false;

      // 5. Fast forward time
      await ethers.provider.send("evm_increaseTime", [3600]);
      await ethers.provider.send("evm_mine", []);

      // 6. Execute operation
      await timelock
        .connect(executor)
        .execute(targets, values, calldatas, ethers.constants.HashZero, salt);

      // 7. Verify execution
      const executedOperation = await timelock.operations(operationId);
      expect(executedOperation.executed).to.be.true;

      // 8. Check delegation status
      const delegate1Info = await delegation.delegateInfo(delegate1.address);
      expect(delegate1Info.totalDelegations).to.equal(1);

      // 9. Generate final report
      const finalMetricValues = [1, 2, 2, 2];
      await reporting.generateReport(
        "governance_completion",
        "0x",
        metricNames,
        finalMetricValues,
        ["proposalType", "status"],
        ["cleanup", "executed"]
      );

      // 10. Verify metric history
      const [values, timestamps] = await reporting.getMetricHistory(
        "totalProposals"
      );
      expect(values.length).to.equal(2);
      expect(values[0]).to.equal(1);
    });

    it("should handle delegation revocation and reporting", async function () {
      // 1. Create delegation
      await delegation
        .connect(delegator1)
        .delegate(delegate1.address, 86400, 0);

      // 2. Generate initial report
      await reporting.generateReport(
        "delegation_status",
        "0x",
        ["delegationCount"],
        [1],
        ["status"],
        ["active"]
      );

      // 3. Revoke delegation
      await delegation.connect(delegator1).revokeDelegation();

      // 4. Generate updated report
      await reporting.generateReport(
        "delegation_status",
        "0x",
        ["delegationCount"],
        [0],
        ["status"],
        ["revoked"]
      );

      // 5. Verify metric history
      const [values, timestamps] = await reporting.getMetricHistory(
        "delegationCount"
      );
      expect(values.length).to.equal(2);
      expect(values[0]).to.equal(1);
      expect(values[1]).to.equal(0);
    });

    it("should detect and report anomalies", async function () {
      // 1. Generate normal reports
      for (let i = 0; i < 5; i++) {
        await reporting.generateReport(
          "governance_metrics",
          "0x",
          ["participationRate"],
          [50], // 50% participation
          ["period"],
          [`period_${i}`]
        );
      }

      // 2. Generate anomalous report
      const anomalyTx = await reporting.generateReport(
        "governance_metrics",
        "0x",
        ["participationRate"],
        [100], // 100% participation (significant deviation)
        ["period"],
        ["anomaly_period"]
      );

      // 3. Verify anomaly detection
      const receipt = await anomalyTx.wait();
      const anomalyEvent = receipt.events?.find(
        (e) => e.event === "AnomalyDetected"
      );
      expect(anomalyEvent).to.not.be.undefined;
      expect(anomalyEvent?.args?.metricName).to.equal("participationRate");
    });
  });
});
