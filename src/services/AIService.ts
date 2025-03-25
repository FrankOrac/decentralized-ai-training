import axios from 'axios';
import { ethers } from 'ethers';

export class AIService {
  private apiKey: string;
  private baseUrl: string;

  constructor(apiKey: string, baseUrl: string) {
    this.apiKey = apiKey;
    this.baseUrl = baseUrl;
  }

  async validateModel(modelHash: string, modelType: string): Promise<{
    isValid: boolean;
    score: number;
    details: any;
  }> {
    try {
      const response = await axios.post(
        `${this.baseUrl}/validate`,
        {
          modelHash,
          modelType,
        },
        {
          headers: {
            'Authorization': `Bearer ${this.apiKey}`,
          },
        }
      );

      return response.data;
    } catch (error) {
      console.error('Error validating model:', error);
      throw error;
    }
  }

  async estimateComputeRequirements(
    modelHash: string,
    modelType: string,
    dataSize: number
  ): Promise<{
    estimatedTime: number;
    requiredMemory: number;
    requiredCompute: number;
    costEstimate: number;
  }> {
    try {
      const response = await axios.post(
        `${this.baseUrl}/estimate`,
        {
          modelHash,
          modelType,
          dataSize,
        },
        {
          headers: {
            'Authorization': `Bearer ${this.apiKey}`,
          },
        }
      );

      return response.data;
    } catch (error) {
      console.error('Error estimating requirements:', error);
      throw error;
    }
  }

  async monitorTraining(taskId: string): Promise<{
    progress: number;
    metrics: any;
    status: string;
  }> {
    try {
      const response = await axios.get(
        `${this.baseUrl}/monitor/${taskId}`,
        {
          headers: {
            'Authorization': `Bearer ${this.apiKey}`,
          },
        }
      );

      return response.data;
    } catch (error) {
      console.error('Error monitoring training:', error);
      throw error;
    }
  }
} 