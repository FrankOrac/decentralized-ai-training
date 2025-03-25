// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/security/Pausable.sol";
import "./interfaces/ILayerZeroEndpoint.sol";

contract CrossChainDelegation is AccessControl, ReentrancyGuard, Pausable {
    bytes32 public constant BRIDGE_ROLE = keccak256("BRIDGE_ROLE");
    bytes32 public constant OPERATOR_ROLE = keccak256("OPERATOR_ROLE");

    struct CrossChainDelegateInfo {
        uint256 sourceChainId;
        address delegator;
        address delegate;
        uint256 startTime;
        uint256 endTime;
        bool isActive;
        uint256 votingPower;
    }

    struct DelegationMessage {
        uint256 sourceChainId;
        address delegator;
        address delegate;
        uint256 votingPower;
        bytes32 delegationId;
        bool isRevocation;
    }

    ILayerZeroEndpoint public immutable lzEndpoint;
    
    mapping(uint256 => mapping(bytes32 => CrossChainDelegateInfo)) public delegations;
    mapping(address => uint256) public totalDelegatedPower;
    mapping(uint256 => uint256) public chainTrustScores;
    mapping(bytes32 => bool) public processedMessages;
    
    uint256 public minDelegationPeriod;
    uint256 public maxDelegationPeriod;
    uint256 public delegationCooldown;
    
    event CrossChainDelegationCreated(
        bytes32 indexed delegationId,
        uint256 indexed sourceChainId,
        address indexed delegator,
        address delegate,
        uint256 votingPower
    );
    event CrossChainDelegationRevoked(
        bytes32 indexed delegationId,
        uint256 indexed sourceChainId,
        address indexed delegator
    );
    event MessageReceived(
        bytes32 indexed messageId,
        uint256 indexed sourceChainId,
        address indexed sender
    );
    event ChainTrustScoreUpdated(
        uint256 indexed chainId,
        uint256 oldScore,
        uint256 newScore
    );

    constructor(
        address _lzEndpoint,
        uint256 _minDelegationPeriod,
        uint256 _maxDelegationPeriod,
        uint256 _delegationCooldown
    ) {
        lzEndpoint = ILayerZeroEndpoint(_lzEndpoint);
        minDelegationPeriod = _minDelegationPeriod;
        maxDelegationPeriod = _maxDelegationPeriod;
        delegationCooldown = _delegationCooldown;

        _setupRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _setupRole(BRIDGE_ROLE, msg.sender);
        _setupRole(OPERATOR_ROLE, msg.sender);
    }

    function createCrossChainDelegation(
        uint256 targetChainId,
        address delegate,
        uint256 duration,
        uint256 votingPower
    ) external payable nonReentrant whenNotPaused {
        require(duration >= minDelegationPeriod, "Duration too short");
        require(duration <= maxDelegationPeriod, "Duration too long");
        require(chainTrustScores[targetChainId] > 0, "Chain not trusted");

        bytes32 delegationId = keccak256(
            abi.encodePacked(
                block.timestamp,
                msg.sender,
                delegate,
                targetChainId
            )
        );

        DelegationMessage memory message = DelegationMessage({
            sourceChainId: block.chainid,
            delegator: msg.sender,
            delegate: delegate,
            votingPower: votingPower,
            delegationId: delegationId,
            isRevocation: false
        });

        _sendMessage(targetChainId, abi.encode(message));

        delegations[targetChainId][delegationId] = CrossChainDelegateInfo({
            sourceChainId: block.chainid,
            delegator: msg.sender,
            delegate: delegate,
            startTime: block.timestamp,
            endTime: block.timestamp + duration,
            isActive: true,
            votingPower: votingPower
        });

        emit CrossChainDelegationCreated(
            delegationId,
            block.chainid,
            msg.sender,
            delegate,
            votingPower
        );
    }

    function revokeCrossChainDelegation(
        uint256 targetChainId,
        bytes32 delegationId
    ) external nonReentrant whenNotPaused {
        CrossChainDelegateInfo storage delegation = delegations[targetChainId][delegationId];
        require(delegation.isActive, "Delegation not active");
        require(
            delegation.delegator == msg.sender || hasRole(OPERATOR_ROLE, msg.sender),
            "Not authorized"
        );

        delegation.isActive = false;
        delegation.endTime = block.timestamp;

        DelegationMessage memory message = DelegationMessage({
            sourceChainId: block.chainid,
            delegator: delegation.delegator,
            delegate: delegation.delegate,
            votingPower: 0,
            delegationId: delegationId,
            isRevocation: true
        });

        _sendMessage(targetChainId, abi.encode(message));

        emit CrossChainDelegationRevoked(
            delegationId,
            block.chainid,
            delegation.delegator
        );
    }

    function lzReceive(
        uint16 _srcChainId,
        bytes memory _srcAddress,
        uint64 _nonce,
        bytes memory _payload
    ) external {
        require(msg.sender == address(lzEndpoint), "Invalid endpoint");
        
        bytes32 messageId = keccak256(
            abi.encodePacked(_srcChainId, _srcAddress, _nonce, _payload)
        );
        require(!processedMessages[messageId], "Message already processed");

        DelegationMessage memory message = abi.decode(_payload, (DelegationMessage));
        
        if (!message.isRevocation) {
            _handleDelegationCreation(message);
        } else {
            _handleDelegationRevocation(message);
        }

        processedMessages[messageId] = true;
        emit MessageReceived(messageId, _srcChainId, msg.sender);
    }

    function updateChainTrustScore(
        uint256 chainId,
        uint256 newScore
    ) external onlyRole(OPERATOR_ROLE) {
        uint256 oldScore = chainTrustScores[chainId];
        chainTrustScores[chainId] = newScore;
        emit ChainTrustScoreUpdated(chainId, oldScore, newScore);
    }

    function _handleDelegationCreation(
        DelegationMessage memory message
    ) internal {
        require(chainTrustScores[message.sourceChainId] > 0, "Chain not trusted");
        
        totalDelegatedPower[message.delegate] += message.votingPower;

        delegations[message.sourceChainId][message.delegationId] = CrossChainDelegateInfo({
            sourceChainId: message.sourceChainId,
            delegator: message.delegator,
            delegate: message.delegate,
            startTime: block.timestamp,
            endTime: block.timestamp + maxDelegationPeriod,
            isActive: true,
            votingPower: message.votingPower
        });
    }

    function _handleDelegationRevocation(
        DelegationMessage memory message
    ) internal {
        CrossChainDelegateInfo storage delegation = delegations[message.sourceChainId][message.delegationId];
        require(delegation.isActive, "Delegation not active");

        delegation.isActive = false;
        delegation.endTime = block.timestamp;
        totalDelegatedPower[delegation.delegate] -= delegation.votingPower;
    }

    function _sendMessage(
        uint256 targetChainId,
        bytes memory payload
    ) internal {
        bytes memory remoteAndLocalAddresses = abi.encodePacked(address(this), address(this));
        
        lzEndpoint.send{value: msg.value}(
            uint16(targetChainId),
            remoteAndLocalAddresses,
            payload,
            payable(msg.sender),
            address(0),
            bytes("")
        );
    }

    function pause() external onlyRole(OPERATOR_ROLE) {
        _pause();
    }

    function unpause() external onlyRole(OPERATOR_ROLE) {
        _unpause();
    }

    receive() external payable {}
} 