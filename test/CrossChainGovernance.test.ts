import { expect } from "chai";
import { ethers } from "hardhat";
import { SignerWithAddress } from "@nomiclabs/hardhat-ethers/signers";
import { CrossChainGovernance } from "../typechain/CrossChainGovernance";
import { MockLayerZeroEndpoint } from "../typechain/MockLayerZeroEndpoint";

describe("CrossChainGovernance", () => {
  let governance: CrossChainGovernance;
  let mockEndpoint: MockLayerZeroEndpoint;
  let owner: SignerWithAddress;
  let admin: SignerWithAddress;
  let users: SignerWithAddress[];

  beforeEach(async () => {
    [owner, admin, ...users] = await ethers.getSigners();

    // Deploy mock LayerZero endpoint
    const MockEndpoint = await ethers.getContractFactory(
      "MockLayerZeroEndpoint"
    );
    mockEndpoint = await MockEndpoint.deploy();
    await mockEndpoint.deployed();

    // Deploy governance contract
    const Governance = await ethers.getContractFactory("CrossChainGovernance");
    governance = await Governance.deploy(mockEndpoint.address);
    await governance.deployed();

    // Setup roles
    await governance.grantRole(
      ethers.utils.keccak256(ethers.utils.toUtf8Bytes("GOVERNANCE_ADMIN")),
      admin.address
    );
  });

  describe("Chain Configuration", () => {
    it("should allow admin to configure chain", async () => {
      const chainId = 1;
      const governanceContract = ethers.Wallet.createRandom().address;
      const trustScore = 80;

      await expect(
        governance
          .connect(admin)
          .configureChain(chainId, governanceContract, trustScore)
      )
        .to.emit(governance, "ChainConfigured")
        .withArgs(chainId, governanceContract, trustScore);

      const config = await governance.chainConfigs(chainId);
      expect(config.chainId).to.equal(chainId);
      expect(config.governanceContract).to.equal(governanceContract);
      expect(config.trustScore).to.equal(trustScore);
      expect(config.isActive).to.be.true;
    });

    it("should revert when non-admin tries to configure chain", async () => {
      await expect(
        governance
          .connect(users[0])
          .configureChain(1, ethers.constants.AddressZero, 80)
      ).to.be.revertedWith("AccessControl");
    });
  });

  describe("Cross-Chain Proposal Creation", () => {
    it("should create proposal and notify other chains", async () => {
      const title = "Test Proposal";
      const actions = [ethers.utils.randomBytes(32)];
      const targets = [ethers.Wallet.createRandom().address];
      const values = [ethers.utils.parseEther("1")];
      const votingPeriod = 86400; // 1 day

      await expect(
        governance.createCrossChainProposal(
          title,
          actions,
          targets,
          values,
          votingPeriod
        )
      ).to.emit(governance, "CrossChainProposalCreated");

      // Verify proposal details
      const proposalId = ethers.utils.keccak256(
        ethers.utils.defaultAbiCoder.encode(
          ["string", "address", "uint256"],
          [
            title,
            owner.address,
            await ethers.provider.getBlock("latest").then((b) => b.timestamp),
          ]
        )
      );

      const proposal = await governance.proposals(proposalId);
      expect(proposal.title).to.equal(title);
      expect(proposal.proposer).to.equal(owner.address);
    });
  });

  describe("Cross-Chain Voting", () => {
    let proposalId: string;

    beforeEach(async () => {
      // Create a proposal
      const tx = await governance.createCrossChainProposal(
        "Test",
        [ethers.utils.randomBytes(32)],
        [ethers.Wallet.createRandom().address],
        [0],
        86400
      );
      const receipt = await tx.wait();
      proposalId = receipt.events?.find(
        (e) => e.event === "CrossChainProposalCreated"
      )?.args?.proposalId;
    });

    it("should receive votes from other chains", async () => {
      const sourceChain = 1;
      const votes = ethers.utils.parseEther("100");

      // Configure source chain
      await governance
        .connect(admin)
        .configureChain(sourceChain, ethers.Wallet.createRandom().address, 80);

      const payload = ethers.utils.defaultAbiCoder.encode(
        ["bytes32", "uint256"],
        [proposalId, votes]
      );

      await expect(
        governance.connect(admin).receiveCrossChainVote(sourceChain, payload)
      )
        .to.emit(governance, "CrossChainVoteReceived")
        .withArgs(proposalId, sourceChain, votes);
    });
  });

  describe("Proposal Execution", () => {
    let proposalId: string;

    beforeEach(async () => {
      // Create and setup proposal
      const tx = await governance.createCrossChainProposal(
        "Test",
        [ethers.utils.randomBytes(32)],
        [ethers.Wallet.createRandom().address],
        [0],
        86400
      );
      const receipt = await tx.wait();
      proposalId = receipt.events?.find(
        (e) => e.event === "CrossChainProposalCreated"
      )?.args?.proposalId;
    });

    it("should execute proposal after delay and sufficient votes", async () => {
      // Add votes from different chains
      const chains = [1, 2, 3];
      for (const chainId of chains) {
        await governance
          .connect(admin)
          .configureChain(chainId, ethers.Wallet.createRandom().address, 80);

        const payload = ethers.utils.defaultAbiCoder.encode(
          ["bytes32", "uint256"],
          [proposalId, ethers.utils.parseEther("100")]
        );
        await governance.connect(admin).receiveCrossChainVote(chainId, payload);
      }

      // Advance time
      await ethers.provider.send("evm_increaseTime", [86400 * 3]); // 3 days
      await ethers.provider.send("evm_mine", []);

      await expect(governance.executeProposal(proposalId))
        .to.emit(governance, "ProposalExecuted")
        .withArgs(proposalId);
    });
  });
});
