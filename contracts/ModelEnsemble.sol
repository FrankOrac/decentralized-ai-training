// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";

contract ModelEnsemble is AccessControl, ReentrancyGuard {
    bytes32 public constant ENSEMBLE_MANAGER_ROLE = keccak256("ENSEMBLE_MANAGER_ROLE");

    struct EnsembleModel {
        string ensembleId;
        string[] baseModelHashes;
        uint256[] weights;
        string aggregationStrategy;
        uint256 minPerformanceThreshold;
        uint256 creationTime;
        address creator;
        EnsembleStatus status;
        mapping(string => ModelPerformance) modelPerformance;
        mapping(address => bool) validators;
        uint256 validationCount;
    }

    struct ModelPerformance {
        uint256 accuracy;
        uint256 latency;
        uint256 resourceUsage;
        uint256 lastUpdated;
    }

    struct ValidationResult {
        string ensembleId;
        string modelHash;
        uint256 accuracy;
        uint256 latency;
        uint256 resourceUsage;
        address validator;
        uint256 timestamp;
    }

    enum EnsembleStatus {
        Created,
        Training,
        Validating,
        Active,
        Deprecated
    }

    mapping(string => EnsembleModel) public ensembles;
    mapping(string => ValidationResult[]) public validations;
    mapping(string => string[]) public modelEnsembles;
    
    uint256 public minValidations;
    uint256 public validationReward;

    event EnsembleCreated(
        string indexed ensembleId,
        string[] baseModelHashes,
        string aggregationStrategy
    );
    event ValidationSubmitted(
        string indexed ensembleId,
        string modelHash,
        address validator,
        uint256 accuracy
    );
    event EnsembleActivated(
        string indexed ensembleId,
        uint256 averageAccuracy
    );
    event EnsembleDeprecated(
        string indexed ensembleId,
        string reason
    );

    constructor(uint256 _minValidations, uint256 _validationReward) {
        _setupRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _setupRole(ENSEMBLE_MANAGER_ROLE, msg.sender);
        minValidations = _minValidations;
        validationReward = _validationReward;
    }

    function createEnsemble(
        string memory _ensembleId,
        string[] memory _baseModelHashes,
        uint256[] memory _weights,
        string memory _aggregationStrategy,
        uint256 _minPerformanceThreshold
    ) external onlyRole(ENSEMBLE_MANAGER_ROLE) {
        require(_baseModelHashes.length >= 2, "Insufficient base models");
        require(_baseModelHashes.length == _weights.length, "Weights mismatch");
        require(_minPerformanceThreshold <= 100, "Invalid threshold");

        uint256 totalWeight = 0;
        for (uint i = 0; i < _weights.length; i++) {
            totalWeight += _weights[i];
        }
        require(totalWeight == 100, "Weights must sum to 100");

        EnsembleModel storage ensemble = ensembles[_ensembleId];
        ensemble.ensembleId = _ensembleId;
        ensemble.baseModelHashes = _baseModelHashes;
        ensemble.weights = _weights;
        ensemble.aggregationStrategy = _aggregationStrategy;
        ensemble.minPerformanceThreshold = _minPerformanceThreshold;
        ensemble.creationTime = block.timestamp;
        ensemble.creator = msg.sender;
        ensemble.status = EnsembleStatus.Created;

        for (uint i = 0; i < _baseModelHashes.length; i++) {
            modelEnsembles[_baseModelHashes[i]].push(_ensembleId);
        }

        emit EnsembleCreated(_ensembleId, _baseModelHashes, _aggregationStrategy);
    }

    function submitValidation(
        string memory _ensembleId,
        string memory _modelHash,
        uint256 _accuracy,
        uint256 _latency,
        uint256 _resourceUsage
    ) external nonReentrant {
        EnsembleModel storage ensemble = ensembles[_ensembleId];
        require(ensemble.status != EnsembleStatus.Active, "Already active");
        require(!ensemble.validators[msg.sender], "Already validated");
        require(_accuracy <= 100, "Invalid accuracy");

        bool isValidModel = false;
        for (uint i = 0; i < ensemble.baseModelHashes.length; i++) {
            if (keccak256(bytes(ensemble.baseModelHashes[i])) == keccak256(bytes(_modelHash))) {
                isValidModel = true;
                break;
            }
        }
        require(isValidModel, "Invalid model hash");

        ensemble.validators[msg.sender] = true;
        ensemble.validationCount++;

        ValidationResult memory result = ValidationResult({
            ensembleId: _ensembleId,
            modelHash: _modelHash,
            accuracy: _accuracy,
            latency: _latency,
            resourceUsage: _resourceUsage,
            validator: msg.sender,
            timestamp: block.timestamp
        });

        validations[_ensembleId].push(result);

        // Update model performance
        ModelPerformance storage performance = ensemble.modelPerformance[_modelHash];
        if (performance.lastUpdated == 0) {
            performance.accuracy = _accuracy;
            performance.latency = _latency;
            performance.resourceUsage = _resourceUsage;
        } else {
            performance.accuracy = (performance.accuracy + _accuracy) / 2;
            performance.latency = (performance.latency + _latency) / 2;
            performance.resourceUsage = (performance.resourceUsage + _resourceUsage) / 2;
        }
        performance.lastUpdated = block.timestamp;

        emit ValidationSubmitted(_ensembleId, _modelHash, msg.sender, _accuracy);

        // Check if enough validations have been collected
        if (ensemble.validationCount >= minValidations) {
            finalizeEnsemble(_ensembleId);
        }

        // Reward validator
        payable(msg.sender).transfer(validationReward);
    }

    function finalizeEnsemble(string memory _ensembleId) internal {
        EnsembleModel storage ensemble = ensembles[_ensembleId];
        uint256 weightedAccuracy = 0;
        uint256 weightedLatency = 0;
        uint256 weightedResourceUsage = 0;

        for (uint i = 0; i < ensemble.baseModelHashes.length; i++) {
            string memory modelHash = ensemble.baseModelHashes[i];
            ModelPerformance storage performance = ensemble.modelPerformance[modelHash];
            
            weightedAccuracy += (performance.accuracy * ensemble.weights[i]) / 100;
            weightedLatency += (performance.latency * ensemble.weights[i]) / 100;
            weightedResourceUsage += (performance.resourceUsage * ensemble.weights[i]) / 100;
        }

        if (weightedAccuracy >= ensemble.minPerformanceThreshold) {
            ensemble.status = EnsembleStatus.Active;
            emit EnsembleActivated(_ensembleId, weightedAccuracy);
        } else {
            ensemble.status = EnsembleStatus.Deprecated;
            emit EnsembleDeprecated(_ensembleId, "Below performance threshold");
        }
    }

    function updateEnsembleWeights(
        string memory _ensembleId,
        uint256[] memory _newWeights
    ) external onlyRole(ENSEMBLE_MANAGER_ROLE) {
        EnsembleModel storage ensemble = ensembles[_ensembleId];
        require(ensemble.status == EnsembleStatus.Active, "Not active");
        require(_newWeights.length == ensemble.baseModelHashes.length, "Invalid weights");

        uint256 totalWeight = 0;
        for (uint i = 0; i < _newWeights.length; i++) {
            totalWeight += _newWeights[i];
        }
        require(totalWeight == 100, "Weights must sum to 100");

        ensemble.weights = _newWeights;
    }

    function deprecateEnsemble(
        string memory _ensembleId,
        string memory _reason
    ) external onlyRole(ENSEMBLE_MANAGER_ROLE) {
        EnsembleModel storage ensemble = ensembles[_ensembleId];
        require(ensemble.status == EnsembleStatus.Active, "Not active");

        ensemble.status = EnsembleStatus.Deprecated;
        emit EnsembleDeprecated(_ensembleId, _reason);
    }

    function getEnsembleDetails(string memory _ensembleId)
        external
        view
        returns (
            string[] memory baseModelHashes,
            uint256[] memory weights,
            string memory aggregationStrategy,
            uint256 minPerformanceThreshold,
            uint256 creationTime,
            address creator,
            EnsembleStatus status,
            uint256 validationCount
        )
    {
        EnsembleModel storage ensemble = ensembles[_ensembleId];
        return (
            ensemble.baseModelHashes,
            ensemble.weights,
            ensemble.aggregationStrategy,
            ensemble.minPerformanceThreshold,
            ensemble.creationTime,
            ensemble.creator,
            ensemble.status,
            ensemble.validationCount
        );
    }

    function getModelPerformance(
        string memory _ensembleId,
        string memory _modelHash
    ) external view returns (
        uint256 accuracy,
        uint256 latency,
        uint256 resourceUsage,
        uint256 lastUpdated
    ) {
        ModelPerformance storage performance = ensembles[_ensembleId].modelPerformance[_modelHash];
        return (
            performance.accuracy,
            performance.latency,
            performance.resourceUsage,
            performance.lastUpdated
        );
    }

    function getValidations(string memory _ensembleId)
        external
        view
        returns (ValidationResult[] memory)
    {
        return validations[_ensembleId];
    }
} 