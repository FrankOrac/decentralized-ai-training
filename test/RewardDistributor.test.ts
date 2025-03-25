import { expect } from "chai";
import { ethers } from "hardhat";
import { SignerWithAddress } from "@nomiclabs/hardhat-ethers/signers";
import { RewardDistributor } from "../typechain-types";

describe("RewardDistributor", function () {
  let rewardDistributor: RewardDistributor;
  let owner: SignerWithAddress;
  let distributor: SignerWithAddress;
  let participant1: SignerWithAddress;
  let participant2: SignerWithAddress;

  const DISTRIBUTOR_ROLE = ethers.utils.keccak256(
    ethers.utils.toUtf8Bytes("DISTRIBUTOR_ROLE")
  );

  beforeEach(async function () {
    [owner, distributor, participant1, participant2] =
      await ethers.getSigners();

    const RewardDistributor = await ethers.getContractFactory(
      "RewardDistributor"
    );
    rewardDistributor = await RewardDistributor.deploy();
    await rewardDistributor.deployed();

    await rewardDistributor.grantRole(DISTRIBUTOR_ROLE, distributor.address);

    // Fund the contract
    await owner.sendTransaction({
      to: rewardDistributor.address,
      value: ethers.utils.parseEther("10.0"),
    });
  });

  describe("Reward Pool Creation", function () {
    it("Should create a new reward pool", async function () {
      const strategy = {
        qualityWeight: 400000,
        participationWeight: 300000,
        reputationWeight: 200000,
        timeWeight: 100000,
        minQualityThreshold: 600000,
        bonusThreshold: 900000,
        bonusMultiplier: 1200000,
      };

      const tx = await rewardDistributor
        .connect(distributor)
        .createRewardPool(ethers.utils.parseEther("1.0"), 3600, strategy);

      const receipt = await tx.wait();
      const event = receipt.events?.find(
        (e) => e.event === "RewardPoolCreated"
      );
      expect(event).to.not.be.undefined;

      const poolId = event?.args?.poolId;
      const details = await rewardDistributor.getPoolDetails(poolId);
      expect(details.totalAmount).to.equal(ethers.utils.parseEther("1.0"));
      expect(details.isActive).to.be.true;
    });
  });

  describe("Contribution Recording", function () {
    let poolId: string;

    beforeEach(async function () {
      const strategy = {
        qualityWeight: 400000,
        participationWeight: 300000,
        reputationWeight: 200000,
        timeWeight: 100000,
        minQualityThreshold: 600000,
        bonusThreshold: 900000,
        bonusMultiplier: 1200000,
      };

      const tx = await rewardDistributor
        .connect(distributor)
        .createRewardPool(ethers.utils.parseEther("1.0"), 3600, strategy);
      const receipt = await tx.wait();
      poolId = receipt.events?.find((e) => e.event === "RewardPoolCreated")
        ?.args?.poolId;
    });

    it("Should record participant contributions", async function () {
      await rewardDistributor.connect(distributor).recordContribution(
        poolId,
        participant1.address,
        800000, // qualityScore
        1000 // participationValue
      );

      const score = await rewardDistributor.getParticipantScore(
        poolId,
        participant1.address
      );
      expect(score.qualityScore).to.equal(800000);
      expect(score.participationScore).to.equal(1000);
    });
  });

  describe("Score Calculation and Reward Distribution", function () {
    let poolId: string;

    beforeEach(async function () {
      const strategy = {
        qualityWeight: 400000,
        participationWeight: 300000,
        reputationWeight: 200000,
        timeWeight: 100000,
        minQualityThreshold: 600000,
        bonusThreshold: 900000,
        bonusMultiplier: 1200000,
      };

      const tx = await rewardDistributor
        .connect(distributor)
        .createRewardPool(ethers.utils.parseEther("1.0"), 3600, strategy);
      const receipt = await tx.wait();
      poolId = receipt.events?.find((e) => e.event === "RewardPoolCreated")
        ?.args?.poolId;

      // Record contributions
      await rewardDistributor
        .connect(distributor)
        .recordContribution(poolId, participant1.address, 800000, 1000);
      await rewardDistributor
        .connect(distributor)
        .recordContribution(poolId, participant2.address, 700000, 800);
    });

    it("Should calculate scores correctly", async function () {
      await rewardDistributor.connect(distributor).calculateScores(poolId);

      const score1 = await rewardDistributor.getParticipantScore(
        poolId,
        participant1.address
      );
      const score2 = await rewardDistributor.getParticipantScore(
        poolId,
        participant2.address
      );

      expect(score1.isCalculated).to.be.true;
      expect(score2.isCalculated).to.be.true;
      expect(score1.totalScore).to.be.gt(score2.totalScore);
    });

    it("Should distribute rewards fairly", async function () {
      await rewardDistributor.connect(distributor).calculateScores(poolId);

      // Fast forward time
      await ethers.provider.send("evm_increaseTime", [3600]);
      await ethers.provider.send("evm_mine", []);

      const initialBalance = await participant1.getBalance();

      await rewardDistributor.connect(participant1).claimReward(poolId);

      const finalBalance = await participant1.getBalance();
      expect(finalBalance).to.be.gt(initialBalance);
    });
  });

  describe("Pool Finalization", function () {
    let poolId: string;

    beforeEach(async function () {
      const strategy = {
        qualityWeight: 400000,
        participationWeight: 300000,
        reputationWeight: 200000,
        timeWeight: 100000,
        minQualityThreshold: 600000,
        bonusThreshold: 900000,
        bonusMultiplier: 1200000,
      };

      const tx = await rewardDistributor
        .connect(distributor)
        .createRewardPool(ethers.utils.parseEther("1.0"), 3600, strategy);
      const receipt = await tx.wait();
      poolId = receipt.events?.find((e) => e.event === "RewardPoolCreated")
        ?.args?.poolId;
    });

    it("Should finalize pool correctly", async function () {
      // Fast forward time
      await ethers.provider.send("evm_increaseTime", [3600]);
      await ethers.provider.send("evm_mine", []);

      await rewardDistributor.connect(distributor).finalizePool(poolId);

      const details = await rewardDistributor.getPoolDetails(poolId);
      expect(details.isActive).to.be.false;
    });
  });
});
