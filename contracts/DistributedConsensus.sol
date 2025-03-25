// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";

contract DistributedConsensus is AccessControl, ReentrancyGuard {
    using ECDSA for bytes32;

    bytes32 public constant VALIDATOR_ROLE = keccak256("VALIDATOR_ROLE");
    bytes32 public constant PROPOSER_ROLE = keccak256("PROPOSER_ROLE");

    struct ConsensusRound {
        bytes32 roundId;
        string proposedValue;
        uint256 startTime;
        uint256 endTime;
        address proposer;
        RoundStatus status;
        uint256 validatorCount;
        uint256 approvalCount;
        uint256 rejectionCount;
        mapping(address => Vote) votes;
    }

    struct Validator {
        uint256 stake;
        uint256 reputation;
        uint256 lastActiveRound;
        bool isActive;
    }

    struct Vote {
        bool hasVoted;
        bool approved;
        uint256 timestamp;
        bytes signature;
    }

    enum RoundStatus {
        Pending,
        Active,
        Completed,
        Failed
    }

    mapping(bytes32 => ConsensusRound) public rounds;
    mapping(address => Validator) public validators;
    mapping(bytes32 => string) public consensusResults;
    
    uint256 public minValidators;
    uint256 public roundDuration;
    uint256 public minStake;
    uint256 public consensusThreshold; // Percentage (1-100)
    
    bytes32[] public activeRounds;
    uint256 public roundCount;

    event RoundStarted(
        bytes32 indexed roundId,
        string proposedValue,
        address proposer
    );
    event VoteSubmitted(
        bytes32 indexed roundId,
        address indexed validator,
        bool approved
    );
    event ConsensusReached(
        bytes32 indexed roundId,
        string result
    );
    event ValidatorRegistered(
        address indexed validator,
        uint256 stake
    );
    event ValidatorSlashed(
        address indexed validator,
        uint256 amount,
        string reason
    );

    constructor(
        uint256 _minValidators,
        uint256 _roundDuration,
        uint256 _minStake,
        uint256 _consensusThreshold
    ) {
        require(_consensusThreshold > 50 && _consensusThreshold <= 100, "Invalid threshold");
        
        _setupRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _setupRole(PROPOSER_ROLE, msg.sender);
        
        minValidators = _minValidators;
        roundDuration = _roundDuration;
        minStake = _minStake;
        consensusThreshold = _consensusThreshold;
    }

    function registerValidator() external payable {
        require(msg.value >= minStake, "Insufficient stake");
        require(!validators[msg.sender].isActive, "Already registered");

        validators[msg.sender] = Validator({
            stake: msg.value,
            reputation: 100,
            lastActiveRound: 0,
            isActive: true
        });

        _setupRole(VALIDATOR_ROLE, msg.sender);
        emit ValidatorRegistered(msg.sender, msg.value);
    }

    function proposeConsensus(string memory _value)
        external
        onlyRole(PROPOSER_ROLE)
        returns (bytes32)
    {
        require(getActiveValidatorCount() >= minValidators, "Insufficient validators");

        bytes32 roundId = keccak256(abi.encodePacked(
            _value,
            block.timestamp,
            msg.sender,
            roundCount++
        ));

        ConsensusRound storage round = rounds[roundId];
        round.roundId = roundId;
        round.proposedValue = _value;
        round.startTime = block.timestamp;
        round.endTime = block.timestamp + roundDuration;
        round.proposer = msg.sender;
        round.status = RoundStatus.Active;
        round.validatorCount = getActiveValidatorCount();

        activeRounds.push(roundId);
        emit RoundStarted(roundId, _value, msg.sender);

        return roundId;
    }

    function submitVote(
        bytes32 _roundId,
        bool _approved,
        bytes memory _signature
    ) external onlyRole(VALIDATOR_ROLE) nonReentrant {
        ConsensusRound storage round = rounds[_roundId];
        require(round.status == RoundStatus.Active, "Round not active");
        require(block.timestamp <= round.endTime, "Round ended");
        require(!round.votes[msg.sender].hasVoted, "Already voted");
        require(validators[msg.sender].isActive, "Validator not active");

        // Verify signature
        bytes32 messageHash = keccak256(abi.encodePacked(_roundId, _approved));
        require(verifySignature(messageHash, _signature), "Invalid signature");

        round.votes[msg.sender] = Vote({
            hasVoted: true,
            approved: _approved,
            timestamp: block.timestamp,
            signature: _signature
        });

        if (_approved) {
            round.approvalCount++;
        } else {
            round.rejectionCount++;
        }

        validators[msg.sender].lastActiveRound = roundCount;
        emit VoteSubmitted(_roundId, msg.sender, _approved);

        checkConsensus(_roundId);
    }

    function checkConsensus(bytes32 _roundId) internal {
        ConsensusRound storage round = rounds[_roundId];
        uint256 totalVotes = round.approvalCount + round.rejectionCount;
        
        if (totalVotes >= (round.validatorCount * consensusThreshold) / 100) {
            if (round.approvalCount > round.rejectionCount) {
                round.status = RoundStatus.Completed;
                consensusResults[_roundId] = round.proposedValue;
                emit ConsensusReached(_roundId, round.proposedValue);
                rewardValidators(_roundId);
            } else {
                round.status = RoundStatus.Failed;
            }
            removeActiveRound(_roundId);
        }
    }

    function rewardValidators(bytes32 _roundId) internal {
        ConsensusRound storage round = rounds[_roundId];
        uint256 rewardPool = 0;

        // Calculate rewards based on participation and correctness
        for (uint256 i = 0; i < getActiveValidatorCount(); i++) {
            address validator = getValidatorAtIndex(i);
            if (round.votes[validator].hasVoted) {
                if (round.votes[validator].approved) {
                    validators[validator].reputation += 1;
                    rewardPool += 100; // Base reward in wei
                }
            } else {
                // Penalize non-participation
                validators[validator].reputation -= 1;
            }
        }

        // Distribute rewards
        if (rewardPool > 0) {
            uint256 rewardPerValidator = rewardPool / round.approvalCount;
            for (uint256 i = 0; i < getActiveValidatorCount(); i++) {
                address validator = getValidatorAtIndex(i);
                if (round.votes[validator].hasVoted && round.votes[validator].approved) {
                    payable(validator).transfer(rewardPerValidator);
                }
            }
        }
    }

    function slashValidator(
        address _validator,
        uint256 _amount,
        string memory _reason
    ) external onlyRole(DEFAULT_ADMIN_ROLE) {
        require(validators[_validator].stake >= _amount, "Insufficient stake");
        
        validators[_validator].stake -= _amount;
        validators[_validator].reputation -= 10;

        if (validators[_validator].stake < minStake) {
            validators[_validator].isActive = false;
            revokeRole(VALIDATOR_ROLE, _validator);
        }

        emit ValidatorSlashed(_validator, _amount, _reason);
    }

    function getActiveValidatorCount() public view returns (uint256) {
        uint256 count = 0;
        uint256 total = getRoleMemberCount(VALIDATOR_ROLE);
        
        for (uint256 i = 0; i < total; i++) {
            address validator = getRoleMember(VALIDATOR_ROLE, i);
            if (validators[validator].isActive) {
                count++;
            }
        }
        
        return count;
    }

    function getValidatorAtIndex(uint256 _index) internal view returns (address) {
        return getRoleMember(VALIDATOR_ROLE, _index);
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

    function removeActiveRound(bytes32 _roundId) internal {
        for (uint256 i = 0; i < activeRounds.length; i++) {
            if (activeRounds[i] == _roundId) {
                activeRounds[i] = activeRounds[activeRounds.length - 1];
                activeRounds.pop();
                break;
            }
        }
    }

    function getConsensusResult(bytes32 _roundId)
        external
        view
        returns (string memory)
    {
        return consensusResults[_roundId];
    }

    function getRoundDetails(bytes32 _roundId)
        external
        view
        returns (
            string memory proposedValue,
            uint256 startTime,
            uint256 endTime,
            address proposer,
            RoundStatus status,
            uint256 approvalCount,
            uint256 rejectionCount
        )
    {
        ConsensusRound storage round = rounds[_roundId];
        return (
            round.proposedValue,
            round.startTime,
            round.endTime,
            round.proposer,
            round.status,
            round.approvalCount,
            round.rejectionCount
        );
    }
} 