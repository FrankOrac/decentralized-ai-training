// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@chainlink/contracts/src/v0.8/ChainlinkClient.sol";
import "@chainlink/contracts/src/v0.8/interfaces/AggregatorV3Interface.sol";

contract SecurityOracle is AccessControl, ReentrancyGuard, ChainlinkClient {
    using Chainlink for Chainlink.Request;

    bytes32 public constant ORACLE_ROLE = keccak256("ORACLE_ROLE");
    bytes32 public constant VALIDATOR_ROLE = keccak256("VALIDATOR_ROLE");

    struct OracleConfig {
        address oracle;
        bytes32 jobId;
        uint256 fee;
        bool isActive;
    }

    struct SecurityCheck {
        bytes32 id;
        string checkType;
        bytes data;
        uint256 timestamp;
        uint256 result;
        bool isComplete;
        mapping(address => bool) validations;
    }

    struct ValidationThreshold {
        uint256 minResponses;
        uint256 consensusPercentage;
    }

    mapping(string => OracleConfig) public oracleConfigs;
    mapping(bytes32 => SecurityCheck) public securityChecks;
    mapping(string => ValidationThreshold) public validationThresholds;
    mapping(bytes32 => bytes32[]) public requestToCheck;

    event OracleConfigured(
        string indexed checkType,
        address oracle,
        bytes32 jobId
    );
    event SecurityCheckInitiated(
        bytes32 indexed checkId,
        string checkType,
        bytes data
    );
    event SecurityCheckCompleted(
        bytes32 indexed checkId,
        uint256 result
    );
    event ValidationSubmitted(
        bytes32 indexed checkId,
        address validator,
        uint256 result
    );
    event ConsensusReached(
        bytes32 indexed checkId,
        uint256 finalResult
    );

    constructor(address _link) {
        setChainlinkToken(_link);
        _setupRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _setupRole(ORACLE_ROLE, msg.sender);
    }

    function configureOracle(
        string memory checkType,
        address oracle,
        bytes32 jobId,
        uint256 fee
    ) external onlyRole(DEFAULT_ADMIN_ROLE) {
        oracleConfigs[checkType] = OracleConfig({
            oracle: oracle,
            jobId: jobId,
            fee: fee,
            isActive: true
        });

        emit OracleConfigured(checkType, oracle, jobId);
    }

    function setValidationThreshold(
        string memory checkType,
        uint256 minResponses,
        uint256 consensusPercentage
    ) external onlyRole(DEFAULT_ADMIN_ROLE) {
        require(consensusPercentage <= 100, "Invalid percentage");
        validationThresholds[checkType] = ValidationThreshold({
            minResponses: minResponses,
            consensusPercentage: consensusPercentage
        });
    }

    function initiateSecurityCheck(
        string memory checkType,
        bytes memory data
    ) external onlyRole(ORACLE_ROLE) returns (bytes32) {
        require(oracleConfigs[checkType].isActive, "Oracle not configured");

        bytes32 checkId = keccak256(
            abi.encodePacked(
                checkType,
                data,
                block.timestamp
            )
        );

        SecurityCheck storage check = securityChecks[checkId];
        check.id = checkId;
        check.checkType = checkType;
        check.data = data;
        check.timestamp = block.timestamp;

        Chainlink.Request memory req = buildChainlinkRequest(
            oracleConfigs[checkType].jobId,
            address(this),
            this.fulfillSecurityCheck.selector
        );

        req.add("checkType", checkType);
        req.addBytes("data", data);

        bytes32 requestId = sendChainlinkRequestTo(
            oracleConfigs[checkType].oracle,
            req,
            oracleConfigs[checkType].fee
        );

        requestToCheck[requestId].push(checkId);

        emit SecurityCheckInitiated(checkId, checkType, data);
        return checkId;
    }

    function fulfillSecurityCheck(
        bytes32 _requestId,
        uint256 _result
    ) external recordChainlinkFulfillment(_requestId) {
        bytes32[] storage checkIds = requestToCheck[_requestId];
        require(checkIds.length > 0, "No security check found");

        for (uint256 i = 0; i < checkIds.length; i++) {
            SecurityCheck storage check = securityChecks[checkIds[i]];
            check.result = _result;
            check.isComplete = true;

            emit SecurityCheckCompleted(checkIds[i], _result);
        }

        delete requestToCheck[_requestId];
    }

    function submitValidation(
        bytes32 checkId,
        uint256 result
    ) external onlyRole(VALIDATOR_ROLE) {
        SecurityCheck storage check = securityChecks[checkId];
        require(check.id == checkId, "Check not found");
        require(!check.validations[msg.sender], "Already validated");

        check.validations[msg.sender] = true;

        emit ValidationSubmitted(checkId, msg.sender, result);

        uint256 validations = 0;
        uint256 consensusCount = 0;
        
        for (uint256 i = 0; i < getRoleMemberCount(VALIDATOR_ROLE); i++) {
            address validator = getRoleMember(VALIDATOR_ROLE, i);
            if (check.validations[validator]) {
                validations++;
                if (check.result == result) {
                    consensusCount++;
                }
            }
        }

        ValidationThreshold memory threshold = validationThresholds[check.checkType];
        if (
            validations >= threshold.minResponses &&
            (consensusCount * 100 / validations) >= threshold.consensusPercentage
        ) {
            emit ConsensusReached(checkId, result);
        }
    }

    function getSecurityCheckStatus(bytes32 checkId)
        external
        view
        returns (
            string memory checkType,
            uint256 timestamp,
            uint256 result,
            bool isComplete,
            uint256 validationCount
        )
    {
        SecurityCheck storage check = securityChecks[checkId];
        require(check.id == checkId, "Check not found");

        uint256 validations = 0;
        for (uint256 i = 0; i < getRoleMemberCount(VALIDATOR_ROLE); i++) {
            address validator = getRoleMember(VALIDATOR_ROLE, i);
            if (check.validations[validator]) {
                validations++;
            }
        }

        return (
            check.checkType,
            check.timestamp,
            check.result,
            check.isComplete,
            validations
        );
    }

    receive() external payable {}
} 