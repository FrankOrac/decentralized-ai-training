export interface Task {
  id: number;
  modelHash: string;
  reward: string;
  creator: string;
  status: number;
  deadline: number;
}

export enum TaskStatus {
  Open,
  InProgress,
  Completed,
  Failed,
}
