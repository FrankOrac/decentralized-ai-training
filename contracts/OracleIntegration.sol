// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@chainlink/contracts/src/v0.8/interfaces/AggregatorV3Interface.sol";
import "@api3/airnode-protocol/contracts/rrp/requesters/RrpRequesterV0.sol";
import "@uma/core/contracts/oracle/interfaces/OptimisticOracleV2Interface.sol";

contract OracleIntegration is AccessControl, ReentrancyGuard, RrpRequesterV0 {
    bytes32 public constant ORACLE_ADMIN = keccak256("ORACLE_ADMIN");
    bytes32 public constant REQUESTER_ROLE = keccak256("REQUESTER_ROLE");

    struct OracleConfig {
        address oracleAddress;
        bytes32 jobId;
        uint256 fee;
        bool isActive;
        string oracleType; // "chainlink", "uma", "api3"
    }

    struct OracleRequest {
        bytes32 id;
        address requester;
        string dataType;
        bytes parameters;
        uint256 timestamp;
        bool fulfilled;
        bytes result;
    }

    mapping(string => OracleConfig) public oracleConfigs;
    mapping(bytes32 => OracleRequest) public requests;
    mapping(string => bytes32[]) public dataTypeToRequests;
    
    OptimisticOracleV2Interface public umaOracle;
    uint256 public constant DISPUTE_PERIOD = 2 hours;
    uint256 public constant BOND_AMOUNT = 0.1 ether;

    event OracleConfigured(
        string indexed oracleType,
        address oracleAddress,
        bytes32 jobId
    );
    event OracleRequestSent(
        bytes32 indexed requestId,
        string dataType,
        address requester
    );
    event OracleResponseReceived(
        bytes32 indexed requestId,
        bytes result
    );
    event DisputeRaised(
        bytes32 indexed requestId,
        address disputer,
        string reason
    );

    constructor(
        address _airnodeRrp,
        address _umaOracle
    ) RrpRequesterV0(_airnodeRrp) {
        _setupRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _setupRole(ORACLE_ADMIN, msg.sender);
        umaOracle = OptimisticOracleV2Interface(_umaOracle);
    }

    function configureOracle(
        string memory oracleType,
        address oracleAddress,
        bytes32 jobId,
        uint256 fee
    ) external onlyRole(ORACLE_ADMIN) {
        require(oracleAddress != address(0), "Invalid oracle address");
        require(bytes(oracleType).length > 0, "Invalid oracle type");

        oracleConfigs[oracleType] = OracleConfig({
            oracleAddress: oracleAddress,
            jobId: jobId,
            fee: fee,
            isActive: true,
            oracleType: oracleType
        });

        emit OracleConfigured(oracleType, oracleAddress, jobId);
    }

    function requestData(
        string memory dataType,
        bytes memory parameters
    ) external onlyRole(REQUESTER_ROLE) returns (bytes32) {
        bytes32 requestId = keccak256(
            abi.encodePacked(
                dataType,
                parameters,
                block.timestamp,
                msg.sender
            )
        );

        requests[requestId] = OracleRequest({
            id: requestId,
            requester: msg.sender,
            dataType: dataType,
            parameters: parameters,
            timestamp: block.timestamp,
            fulfilled: false,
            result: new bytes(0)
        });

        dataTypeToRequests[dataType].push(requestId);

        // Route to appropriate oracle based on data type
        if (keccak256(bytes(dataType)) == keccak256(bytes("PRICE_FEED"))) {
            _requestChainlinkData(requestId, parameters);
        } else if (keccak256(bytes(dataType)) == keccak256(bytes("OFF_CHAIN_DATA"))) {
            _requestApi3Data(requestId, parameters);
        } else if (keccak256(bytes(dataType)) == keccak256(bytes("DISPUTE_RESOLUTION"))) {
            _requestUmaData(requestId, parameters);
        }

        emit OracleRequestSent(requestId, dataType, msg.sender);
        return requestId;
    }

    function _requestChainlinkData(
        bytes32 requestId,
        bytes memory parameters
    ) private {
        OracleConfig memory config = oracleConfigs["chainlink"];
        require(config.isActive, "Chainlink oracle not configured");

        AggregatorV3Interface aggregator = AggregatorV3Interface(config.oracleAddress);
        (, int256 price,,,) = aggregator.latestRoundData();
        
        _fulfillRequest(requestId, abi.encode(price));
    }

    function _requestApi3Data(
        bytes32 requestId,
        bytes memory parameters
    ) private {
        OracleConfig memory config = oracleConfigs["api3"];
        require(config.isActive, "API3 oracle not configured");

        (address airnode, bytes32 endpointId) = abi.decode(parameters, (address, bytes32));
        
        bytes32 api3RequestId = airnodeRrp.makeFullRequest(
            airnode,
            endpointId,
            address(this),
            msg.sender,
            address(this),
            this.fulfillApi3Request.selector,
            parameters
        );

        // Store mapping between API3 request ID and our request ID
        requests[requestId].parameters = abi.encode(api3RequestId);
    }

    function _requestUmaData(
        bytes32 requestId,
        bytes memory parameters
    ) private {
        OracleConfig memory config = oracleConfigs["uma"];
        require(config.isActive, "UMA oracle not configured");

        bytes memory ancillaryData = abi.encodePacked(
            "requestId:", requestId,
            ",parameters:", parameters
        );

        umaOracle.requestPrice(
            keccak256(ancillaryData),
            DISPUTE_PERIOD,
            ancillaryData,
            BOND_AMOUNT,
            msg.sender
        );
    }

    function fulfillApi3Request(
        bytes32 api3RequestId,
        bytes calldata data
    ) external onlyAirnodeRrp {
        // Find our request ID from API3 request ID
        bytes32 requestId;
        for (uint i = 0; i < dataTypeToRequests["OFF_CHAIN_DATA"].length; i++) {
            bytes32 rId = dataTypeToRequests["OFF_CHAIN_DATA"][i];
            if (keccak256(requests[rId].parameters) == keccak256(abi.encode(api3RequestId))) {
                requestId = rId;
                break;
            }
        }
        require(requestId != bytes32(0), "Request not found");

        _fulfillRequest(requestId, data);
    }

    function fulfillUmaRequest(
        bytes32 requestId,
        bytes memory result
    ) external {
        require(msg.sender == address(umaOracle), "Unauthorized");
        _fulfillRequest(requestId, result);
    }

    function _fulfillRequest(
        bytes32 requestId,
        bytes memory result
    ) private {
        OracleRequest storage request = requests[requestId];
        require(!request.fulfilled, "Request already fulfilled");

        request.fulfilled = true;
        request.result = result;

        emit OracleResponseReceived(requestId, result);
    }

    function raiseDispute(
        bytes32 requestId,
        string memory reason
    ) external {
        require(
            requests[requestId].fulfilled,
            "Request not fulfilled"
        );
        require(
            block.timestamp <= requests[requestId].timestamp + DISPUTE_PERIOD,
            "Dispute period ended"
        );

        emit DisputeRaised(requestId, msg.sender, reason);

        // If UMA request, trigger dispute resolution
        if (keccak256(bytes(requests[requestId].dataType)) == keccak256(bytes("DISPUTE_RESOLUTION"))) {
            umaOracle.disputePrice(
                msg.sender,
                keccak256(requests[requestId].parameters),
                requests[requestId].timestamp,
                requests[requestId].parameters
            );
        }
    }

    function getRequestResult(
        bytes32 requestId
    ) external view returns (bytes memory) {
        require(requests[requestId].fulfilled, "Request not fulfilled");
        return requests[requestId].result;
    }

    function getRequestsByDataType(
        string memory dataType
    ) external view returns (bytes32[] memory) {
        return dataTypeToRequests[dataType];
    }

    receive() external payable {}
} 