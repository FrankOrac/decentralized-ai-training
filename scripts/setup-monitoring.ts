import { ethers } from "hardhat";
import { readFileSync } from "fs";
import { join } from "path";

async function main() {
  const [deployer] = await ethers.getSigners();
  console.log("Setting up monitoring with account:", deployer.address);

  // Load deployment information
  const deploymentInfo = JSON.parse(
    readFileSync(join(__dirname, "..", "deployment.json"), "utf8")
  );

  const monitoringSystem = await ethers.getContractAt(
    "MonitoringSystem",
    deploymentInfo.monitoringSystem
  );

  // Set up initial metrics
  const metrics = [
    { name: "network_latency", type: 1 }, // Gauge
    { name: "transaction_count", type: 0 }, // Counter
    { name: "model_accuracy", type: 1 }, // Gauge
    { name: "resource_usage", type: 1 }, // Gauge
  ];

  for (const metric of metrics) {
    console.log(`Setting up metric: ${metric.name}`);
    await monitoringSystem.recordMetric(metric.name, 0, metric.type);
  }

  // Set up alerts
  const alerts = [
    {
      metricName: "network_latency",
      threshold: 1000, // 1 second
      alertType: 0, // GreaterThan
    },
    {
      metricName: "model_accuracy",
      threshold: 80, // 80%
      alertType: 1, // LessThan
    },
    {
      metricName: "resource_usage",
      threshold: 90, // 90%
      alertType: 0, // GreaterThan
    },
  ];

  for (const alert of alerts) {
    console.log(`Setting up alert for: ${alert.metricName}`);
    await monitoringSystem.createAlert(
      alert.metricName,
      alert.threshold,
      alert.alertType
    );
  }

  // Set up health checks
  const components = [
    "federated_learning",
    "reward_distributor",
    "model_storage",
    "validation_system",
  ];

  for (const component of components) {
    console.log(`Setting up health check for: ${component}`);
    await monitoringSystem.updateHealthStatus(
      component,
      true // initially healthy
    );
  }

  console.log("Monitoring system setup completed successfully");
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
