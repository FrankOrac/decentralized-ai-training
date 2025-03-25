import { ethers } from "hardhat";
import { writeFileSync } from "fs";
import { join } from "path";
import { configs } from "./deploy-config";

async function main() {
  const network = await ethers.provider.getNetwork();
  const networkName = network.name;
  const config = configs[networkName];

  if (!config) {
    throw new Error(`No configuration found for network: ${networkName}`);
  }

  console.log(`Deploying to ${networkName} with config:`, config);

  const [deployer] = await ethers.getSigners();
  console.log("Deploying contracts with account:", deployer.address);

  // Deploy GovernanceSystem
  const GovernanceSystem = await ethers.getContractFactory("GovernanceSystem");
  const governanceSystem = await GovernanceSystem.deploy();
  await governanceSystem.deployed();
  console.log("GovernanceSystem deployed to:", governanceSystem.address);

  // Initialize parameters
  const tx = await governanceSystem.updateParameters({
    votingPeriod: config.votingPeriod,
    votingDelay: config.votingDelay,
    proposalThreshold: ethers.utils.parseEther(config.proposalThreshold),
    quorumPercentage: config.quorumPercentage,
    executionDelay: config.executionDelay,
  });
  await tx.wait();
  console.log("Parameters initialized");

  // Save deployment information
  const deploymentInfo = {
    network: networkName,
    governanceSystem: governanceSystem.address,
    deployer: deployer.address,
    parameters: config,
    timestamp: new Date().toISOString(),
  };

  const deploymentPath = join(__dirname, "..", "deployments");
  writeFileSync(
    join(deploymentPath, `${networkName}.json`),
    JSON.stringify(deploymentInfo, null, 2)
  );

  // Verify contract if configured
  if (config.verifyContract && process.env.ETHERSCAN_API_KEY) {
    console.log("Waiting for block confirmations...");
    await governanceSystem.deployTransaction.wait(6);

    console.log("Verifying contract...");
    try {
      await hre.run("verify:verify", {
        address: governanceSystem.address,
        constructorArguments: [],
      });
    } catch (error) {
      console.error("Error verifying contract:", error);
    }
  }

  console.log("Deployment completed successfully");
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
