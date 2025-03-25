// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/utils/math/SafeMath.sol";

contract ProposalDelegation is AccessControl, ReentrancyGuard {
    using SafeMath for uint256;

    struct Delegation {
        address delegator;
        address delegate;
        uint256 startTime;
        uint256 endTime;
        bool isActive;
        DelegationType delegationType;
    }

    struct DelegateInfo {
        uint256 totalDelegations;
        uint256 activeVotingPower;
        mapping(address => bool) delegators;
    }

    enum DelegationType { Full, VotingOnly, ProposalOnly }

    mapping(address => Delegation[]) public delegationsBy;
    mapping(address => DelegateInfo) public delegateInfo;
    mapping(address => address) public currentDelegate;

    event DelegationCreated(
        address indexed delegator,
        address indexed delegate,
        uint256 startTime,
        uint256 endTime,
        DelegationType delegationType
    );
    event DelegationRevoked(
        address indexed delegator,
        address indexed delegate
    );
    event DelegationExpired(
        address indexed delegator,
        address indexed delegate
    );
    event VoteCast(
        address indexed delegate,
        address indexed delegator,
        uint256 indexed proposalId,
        bool support
    );

    constructor() {
        _setupRole(DEFAULT_ADMIN_ROLE, msg.sender);
    }

    function delegate(
        address _delegate,
        uint256 _duration,
        DelegationType _type
    ) external {
        require(_delegate != msg.sender, "Cannot delegate to self");
        require(_delegate != address(0), "Cannot delegate to zero address");
        require(_duration > 0, "Duration must be greater than 0");

        // Revoke any existing active delegation
        if (currentDelegate[msg.sender] != address(0)) {
            revokeDelegation();
        }

        uint256 startTime = block.timestamp;
        uint256 endTime = startTime.add(_duration);

        Delegation memory newDelegation = Delegation({
            delegator: msg.sender,
            delegate: _delegate,
            startTime: startTime,
            endTime: endTime,
            isActive: true,
            delegationType: _type
        });

        delegationsBy[msg.sender].push(newDelegation);
        delegateInfo[_delegate].totalDelegations = delegateInfo[_delegate].totalDelegations.add(1);
        delegateInfo[_delegate].activeVotingPower = delegateInfo[_delegate].activeVotingPower.add(1);
        delegateInfo[_delegate].delegators[msg.sender] = true;
        currentDelegate[msg.sender] = _delegate;

        emit DelegationCreated(
            msg.sender,
            _delegate,
            startTime,
            endTime,
            _type
        );
    }

    function revokeDelegation() public {
        address currentDel = currentDelegate[msg.sender];
        require(currentDel != address(0), "No active delegation");

        Delegation[] storage delegations = delegationsBy[msg.sender];
        for (uint256 i = 0; i < delegations.length; i++) {
            if (delegations[i].isActive) {
                delegations[i].isActive = false;
                delegations[i].endTime = block.timestamp;
                
                delegateInfo[currentDel].activeVotingPower = 
                    delegateInfo[currentDel].activeVotingPower.sub(1);
                delegateInfo[currentDel].delegators[msg.sender] = false;
                
                emit DelegationRevoked(msg.sender, currentDel);
                break;
            }
        }

        currentDelegate[msg.sender] = address(0);
    }

    function castVoteByDelegate(
        address delegator,
        uint256 proposalId,
        bool support
    ) external {
        require(
            currentDelegate[delegator] == msg.sender,
            "Not authorized to vote for delegator"
        );

        Delegation[] storage delegations = delegationsBy[delegator];
        bool foundActive = false;
        
        for (uint256 i = 0; i < delegations.length; i++) {
            if (delegations[i].isActive) {
                require(
                    delegations[i].delegationType != DelegationType.ProposalOnly,
                    "Delegation type does not allow voting"
                );
                require(
                    block.timestamp <= delegations[i].endTime,
                    "Delegation expired"
                );
                foundActive = true;
                break;
            }
        }

        require(foundActive, "No active delegation found");

        emit VoteCast(msg.sender, delegator, proposalId, support);
    }

    function getDelegateVotingPower(address _delegate) 
        external 
        view 
        returns (uint256) 
    {
        return delegateInfo[_delegate].activeVotingPower;
    }

    function getDelegatorDelegations(address _delegator)
        external
        view
        returns (Delegation[] memory)
    {
        return delegationsBy[_delegator];
    }

    function checkDelegation(address _delegator, address _delegate)
        external
        view
        returns (bool)
    {
        return currentDelegate[_delegator] == _delegate;
    }

    function cleanupExpiredDelegations() external {
        Delegation[] storage delegations = delegationsBy[msg.sender];
        
        for (uint256 i = 0; i < delegations.length; i++) {
            if (delegations[i].isActive && 
                block.timestamp > delegations[i].endTime) {
                delegations[i].isActive = false;
                
                address delegate = delegations[i].delegate;
                delegateInfo[delegate].activeVotingPower = 
                    delegateInfo[delegate].activeVotingPower.sub(1);
                delegateInfo[delegate].delegators[msg.sender] = false;
                
                if (currentDelegate[msg.sender] == delegate) {
                    currentDelegate[msg.sender] = address(0);
                }
                
                emit DelegationExpired(msg.sender, delegate);
            }
        }
    }
} 