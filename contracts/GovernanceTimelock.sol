// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/utils/math/SafeMath.sol";

contract GovernanceTimelock is AccessControl, ReentrancyGuard {
    using SafeMath for uint256;

    bytes32 public constant PROPOSER_ROLE = keccak256("PROPOSER_ROLE");
    bytes32 public constant EXECUTOR_ROLE = keccak256("EXECUTOR_ROLE");
    bytes32 public constant CANCELLER_ROLE = keccak256("CANCELLER_ROLE");

    struct TimelockOperation {
        bytes32 id;
        address[] targets;
        uint256[] values;
        bytes[] calldatas;
        bytes32 predecessor;
        bytes32 salt;
        uint256 delay;
        uint256 scheduledAt;
        bool executed;
        bool canceled;
    }

    mapping(bytes32 => TimelockOperation) public operations;
    mapping(bytes32 => bool) public queuedOperations;

    uint256 public minDelay;
    uint256 public maxDelay;
    uint256 public gracePeriod;

    event OperationScheduled(
        bytes32 indexed id,
        address[] targets,
        uint256[] values,
        bytes[] calldatas,
        bytes32 predecessor,
        bytes32 salt,
        uint256 delay
    );
    event OperationExecuted(bytes32 indexed id);
    event OperationCanceled(bytes32 indexed id);
    event DelayChanged(uint256 oldDelay, uint256 newDelay);

    constructor(uint256 _minDelay, uint256 _maxDelay, uint256 _gracePeriod) {
        require(_minDelay > 0, "Timelock: minimum delay must be greater than 0");
        require(_maxDelay >= _minDelay, "Timelock: max delay must be >= min delay");
        require(_gracePeriod > 0, "Timelock: grace period must be greater than 0");

        _setupRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _setupRole(PROPOSER_ROLE, msg.sender);
        _setupRole(EXECUTOR_ROLE, msg.sender);
        _setupRole(CANCELLER_ROLE, msg.sender);

        minDelay = _minDelay;
        maxDelay = _maxDelay;
        gracePeriod = _gracePeriod;
    }

    function schedule(
        address[] memory targets,
        uint256[] memory values,
        bytes[] memory calldatas,
        bytes32 predecessor,
        bytes32 salt,
        uint256 delay
    ) public onlyRole(PROPOSER_ROLE) returns (bytes32) {
        require(delay >= minDelay, "Timelock: insufficient delay");
        require(delay <= maxDelay, "Timelock: excessive delay");
        require(
            targets.length == values.length &&
            targets.length == calldatas.length,
            "Timelock: length mismatch"
        );

        bytes32 id = hashOperation(targets, values, calldatas, predecessor, salt);
        require(!queuedOperations[id], "Timelock: operation already queued");

        if (predecessor != bytes32(0)) {
            require(
                isOperationDone(predecessor),
                "Timelock: predecessor not completed"
            );
        }

        operations[id] = TimelockOperation({
            id: id,
            targets: targets,
            values: values,
            calldatas: calldatas,
            predecessor: predecessor,
            salt: salt,
            delay: delay,
            scheduledAt: block.timestamp,
            executed: false,
            canceled: false
        });

        queuedOperations[id] = true;

        emit OperationScheduled(
            id,
            targets,
            values,
            calldatas,
            predecessor,
            salt,
            delay
        );

        return id;
    }

    function execute(
        address[] memory targets,
        uint256[] memory values,
        bytes[] memory calldatas,
        bytes32 predecessor,
        bytes32 salt
    ) public payable nonReentrant onlyRole(EXECUTOR_ROLE) {
        bytes32 id = hashOperation(targets, values, calldatas, predecessor, salt);
        TimelockOperation storage operation = operations[id];
        
        require(queuedOperations[id], "Timelock: operation not queued");
        require(!operation.executed, "Timelock: operation already executed");
        require(!operation.canceled, "Timelock: operation canceled");
        require(
            block.timestamp >= operation.scheduledAt.add(operation.delay),
            "Timelock: operation not ready"
        );
        require(
            block.timestamp <= operation.scheduledAt.add(operation.delay).add(gracePeriod),
            "Timelock: operation expired"
        );

        operation.executed = true;

        for (uint256 i = 0; i < targets.length; i++) {
            (bool success, ) = targets[i].call{value: values[i]}(calldatas[i]);
            require(success, "Timelock: execution failed");
        }

        emit OperationExecuted(id);
    }

    function cancel(bytes32 id) public onlyRole(CANCELLER_ROLE) {
        require(queuedOperations[id], "Timelock: operation not queued");
        TimelockOperation storage operation = operations[id];
        require(!operation.executed, "Timelock: operation already executed");
        require(!operation.canceled, "Timelock: operation already canceled");

        operation.canceled = true;
        emit OperationCanceled(id);
    }

    function updateDelay(uint256 newMinDelay, uint256 newMaxDelay) 
        public 
        onlyRole(DEFAULT_ADMIN_ROLE) 
    {
        require(newMinDelay > 0, "Timelock: minimum delay must be greater than 0");
        require(
            newMaxDelay >= newMinDelay,
            "Timelock: max delay must be >= min delay"
        );

        uint256 oldMinDelay = minDelay;
        uint256 oldMaxDelay = maxDelay;
        minDelay = newMinDelay;
        maxDelay = newMaxDelay;

        emit DelayChanged(oldMinDelay, newMinDelay);
        emit DelayChanged(oldMaxDelay, newMaxDelay);
    }

    function hashOperation(
        address[] memory targets,
        uint256[] memory values,
        bytes[] memory calldatas,
        bytes32 predecessor,
        bytes32 salt
    ) public pure returns (bytes32) {
        return keccak256(abi.encode(
            targets,
            values,
            calldatas,
            predecessor,
            salt
        ));
    }

    function isOperationPending(bytes32 id) public view returns (bool) {
        return queuedOperations[id] && 
               !operations[id].executed && 
               !operations[id].canceled;
    }

    function isOperationReady(bytes32 id) public view returns (bool) {
        TimelockOperation storage operation = operations[id];
        return queuedOperations[id] && 
               !operation.executed && 
               !operation.canceled && 
               block.timestamp >= operation.scheduledAt.add(operation.delay);
    }

    function isOperationDone(bytes32 id) public view returns (bool) {
        return operations[id].executed || operations[id].canceled;
    }

    receive() external payable {}
} 