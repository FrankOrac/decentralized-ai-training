import { expect } from "chai";
import { ethers } from "hardhat";
import { SignerWithAddress } from "@nomiclabs/hardhat-ethers/signers";
import { GovernanceSystem } from "../typechain-types";

describe("GovernanceSystem", function () {
  let governanceSystem: GovernanceSystem;
  let admin: SignerWithAddress;
  let proposer: SignerWithAddress;
  let executor: SignerWithAddress;
  let voter1: SignerWithAddress;
  let voter2: SignerWithAddress;

  beforeEach(async function () {
    [admin, proposer, executor, voter1, voter2] = await ethers.getSigners();

    const GovernanceSystem = await ethers.getContractFactory(
      "GovernanceSystem"
    );
    governanceSystem = await GovernanceSystem.deploy();
    await governanceSystem.deployed();

    // Setup roles
    const proposerRole = await governanceSystem.PROPOSER_ROLE();
    const executorRole = await governanceSystem.EXECUTOR_ROLE();

    await governanceSystem.grantRole(proposerRole, proposer.address);
    await governanceSystem.grantRole(executorRole, executor.address);
  });

  describe("Proposal Creation", function () {
    it("should allow proposer to create proposal", async function () {
      const targets = [governanceSystem.address];
      const values = [0];
      const calldatas = ["0x"];
      const description = "Test Proposal";

      await expect(
        governanceSystem
          .connect(proposer)
          .propose(targets, values, calldatas, description)
      )
        .to.emit(governanceSystem, "ProposalCreated")
        .withArgs(1, proposer.address, description);
    });

    it("should reject proposal from non-proposer", async function () {
      const targets = [governanceSystem.address];
      const values = [0];
      const calldatas = ["0x"];
      const description = "Test Proposal";

      await expect(
        governanceSystem
          .connect(voter1)
          .propose(targets, values, calldatas, description)
      ).to.be.revertedWith("GovernanceSystem: must have proposer role");
    });
  });

  describe("Voting", function () {
    beforeEach(async function () {
      const targets = [governanceSystem.address];
      const values = [0];
      const calldatas = ["0x"];
      const description = "Test Proposal";

      await governanceSystem
        .connect(proposer)
        .propose(targets, values, calldatas, description);
    });

    it("should allow voting on active proposal", async function () {
      // Move past voting delay
      await ethers.provider.send("evm_mine", []);

      await expect(governanceSystem.connect(voter1).castVote(1, true))
        .to.emit(governanceSystem, "VoteCast")
        .withArgs(voter1.address, 1, true);
    });

    it("should prevent double voting", async function () {
      await ethers.provider.send("evm_mine", []);

      await governanceSystem.connect(voter1).castVote(1, true);

      await expect(
        governanceSystem.connect(voter1).castVote(1, true)
      ).to.be.revertedWith("GovernanceSystem: already voted");
    });
  });

  describe("Proposal Execution", function () {
    beforeEach(async function () {
      const targets = [governanceSystem.address];
      const values = [0];
      const calldatas = ["0x"];
      const description = "Test Proposal";

      await governanceSystem
        .connect(proposer)
        .propose(targets, values, calldatas, description);

      // Move past voting delay
      await ethers.provider.send("evm_mine", []);

      // Cast votes
      await governanceSystem.connect(voter1).castVote(1, true);
      await governanceSystem.connect(voter2).castVote(1, true);
    });

    it("should execute successful proposal", async function () {
      // Move past voting period and execution delay
      for (let i = 0; i < 40325; i++) {
        await ethers.provider.send("evm_mine", []);
      }

      await expect(governanceSystem.connect(executor).executeProposal(1))
        .to.emit(governanceSystem, "ProposalExecuted")
        .withArgs(1);
    });

    it("should prevent execution before delay", async function () {
      await expect(
        governanceSystem.connect(executor).executeProposal(1)
      ).to.be.revertedWith("GovernanceSystem: execution delay not met");
    });
  });

  describe("Parameter Updates", function () {
    it("should allow admin to update parameters", async function () {
      const newParameters = {
        votingPeriod: 50400,
        votingDelay: 2,
        proposalThreshold: ethers.utils.parseEther("200"),
        quorumPercentage: 5,
        executionDelay: 3,
      };

      await expect(
        governanceSystem.connect(admin).updateParameters(newParameters)
      ).to.emit(governanceSystem, "ParametersUpdated");

      const params = await governanceSystem.parameters();
      expect(params.votingPeriod).to.equal(newParameters.votingPeriod);
      expect(params.quorumPercentage).to.equal(newParameters.quorumPercentage);
    });

    it("should reject parameter updates from non-admin", async function () {
      const newParameters = {
        votingPeriod: 50400,
        votingDelay: 2,
        proposalThreshold: ethers.utils.parseEther("200"),
        quorumPercentage: 5,
        executionDelay: 3,
      };

      await expect(
        governanceSystem.connect(voter1).updateParameters(newParameters)
      ).to.be.revertedWith("GovernanceSystem: must have admin role");
    });
  });
});
