// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";

contract ResponsePlaybook is AccessControl, ReentrancyGuard {
    bytes32 public constant PLAYBOOK_ADMIN = keccak256("PLAYBOOK_ADMIN");
    bytes32 public constant EXECUTOR_ROLE = keccak256("EXECUTOR_ROLE");

    struct Action {
        bytes32 id;
        string name;
        bytes data;
        address target;
        bool requiresApproval;
        bool isActive;
        mapping(address => bool) approvals;
    }

    struct Playbook {
        bytes32 id;
        string name;
        string[] triggerConditions;
        bytes32[] actions;
        uint256 minSeverity;
        bool isActive;
        uint256 cooldownPeriod;
        uint256 lastExecution;
    }

    struct ExecutionResult {
        bytes32 id;
        bytes32 playbookId;
        uint256 timestamp;
        bool success;
        string result;
        mapping(bytes32 => bool) actionResults;
    }

    mapping(bytes32 => Action) public actions;
    mapping(bytes32 => Playbook) public playbooks;
    mapping(bytes32 => ExecutionResult) public executions;
    mapping(string => bytes32[]) public triggerToPlaybooks;

    event ActionCreated(
        bytes32 indexed actionId,
        string name,
        address target
    );
    event PlaybookCreated(
        bytes32 indexed playbookId,
        string name,
        uint256 minSeverity
    );
    event PlaybookExecuted(
        bytes32 indexed playbookId,
        bytes32 indexed executionId,
        bool success
    );
    event ActionExecuted(
        bytes32 indexed actionId,
        bytes32 indexed executionId,
        bool success
    );

    constructor() {
        _setupRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _setupRole(PLAYBOOK_ADMIN, msg.sender);
    }

    function createAction(
        string memory name,
        bytes memory data,
        address target,
        bool requiresApproval
    ) external onlyRole(PLAYBOOK_ADMIN) returns (bytes32) {
        bytes32 actionId = keccak256(
            abi.encodePacked(
                name,
                target,
                block.timestamp
            )
        );

        Action storage action = actions[actionId];
        action.id = actionId;
        action.name = name;
        action.data = data;
        action.target = target;
        action.requiresApproval = requiresApproval;
        action.isActive = true;

        emit ActionCreated(actionId, name, target);
        return actionId;
    }

    function createPlaybook(
        string memory name,
        string[] memory triggerConditions,
        bytes32[] memory actionIds,
        uint256 minSeverity,
        uint256 cooldownPeriod
    ) external onlyRole(PLAYBOOK_ADMIN) returns (bytes32) {
        require(triggerConditions.length > 0, "No trigger conditions");
        require(actionIds.length > 0, "No actions specified");

        bytes32 playbookId = keccak256(
            abi.encodePacked(
                name,
                block.timestamp
            )
        );

        Playbook storage playbook = playbooks[playbookId];
        playbook.id = playbookId;
        playbook.name = name;
        playbook.triggerConditions = triggerConditions;
        playbook.actions = actionIds;
        playbook.minSeverity = minSeverity;
        playbook.isActive = true;
        playbook.cooldownPeriod = cooldownPeriod;

        for (uint256 i = 0; i < triggerConditions.length; i++) {
            triggerToPlaybooks[triggerConditions[i]].push(playbookId);
        }

        emit PlaybookCreated(playbookId, name, minSeverity);
        return playbookId;
    }

    function executePlaybook(
        bytes32 playbookId,
        uint256 severity
    ) external onlyRole(EXECUTOR_ROLE) nonReentrant returns (bytes32) {
        Playbook storage playbook = playbooks[playbookId];
        require(playbook.isActive, "Playbook not active");
        require(severity >= playbook.minSeverity, "Severity too low");
        require(
            block.timestamp >= playbook.lastExecution + playbook.cooldownPeriod,
            "Cooldown period active"
        );

        bytes32 executionId = keccak256(
            abi.encodePacked(
                playbookId,
                block.timestamp,
                msg.sender
            )
        );

        ExecutionResult storage result = executions[executionId];
        result.id = executionId;
        result.playbookId = playbookId;
        result.timestamp = block.timestamp;

        bool success = true;
        string memory errorMessage = "";

        for (uint256 i = 0; i < playbook.actions.length; i++) {
            Action storage action = actions[playbook.actions[i]];
            
            if (action.requiresApproval) {
                require(
                    hasRole(PLAYBOOK_ADMIN, msg.sender),
                    "Action requires admin approval"
                );
            }

            (bool actionSuccess, bytes memory actionResult) = action.target.call(
                action.data
            );

            result.actionResults[action.id] = actionSuccess;

            if (!actionSuccess) {
                success = false;
                errorMessage = string(actionResult);
                break;
            }

            emit ActionExecuted(action.id, executionId, actionSuccess);
        }

        result.success = success;
        result.result = success ? "Success" : errorMessage;
        playbook.lastExecution = block.timestamp;

        emit PlaybookExecuted(playbookId, executionId, success);
        return executionId;
    }

    function approveAction(
        bytes32 actionId
    ) external onlyRole(PLAYBOOK_ADMIN) {
        Action storage action = actions[actionId];
        require(action.requiresApproval, "Action doesn't require approval");
        require(!action.approvals[msg.sender], "Already approved");

        action.approvals[msg.sender] = true;
    }

    function getPlaybooksForTrigger(string memory trigger)
        external
        view
        returns (bytes32[] memory)
    {
        return triggerToPlaybooks[trigger];
    }

    function getExecutionDetails(bytes32 executionId)
        external
        view
        returns (
            bytes32 playbookId,
            uint256 timestamp,
            bool success,
            string memory result
        )
    {
        ExecutionResult storage execution = executions[executionId];
        return (
            execution.playbookId,
            execution.timestamp,
            execution.success,
            execution.result
        );
    }

    function isActionApproved(bytes32 actionId, address approver)
        external
        view
        returns (bool)
    {
        return actions[actionId].approvals[approver];
    }
} 