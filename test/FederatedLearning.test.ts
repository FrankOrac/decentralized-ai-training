import { expect } from "chai";
import { ethers } from "hardhat";
import { SignerWithAddress } from "@nomiclabs/hardhat-ethers/signers";
import { FederatedLearning } from "../typechain-types";

describe("FederatedLearning", function () {
  let federatedLearning: FederatedLearning;
  let owner: SignerWithAddress;
  let coordinator: SignerWithAddress;
  let participant1: SignerWithAddress;
  let participant2: SignerWithAddress;

  const COORDINATOR_ROLE = ethers.utils.keccak256(
    ethers.utils.toUtf8Bytes("COORDINATOR_ROLE")
  );
  const PARTICIPANT_ROLE = ethers.utils.keccak256(
    ethers.utils.toUtf8Bytes("PARTICIPANT_ROLE")
  );

  beforeEach(async function () {
    [owner, coordinator, participant1, participant2] =
      await ethers.getSigners();

    const FederatedLearning = await ethers.getContractFactory(
      "FederatedLearning"
    );
    federatedLearning = await FederatedLearning.deploy(
      3600, // roundDuration
      0, // minReputation
      ethers.utils.parseEther("0.1"), // baseReward
      2 // validationThreshold
    );
    await federatedLearning.deployed();

    // Grant roles
    await federatedLearning.grantRole(COORDINATOR_ROLE, coordinator.address);
    await federatedLearning.grantRole(PARTICIPANT_ROLE, participant1.address);
    await federatedLearning.grantRole(PARTICIPANT_ROLE, participant2.address);
  });

  describe("Round Creation and Participation", function () {
    it("Should create a new training round", async function () {
      const tx = await federatedLearning
        .connect(coordinator)
        .createRound("QmTestModel", "FedAvg", 2, 5);

      const receipt = await tx.wait();
      const event = receipt.events?.find((e) => e.event === "RoundCreated");
      expect(event).to.not.be.undefined;

      const roundId = event?.args?.roundId;
      const details = await federatedLearning.getRoundDetails(roundId);
      expect(details.globalModelHash).to.equal("QmTestModel");
      expect(details.minParticipants).to.equal(2);
    });

    it("Should allow participants to join round", async function () {
      const tx = await federatedLearning
        .connect(coordinator)
        .createRound("QmTestModel", "FedAvg", 2, 5);
      const receipt = await tx.wait();
      const roundId = receipt.events?.find((e) => e.event === "RoundCreated")
        ?.args?.roundId;

      await federatedLearning.connect(participant1).joinRound(roundId);
      const details = await federatedLearning.getRoundDetails(roundId);
      expect(details.participants).to.include(participant1.address);
    });
  });

  describe("Update Submission and Validation", function () {
    let roundId: string;

    beforeEach(async function () {
      const tx = await federatedLearning
        .connect(coordinator)
        .createRound("QmTestModel", "FedAvg", 2, 5);
      const receipt = await tx.wait();
      roundId = receipt.events?.find((e) => e.event === "RoundCreated")?.args
        ?.roundId;

      await federatedLearning.connect(participant1).joinRound(roundId);
      await federatedLearning.connect(participant2).joinRound(roundId);
    });

    it("Should accept valid local updates", async function () {
      const messageHash = ethers.utils.solidityKeccak256(
        ["bytes32", "string", "uint256", "uint256"],
        [roundId, "QmLocalUpdate1", 1000, 60]
      );
      const signature = await participant1.signMessage(
        ethers.utils.arrayify(messageHash)
      );

      await federatedLearning
        .connect(participant1)
        .submitUpdate(roundId, "QmLocalUpdate1", 1000, 60, signature);

      const update = await federatedLearning.getUpdateDetails(
        roundId,
        participant1.address
      );
      expect(update.modelHash).to.equal("QmLocalUpdate1");
      expect(update.isValid).to.be.true;
    });

    it("Should validate updates correctly", async function () {
      // Submit updates
      const messageHash1 = ethers.utils.solidityKeccak256(
        ["bytes32", "string", "uint256", "uint256"],
        [roundId, "QmLocalUpdate1", 1000, 60]
      );
      const signature1 = await participant1.signMessage(
        ethers.utils.arrayify(messageHash1)
      );

      await federatedLearning
        .connect(participant1)
        .submitUpdate(roundId, "QmLocalUpdate1", 1000, 60, signature1);

      // Validate updates
      await federatedLearning
        .connect(coordinator)
        .validateUpdate(roundId, participant1.address, true, 95);

      const update = await federatedLearning.getUpdateDetails(
        roundId,
        participant1.address
      );
      expect(update.score).to.equal(95);
    });
  });

  describe("Reward Distribution", function () {
    let roundId: string;

    beforeEach(async function () {
      const tx = await federatedLearning
        .connect(coordinator)
        .createRound("QmTestModel", "FedAvg", 2, 5);
      const receipt = await tx.wait();
      roundId = receipt.events?.find((e) => e.event === "RoundCreated")?.args
        ?.roundId;

      await federatedLearning.connect(participant1).joinRound(roundId);
      await federatedLearning.connect(participant2).joinRound(roundId);
    });

    it("Should distribute rewards after successful validation", async function () {
      // Submit and validate updates
      const messageHash1 = ethers.utils.solidityKeccak256(
        ["bytes32", "string", "uint256", "uint256"],
        [roundId, "QmLocalUpdate1", 1000, 60]
      );
      const signature1 = await participant1.signMessage(
        ethers.utils.arrayify(messageHash1)
      );

      await federatedLearning
        .connect(participant1)
        .submitUpdate(roundId, "QmLocalUpdate1", 1000, 60, signature1);

      const initialBalance = await participant1.getBalance();

      await federatedLearning
        .connect(coordinator)
        .validateUpdate(roundId, participant1.address, true, 95);

      const finalBalance = await participant1.getBalance();
      expect(finalBalance).to.be.gt(initialBalance);
    });
  });
});
