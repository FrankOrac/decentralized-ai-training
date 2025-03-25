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

    function receivePayload(
        uint16 _srcChainId,
        bytes calldata _srcAddress,
        address _dstAddress,
        uint64 _nonce,
        bytes calldata _payload
    ) external;
}

contract CrossChainModelVerifier is AccessControl, ReentrancyGuard {
    using ECDSA for bytes32;

    bytes32 public constant VERIFIER_ROLE = keccak256("VERIFIER_ROLE");

    struct ModelVerification {
        string modelHash;
        string modelURI;
        uint256[] targetChains;
        uint256 requiredVerifications;
        uint256 verificationCount;
        VerificationStatus status;
        mapping(uint256 => bool) chainVerified;
        mapping(address => bool) verifierApproved;
    }

    struct VerificationResult {
        bool success;
        string resultHash;
        bytes signature;
        uint256 timestamp;
        address verifier;
    }

    enum VerificationStatus {
        Pending,
        InProgress,
        Verified,
        Failed
    }

    ILayerZeroEndpoint public endpoint;
    mapping(string => ModelVerification) public verifications;
    mapping(string => VerificationResult[]) public verificationResults;
    mapping(uint256 => address) public trustedVerifiers;
    mapping(uint256 => string) public chainIdentifiers;

    uint256 public verificationTimeout;
    uint256 public minVerifications;

    event VerificationRequested(
        string indexed modelHash,
        uint256[] targetChains,
        uint256 requiredVerifications
    );
    event VerificationReceived(
        string indexed modelHash,
        uint256 sourceChain,
        bool success
    );
    event ModelVerified(
        string indexed modelHash,
        string resultHash
    );
    event VerificationFailed(
        string indexed modelHash,
        string reason
    );

    constructor(
        address _endpoint,
        uint256 _verificationTimeout,
        uint256 _minVerifications
    ) {
        endpoint = ILayerZeroEndpoint(_endpoint);
        verificationTimeout = _verificationTimeout;
        minVerifications = _minVerifications;
        _setupRole(DEFAULT_ADMIN_ROLE, msg.sender);
    }

    function requestVerification(
        string memory _modelHash,
        string memory _modelURI,
        uint256[] memory _targetChains
    ) external payable nonReentrant {
        require(_targetChains.length >= minVerifications, "Insufficient target chains");
        require(bytes(_modelURI).length > 0, "Invalid model URI");

        ModelVerification storage verification = verifications[_modelHash];
        require(verification.status == VerificationStatus.Pending, "Verification exists");

        verification.modelHash = _modelHash;
        verification.modelURI = _modelURI;
        verification.targetChains = _targetChains;
        verification.requiredVerifications = _targetChains.length;
        verification.status = VerificationStatus.InProgress;

        // Send verification requests to target chains
        for (uint i = 0; i < _targetChains.length; i++) {
            bytes memory payload = abi.encode(
                _modelHash,
                _modelURI,
                block.chainid
            );

            endpoint.send{value: msg.value / _targetChains.length}(
                uint16(_targetChains[i]),
                abi.encodePacked(trustedVerifiers[_targetChains[i]]),
                payload,
                payable(msg.sender),
                address(0),
                ""
            );
        }

        emit VerificationRequested(
            _modelHash,
            _targetChains,
            verification.requiredVerifications
        );
    }

    function submitVerification(
        string memory _modelHash,
        bool _success,
        string memory _resultHash,
        bytes memory _signature
    ) external onlyRole(VERIFIER_ROLE) {
        ModelVerification storage verification = verifications[_modelHash];
        require(
            verification.status == VerificationStatus.InProgress,
            "Invalid verification status"
        );
        require(!verification.verifierApproved[msg.sender], "Already verified");

        // Verify signature
        bytes32 messageHash = keccak256(abi.encodePacked(
            _modelHash,
            _success,
            _resultHash
        ));
        require(verifySignature(messageHash, _signature), "Invalid signature");

        verification.verifierApproved[msg.sender] = true;
        verification.chainVerified[block.chainid] = _success;
        verification.verificationCount++;

        verificationResults[_modelHash].push(VerificationResult({
            success: _success,
            resultHash: _resultHash,
            signature: _signature,
            timestamp: block.timestamp,
            verifier: msg.sender
        }));

        emit VerificationReceived(_modelHash, block.chainid, _success);

        if (verification.verificationCount >= verification.requiredVerifications) {
            finalizeVerification(_modelHash);
        }
    }

    function finalizeVerification(string memory _modelHash) internal {
        ModelVerification storage verification = verifications[_modelHash];
        uint256 successCount = 0;
        string memory finalResultHash;

        for (uint i = 0; i < verificationResults[_modelHash].length; i++) {
            if (verificationResults[_modelHash][i].success) {
                successCount++;
                finalResultHash = verificationResults[_modelHash][i].resultHash;
            }
        }

        if (successCount >= verification.requiredVerifications) {
            verification.status = VerificationStatus.Verified;
            emit ModelVerified(_modelHash, finalResultHash);
        } else {
            verification.status = VerificationStatus.Failed;
            emit VerificationFailed(_modelHash, "Insufficient successful verifications");
        }
    }

    function lzReceive(
        uint16 _srcChainId,
        bytes memory _srcAddress,
        uint64 _nonce,
        bytes memory _payload
    ) external {
        require(msg.sender == address(endpoint), "Invalid endpoint");
        
        (
            string memory modelHash,
            string memory modelURI,
            uint256 sourceChain
        ) = abi.decode(_payload, (string, string, uint256));

        // Verify the source chain
        require(
            trustedVerifiers[_srcChainId] == address(uint160(bytes20(_srcAddress))),
            "Invalid source verifier"
        );

        // Start local verification process
        startLocalVerification(modelHash, modelURI, sourceChain);
    }

    function startLocalVerification(
        string memory _modelHash,
        string memory _modelURI,
        uint256 _sourceChain
    ) internal {
        ModelVerification storage verification = verifications[_modelHash];
        verification.modelHash = _modelHash;
        verification.modelURI = _modelURI;
        verification.status = VerificationStatus.InProgress;
        verification.targetChains = new uint256[](1);
        verification.targetChains[0] = _sourceChain;
        verification.requiredVerifications = 1;
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
        uint256 _chainId,
        address _verifier
    ) external onlyRole(DEFAULT_ADMIN_ROLE) {
        trustedVerifiers[_chainId] = _verifier;
    }

    function setChainIdentifier(
        uint256 _chainId,
        string memory _identifier
    ) external onlyRole(DEFAULT_ADMIN_ROLE) {
        chainIdentifiers[_chainId] = _identifier;
    }

    function getVerificationStatus(string memory _modelHash)
        external
        view
        returns (
            VerificationStatus status,
            uint256 verificationCount,
            uint256 requiredVerifications,
            VerificationResult[] memory results
        )
    {
        ModelVerification storage verification = verifications[_modelHash];
        return (
            verification.status,
            verification.verificationCount,
            verification.requiredVerifications,
            verificationResults[_modelHash]
        );
    }
} 