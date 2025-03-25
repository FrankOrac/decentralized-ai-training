// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";

contract EnsembleTraining is AccessControl, ReentrancyGuard {
    struct EnsembleModel {
        string[] baseModelHashes;
        string[] weights;
        string aggregationStrategy;
        uint256 minPerformanceThreshold;
        EnsembleStatus status;
        mapping(address => bool) validators;
        uint256 validationCount;
        string finalModelHash;
    }

    struct ValidationResult {
        bool approved;
        uint256 performance;
        string comments;
    }

    enum EnsembleStatus {
        Created,
        Training,
        Validating,
        Completed,
        Failed
    }

    mapping(uint256 => EnsembleModel) public ensembles;
    mapping(uint256 => mapping(address => ValidationResult)) public validations;
    uint256 public ensembleCount;
    uint256 public minValidations;

    event EnsembleCreated(uint256 indexed ensembleId, string[] baseModels);
    event ValidationSubmitted(uint256 indexed ensembleId, address validator, bool approved);
    event EnsembleCompleted(uint256 indexed ensembleId, string finalModelHash);

    constructor(uint256 _minValidations) {
        _setupRole(DEFAULT_ADMIN_ROLE, msg.sender);
        minValidations = _minValidations;
    }

    function createEnsemble(
        string[] memory _baseModelHashes,
        string[] memory _weights,
        string memory _aggregationStrategy,
        uint256 _minPerformanceThreshold
    ) external returns (uint256) {
        require(_baseModelHashes.length == _weights.length, "Mismatched arrays");
        require(_baseModelHashes.length >= 2, "Min 2 models required");

        ensembleCount++;
        EnsembleModel storage ensemble = ensembles[ensembleCount];
        ensemble.baseModelHashes = _baseModelHashes;
        ensemble.weights = _weights;
        ensemble.aggregationStrategy = _aggregationStrategy;
        ensemble.minPerformanceThreshold = _minPerformanceThreshold;
        ensemble.status = EnsembleStatus.Created;

        emit EnsembleCreated(ensembleCount, _baseModelHashes);
        return ensembleCount;
    }

    function submitValidation(
        uint256 _ensembleId,
        bool _approved,
        uint256 _performance,
        string memory _comments
    ) external {
        require(_ensembleId <= ensembleCount, "Invalid ensemble ID");
        EnsembleModel storage ensemble = ensembles[_ensembleId];
        require(ensemble.status == EnsembleStatus.Validating, "Not in validation");
        require(!ensemble.validators[msg.sender], "Already validated");

        ensemble.validators[msg.sender] = true;
        ensemble.validationCount++;

        validations[_ensembleId][msg.sender] = ValidationResult({
            approved: _approved,
            performance: _performance,
            comments: _comments
        });

        emit ValidationSubmitted(_ensembleId, msg.sender, _approved);

        if (ensemble.validationCount >= minValidations) {
            finalizeEnsemble(_ensembleId);
        }
    }

    function finalizeEnsemble(uint256 _ensembleId) internal {
        EnsembleModel storage ensemble = ensembles[_ensembleId];
        uint256 approvalCount = 0;
        uint256 totalPerformance = 0;

        for (uint256 i = 0; i < ensemble.validationCount; i++) {
            ValidationResult storage result = validations[_ensembleId][msg.sender];
            if (result.approved) {
                approvalCount++;
                totalPerformance += result.performance;
            }
        }

        uint256 averagePerformance = totalPerformance / ensemble.validationCount;
        if (approvalCount >= minValidations && 
            averagePerformance >= ensemble.minPerformanceThreshold) {
            ensemble.status = EnsembleStatus.Completed;
        } else {
            ensemble.status = EnsembleStatus.Failed;
        }

        emit EnsembleCompleted(_ensembleId, ensemble.finalModelHash);
    }

    function getEnsembleDetails(uint256 _ensembleId)
        external view returns (
            string[] memory baseModels,
            string[] memory weights,
            string memory strategy,
            EnsembleStatus status,
            uint256 validationCount
        )
    {
        EnsembleModel storage ensemble = ensembles[_ensembleId];
        return (
            ensemble.baseModelHashes,
            ensemble.weights,
            ensemble.aggregationStrategy,
            ensemble.status,
            ensemble.validationCount
        );
    }
} 