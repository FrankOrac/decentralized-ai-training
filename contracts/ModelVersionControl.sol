// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";

contract ModelVersionControl is AccessControl, ReentrancyGuard {
    bytes32 public constant MODEL_MANAGER_ROLE = keccak256("MODEL_MANAGER_ROLE");

    struct ModelVersion {
        string modelHash;
        string parentHash;
        string metadataURI;
        uint256 timestamp;
        address creator;
        VersionStatus status;
        string[] dependencies;
        mapping(address => bool) approvals;
        uint256 approvalCount;
    }

    struct ModelBranch {
        string branchName;
        string headVersion;
        uint256 createdAt;
        address creator;
        bool isActive;
    }

    enum VersionStatus {
        Draft,
        PendingApproval,
        Approved,
        Rejected,
        Deprecated
    }

    mapping(string => ModelVersion) public versions;
    mapping(string => ModelBranch) public branches;
    mapping(string => string[]) public modelHistory;
    mapping(string => string) public activeVersion;
    
    uint256 public requiredApprovals;
    string[] public allBranches;

    event VersionCreated(
        string modelHash,
        string parentHash,
        address creator
    );
    event VersionApproved(
        string modelHash,
        address approver
    );
    event VersionRejected(
        string modelHash,
        address rejector
    );
    event BranchCreated(
        string branchName,
        string baseVersion,
        address creator
    );
    event ModelRollback(
        string modelHash,
        string targetVersion,
        address initiator
    );

    constructor(uint256 _requiredApprovals) {
        _setupRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _setupRole(MODEL_MANAGER_ROLE, msg.sender);
        requiredApprovals = _requiredApprovals;

        // Create main branch
        createBranch("main", "", address(0));
    }

    function createVersion(
        string memory _modelHash,
        string memory _parentHash,
        string memory _metadataURI,
        string[] memory _dependencies,
        string memory _branchName
    ) external onlyRole(MODEL_MANAGER_ROLE) {
        require(bytes(_modelHash).length > 0, "Invalid model hash");
        require(branches[_branchName].isActive, "Invalid branch");
        
        if (bytes(_parentHash).length > 0) {
            require(
                versions[_parentHash].status == VersionStatus.Approved,
                "Parent version not approved"
            );
        }

        ModelVersion storage version = versions[_modelHash];
        version.modelHash = _modelHash;
        version.parentHash = _parentHash;
        version.metadataURI = _metadataURI;
        version.timestamp = block.timestamp;
        version.creator = msg.sender;
        version.status = VersionStatus.Draft;
        version.dependencies = _dependencies;

        modelHistory[_branchName].push(_modelHash);
        
        emit VersionCreated(_modelHash, _parentHash, msg.sender);
    }

    function approveVersion(string memory _modelHash)
        external
        onlyRole(MODEL_MANAGER_ROLE)
    {
        ModelVersion storage version = versions[_modelHash];
        require(
            version.status == VersionStatus.Draft ||
            version.status == VersionStatus.PendingApproval,
            "Invalid version status"
        );
        require(!version.approvals[msg.sender], "Already approved");

        version.approvals[msg.sender] = true;
        version.approvalCount++;

        if (version.approvalCount >= requiredApprovals) {
            version.status = VersionStatus.Approved;
            
            // Update active version for the branch
            for (uint i = 0; i < allBranches.length; i++) {
                if (contains(modelHistory[allBranches[i]], _modelHash)) {
                    activeVersion[allBranches[i]] = _modelHash;
                    break;
                }
            }
        } else {
            version.status = VersionStatus.PendingApproval;
        }

        emit VersionApproved(_modelHash, msg.sender);
    }

    function rejectVersion(string memory _modelHash)
        external
        onlyRole(MODEL_MANAGER_ROLE)
    {
        ModelVersion storage version = versions[_modelHash];
        require(
            version.status == VersionStatus.Draft ||
            version.status == VersionStatus.PendingApproval,
            "Invalid version status"
        );

        version.status = VersionStatus.Rejected;
        emit VersionRejected(_modelHash, msg.sender);
    }

    function createBranch(
        string memory _branchName,
        string memory _baseVersion,
        address _creator
    ) public onlyRole(MODEL_MANAGER_ROLE) {
        require(bytes(_branchName).length > 0, "Invalid branch name");
        require(!branches[_branchName].isActive, "Branch already exists");

        branches[_branchName] = ModelBranch({
            branchName: _branchName,
            headVersion: _baseVersion,
            createdAt: block.timestamp,
            creator: _creator,
            isActive: true
        });

        allBranches.push(_branchName);
        emit BranchCreated(_branchName, _baseVersion, _creator);
    }

    function rollbackVersion(
        string memory _branchName,
        string memory _targetVersion
    ) external onlyRole(MODEL_MANAGER_ROLE) nonReentrant {
        require(branches[_branchName].isActive, "Invalid branch");
        require(
            versions[_targetVersion].status == VersionStatus.Approved,
            "Invalid target version"
        );
        require(
            contains(modelHistory[_branchName], _targetVersion),
            "Version not in branch"
        );

        activeVersion[_branchName] = _targetVersion;
        emit ModelRollback(_branchName, _targetVersion, msg.sender);
    }

    function getVersionDetails(string memory _modelHash)
        external
        view
        returns (
            string memory parentHash,
            string memory metadataURI,
            uint256 timestamp,
            address creator,
            VersionStatus status,
            string[] memory dependencies,
            uint256 approvalCount
        )
    {
        ModelVersion storage version = versions[_modelHash];
        return (
            version.parentHash,
            version.metadataURI,
            version.timestamp,
            version.creator,
            version.status,
            version.dependencies,
            version.approvalCount
        );
    }

    function getBranchHistory(string memory _branchName)
        external
        view
        returns (string[] memory)
    {
        return modelHistory[_branchName];
    }

    function contains(string[] storage array, string memory value)
        internal
        view
        returns (bool)
    {
        for (uint i = 0; i < array.length; i++) {
            if (keccak256(abi.encodePacked(array[i])) ==
                keccak256(abi.encodePacked(value))) {
                return true;
            }
        }
        return false;
    }
} 