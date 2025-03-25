// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";

contract DecentralizedBackup is AccessControl, ReentrancyGuard {
    bytes32 public constant BACKUP_ROLE = keccak256("BACKUP_ROLE");
    
    struct BackupNode {
        address nodeAddress;
        uint256 lastHeartbeat;
        uint256 storageCapacity;
        uint256 usedStorage;
        bool isActive;
    }

    struct BackupRecord {
        string dataHash;
        string encryptionKey;
        uint256 timestamp;
        address owner;
        uint256 size;
        BackupStatus status;
        uint256 replicationCount;
        mapping(address => bool) nodeAssignments;
    }

    struct RestoreRequest {
        string dataHash;
        address requester;
        uint256 timestamp;
        RestoreStatus status;
        address assignedNode;
    }

    enum BackupStatus {
        Pending,
        InProgress,
        Completed,
        Failed
    }

    enum RestoreStatus {
        Requested,
        InProgress,
        Completed,
        Failed
    }

    mapping(address => BackupNode) public backupNodes;
    mapping(string => BackupRecord) public backupRecords;
    mapping(uint256 => RestoreRequest) public restoreRequests;
    
    address[] public activeNodes;
    uint256 public minReplicationCount = 3;
    uint256 public heartbeatInterval = 1 hours;
    uint256 public restoreRequestCount;

    event NodeRegistered(address indexed node, uint256 storageCapacity);
    event NodeHeartbeat(address indexed node, uint256 timestamp);
    event BackupInitiated(string dataHash, address indexed owner);
    event BackupCompleted(string dataHash, uint256 replicationCount);
    event RestoreRequested(uint256 indexed requestId, string dataHash);
    event RestoreCompleted(uint256 indexed requestId, string dataHash);

    constructor() {
        _setupRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _setupRole(BACKUP_ROLE, msg.sender);
    }

    function registerNode(uint256 _storageCapacity) external {
        require(!backupNodes[msg.sender].isActive, "Node already registered");
        
        BackupNode memory newNode = BackupNode({
            nodeAddress: msg.sender,
            lastHeartbeat: block.timestamp,
            storageCapacity: _storageCapacity,
            usedStorage: 0,
            isActive: true
        });

        backupNodes[msg.sender] = newNode;
        activeNodes.push(msg.sender);

        emit NodeRegistered(msg.sender, _storageCapacity);
    }

    function sendHeartbeat() external {
        require(backupNodes[msg.sender].isActive, "Node not registered");
        backupNodes[msg.sender].lastHeartbeat = block.timestamp;
        emit NodeHeartbeat(msg.sender, block.timestamp);
    }

    function initiateBackup(
        string memory _dataHash,
        string memory _encryptionKey,
        uint256 _size
    ) external nonReentrant {
        require(_size > 0, "Invalid backup size");
        
        BackupRecord storage newBackup = backupRecords[_dataHash];
        newBackup.dataHash = _dataHash;
        newBackup.encryptionKey = _encryptionKey;
        newBackup.timestamp = block.timestamp;
        newBackup.owner = msg.sender;
        newBackup.size = _size;
        newBackup.status = BackupStatus.Pending;
        newBackup.replicationCount = 0;

        assignBackupNodes(_dataHash, _size);
        emit BackupInitiated(_dataHash, msg.sender);
    }

    function confirmBackup(string memory _dataHash) external {
        require(backupNodes[msg.sender].isActive, "Node not registered");
        require(
            backupRecords[_dataHash].nodeAssignments[msg.sender],
            "Node not assigned to this backup"
        );

        BackupRecord storage backup = backupRecords[_dataHash];
        backup.replicationCount++;
        backupNodes[msg.sender].usedStorage += backup.size;

        if (backup.replicationCount >= minReplicationCount) {
            backup.status = BackupStatus.Completed;
            emit BackupCompleted(_dataHash, backup.replicationCount);
        }
    }

    function requestRestore(string memory _dataHash) external nonReentrant {
        require(
            backupRecords[_dataHash].owner == msg.sender,
            "Not the backup owner"
        );
        require(
            backupRecords[_dataHash].status == BackupStatus.Completed,
            "Backup not completed"
        );

        restoreRequestCount++;
        RestoreRequest storage request = restoreRequests[restoreRequestCount];
        request.dataHash = _dataHash;
        request.requester = msg.sender;
        request.timestamp = block.timestamp;
        request.status = RestoreStatus.Requested;

        // Assign the restore request to an active node
        address assignedNode = findAvailableNode(_dataHash);
        require(assignedNode != address(0), "No available nodes");
        request.assignedNode = assignedNode;

        emit RestoreRequested(restoreRequestCount, _dataHash);
    }

    function confirmRestore(uint256 _requestId) external {
        RestoreRequest storage request = restoreRequests[_requestId];
        require(msg.sender == request.assignedNode, "Not assigned node");
        require(
            request.status == RestoreStatus.Requested,
            "Invalid request status"
        );

        request.status = RestoreStatus.Completed;
        emit RestoreCompleted(_requestId, request.dataHash);
    }

    function assignBackupNodes(string memory _dataHash, uint256 _size) internal {
        uint256 assignedCount = 0;
        
        for (uint i = 0; i < activeNodes.length && assignedCount < minReplicationCount; i++) {
            address node = activeNodes[i];
            BackupNode storage backupNode = backupNodes[node];
            
            if (backupNode.isActive &&
                block.timestamp - backupNode.lastHeartbeat <= heartbeatInterval &&
                backupNode.storageCapacity - backupNode.usedStorage >= _size) {
                
                backupRecords[_dataHash].nodeAssignments[node] = true;
                assignedCount++;
            }
        }

        require(assignedCount >= minReplicationCount, "Insufficient available nodes");
    }

    function findAvailableNode(string memory _dataHash) internal view returns (address) {
        for (uint i = 0; i < activeNodes.length; i++) {
            address node = activeNodes[i];
            if (backupRecords[_dataHash].nodeAssignments[node] &&
                backupNodes[node].isActive &&
                block.timestamp - backupNodes[node].lastHeartbeat <= heartbeatInterval) {
                return node;
            }
        }
        return address(0);
    }

    function getBackupStatus(string memory _dataHash)
        external
        view
        returns (
            BackupStatus status,
            uint256 replicationCount,
            uint256 timestamp,
            address owner
        )
    {
        BackupRecord storage backup = backupRecords[_dataHash];
        return (
            backup.status,
            backup.replicationCount,
            backup.timestamp,
            backup.owner
        );
    }

    function getRestoreRequest(uint256 _requestId)
        external
        view
        returns (
            string memory dataHash,
            address requester,
            uint256 timestamp,
            RestoreStatus status,
            address assignedNode
        )
    {
        RestoreRequest storage request = restoreRequests[_requestId];
        return (
            request.dataHash,
            request.requester,
            request.timestamp,
            request.status,
            request.assignedNode
        );
    }
} 