// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";

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

contract CrossChainVerifier is AccessControl, ReentrancyGuard {
    using ECDSA for bytes32;

    bytes32 public constant VERIFIER_ROLE = keccak256("VERIFIER_ROLE");
    bytes32 public constant BRIDGE_ROLE = keccak256("BRIDGE_ROLE");
    
    struct VerificationRequest {
        bytes32 requestId;
        string modelHash;
        uint16[] targetChains;
        mapping(uint16 => bool) chainVerified;
        mapping(uint16 => bytes32) proofs;
        uint256 requiredVerifications;
        uint256 completedVerifications;
        VerificationStatus status;
        address requester;
        uint256 timestamp;
    }

    struct ChainVerification {
        bytes32 requestId;
        uint16 sourceChain;
        bytes32 proof;
        address verifier;
        uint256 timestamp;
        bool isValid;
    }

    enum VerificationStatus {
        Pending,
        InProgress,
        Completed,
        Failed
    }

    ILayerZeroEndpoint public endpoint;
    mapping(bytes32 => VerificationRequest) public requests;
    mapping(bytes32 => ChainVerification[]) public verifications;
    mapping(uint16 => address) public trustedVerifiers;
    mapping(uint16 => bytes32) public chainTrustAnchors;
    
    uint256 public verificationTimeout;
    uint256 public requiredConfirmations;
    uint256 public verificationFee;

    event VerificationRequested(
        bytes32 indexed requestId,
        string modelHash,
        uint16[] targetChains
    );
    event VerificationReceived(
        bytes32 indexed requestId,
        uint16 sourceChain,
        bytes32 proof
    );
    event VerificationCompleted(
        bytes32 indexed requestId,
        bool success
    );
    event TrustAnchorUpdated(
        uint16 indexed chainId,
        bytes32 trustAnchor
    );

    constructor(
        address _endpoint,
        uint256 _verificationTimeout,
        uint256 _requiredConfirmations,
        uint256 _verificationFee
    ) {
        endpoint = ILayerZeroEndpoint(_endpoint);
        verificationTimeout = _verificationTimeout;
        requiredConfirmations = _requiredConfirmations;
        verificationFee = _verificationFee;
        
        _setupRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _setupRole(VERIFIER_ROLE, msg.sender);
    }

    function requestVerification(
        string memory _modelHash,
        uint16[] memory _targetChains
    ) external payable nonReentrant returns (bytes32) {
        require(_targetChains.length > 0, "No target chains specified");
        require(
            msg.value >= verificationFee * _targetChains.length,
            "Insufficient verification fee"
        );

        bytes32 requestId = keccak256(abi.encodePacked(
            _modelHash,
            block.timestamp,
            msg.sender
        ));

        VerificationRequest storage request = requests[requestId];
        request.requestId = requestId;
        request.modelHash = _modelHash;
        request.targetChains = _targetChains;
        request.requiredVerifications = _targetChains.length;
        request.status = VerificationStatus.InProgress;
        request.requester = msg.sender;
        request.timestamp = block.timestamp;

        // Send verification requests to target chains
        for (uint i = 0; i < _targetChains.length; i++) {
            require(
                trustedVerifiers[_targetChains[i]] != address(0),
                "Untrusted chain"
            );
            
            bytes memory payload = abi.encode(
                requestId,
                _modelHash,
                block.chainid
            );

            endpoint.send{value: verificationFee}(
                _targetChains[i],
                abi.encodePacked(trustedVerifiers[_targetChains[i]]),
                payload,
                payable(msg.sender),
                address(0),
                ""
            );
        }

        emit VerificationRequested(requestId, _modelHash, _targetChains);
        return requestId;
    }

    function submitVerification(
        bytes32 _requestId,
        bytes32 _proof,
        bytes memory _signature
    ) external onlyRole(VERIFIER_ROLE) {
        VerificationRequest storage request = requests[_requestId];
        require(
            request.status == VerificationStatus.InProgress,
            "Invalid request status"
        );
        require(
            block.timestamp <= request.timestamp + verificationTimeout,
            "Verification timeout"
        );

        // Verify signature
        bytes32 messageHash = keccak256(abi.encodePacked(_requestId, _proof));
        require(verifySignature(messageHash, _signature), "Invalid signature");

        uint16 sourceChain = uint16(block.chainid);
        require(!request.chainVerified[sourceChain], "Already verified");

        request.chainVerified[sourceChain] = true;
        request.proofs[sourceChain] = _proof;
        request.completedVerifications++;

        verifications[_requestId].push(ChainVerification({
            requestId: _requestId,
            sourceChain: sourceChain,
            proof: _proof,
            verifier: msg.sender,
            timestamp: block.timestamp,
            isValid: true
        }));

        emit VerificationReceived(_requestId, sourceChain, _proof);

        if (request.completedVerifications >= request.requiredVerifications) {
            finalizeVerification(_requestId);
        }
    }

    function finalizeVerification(bytes32 _requestId) internal {
        VerificationRequest storage request = requests[_requestId];
        bool isValid = true;

        // Check all proofs against trust anchors
        for (uint i = 0; i < request.targetChains.length; i++) {
            uint16 chainId = request.targetChains[i];
            if (!request.chainVerified[chainId] ||
                !validateProof(request.proofs[chainId], chainTrustAnchors[chainId])) {
                isValid = false;
                break;
            }
        }

        request.status = isValid ? 
            VerificationStatus.Completed : 
            VerificationStatus.Failed;

        emit VerificationCompleted(_requestId, isValid);
    }

    function validateProof(
        bytes32 _proof,
        bytes32 _trustAnchor
    ) internal pure returns (bool) {
        // Implement proof validation logic against trust anchor
        // This is a simplified version
        return _proof != bytes32(0) && _trustAnchor != bytes32(0);
    }

    function verifySignature(
        bytes32 _messageHash,
        bytes memory _signature
    ) internal view returns (bool) {
        bytes32 ethSignedMessageHash = _messageHash.toEthSignedMessageHash();
        address signer = ethSignedMessageHash.recover(_signature);
        return hasRole(VERIFIER_ROLE, signer);
    }

    function setTrustedVerifier(
        uint16 _chainId,
        address _verifier
    ) external onlyRole(DEFAULT_ADMIN_ROLE) {
        trustedVerifiers[_chainId] = _verifier;
    }

    function setTrustAnchor(
        uint16 _chainId,
        bytes32 _trustAnchor
    ) external onlyRole(DEFAULT_ADMIN_ROLE) {
        chainTrustAnchors[_chainId] = _trustAnchor;
        emit TrustAnchorUpdated(_chainId, _trustAnchor);
    }

    function getVerificationStatus(bytes32 _requestId)
        external
        view
        returns (
            string memory modelHash,
            uint16[] memory targetChains,
            uint256 completedVerifications,
            VerificationStatus status,
            address requester,
            uint256 timestamp
        )
    {
        VerificationRequest storage request = requests[_requestId];
        return (
            request.modelHash,
            request.targetChains,
            request.completedVerifications,
            request.status,
            request.requester,
            request.timestamp
        );
    }

    function getVerifications(bytes32 _requestId)
        external
        view
        returns (ChainVerification[] memory)
    {
        return verifications[_requestId];
    }

    function updateVerificationParams(
        uint256 _timeout,
        uint256 _confirmations,
        uint256 _fee
    ) external onlyRole(DEFAULT_ADMIN_ROLE) {
        verificationTimeout = _timeout;
        requiredConfirmations = _confirmations;
        verificationFee = _fee;
    }
} 