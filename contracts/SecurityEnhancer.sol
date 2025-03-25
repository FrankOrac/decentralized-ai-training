// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/security/Pausable.sol";
import "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";

contract SecurityEnhancer is AccessControl, ReentrancyGuard, Pausable {
    using ECDSA for bytes32;

    bytes32 public constant SECURITY_ADMIN_ROLE = keccak256("SECURITY_ADMIN_ROLE");
    bytes32 public constant GUARDIAN_ROLE = keccak256("GUARDIAN_ROLE");

    struct SecurityConfig {
        uint256 maxTransactionValue;
        uint256 dailyLimit;
        uint256 cooldownPeriod;
        uint256 requiredApprovals;
        bool requireMultisig;
    }

    struct Transaction {
        bytes32 txHash;
        address initiator;
        bytes data;
        uint256 value;
        uint256 timestamp;
        TransactionStatus status;
        uint256 approvalCount;
        mapping(address => bool) approvals;
    }

    struct GuardianKey {
        bytes publicKey;
        uint256 lastRotation;
        bool isActive;
    }

    enum TransactionStatus {
        Pending,
        Approved,
        Executed,
        Rejected,
        Cancelled
    }

    mapping(bytes32 => Transaction) public transactions;
    mapping(address => GuardianKey) public guardianKeys;
    mapping(address => uint256) public dailyTransactions;
    mapping(address => uint256) public lastTransactionTime;
    mapping(address => uint256) public consecutiveFailedAttempts;

    SecurityConfig public config;
    uint256 public constant MAX_FAILED_ATTEMPTS = 3;
    uint256 public constant LOCKOUT_DURATION = 24 hours;

    event TransactionInitiated(
        bytes32 indexed txHash,
        address indexed initiator,
        uint256 value
    );
    event TransactionApproved(
        bytes32 indexed txHash,
        address indexed approver
    );
    event TransactionExecuted(
        bytes32 indexed txHash,
        address indexed executor
    );
    event SecurityAlert(
        address indexed subject,
        string alertType,
        string details
    );
    event GuardianKeyRotated(
        address indexed guardian,
        bytes newPublicKey
    );

    constructor(
        uint256 _maxTransactionValue,
        uint256 _dailyLimit,
        uint256 _cooldownPeriod,
        uint256 _requiredApprovals
    ) {
        _setupRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _setupRole(SECURITY_ADMIN_ROLE, msg.sender);

        config = SecurityConfig({
            maxTransactionValue: _maxTransactionValue,
            dailyLimit: _dailyLimit,
            cooldownPeriod: _cooldownPeriod,
            requiredApprovals: _requiredApprovals,
            requireMultisig: true
        });
    }

    modifier notLocked(address _account) {
        require(
            block.timestamp >= lastTransactionTime[_account] + LOCKOUT_DURATION ||
            consecutiveFailedAttempts[_account] < MAX_FAILED_ATTEMPTS,
            "Account temporarily locked"
        );
        _;
    }

    modifier withinLimits(uint256 _value) {
        require(_value <= config.maxTransactionValue, "Exceeds transaction limit");
        require(
            dailyTransactions[msg.sender] + _value <= config.dailyLimit,
            "Exceeds daily limit"
        );
        _;
    }

    function initiateTransaction(
        bytes memory _data,
        uint256 _value,
        bytes memory _signature
    ) external notLocked(msg.sender) withinLimits(_value) nonReentrant returns (bytes32) {
        require(
            block.timestamp >= lastTransactionTime[msg.sender] + config.cooldownPeriod,
            "Cooldown period not elapsed"
        );

        bytes32 txHash = keccak256(abi.encodePacked(
            _data,
            _value,
            block.timestamp,
            msg.sender
        ));

        // Verify signature
        require(verifySignature(txHash, _signature), "Invalid signature");

        Transaction storage transaction = transactions[txHash];
        transaction.txHash = txHash;
        transaction.initiator = msg.sender;
        transaction.data = _data;
        transaction.value = _value;
        transaction.timestamp = block.timestamp;
        transaction.status = TransactionStatus.Pending;

        if (!config.requireMultisig) {
            transaction.status = TransactionStatus.Approved;
        }

        emit TransactionInitiated(txHash, msg.sender, _value);
        return txHash;
    }

    function approveTransaction(
        bytes32 _txHash,
        bytes memory _signature
    ) external onlyRole(GUARDIAN_ROLE) nonReentrant {
        Transaction storage transaction = transactions[_txHash];
        require(
            transaction.status == TransactionStatus.Pending,
            "Invalid transaction status"
        );
        require(!transaction.approvals[msg.sender], "Already approved");

        // Verify guardian signature
        require(
            verifyGuardianSignature(_txHash, _signature, msg.sender),
            "Invalid guardian signature"
        );

        transaction.approvals[msg.sender] = true;
        transaction.approvalCount++;

        if (transaction.approvalCount >= config.requiredApprovals) {
            transaction.status = TransactionStatus.Approved;
        }

        emit TransactionApproved(_txHash, msg.sender);
    }

    function executeTransaction(bytes32 _txHash)
        external
        nonReentrant
        returns (bool)
    {
        Transaction storage transaction = transactions[_txHash];
        require(
            transaction.status == TransactionStatus.Approved,
            "Transaction not approved"
        );

        (bool success, ) = transaction.initiator.call{value: transaction.value}(
            transaction.data
        );

        if (success) {
            transaction.status = TransactionStatus.Executed;
            dailyTransactions[transaction.initiator] += transaction.value;
            lastTransactionTime[transaction.initiator] = block.timestamp;
            consecutiveFailedAttempts[transaction.initiator] = 0;
            emit TransactionExecuted(_txHash, msg.sender);
        } else {
            consecutiveFailedAttempts[transaction.initiator]++;
            if (consecutiveFailedAttempts[transaction.initiator] >= MAX_FAILED_ATTEMPTS) {
                emit SecurityAlert(
                    transaction.initiator,
                    "ACCOUNT_LOCKED",
                    "Too many failed attempts"
                );
            }
        }

        return success;
    }

    function rotateGuardianKey(bytes memory _newPublicKey, bytes memory _signature)
        external
        onlyRole(GUARDIAN_ROLE)
    {
        require(_newPublicKey.length > 0, "Invalid public key");
        
        bytes32 messageHash = keccak256(abi.encodePacked(
            msg.sender,
            _newPublicKey,
            block.timestamp
        ));

        require(
            verifyGuardianSignature(messageHash, _signature, msg.sender),
            "Invalid signature"
        );

        guardianKeys[msg.sender] = GuardianKey({
            publicKey: _newPublicKey,
            lastRotation: block.timestamp,
            isActive: true
        });

        emit GuardianKeyRotated(msg.sender, _newPublicKey);
    }

    function verifySignature(bytes32 _messageHash, bytes memory _signature)
        internal
        view
        returns (bool)
    {
        bytes32 ethSignedMessageHash = _messageHash.toEthSignedMessageHash();
        address signer = ethSignedMessageHash.recover(_signature);
        return signer == msg.sender;
    }

    function verifyGuardianSignature(
        bytes32 _messageHash,
        bytes memory _signature,
        address _guardian
    ) internal view returns (bool) {
        require(guardianKeys[_guardian].isActive, "Guardian key not active");
        bytes32 ethSignedMessageHash = _messageHash.toEthSignedMessageHash();
        address signer = ethSignedMessageHash.recover(_signature);
        return signer == _guardian;
    }

    function updateSecurityConfig(
        uint256 _maxTransactionValue,
        uint256 _dailyLimit,
        uint256 _cooldownPeriod,
        uint256 _requiredApprovals,
        bool _requireMultisig
    ) external onlyRole(SECURITY_ADMIN_ROLE) {
        config.maxTransactionValue = _maxTransactionValue;
        config.dailyLimit = _dailyLimit;
        config.cooldownPeriod = _cooldownPeriod;
        config.requiredApprovals = _requiredApprovals;
        config.requireMultisig = _requireMultisig;
    }

    function pause() external onlyRole(SECURITY_ADMIN_ROLE) {
        _pause();
    }

    function unpause() external onlyRole(SECURITY_ADMIN_ROLE) {
        _unpause();
    }
} 