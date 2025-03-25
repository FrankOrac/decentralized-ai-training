// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";

interface ILayerZeroEndpoint {
    function send(
        uint16 _dstChainId,
        bytes calldata _destination,
        bytes calldata _payload,
        address payable _refundAddress,
        address _zroPaymentAddress,
        bytes calldata _adapterParams
    ) external payable;
}

contract CrossChainBridge is AccessControl, ReentrancyGuard {
    ILayerZeroEndpoint public endpoint;
    
    struct CrossChainModel {
        string modelHash;
        uint256 sourceChainId;
        address creator;
        uint256 timestamp;
        bool isVerified;
    }

    mapping(uint256 => CrossChainModel) public models;
    mapping(uint16 => address) public trustedRemotes;
    uint256 public modelCount;

    event ModelShared(uint256 indexed modelId, uint16 targetChain);
    event ModelReceived(uint256 indexed modelId, uint16 sourceChain);
    event TrustedRemoteAdded(uint16 chainId, address remote);

    constructor(address _endpoint) {
        endpoint = ILayerZeroEndpoint(_endpoint);
        _setupRole(DEFAULT_ADMIN_ROLE, msg.sender);
    }

    function shareModel(
        string memory _modelHash,
        uint16 _targetChain
    ) external payable nonReentrant {
        require(trustedRemotes[_targetChain] != address(0), "Invalid target chain");

        modelCount++;
        models[modelCount] = CrossChainModel({
            modelHash: _modelHash,
            sourceChainId: block.chainid,
            creator: msg.sender,
            timestamp: block.timestamp,
            isVerified: false
        });

        bytes memory payload = abi.encode(
            modelCount,
            _modelHash,
            msg.sender
        );

        endpoint.send{value: msg.value}(
            _targetChain,
            abi.encodePacked(trustedRemotes[_targetChain], address(this)),
            payload,
            payable(msg.sender),
            address(0),
            ""
        );

        emit ModelShared(modelCount, _targetChain);
    }

    function lzReceive(
        uint16 _srcChainId,
        bytes memory _srcAddress,
        uint64 _nonce,
        bytes memory _payload
    ) external {
        require(msg.sender == address(endpoint), "Invalid endpoint");
        require(
            _srcAddress.length == 40 && 
            address(uint160(uint256(bytes32(_srcAddress)))) == trustedRemotes[_srcChainId],
            "Invalid source"
        );

        (
            uint256 modelId,
            string memory modelHash,
            address creator
        ) = abi.decode(_payload, (uint256, string, address));

        modelCount++;
        models[modelCount] = CrossChainModel({
            modelHash: modelHash,
            sourceChainId: _srcChainId,
            creator: creator,
            timestamp: block.timestamp,
            isVerified: false
        });

        emit ModelReceived(modelCount, _srcChainId);
    }

    function setTrustedRemote(
        uint16 _chainId,
        address _remote
    ) external onlyRole(DEFAULT_ADMIN_ROLE) {
        trustedRemotes[_chainId] = _remote;
        emit TrustedRemoteAdded(_chainId, _remote);
    }

    function verifyModel(
        uint256 _modelId
    ) external onlyRole(DEFAULT_ADMIN_ROLE) {
        require(_modelId <= modelCount, "Invalid model ID");
        models[_modelId].isVerified = true;
    }

    function getModel(uint256 _modelId)
        external view returns (CrossChainModel memory)
    {
        require(_modelId <= modelCount, "Invalid model ID");
        return models[_modelId];
    }
} 