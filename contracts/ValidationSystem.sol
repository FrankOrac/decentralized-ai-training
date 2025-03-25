// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";

contract ValidationSystem is AccessControl, ReentrancyGuard {
    bytes32 public constant VALIDATOR_ROLE = keccak256("VALIDATOR_ROLE");
    
    struct Validation {
        address validator;
        uint256 score;
        string resultHash;
        string comments;
        uint256 timestamp;
        bool isApproved;
    }

    struct ValidationMetrics {
        uint256 totalValidations;
        uint256 successRate;
        uint256 averageScore;
        uint256 responseTime;
    }

    mapping(uint256 => Validation[]) public taskValidations;
    mapping(uint256 => bool) public isTaskValidated;
    mapping(address => ValidationMetrics) public validatorMetrics;
    
    uint256 public minValidationsRequired;
    uint256 public minValidationScore;
    
    event ValidationSubmitted(uint256 indexed taskId, address validator, uint256 score);
    event TaskValidated(uint256 indexed taskId, bool isApproved);
    event ValidatorAdded(address indexed validator);
    event ValidatorRemoved(address indexed validator);

    constructor(uint256 _minValidations, uint256 _minScore) {
        _setupRole(DEFAULT_ADMIN_ROLE, msg.sender);
        minValidationsRequired = _minValidations;
        minValidationScore = _minScore;
    }

    function submitValidation(
        uint256 _taskId,
        uint256 _score,
        string memory _resultHash,
        string memory _comments
    ) external onlyRole(VALIDATOR_ROLE) nonReentrant {
        require(!isTaskValidated[_taskId], "Task already validated");
        require(_score <= 100, "Score must be <= 100");

        Validation memory validation = Validation({
            validator: msg.sender,
            score: _score,
            resultHash: _resultHash,
            comments: _comments,
            timestamp: block.timestamp,
            isApproved: _score >= minValidationScore
        });

        taskValidations[_taskId].push(validation);
        updateValidatorMetrics(msg.sender, _score);

        emit ValidationSubmitted(_taskId, msg.sender, _score);

        if (taskValidations[_taskId].length >= minValidationsRequired) {
            finalizeValidation(_taskId);
        }
    }

    function finalizeValidation(uint256 _taskId) internal {
        Validation[] storage validations = taskValidations[_taskId];
        uint256 totalScore = 0;
        uint256 approvalCount = 0;

        for (uint256 i = 0; i < validations.length; i++) {
            totalScore += validations[i].score;
            if (validations[i].isApproved) {
                approvalCount++;
            }
        }

        uint256 averageScore = totalScore / validations.length;
        bool isApproved = averageScore >= minValidationScore &&
            approvalCount >= minValidationsRequired;

        isTaskValidated[_taskId] = true;
        emit TaskValidated(_taskId, isApproved);
    }

    function updateValidatorMetrics(address _validator, uint256 _score) internal {
        ValidationMetrics storage metrics = validatorMetrics[_validator];
        metrics.totalValidations++;
        metrics.averageScore = (metrics.averageScore * (metrics.totalValidations - 1) + _score) 
            / metrics.totalValidations;
        metrics.successRate = (metrics.successRate * (metrics.totalValidations - 1) + 
            (_score >= minValidationScore ? 100 : 0)) / metrics.totalValidations;
    }

    function getTaskValidations(uint256 _taskId) 
        external view returns (Validation[] memory) 
    {
        return taskValidations[_taskId];
    }

    function getValidatorMetrics(address _validator) 
        external view returns (ValidationMetrics memory) 
    {
        return validatorMetrics[_validator];
    }
} 