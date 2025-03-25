// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/security/Pausable.sol";
import "@openzeppelin/contracts/access/AccessControl.sol";

contract SecurityModule is ReentrancyGuard, Pausable, AccessControl {
    bytes32 public constant ADMIN_ROLE = keccak256("ADMIN_ROLE");
    bytes32 public constant MODERATOR_ROLE = keccak256("MODERATOR_ROLE");

    mapping(address => uint256) public lastActionTimestamp;
    mapping(address => uint256) public actionCount;
    
    uint256 public constant RATE_LIMIT_WINDOW = 1 hours;
    uint256 public constant MAX_ACTIONS_PER_WINDOW = 50;
    
    event SecurityIncident(address indexed user, string description);
    
    modifier rateLimit() {
        require(
            !isRateLimited(msg.sender),
            "Rate limit exceeded"
        );
        _;
        updateRateLimit(msg.sender);
    }

    constructor() {
        _setupRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _setupRole(ADMIN_ROLE, msg.sender);
    }

    function isRateLimited(address user) public view returns (bool) {
        if (hasRole(ADMIN_ROLE, user)) return false;
        
        if (block.timestamp - lastActionTimestamp[user] >= RATE_LIMIT_WINDOW) {
            return false;
        }
        
        return actionCount[user] >= MAX_ACTIONS_PER_WINDOW;
    }

    function updateRateLimit(address user) internal {
        if (block.timestamp - lastActionTimestamp[user] >= RATE_LIMIT_WINDOW) {
            actionCount[user] = 1;
            lastActionTimestamp[user] = block.timestamp;
        } else {
            actionCount[user]++;
        }
    }

    function reportSecurityIncident(
        address user,
        string memory description
    ) external onlyRole(MODERATOR_ROLE) {
        emit SecurityIncident(user, description);
    }

    function pause() external onlyRole(ADMIN_ROLE) {
        _pause();
    }

    function unpause() external onlyRole(ADMIN_ROLE) {
        _unpause();
    }
} 