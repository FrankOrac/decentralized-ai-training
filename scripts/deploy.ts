import { ethers } from "hardhat";
import { writeFileSync } from 'fs';
import { join } from 'path';

async function main() {
  const [deployer] = await ethers.getSigners();
  console.log("Deploying contracts with the account:", deployer.address);

  // Deploy MonitoringSystem
  const MonitoringSystem = await ethers.getContractFactory("MonitoringSystem");
  const monitoringSystem = await MonitoringSystem.deploy();
  await monitoringSystem.deployed();
  console.log("MonitoringSystem deployed to:", monitoringSystem.address);

  // Deploy FederatedLearning
  const FederatedLearning = await ethers.getContractFactory("FederatedLearning");
  const federatedLearning = await FederatedLearning.deploy(
    3600, // roundDuration
    0,    // minReputation
    ethers.utils.parseEther("0.1"), // baseReward
    2     // validationThreshold
  );
  await federatedLearning.deployed();
  console.log("FederatedLearning deployed to:", federatedLearning.address);

  // Deploy RewardDistributor
  const RewardDistributor = await ethers.getContractFactory("RewardDistributor");
  const rewardDistributor = await RewardDistributor.deploy();
  await rewardDistributor.deployed();
  console.log("RewardDistributor deployed to:", rewardDistributor.address);

  // Save deployment information
  const deploymentInfo = {
    monitoringSystem: monitoringSystem.address,
    federatedLearning: federatedLearning.address,
    rewardDistributor: rewardDistributor.address,
    network: network.name,
    timestamp: new Date().toISOString(),
    deployer: deployer.address
  };

  writeFileSync(
    join(__dirname, '..', 'deployment.json'),
    JSON.stringify(deploymentInfo, null, 2)
  );

  // Verify contracts on Etherscan if not on local network
  if (network.name !== "hardhat" && network.name !== "localhost") {
    console.log("Waiting for block confirmations...");
    
    await monitoringSystem.deployTransaction.wait(6);
    await federatedLearning.deployTransaction.wait(6);
    await rewardDistributor.deployTransaction.wait(6);

    await hre.run("verify:verify", {
      address: monitoringSystem.address,
      constructorArguments: []
    });

    await hre.run("verify:verify", {
      address: federatedLearning.address,
      constructorArguments: [3600, 0, ethers.utils.parseEther("0.1"), 2]
    });

    await hre.run("verify:verify", {
      address: rewardDistributor.address,
      constructorArguments: []
    });
  }

  console.log("Deployment completed successfully");
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  }); 