// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";

contract AutomatedWorkflow is AccessControl, ReentrancyGuard {
    using EnumerableSet for EnumerableSet.Bytes32Set;

    bytes32 public constant WORKFLOW_ADMIN = keccak256("WORKFLOW_ADMIN");
    bytes32 public constant EXECUTOR_ROLE = keccak256("EXECUTOR_ROLE");

    struct WorkflowStep {
        bytes32 id;
        string name;
        bytes actionData;
        address targetContract;
        uint256 requiredApprovals;
        bool isActive;
        bool requiresHumanApproval;
        mapping(address => bool) approvals;
    }

    struct Workflow {
        bytes32 id;
        string name;
        bytes32[] steps;
        uint256 currentStep;
        uint256 createdAt;
        uint256 completedAt;
        WorkflowStatus status;
        address initiator;
    }

    enum WorkflowStatus {
        Pending,
        InProgress,
        Completed,
        Failed,
        Cancelled
    }

    struct ExecutionResult {
        bool success;
        bytes result;
        uint256 timestamp;
        address executor;
    }

    mapping(bytes32 => Workflow) public workflows;
    mapping(bytes32 => WorkflowStep) public workflowSteps;
    mapping(bytes32 => ExecutionResult[]) public stepExecutions;
    mapping(bytes32 => EnumerableSet.Bytes32Set) private workflowTemplates;

    event WorkflowCreated(
        bytes32 indexed workflowId,
        string name,
        address initiator
    );
    event StepExecuted(
        bytes32 indexed workflowId,
        bytes32 indexed stepId,
        bool success
    );
    event WorkflowCompleted(
        bytes32 indexed workflowId,
        WorkflowStatus status
    );
    event StepApprovalGranted(
        bytes32 indexed stepId,
        address approver
    );

    constructor() {
        _setupRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _setupRole(WORKFLOW_ADMIN, msg.sender);
    }

    function createWorkflowTemplate(
        string memory name,
        bytes32[] memory stepIds
    ) external onlyRole(WORKFLOW_ADMIN) returns (bytes32) {
        bytes32 templateId = keccak256(
            abi.encodePacked(
                name,
                block.timestamp
            )
        );

        for (uint256 i = 0; i < stepIds.length; i++) {
            require(workflowSteps[stepIds[i]].isActive, "Invalid step");
            workflowTemplates[templateId].add(stepIds[i]);
        }

        return templateId;
    }

    function createWorkflowStep(
        string memory name,
        bytes memory actionData,
        address targetContract,
        uint256 requiredApprovals,
        bool requiresHumanApproval
    ) external onlyRole(WORKFLOW_ADMIN) returns (bytes32) {
        bytes32 stepId = keccak256(
            abi.encodePacked(
                name,
                targetContract,
                block.timestamp
            )
        );

        WorkflowStep storage step = workflowSteps[stepId];
        step.id = stepId;
        step.name = name;
        step.actionData = actionData;
        step.targetContract = targetContract;
        step.requiredApprovals = requiredApprovals;
        step.requiresHumanApproval = requiresHumanApproval;
        step.isActive = true;

        return stepId;
    }

    function initiateWorkflow(
        bytes32 templateId,
        string memory name
    ) external returns (bytes32) {
        require(workflowTemplates[templateId].length() > 0, "Template not found");

        bytes32 workflowId = keccak256(
            abi.encodePacked(
                templateId,
                name,
                block.timestamp,
                msg.sender
            )
        );

        Workflow storage workflow = workflows[workflowId];
        workflow.id = workflowId;
        workflow.name = name;
        workflow.steps = new bytes32[](workflowTemplates[templateId].length());
        
        for (uint256 i = 0; i < workflowTemplates[templateId].length(); i++) {
            workflow.steps[i] = workflowTemplates[templateId].at(i);
        }
        
        workflow.currentStep = 0;
        workflow.createdAt = block.timestamp;
        workflow.status = WorkflowStatus.Pending;
        workflow.initiator = msg.sender;

        emit WorkflowCreated(workflowId, name, msg.sender);
        return workflowId;
    }

    function executeWorkflowStep(
        bytes32 workflowId
    ) external onlyRole(EXECUTOR_ROLE) nonReentrant {
        Workflow storage workflow = workflows[workflowId];
        require(workflow.status == WorkflowStatus.Pending || 
                workflow.status == WorkflowStatus.InProgress, "Invalid workflow status");
        require(workflow.currentStep < workflow.steps.length, "Workflow completed");

        bytes32 currentStepId = workflow.steps[workflow.currentStep];
        WorkflowStep storage step = workflowSteps[currentStepId];

        if (step.requiresHumanApproval) {
            require(
                getApprovalCount(currentStepId) >= step.requiredApprovals,
                "Insufficient approvals"
            );
        }

        workflow.status = WorkflowStatus.InProgress;

        (bool success, bytes memory result) = step.targetContract.call(step.actionData);

        ExecutionResult memory execResult = ExecutionResult({
            success: success,
            result: result,
            timestamp: block.timestamp,
            executor: msg.sender
        });

        stepExecutions[currentStepId].push(execResult);

        emit StepExecuted(workflowId, currentStepId, success);

        if (success) {
            workflow.currentStep++;
            if (workflow.currentStep >= workflow.steps.length) {
                workflow.status = WorkflowStatus.Completed;
                workflow.completedAt = block.timestamp;
                emit WorkflowCompleted(workflowId, WorkflowStatus.Completed);
            }
        } else {
            workflow.status = WorkflowStatus.Failed;
            emit WorkflowCompleted(workflowId, WorkflowStatus.Failed);
        }
    }

    function approveStep(bytes32 stepId) external {
        WorkflowStep storage step = workflowSteps[stepId];
        require(step.isActive, "Step not active");
        require(step.requiresHumanApproval, "Human approval not required");
        require(!step.approvals[msg.sender], "Already approved");
        require(hasRole(WORKFLOW_ADMIN, msg.sender), "Not authorized");

        step.approvals[msg.sender] = true;
        emit StepApprovalGranted(stepId, msg.sender);
    }

    function getApprovalCount(bytes32 stepId) public view returns (uint256) {
        WorkflowStep storage step = workflowSteps[stepId];
        uint256 count = 0;
        
        for (uint256 i = 0; i < getRoleMemberCount(WORKFLOW_ADMIN); i++) {
            address admin = getRoleMember(WORKFLOW_ADMIN, i);
            if (step.approvals[admin]) {
                count++;
            }
        }
        
        return count;
    }

    function getWorkflowSteps(bytes32 workflowId)
        external
        view
        returns (bytes32[] memory)
    {
        return workflows[workflowId].steps;
    }

    function getStepExecutions(bytes32 stepId)
        external
        view
        returns (ExecutionResult[] memory)
    {
        return stepExecutions[stepId];
    }
} 