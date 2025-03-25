// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "./SecurityMonitor.sol";

contract IncidentResponsePlaybook is AccessControl, ReentrancyGuard {
    bytes32 public constant PLAYBOOK_ADMIN = keccak256("PLAYBOOK_ADMIN");
    bytes32 public constant EXECUTOR_ROLE = keccak256("EXECUTOR_ROLE");

    struct ResponseAction {
        bytes32 id;
        string name;
        bytes actionData;
        address targetContract;
        bool requiresApproval;
        bool isActive;
    }

    struct Playbook {
        bytes32 id;
        string name;
        string[] triggerConditions;
        bytes32[] actions;
        uint256 minSeverity;
        bool isActive;
    }

    struct ExecutionRecord {
        bytes32 id;
        bytes32 playbookId;
        bytes32 incidentId;
        uint256 timestamp;
        bool success;
        string result;
    }

    SecurityMonitor public securityMonitor;
    
    mapping(bytes32 => ResponseAction) public actions;
    mapping(bytes32 => Playbook) public playbooks;
    mapping(bytes32 => ExecutionRecord[]) public executions;
    mapping(string => bytes32[]) public triggerToPlaybooks;

    event PlaybookCreated(
        bytes32 indexed playbookId,
        string name,
        uint256 minSeverity
    );
    event ActionCreated(
        bytes32 indexed actionId,
        string name,
        address targetContract
    );
    event PlaybookExecuted(
        bytes32 indexed playbookId,
        bytes32 indexed incidentId,
        bool success
    );
    event ActionExecuted(
        bytes32 indexed actionId,
        bytes32 indexed executionId,
        bool success
    );

    constructor(address _securityMonitor) {
        securityMonitor = SecurityMonitor(_securityMonitor);
        _setupRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _setupRole(PLAYBOOK_ADMIN, msg.sender);
    }

    function createAction(
        string memory name,
        bytes memory actionData,
        address targetContract,
        bool requiresApproval
    ) external onlyRole(PLAYBOOK_ADMIN) returns (bytes32) {
        bytes32 actionId = keccak256(
            abi.encodePacked(
                name,
                targetContract,
                block.timestamp
            )
        );

        actions[actionId] = ResponseAction({
            id: actionId,
            name: name,
            actionData: actionData,
            targetContract: targetContract,
            requiresApproval: requiresApproval,
            isActive: true
        });

        emit ActionCreated(actionId, name, targetContract);
        return actionId;
    }

    function createPlaybook(
        string memory name,
        string[] memory triggerConditions,
        bytes32[] memory actionIds,
        uint256 minSeverity
    ) external onlyRole(PLAYBOOK_ADMIN) returns (bytes32) {
        require(triggerConditions.length > 0, "No trigger conditions");
        require(actionIds.length > 0, "No actions specified");

        bytes32 playbookId = keccak256(
            abi.encodePacked(
                name,
                block.timestamp
            )
        );

        playbooks[playbookId] = Playbook({
            id: playbookId,
            name: name,
            triggerConditions: triggerConditions,
            actions: actionIds,
            minSeverity: minSeverity,
            isActive: true
        });

        for (uint256 i = 0; i < triggerConditions.length; i++) {
            triggerToPlaybooks[triggerConditions[i]].push(playbookId);
        }

        emit PlaybookCreated(playbookId, name, minSeverity);
        return playbookId;
    }

    function executePlaybook(
        bytes32 playbookId,
        bytes32 incidentId
    ) external onlyRole(EXECUTOR_ROLE) nonReentrant {
        Playbook storage playbook = playbooks[playbookId];
        require(playbook.isActive, "Playbook not active");

        (,, uint256 severity,,,) = securityMonitor.incidents(incidentId);
        require(severity >= playbook.minSeverity, "Incident severity too low");

        bytes32 executionId = keccak256(
            abi.encodePacked(
                playbookId,
                incidentId,
                block.timestamp
            )
        );

        bool success = true;
        string memory result = "";

        for (uint256 i = 0; i < playbook.actions.length; i++) {
            ResponseAction storage action = actions[playbook.actions[i]];
            
            if (action.requiresApproval) {
                require(
                    securityMonitor.hasRole(securityMonitor.GUARDIAN_ROLE(), msg.sender),
                    "Action requires guardian approval"
                );
            }

            (bool actionSuccess, bytes memory actionResult) = action.targetContract.call(
                action.actionData
            );

            if (!actionSuccess) {
                success = false;
                result = string(actionResult);
                break;
            }

            emit ActionExecuted(action.id, executionId, actionSuccess);
        }

        executions[playbookId].push(ExecutionRecord({
            id: executionId,
            playbookId: playbookId,
            incidentId: incidentId,
            timestamp: block.timestamp,
            success: success,
            result: result
        }));

        emit PlaybookExecuted(playbookId, incidentId, success);
    }

    function getPlaybooksForTrigger(string memory trigger)
        external
        view
        returns (bytes32[] memory)
    {
        return triggerToPlaybooks[trigger];
    }

    function getPlaybookExecutions(bytes32 playbookId)
        external
        view
        returns (ExecutionRecord[] memory)
    {
        return executions[playbookId];
    }
} 