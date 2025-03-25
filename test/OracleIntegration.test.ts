import { expect } from "chai";
import { ethers } from "hardhat";
import { SignerWithAddress } from "@nomiclabs/hardhat-ethers/signers";
import {
  OracleIntegration,
  MockChainlinkAggregator,
  MockAirnodeRrp,
  MockUmaOracle,
} from "../typechain";

describe("OracleIntegration", () => {
  let oracleIntegration: OracleIntegration;
  let mockChainlink: MockChainlinkAggregator;
  let mockAirnode: MockAirnodeRrp;
  let mockUma: MockUmaOracle;
  let owner: SignerWithAddress;
  let admin: SignerWithAddress;
  let requester: SignerWithAddress;
  let users: SignerWithAddress[];

  beforeEach(async () => {
    [owner, admin, requester, ...users] = await ethers.getSigners();

    // Deploy mock oracles
    const MockChainlink = await ethers.getContractFactory(
      "MockChainlinkAggregator"
    );
    mockChainlink = await MockChainlink.deploy();
    await mockChainlink.deployed();

    const MockAirnode = await ethers.getContractFactory("MockAirnodeRrp");
    mockAirnode = await MockAirnode.deploy();
    await mockAirnode.deployed();

    const MockUma = await ethers.getContractFactory("MockUmaOracle");
    mockUma = await MockUma.deploy();
    await mockUma.deployed();

    // Deploy oracle integration
    const OracleIntegration = await ethers.getContractFactory(
      "OracleIntegration"
    );
    oracleIntegration = await OracleIntegration.deploy(
      mockAirnode.address,
      mockUma.address
    );
    await oracleIntegration.deployed();

    // Setup roles
    await oracleIntegration.grantRole(
      ethers.utils.keccak256(ethers.utils.toUtf8Bytes("ORACLE_ADMIN")),
      admin.address
    );
    await oracleIntegration.grantRole(
      ethers.utils.keccak256(ethers.utils.toUtf8Bytes("REQUESTER_ROLE")),
      requester.address
    );
  });

  describe("Oracle Configuration", () => {
    it("should allow admin to configure oracle", async () => {
      const oracleType = "chainlink";
      const jobId = ethers.utils.formatBytes32String("jobId");
      const fee = ethers.utils.parseEther("0.1");

      await expect(
        oracleIntegration
          .connect(admin)
          .configureOracle(oracleType, mockChainlink.address, jobId, fee)
      )
        .to.emit(oracleIntegration, "OracleConfigured")
        .withArgs(oracleType, mockChainlink.address, jobId);

      const config = await oracleIntegration.oracleConfigs(oracleType);
      expect(config.oracleAddress).to.equal(mockChainlink.address);
      expect(config.jobId).to.equal(jobId);
      expect(config.fee).to.equal(fee);
      expect(config.isActive).to.be.true;
    });

    it("should revert when non-admin tries to configure oracle", async () => {
      await expect(
        oracleIntegration
          .connect(users[0])
          .configureOracle(
            "chainlink",
            mockChainlink.address,
            ethers.utils.formatBytes32String("jobId"),
            ethers.utils.parseEther("0.1")
          )
      ).to.be.revertedWith("AccessControl");
    });
  });

  describe("Data Requests", () => {
    beforeEach(async () => {
      // Configure oracles
      await oracleIntegration
        .connect(admin)
        .configureOracle(
          "chainlink",
          mockChainlink.address,
          ethers.utils.formatBytes32String("jobId"),
          ethers.utils.parseEther("0.1")
        );

      await oracleIntegration
        .connect(admin)
        .configureOracle(
          "api3",
          mockAirnode.address,
          ethers.utils.formatBytes32String("jobId"),
          ethers.utils.parseEther("0.1")
        );

      await oracleIntegration
        .connect(admin)
        .configureOracle(
          "uma",
          mockUma.address,
          ethers.utils.formatBytes32String("jobId"),
          ethers.utils.parseEther("0.1")
        );
    });

    it("should request Chainlink price feed data", async () => {
      const dataType = "PRICE_FEED";
      const parameters = ethers.utils.defaultAbiCoder.encode(
        ["string", "string"],
        ["ETH", "USD"]
      );

      await expect(
        oracleIntegration.connect(requester).requestData(dataType, parameters)
      )
        .to.emit(oracleIntegration, "OracleRequestSent")
        .withArgs(
          ethers.utils.keccak256(
            ethers.utils.defaultAbiCoder.encode(
              ["string", "bytes", "uint256", "address"],
              [
                dataType,
                parameters,
                await ethers.provider
                  .getBlock("latest")
                  .then((b) => b.timestamp),
                requester.address,
              ]
            )
          ),
          dataType,
          requester.address
        );
    });

    it("should request API3 off-chain data", async () => {
      const dataType = "OFF_CHAIN_DATA";
      const parameters = ethers.utils.defaultAbiCoder.encode(
        ["address", "bytes32"],
        [mockAirnode.address, ethers.utils.formatBytes32String("endpointId")]
      );

      await expect(
        oracleIntegration.connect(requester).requestData(dataType, parameters)
      ).to.emit(oracleIntegration, "OracleRequestSent");
    });

    it("should request UMA dispute resolution", async () => {
      const dataType = "DISPUTE_RESOLUTION";
      const parameters = ethers.utils.defaultAbiCoder.encode(
        ["string"],
        ["Dispute data"]
      );

      await expect(
        oracleIntegration.connect(requester).requestData(dataType, parameters)
      ).to.emit(oracleIntegration, "OracleRequestSent");
    });
  });

  describe("Request Fulfillment", () => {
    let requestId: string;

    beforeEach(async () => {
      // Configure oracle and make request
      await oracleIntegration
        .connect(admin)
        .configureOracle(
          "chainlink",
          mockChainlink.address,
          ethers.utils.formatBytes32String("jobId"),
          ethers.utils.parseEther("0.1")
        );

      const tx = await oracleIntegration
        .connect(requester)
        .requestData(
          "PRICE_FEED",
          ethers.utils.defaultAbiCoder.encode(
            ["string", "string"],
            ["ETH", "USD"]
          )
        );
      const receipt = await tx.wait();
      requestId = receipt.events?.find((e) => e.event === "OracleRequestSent")
        ?.args?.requestId;
    });

    it("should fulfill request with result", async () => {
      const result = ethers.utils.defaultAbiCoder.encode(["uint256"], [1500]);

      await expect(mockChainlink.fulfillRequest(requestId, result))
        .to.emit(oracleIntegration, "OracleResponseReceived")
        .withArgs(requestId, result);

      const request = await oracleIntegration.requests(requestId);
      expect(request.fulfilled).to.be.true;
      expect(request.result).to.equal(result);
    });

    it("should allow dispute within period", async () => {
      const result = ethers.utils.defaultAbiCoder.encode(["uint256"], [1500]);
      await mockChainlink.fulfillRequest(requestId, result);

      await expect(
        oracleIntegration
          .connect(users[0])
          .raiseDispute(requestId, "Invalid price")
      )
        .to.emit(oracleIntegration, "DisputeRaised")
        .withArgs(requestId, users[0].address, "Invalid price");
    });
  });

  describe("Request Retrieval", () => {
    it("should return requests by data type", async () => {
      // Make multiple requests
      const dataType = "PRICE_FEED";
      const parameters = ethers.utils.defaultAbiCoder.encode(
        ["string", "string"],
        ["ETH", "USD"]
      );

      await oracleIntegration
        .connect(admin)
        .configureOracle(
          "chainlink",
          mockChainlink.address,
          ethers.utils.formatBytes32String("jobId"),
          ethers.utils.parseEther("0.1")
        );

      await oracleIntegration
        .connect(requester)
        .requestData(dataType, parameters);
      await oracleIntegration
        .connect(requester)
        .requestData(dataType, parameters);

      const requests = await oracleIntegration.getRequestsByDataType(dataType);
      expect(requests.length).to.equal(2);
    });
  });
});
