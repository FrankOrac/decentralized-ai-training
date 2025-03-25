// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/security/Pausable.sol";
import "@chainlink/contracts/src/v0.8/ChainlinkClient.sol";

contract AutomatedResponse is AccessControl, ReentrancyGuard, Pausable, ChainlinkClient {
    using Chainlink for Chainlink.Request;

    bytes32 public constant RESPONDER_ROLE = keccak256("RESPONDER_ROLE");
    bytes32 public constant ORACLE_ROLE = keccak256("ORACLE_ROLE");

    struct ResponseRule {
        bytes32 id;
        string triggerCondition;
        bytes actionData;
        address targetContract;
        uint256 threshold;
        uint256 cooldown;
        uint256 lastTriggered;
        bool isActive;
        ResponseType responseType;
    }

    struct ResponseAction {
        bytes32 id;
        bytes32 ruleId;
        uint256 timestamp;
        bool success;
        string result;
        address executor;
    }

    enum ResponseType {
        PAUSE_CONTRACT,
        LIMIT_OPERATIONS,
        NOTIFY_GUARDIANS,
        EXECUTE_RECOVERY,
        CUSTOM_ACTION
    }

    mapping(bytes32 => ResponseRule) public rules;
    mapping(bytes32 => ResponseAction[]) public ruleActions;
    mapping(address => mapping(bytes32 => bool)) public guardianAcknowledgements;
    
    uint256 public constant MAX_RESPONSE_DELAY = 1 hours;
    uint256 public constant MIN_GUARDIAN_CONFIRMATIONS = 2;

    event RuleCreated(
        bytes32 indexed ruleId,
        string triggerCondition,
        ResponseType responseType
    );
    event ResponseTriggered(
        bytes32 indexed ruleId,
        bytes32 indexed actionId,
        ResponseType responseType
    );
    event ResponseExecuted(
        bytes32 indexed actionId,
        bool success,
        string result
    );
    event GuardianAcknowledged(
        bytes32 indexed actionId,
        address indexed guardian
    );

    constructor(address _link) {
        setChainlinkToken(_link);
        _setupRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _setupRole(RESPONDER_ROLE, msg.sender);
    }

    function createResponseRule(
        string memory triggerCondition,
        bytes memory actionData,
        address targetContract,
        uint256 threshold,
        uint256 cooldown,
        ResponseType responseType
    ) external onlyRole(DEFAULT_ADMIN_ROLE) returns (bytes32) {
        bytes32 ruleId = keccak256(
            abi.encodePacked(
                triggerCondition,
                targetContract,
                block.timestamp
            )
        );

        rules[ruleId] = ResponseRule({
            id: ruleId,
            triggerCondition: triggerCondition,
            actionData: actionData,
            targetContract: targetContract,
            threshold: threshold,
            cooldown: cooldown,
            lastTriggered: 0,
            isActive: true,
            responseType: responseType
        });

        emit RuleCreated(ruleId, triggerCondition, responseType);
        return ruleId;
    }

    function triggerResponse(
        bytes32 ruleId,
        bytes memory triggerData
    ) external onlyRole(RESPONDER_ROLE) nonReentrant returns (bytes32) {
        ResponseRule storage rule = rules[ruleId];
        require(rule.isActive, "Rule not active");
        require(
            block.timestamp >= rule.lastTriggered + rule.cooldown,
            "Cooldown period active"
        );

        bytes32 actionId = keccak256(
            abi.encodePacked(
                ruleId,
                block.timestamp,
                msg.sender
            )
        );

        ResponseAction memory action = ResponseAction({
            id: actionId,
            ruleId: ruleId,
            timestamp: block.timestamp,
            success: false,
            result: "",
            executor: msg.sender
        });

        ruleActions[ruleId].push(action);
        rule.lastTriggered = block.timestamp;

        emit ResponseTriggered(ruleId, actionId, rule.responseType);

        if (rule.responseType == ResponseType.PAUSE_CONTRACT) {
            _executePauseAction(rule.targetContract);
        } else if (rule.responseType == ResponseType.LIMIT_OPERATIONS) {
            _executeLimitAction(rule.targetContract, rule.actionData);
        } else if (rule.responseType == ResponseType.NOTIFY_GUARDIANS) {
            _notifyGuardians(actionId, triggerData);
        } else if (rule.responseType == ResponseType.EXECUTE_RECOVERY) {
            _executeRecoveryAction(rule.targetContract, rule.actionData);
        } else {
            _executeCustomAction(rule.targetContract, rule.actionData);
        }

        return actionId;
    }

    function acknowledgeResponse(
        bytes32 actionId,
        bytes32 ruleId
    ) external onlyRole(RESPONDER_ROLE) {
        require(!guardianAcknowledgements[msg.sender][actionId], "Already acknowledged");
        
        guardianAcknowledgements[msg.sender][actionId] = true;
        emit GuardianAcknowledged(actionId, msg.sender);

        uint256 acknowledgements = 0;
        for (uint256 i = 0; i < getRoleMemberCount(RESPONDER_ROLE); i++) {
            address guardian = getRoleMember(RESPONDER_ROLE, i);
            if (guardianAcknowledgements[guardian][actionId]) {
                acknowledgements++;
            }
        }

        if (acknowledgements >= MIN_GUARDIAN_CONFIRMATIONS) {
            _finalizeResponse(actionId, ruleId);
        }
    }

    function _executePauseAction(address target) internal {
        (bool success, ) = target.call(
            abi.encodeWithSignature("pause()")
        );
        require(success, "Pause action failed");
    }

    function _executeLimitAction(
        address target,
        bytes memory limitData
    ) internal {
        (bool success, ) = target.call(limitData);
        require(success, "Limit action failed");
    }

    function _notifyGuardians(
        bytes32 actionId,
        bytes memory triggerData
    ) internal {
        for (uint256 i = 0; i < getRoleMemberCount(RESPONDER_ROLE); i++) {
            address guardian = getRoleMember(RESPONDER_ROLE, i);
            // Implement notification mechanism (e.g., events, external service)
            emit GuardianAcknowledged(actionId, guardian);
        }
    }

    function _executeRecoveryAction(
        address target,
        bytes memory recoveryData
    ) internal {
        (bool success, ) = target.call(recoveryData);
        require(success, "Recovery action failed");
    }

    function _executeCustomAction(
        address target,
        bytes memory actionData
    ) internal {
        (bool success, ) = target.call(actionData);
        require(success, "Custom action failed");
    }

    function _finalizeResponse(
        bytes32 actionId,
        bytes32 ruleId
    ) internal {
        ResponseAction[] storage actions = ruleActions[ruleId];
        for (uint256 i = 0; i < actions.length; i++) {
            if (actions[i].id == actionId) {
                actions[i].success = true;
                actions[i].result = "Response executed successfully";
                emit ResponseExecuted(
                    actionId,
                    true,
                    actions[i].result
                );
                break;
            }
        }
    }

    function getRuleActions(bytes32 ruleId)
        external
        view
        returns (ResponseAction[] memory)
    {
        return ruleActions[ruleId];
    }

    function isActionAcknowledged(
        bytes32 actionId,
        address guardian
    ) external view returns (bool) {
        return guardianAcknowledgements[guardian][actionId];
    }

    receive() external payable {}
} 