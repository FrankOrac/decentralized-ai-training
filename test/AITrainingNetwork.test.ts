import { expect } from "chai";
import { ethers } from "hardhat";
import { SignerWithAddress } from "@nomiclabs/hardhat-ethers/signers";
import {
  AITrainingNetwork,
  ValidationSystem,
  DisputeResolution,
  FederatedLearning,
} from "../typechain";

describe("AI Training Network", function () {
  let aiTraining: AITrainingNetwork;
  let validation: ValidationSystem;
  let dispute: DisputeResolution;
  let federated: FederatedLearning;
  let owner: SignerWithAddress;
  let contributor: SignerWithAddress;
  let validator: SignerWithAddress;

  beforeEach(async function () {
    [owner, contributor, validator] = await ethers.getSigners();

    // Deploy contracts
    const AITrainingNetwork = await ethers.getContractFactory(
      "AITrainingNetwork"
    );
    aiTraining = await AITrainingNetwork.deploy();
    await aiTraining.deployed();

    const ValidationSystem = await ethers.getContractFactory(
      "ValidationSystem"
    );
    validation = await ValidationSystem.deploy(3, 70);
    await validation.deployed();

    const DisputeResolution = await ethers.getContractFactory(
      "DisputeResolution"
    );
    dispute = await DisputeResolution.deploy(100, 3, 86400);
    await dispute.deployed();

    const FederatedLearning = await ethers.getContractFactory(
      "FederatedLearning"
    );
    federated = await FederatedLearning.deploy();
    await federated.deployed();
  });

  describe("Task Creation", function () {
    it("Should create a new task", async function () {
      const reward = ethers.utils.parseEther("1");
      const deadline = Math.floor(Date.now() / 1000) + 86400;

      await aiTraining.createTask("QmModelHash", reward, deadline);

      const task = await aiTraining.tasks(1);
      expect(task.modelHash).to.equal("QmModelHash");
      expect(task.reward).to.equal(reward);
      expect(task.deadline).to.equal(deadline);
    });

    it("Should fail with invalid deadline", async function () {
      const reward = ethers.utils.parseEther("1");
      const deadline = Math.floor(Date.now() / 1000) - 86400;

      await expect(
        aiTraining.createTask("QmModelHash", reward, deadline)
      ).to.be.revertedWith("Invalid deadline");
    });
  });

  describe("Validation System", function () {
    it("Should validate a task result", async function () {
      await validation.grantRole(
        ethers.utils.keccak256(ethers.utils.toUtf8Bytes("VALIDATOR_ROLE")),
        validator.address
      );

      await validation
        .connect(validator)
        .submitValidation(1, 85, "QmResultHash", "Good performance");

      const validationResult = await validation.getTaskValidations(1);
      expect(validationResult[0].score).to.equal(85);
    });
  });

  describe("Dispute Resolution", function () {
    it("Should create and resolve a dispute", async function () {
      await dispute.createDispute(1, "Invalid results", "QmEvidenceHash");

      await dispute.grantRole(
        ethers.utils.keccak256(ethers.utils.toUtf8Bytes("ARBITRATOR_ROLE")),
        validator.address
      );

      await dispute.connect(validator).castVote(1, true, "Valid dispute");

      const disputeDetails = await dispute.getDisputeDetails(1);
      expect(disputeDetails.votesFor).to.equal(1);
    });
  });

  describe("Federated Learning", function () {
    it("Should create and complete a federated task", async function () {
      await federated.createFederatedTask("QmBaseModelHash", 3, 2);

      await federated.connect(contributor).joinTask(1);
      await federated.joinTask(1);

      await federated.connect(contributor).submitUpdate(1, 1, "QmUpdateHash1");

      const taskDetails = await federated.getTaskDetails(1);
      expect(taskDetails.currentRound).to.equal(1);
    });
  });
});
