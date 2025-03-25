// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";

contract ModelVersioning is AccessControl, ReentrancyGuard {
    struct ModelVersion {
        string modelHash;
        string parentHash;
        address creator;
        uint256 timestamp;
        string changelog;
        VersionStatus status;
        mapping(string => string) metadata;
    }

    struct Branch {
        string name;
        string latestVersionHash;
        address owner;
        bool isActive;
    }

    enum VersionStatus {
        Pending,
        Approved,
        Rejected,
        Deprecated
    }

    mapping(string => ModelVersion) public versions;
    mapping(string => Branch) public branches;
    mapping(address => string[]) public userVersions;
    
    string[] public allVersionHashes;
    string[] public allBranchNames;

    event VersionCreated(string versionHash, string parentHash, address creator);
    event BranchCreated(string name, address owner);
    event VersionStatusUpdated(string versionHash, VersionStatus status);

    constructor() {
        _setupRole(DEFAULT_ADMIN_ROLE, msg.sender);
    }

    function createVersion(
        string memory _modelHash,
        string memory _parentHash,
        string memory _changelog,
        string[] memory _metadataKeys,
        string[] memory _metadataValues
    ) external nonReentrant {
        require(bytes(_modelHash).length > 0, "Invalid model hash");
        require(_metadataKeys.length == _metadataValues.length, "Metadata mismatch");

        ModelVersion storage version = versions[_modelHash];
        version.modelHash = _modelHash;
        version.parentHash = _parentHash;
        version.creator = msg.sender;
        version.timestamp = block.timestamp;
        version.changelog = _changelog;
        version.status = VersionStatus.Pending;

        for (uint i = 0; i < _metadataKeys.length; i++) {
            version.metadata[_metadataKeys[i]] = _metadataValues[i];
        }

        userVersions[msg.sender].push(_modelHash);
        allVersionHashes.push(_modelHash);

        emit VersionCreated(_modelHash, _parentHash, msg.sender);
    }

    function createBranch(
        string memory _name,
        string memory _baseVersionHash
    ) external {
        require(bytes(_name).length > 0, "Invalid branch name");
        require(versions[_baseVersionHash].timestamp > 0, "Base version not found");

        Branch storage branch = branches[_name];
        require(branch.owner == address(0), "Branch already exists");

        branch.name = _name;
        branch.latestVersionHash = _baseVersionHash;
        branch.owner = msg.sender;
        branch.isActive = true;

        allBranchNames.push(_name);
        emit BranchCreated(_name, msg.sender);
    }

    function updateVersionStatus(
        string memory _versionHash,
        VersionStatus _status
    ) external onlyRole(DEFAULT_ADMIN_ROLE) {
        require(versions[_versionHash].timestamp > 0, "Version not found");
        versions[_versionHash].status = _status;
        emit VersionStatusUpdated(_versionHash, _status);
    }

    function getVersionHistory(string memory _versionHash) 
        external view returns (string[] memory) 
    {
        string[] memory history = new string[](100); // Max depth
        uint256 count = 0;
        string memory currentHash = _versionHash;

        while (bytes(currentHash).length > 0 && count < 100) {
            history[count] = currentHash;
            currentHash = versions[currentHash].parentHash;
            count++;
        }

        string[] memory result = new string[](count);
        for (uint256 i = 0; i < count; i++) {
            result[i] = history[i];
        }

        return result;
    }

    function getBranchVersions(string memory _branchName)
        external view returns (string[] memory)
    {
        require(branches[_branchName].isActive, "Branch not found");
        return userVersions[branches[_branchName].owner];
    }
} 