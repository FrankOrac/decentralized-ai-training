import React, { useState, useEffect, useCallback } from "react";
import {
  Box,
  VStack,
  HStack,
  Text,
  Button,
  useToast,
  Spinner,
  Badge,
  Tooltip,
  Progress,
  Modal,
  ModalOverlay,
  ModalContent,
  ModalHeader,
  ModalBody,
  ModalCloseButton,
} from "@chakra-ui/react";
import {
  ResponsiveContainer,
  Sankey,
  Tooltip as RechartsTooltip,
  Rectangle,
  FlowMap,
} from "recharts";
import ReactFlow, {
  Handle,
  Position,
  MarkerType,
  Edge,
  Node,
} from "react-flow-renderer";
import { format } from "date-fns";
import { useContract } from "../hooks/useContract";
import { ethers } from "ethers";

interface WorkflowNode {
  id: string;
  type: "step" | "approval" | "execution";
  data: {
    label: string;
    status: string;
    timestamp: number;
    details: any;
  };
  position: { x: number; y: number };
}

interface WorkflowData {
  id: string;
  name: string;
  status: string;
  currentStep: number;
  createdAt: number;
  completedAt: number;
  steps: any[];
  executions: any[];
}

const CustomNode: React.FC<{ data: any }> = ({ data }) => {
  const getStatusColor = (status: string) => {
    switch (status) {
      case "completed":
        return "green.500";
      case "pending":
        return "yellow.500";
      case "failed":
        return "red.500";
      default:
        return "gray.500";
    }
  };

  return (
    <Box
      p={3}
      bg="white"
      borderWidth={2}
      borderColor={getStatusColor(data.status)}
      borderRadius="md"
      shadow="md"
    >
      <Handle type="target" position={Position.Left} />
      <VStack spacing={2} align="start">
        <Text fontWeight="bold">{data.label}</Text>
        <Badge colorScheme={data.status === "completed" ? "green" : "yellow"}>
          {data.status}
        </Badge>
        {data.timestamp && (
          <Text fontSize="sm" color="gray.500">
            {format(data.timestamp * 1000, "yyyy-MM-dd HH:mm:ss")}
          </Text>
        )}
      </VStack>
      <Handle type="source" position={Position.Right} />
    </Box>
  );
};

export const WorkflowVisualizer: React.FC = () => {
  const [workflows, setWorkflows] = useState<WorkflowData[]>([]);
  const [selectedWorkflow, setSelectedWorkflow] = useState<string | null>(null);
  const [nodes, setNodes] = useState<Node[]>([]);
  const [edges, setEdges] = useState<Edge[]>([]);
  const [loading, setLoading] = useState(true);
  const [isModalOpen, setIsModalOpen] = useState(false);
  const [modalData, setModalData] = useState<any>(null);

  const toast = useToast();
  const { contract } = useContract("AutomatedWorkflow");

  const fetchWorkflowData = useCallback(async () => {
    try {
      setLoading(true);
      const filter = contract.filters.WorkflowCreated();
      const events = await contract.queryFilter(filter, -10000);

      const workflowData = await Promise.all(
        events.map(async (event) => {
          const workflow = await contract.workflows(event.args.workflowId);
          const steps = await contract.getWorkflowSteps(event.args.workflowId);

          const stepData = await Promise.all(
            steps.map(async (stepId: string) => {
              const step = await contract.workflowSteps(stepId);
              const executions = await contract.getStepExecutions(stepId);
              return { ...step, executions };
            })
          );

          return {
            id: event.args.workflowId,
            name: workflow.name,
            status: WorkflowStatus[workflow.status],
            currentStep: workflow.currentStep.toNumber(),
            createdAt: workflow.createdAt.toNumber(),
            completedAt: workflow.completedAt.toNumber(),
            steps: stepData,
            executions: stepData.map((s) => s.executions).flat(),
          };
        })
      );

      setWorkflows(workflowData);
      if (selectedWorkflow) {
        generateGraph(workflowData.find((w) => w.id === selectedWorkflow));
      }
      setLoading(false);
    } catch (error) {
      console.error("Error fetching workflow data:", error);
      toast({
        title: "Error",
        description: "Failed to fetch workflow data",
        status: "error",
        duration: 5000,
      });
      setLoading(false);
    }
  }, [contract, selectedWorkflow, toast]);

  useEffect(() => {
    fetchWorkflowData();
    const interval = setInterval(fetchWorkflowData, 30000);
    return () => clearInterval(interval);
  }, [fetchWorkflowData]);

  const generateGraph = (workflow: WorkflowData) => {
    if (!workflow) return;

    const newNodes: Node[] = [];
    const newEdges: Edge[] = [];
    let xPosition = 0;
    let yPosition = 0;

    // Add start node
    newNodes.push({
      id: "start",
      type: "default",
      data: {
        label: "Start",
        status: "completed",
        timestamp: workflow.createdAt,
      },
      position: { x: xPosition, y: yPosition },
    });

    xPosition += 200;

    // Add step nodes
    workflow.steps.forEach((step, index) => {
      const stepNode: WorkflowNode = {
        id: `step-${step.id}`,
        type: "step",
        data: {
          label: step.name,
          status:
            index < workflow.currentStep
              ? "completed"
              : index === workflow.currentStep
              ? "pending"
              : "waiting",
          timestamp: step.executions[0]?.timestamp || null,
          details: step,
        },
        position: { x: xPosition, y: yPosition },
      };
      newNodes.push(stepNode);

      // Add edge from previous node
      newEdges.push({
        id: `edge-${index}`,
        source: index === 0 ? "start" : `step-${workflow.steps[index - 1].id}`,
        target: `step-${step.id}`,
        type: "smoothstep",
        markerEnd: { type: MarkerType.ArrowClosed },
      });

      // If step requires approval, add approval node
      if (step.requiresHumanApproval) {
        yPosition += 100;
        const approvalNode: WorkflowNode = {
          id: `approval-${step.id}`,
          type: "approval",
          data: {
            label: "Approval Required",
            status: step.approvals ? "completed" : "pending",
            timestamp: null,
            details: step,
          },
          position: { x: xPosition, y: yPosition },
        };
        newNodes.push(approvalNode);
        newEdges.push({
          id: `edge-approval-${index}`,
          source: `step-${step.id}`,
          target: `approval-${step.id}`,
          type: "smoothstep",
          markerEnd: { type: MarkerType.ArrowClosed },
        });
        yPosition -= 100;
      }

      xPosition += 200;
    });

    // Add end node
    newNodes.push({
      id: "end",
      type: "default",
      data: {
        label: "End",
        status: workflow.status === "Completed" ? "completed" : "waiting",
        timestamp: workflow.completedAt || null,
      },
      position: { x: xPosition, y: yPosition },
    });

    // Add final edge
    newEdges.push({
      id: "edge-final",
      source: `step-${workflow.steps[workflow.steps.length - 1].id}`,
      target: "end",
      type: "smoothstep",
      markerEnd: { type: MarkerType.ArrowClosed },
    });

    setNodes(newNodes);
    setEdges(newEdges);
  };

  const handleNodeClick = (node: Node) => {
    if (node.type === "step" || node.type === "approval") {
      setModalData(node.data.details);
      setIsModalOpen(true);
    }
  };

  return (
    <Box p={6}>
      <VStack spacing={6} align="stretch">
        <HStack justify="space-between">
          <Text fontSize="2xl" fontWeight="bold">
            Workflow Visualizer
          </Text>
          <Select
            value={selectedWorkflow || ""}
            onChange={(e) => setSelectedWorkflow(e.target.value)}
            w="300px"
          >
            <option value="">Select Workflow</option>
            {workflows.map((workflow) => (
              <option key={workflow.id} value={workflow.id}>
                {workflow.name} ({workflow.status})
              </option>
            ))}
          </Select>
        </HStack>

        {loading ? (
          <Box textAlign="center" py={10}>
            <Spinner size="xl" />
          </Box>
        ) : selectedWorkflow ? (
          <Box
            h="600px"
            border="1px solid"
            borderColor="gray.200"
            borderRadius="md"
          >
            <ReactFlow
              nodes={nodes}
              edges={edges}
              onNodeClick={(_, node) => handleNodeClick(node)}
              nodeTypes={{ step: CustomNode }}
              fitView
            >
              <RechartsTooltip />
            </ReactFlow>
          </Box>
        ) : (
          <Text textAlign="center">Select a workflow to visualize</Text>
        )}

        <Modal
          isOpen={isModalOpen}
          onClose={() => setIsModalOpen(false)}
          size="xl"
        >
          <ModalOverlay />
          <ModalContent>
            <ModalHeader>Step Details</ModalHeader>
            <ModalCloseButton />
            <ModalBody>
              {modalData && (
                <VStack align="stretch" spacing={4}>
                  <Text>
                    <strong>Name:</strong> {modalData.name}
                  </Text>
                  <Text>
                    <strong>Target Contract:</strong> {modalData.targetContract}
                  </Text>
                  <Text>
                    <strong>Required Approvals:</strong>{" "}
                    {modalData.requiredApprovals}
                  </Text>
                  <Text>
                    <strong>Status:</strong> {modalData.status}
                  </Text>
                  {modalData.executions.length > 0 && (
                    <Box>
                      <Text fontWeight="bold" mb={2}>
                        Executions:
                      </Text>
                      <VStack align="stretch">
                        {modalData.executions.map(
                          (execution: any, index: number) => (
                            <Box
                              key={index}
                              p={3}
                              borderWidth={1}
                              borderRadius="md"
                            >
                              <Text>
                                Result:{" "}
                                {execution.success ? "Success" : "Failed"}
                              </Text>
                              <Text>Executor: {execution.executor}</Text>
                              <Text>
                                Time:{" "}
                                {format(
                                  execution.timestamp * 1000,
                                  "yyyy-MM-dd HH:mm:ss"
                                )}
                              </Text>
                            </Box>
                          )
                        )}
                      </VStack>
                    </Box>
                  )}
                </VStack>
              )}
            </ModalBody>
          </ModalContent>
        </Modal>
      </VStack>
    </Box>
  );
};
