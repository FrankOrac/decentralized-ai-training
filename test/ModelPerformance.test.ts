import { expect } from "chai";
import { ethers } from "hardhat";
import { SignerWithAddress } from "@nomiclabs/hardhat-ethers/signers";
import {
  ModelAnalytics,
  ModelMarketplace,
  AITrainingNetwork,
} from "../typechain-types";

describe("Model Performance Testing", () => {
  let modelAnalytics: ModelAnalytics;
  let modelMarketplace: ModelMarketplace;
  let aiTrainingNetwork: AITrainingNetwork;
  let owner: SignerWithAddress;
  let user1: SignerWithAddress;
  let user2: SignerWithAddress;

  beforeEach(async () => {
    [owner, user1, user2] = await ethers.getSigners();

    // Deploy contracts
    const ModelAnalytics = await ethers.getContractFactory("ModelAnalytics");
    modelAnalytics = await ModelAnalytics.deploy();
    await modelAnalytics.deployed();

    const ModelMarketplace = await ethers.getContractFactory(
      "ModelMarketplace"
    );
    modelMarketplace = await ModelMarketplace.deploy();
    await modelMarketplace.deployed();

    const AITrainingNetwork = await ethers.getContractFactory(
      "AITrainingNetwork"
    );
    aiTrainingNetwork = await AITrainingNetwork.deploy();
    await aiTrainingNetwork.deployed();
  });

  describe("Model Metrics", () => {
    it("should record and retrieve model metrics correctly", async () => {
      const modelHash = ethers.utils.id("testModel");
      const accuracy = 95;
      const latency = 100;
      const resourceUsage = 80;

      await modelAnalytics.updateModelMetrics(
        modelHash,
        accuracy,
        latency,
        resourceUsage
      );

      const metrics = await modelAnalytics.getModelMetrics(modelHash);

      expect(metrics.accuracy).to.equal(accuracy);
      expect(metrics.latency).to.equal(latency);
      expect(metrics.resourceUsage).to.equal(resourceUsage);
    });

    it("should track performance history correctly", async () => {
      const modelHash = ethers.utils.id("testModel");

      // Record multiple data points
      for (let i = 0; i < 5; i++) {
        await modelAnalytics.updateModelMetrics(modelHash, 90 + i, 100 - i, 80);
      }

      const history = await modelAnalytics.getPerformanceHistory(modelHash);
      expect(history.length).to.equal(5);
    });
  });

  describe("Model Marketplace Integration", () => {
    it("should update metrics when model is purchased", async () => {
      const modelHash = ethers.utils.id("testModel");
      const price = ethers.utils.parseEther("1");

      await modelMarketplace
        .connect(user1)
        .listModel(modelHash, "Test Model", "Description", price);

      await modelMarketplace.connect(user2).purchaseModel(modelHash, {
        value: price,
      });

      const metrics = await modelAnalytics.getModelMetrics(modelHash);
      expect(metrics.purchases).to.be.gt(0);
    });
  });

  describe("Training Network Integration", () => {
    it("should record training task completion metrics", async () => {
      const modelHash = ethers.utils.id("testModel");
      const taskId = 1;

      await aiTrainingNetwork.createTrainingTask(modelHash, "Test Task", 100);

      await aiTrainingNetwork.completeTrainingTask(taskId, 95, 150);

      const metrics = await modelAnalytics.getModelMetrics(modelHash);
      expect(metrics.trainingTasks).to.be.gt(0);
    });
  });
});
