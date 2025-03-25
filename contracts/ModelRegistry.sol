// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";

contract ModelRegistry is AccessControl, ReentrancyGuard {
    bytes32 public constant MODEL_VALIDATOR_ROLE = keccak256("MODEL_VALIDATOR_ROLE");

    struct ModelType {
        string name;
        string description;
        uint256 baseComputeScore;
        uint256 minReputation;
        bool isActive;
        mapping(address => bool) approvedValidators;
    }

    struct ModelInstance {
        uint256 modelTypeId;
        string modelHash;
        address owner;
        uint256 version;
        ModelStatus status;
        mapping(address => ValidationResult) validations;
    }

    enum ModelStatus {
        Pending,
        Approved,
        Rejected,
        Deprecated
    }

    struct ValidationResult {
        bool isValidated;
        bool passed;
        string comments;
        uint256 timestamp;
    }

    mapping(uint256 => ModelType) public modelTypes;
    mapping(uint256 => ModelInstance) public modelInstances;
    uint256 public modelTypeCount;
    uint256 public modelInstanceCount;

    event ModelTypeRegistered(uint256 indexed typeId, string name);
    event ModelInstanceRegistered(uint256 indexed instanceId, uint256 typeId);
    event ModelValidated(uint256 indexed instanceId, address validator, bool passed);

    constructor() {
        _setupRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _setupRole(MODEL_VALIDATOR_ROLE, msg.sender);
    }

    function registerModelType(
        string memory _name,
        string memory _description,
        uint256 _baseComputeScore,
        uint256 _minReputation
    ) external onlyRole(DEFAULT_ADMIN_ROLE) {
        modelTypeCount++;
        ModelType storage newType = modelTypes[modelTypeCount];
        newType.name = _name;
        newType.description = _description;
        newType.baseComputeScore = _baseComputeScore;
        newType.minReputation = _minReputation;
        newType.isActive = true;

        emit ModelTypeRegistered(modelTypeCount, _name);
    }

    function registerModelInstance(
        uint256 _typeId,
        string memory _modelHash,
        uint256 _version
    ) external nonReentrant {
        require(_typeId <= modelTypeCount, "Invalid model type");
        require(modelTypes[_typeId].isActive, "Model type not active");

        modelInstanceCount++;
        ModelInstance storage newInstance = modelInstances[modelInstanceCount];
        newInstance.modelTypeId = _typeId;
        newInstance.modelHash = _modelHash;
        newInstance.owner = msg.sender;
        newInstance.version = _version;
        newInstance.status = ModelStatus.Pending;

        emit ModelInstanceRegistered(modelInstanceCount, _typeId);
    }

    function validateModel(
        uint256 _instanceId,
        bool _passed,
        string memory _comments
    ) external onlyRole(MODEL_VALIDATOR_ROLE) {
        require(_instanceId <= modelInstanceCount, "Invalid model instance");
        ModelInstance storage instance = modelInstances[_instanceId];
        
        instance.validations[msg.sender] = ValidationResult({
            isValidated: true,
            passed: _passed,
            comments: _comments,
            timestamp: block.timestamp
        });

        updateModelStatus(_instanceId);
        emit ModelValidated(_instanceId, msg.sender, _passed);
    }

    function updateModelStatus(uint256 _instanceId) internal {
        ModelInstance storage instance = modelInstances[_instanceId];
        uint256 passCount = 0;
        uint256 failCount = 0;

        uint256 validatorCount = getRoleMemberCount(MODEL_VALIDATOR_ROLE);
        for (uint256 i = 0; i < validatorCount; i++) {
            address validator = getRoleMember(MODEL_VALIDATOR_ROLE, i);
            if (instance.validations[validator].isValidated) {
                if (instance.validations[validator].passed) {
                    passCount++;
                } else {
                    failCount++;
                }
            }
        }

        if (passCount > validatorCount / 2) {
            instance.status = ModelStatus.Approved;
        } else if (failCount > validatorCount / 2) {
            instance.status = ModelStatus.Rejected;
        }
    }
} 