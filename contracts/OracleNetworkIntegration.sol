// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@chainlink/contracts/src/v0.8/ChainlinkClient.sol";
import "@api3/airnode-protocol/contracts/rrp/requesters/RrpRequesterV0.sol";
import "@uma/core/contracts/oracle/interfaces/OptimisticOracleV2Interface.sol";

contract OracleNetworkIntegration is AccessControl, ReentrancyGuard, ChainlinkClient, RrpRequesterV0 {
    bytes32 public constant ORACLE_MANAGER = keccak256("ORACLE_MANAGER");
    
    struct OracleConfig {
        string provider;
        address oracle;
        bytes32 jobId;
        uint256 fee;
        bool isActive;
        uint256 minimumResponses;
        uint256 responseTimeout;
    }

    struct OracleRequest {
        bytes32 id;
        string dataType;
        bytes parameters;
        uint256 timestamp;
        uint256 responses;
        mapping(address => bytes) oracleResponses;
        bool isResolved;
        bytes result;
    }

    struct ProviderMetrics {
        uint256 totalRequests;
        uint256 successfulResponses;
        uint256 failedResponses;
        uint256 averageResponseTime;
        uint256 lastUpdateTime;
    }

    mapping(string => OracleConfig) public oracleConfigs;
    mapping(bytes32 => OracleRequest) public requests;
    mapping(address => ProviderMetrics) public providerMetrics;
    mapping(bytes32 => bytes32) public requestToAirnode;
    
    OptimisticOracleV2Interface public umaOracle;
    
    event OracleConfigured(
        string provider,
        address oracle,
        bytes32 jobId
    );
    event RequestCreated(
        bytes32 indexed requestId,
        string dataType,
        bytes parameters
    );
    event ResponseReceived(
        bytes32 indexed requestId,
        address oracle,
        bytes result
    );
    event RequestResolved(
        bytes32 indexed requestId,
        bytes result
    );
    event ProviderMetricsUpdated(
        address indexed provider,
        uint256 successRate,
        uint256 averageResponseTime
    );

    constructor(
        address _link,
        address _airnodeRrp,
        address _umaOracle
    ) RrpRequesterV0(_airnodeRrp) {
        setChainlinkToken(_link);
        umaOracle = OptimisticOracleV2Interface(_umaOracle);
        _setupRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _setupRole(ORACLE_MANAGER, msg.sender);
    }

    function configureOracle(
        string memory provider,
        address oracle,
        bytes32 jobId,
        uint256 fee,
        uint256 minimumResponses,
        uint256 responseTimeout
    ) external onlyRole(ORACLE_MANAGER) {
        require(oracle != address(0), "Invalid oracle address");
        require(fee > 0, "Invalid fee");
        require(minimumResponses > 0, "Invalid minimum responses");
        require(responseTimeout > 0, "Invalid timeout");

        oracleConfigs[provider] = OracleConfig({
            provider: provider,
            oracle: oracle,
            jobId: jobId,
            fee: fee,
            isActive: true,
            minimumResponses: minimumResponses,
            responseTimeout: responseTimeout
        });

        emit OracleConfigured(provider, oracle, jobId);
    }

    function createRequest(
        string memory dataType,
        bytes memory parameters
    ) external onlyRole(ORACLE_MANAGER) returns (bytes32) {
        bytes32 requestId = keccak256(
            abi.encodePacked(
                dataType,
                parameters,
                block.timestamp
            )
        );

        OracleRequest storage request = requests[requestId];
        request.id = requestId;
        request.dataType = dataType;
        request.parameters = parameters;
        request.timestamp = block.timestamp;

        // Make requests to all configured oracles
        _makeChainlinkRequest(requestId, dataType, parameters);
        _makeAirnodeRequest(requestId, dataType, parameters);
        _makeUMARequest(requestId, dataType, parameters);

        emit RequestCreated(requestId, dataType, parameters);
        return requestId;
    }

    function _makeChainlinkRequest(
        bytes32 requestId,
        string memory dataType,
        bytes memory parameters
    ) internal {
        OracleConfig storage config = oracleConfigs["chainlink"];
        if (!config.isActive) return;

        Chainlink.Request memory req = buildChainlinkRequest(
            config.jobId,
            address(this),
            this.fulfillChainlinkRequest.selector
        );

        req.add("requestId", bytes32ToString(requestId));
        req.add("dataType", dataType);
        req.addBytes("parameters", parameters);

        sendChainlinkRequestTo(config.oracle, req, config.fee);
    }

    function _makeAirnodeRequest(
        bytes32 requestId,
        string memory dataType,
        bytes memory parameters
    ) internal {
        OracleConfig storage config = oracleConfigs["airnode"];
        if (!config.isActive) return;

        bytes32 airnodeRequestId = makeRequestToAirnode(
            config.oracle,
            config.jobId,
            address(this),
            this.fulfillAirnodeRequest.selector,
            abi.encode(requestId, dataType, parameters)
        );

        requestToAirnode[requestId] = airnodeRequestId;
    }

    function _makeUMARequest(
        bytes32 requestId,
        string memory dataType,
        bytes memory parameters
    ) internal {
        OracleConfig storage config = oracleConfigs["uma"];
        if (!config.isActive) return;

        bytes memory ancillaryData = abi.encodePacked(
            "requestId:", requestId,
            ",dataType:", bytes(dataType),
            ",parameters:", parameters
        );

        umaOracle.requestPrice(
            keccak256(ancillaryData),
            address(this),
            config.oracle,
            address(0),
            config.responseTimeout,
            config.fee,
            0,
            ancillaryData
        );
    }

    function fulfillChainlinkRequest(
        bytes32 _requestId,
        bytes memory _result
    ) external recordChainlinkFulfillment(_requestId) {
        _handleOracleResponse(_requestId, msg.sender, _result);
    }

    function fulfillAirnodeRequest(
        bytes32 _airnodeRequestId,
        bytes memory _result
    ) external {
        bytes32 requestId;
        for (bytes32 rid : requestToAirnode) {
            if (requestToAirnode[rid] == _airnodeRequestId) {
                requestId = rid;
                break;
            }
        }
        require(requestId != bytes32(0), "Request not found");
        _handleOracleResponse(requestId, msg.sender, _result);
    }

    function priceSettled(
        bytes32 _requestId,
        bytes memory _result
    ) external {
        require(msg.sender == address(umaOracle), "Unauthorized");
        _handleOracleResponse(_requestId, msg.sender, _result);
    }

    function _handleOracleResponse(
        bytes32 requestId,
        address oracle,
        bytes memory result
    ) internal {
        OracleRequest storage request = requests[requestId];
        require(request.id == requestId, "Request not found");
        require(!request.oracleResponses[oracle], "Already responded");

        request.oracleResponses[oracle] = result;
        request.responses++;

        // Update provider metrics
        ProviderMetrics storage metrics = providerMetrics[oracle];
        metrics.totalRequests++;
        metrics.successfulResponses++;
        metrics.averageResponseTime = (
            metrics.averageResponseTime * (metrics.successfulResponses - 1) +
            (block.timestamp - request.timestamp)
        ) / metrics.successfulResponses;
        metrics.lastUpdateTime = block.timestamp;

        emit ResponseReceived(requestId, oracle, result);

        // Check if we have enough responses
        OracleConfig storage config = oracleConfigs[_getProviderForOracle(oracle)];
        if (request.responses >= config.minimumResponses) {
            _resolveRequest(request);
        }

        emit ProviderMetricsUpdated(
            oracle,
            (metrics.successfulResponses * 100) / metrics.totalRequests,
            metrics.averageResponseTime
        );
    }

    function _resolveRequest(OracleRequest storage request) internal {
        if (request.isResolved) return;

        // Aggregate responses
        bytes[] memory responses = new bytes[](request.responses);
        uint256 i = 0;
        for (address oracle : request.oracleResponses) {
            if (request.oracleResponses[oracle].length > 0) {
                responses[i] = request.oracleResponses[oracle];
                i++;
            }
        }

        request.result = _aggregateResponses(responses);
        request.isResolved = true;

        emit RequestResolved(request.id, request.result);
    }

    function _aggregateResponses(bytes[] memory responses)
        internal
        pure
        returns (bytes memory)
    {
        // Implement your response aggregation logic here
        // This is a simplified version that returns the most common response
        bytes memory mostCommon = responses[0];
        uint256 maxCount = 1;

        for (uint256 i = 0; i < responses.length; i++) {
            uint256 count = 1;
            for (uint256 j = i + 1; j < responses.length; j++) {
                if (keccak256(responses[i]) == keccak256(responses[j])) {
                    count++;
                }
            }
            if (count > maxCount) {
                maxCount = count;
                mostCommon = responses[i];
            }
        }

        return mostCommon;
    }

    function _getProviderForOracle(address oracle)
        internal
        view
        returns (string memory)
    {
        if (oracle == oracleConfigs["chainlink"].oracle) return "chainlink";
        if (oracle == oracleConfigs["airnode"].oracle) return "airnode";
        if (oracle == oracleConfigs["uma"].oracle) return "uma";
        return "";
    }

    function bytes32ToString(bytes32 _bytes32)
        internal
        pure
        returns (string memory)
    {
        bytes memory bytesArray = new bytes(64);
        for (uint256 i = 0; i < 32; i++) {
            bytes1 char = bytes1(uint8(uint256(_bytes32) / (2**(8*(31 - i)))));
            bytes1 hi = bytes1(uint8(char) / 16);
            bytes1 lo = bytes1(uint8(char) - 16 * uint8(hi));
            bytesArray[i*2] = char2hex(hi);
            bytesArray[i*2+1] = char2hex(lo);
        }
        return string(bytesArray);
    }

    function char2hex(bytes1 char) internal pure returns (bytes1) {
        if (uint8(char) < 10) return bytes1(uint8(char) + 0x30);
        else return bytes1(uint8(char) + 0x57);
    }

    receive() external payable {}
} 