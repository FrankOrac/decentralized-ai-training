import { ethers } from "ethers";
import { uploadToIPFS } from "../utils/ipfs";

export class TrainingCoordinator {
  private worker: Worker | null = null;
  private currentTask: number | null = null;
  private onProgressCallback: ((progress: number) => void) | null = null;

  constructor(private contract: ethers.Contract, private account: string) {}

  async startTask(taskId: number, onProgress?: (progress: number) => void) {
    if (this.currentTask) {
      throw new Error("Already processing a task");
    }

    this.onProgressCallback = onProgress || null;
    const task = await this.contract.tasks(taskId);

    // Create new worker
    this.worker = new Worker(
      new URL("../workers/trainingWorker.ts", import.meta.url)
    );
    this.currentTask = taskId;

    // Set up message handling
    this.worker.onmessage = async (e) => {
      const { type, data } = e.data;

      switch (type) {
        case "progress":
          this.handleProgress(data);
          break;
        case "complete":
          await this.handleCompletion(data);
          break;
        case "error":
          this.handleError(data);
          break;
      }
    };

    // Start the training
    this.worker.postMessage({
      taskId,
      modelHash: task.modelHash,
      hyperparameters: {
        epochs: 10,
        batchSize: 32,
        learningRate: 0.001,
      },
    });
  }

  private handleProgress(data: any) {
    if (this.onProgressCallback) {
      this.onProgressCallback(data.progress);
    }
  }

  private async handleCompletion(data: any) {
    try {
      // Submit the result to the contract
      const tx = await this.contract.completeTask(
        this.currentTask,
        data.result
      );
      await tx.wait();

      // Clean up
      this.cleanup();
    } catch (error) {
      console.error("Error completing task:", error);
      this.handleError({ error });
    }
  }

  private handleError(data: any) {
    console.error("Training error:", data.error);
    this.cleanup();
  }

  private cleanup() {
    if (this.worker) {
      this.worker.terminate();
      this.worker = null;
    }
    this.currentTask = null;
    this.onProgressCallback = null;
  }

  stop() {
    this.cleanup();
  }
}
