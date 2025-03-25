// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/utils/math/SafeMath.sol";
import "./interfaces/ILayerZeroEndpoint.sol";

contract CrossChainGovernance is AccessControl, ReentrancyGuard {
    using SafeMath for uint256;

    bytes32 public constant BRIDGE_ROLE = keccak256("BRIDGE_ROLE");
    bytes32 public constant EXECUTOR_ROLE = keccak256("EXECUTOR_ROLE");

    struct CrossChainProposal {
        uint256 id;
        uint256 sourceChainId;
        address sourceProposer;
        string description;
        bytes[] calldatas;
        address[] targets;
        uint256[] values;
        uint256 startTimestamp;
        uint256 endTimestamp;
        mapping(uint256 => uint256) chainVotes; // chainId => votes
        bool executed;
        bool canceled;
    }

    struct VoteInfo {
        uint256 chainId;
        uint256 proposalId;
        uint256 votes;
        bytes32 voteHash;
    }

    ILayerZeroEndpoint public immutable lzEndpoint;
    mapping(uint256 => CrossChainProposal) public proposals;
    mapping(uint256 => mapping(uint256 => bytes32)) public chainVoteHashes; // proposalId => chainId => voteHash
    uint256 public proposalCount;
    uint256 public minVotingPeriod;
    uint256[] public supportedChains;

    event ProposalCreated(
        uint256 indexed proposalId,
        uint256 sourceChainId,
        address sourceProposer,
        string description
    );
    event VotesReceived(
        uint256 indexed proposalId,
        uint256 chainId,
        uint256 votes,
        bytes32 voteHash
    );
    event ProposalExecuted(uint256 indexed proposalId);
    event ProposalCanceled(uint256 indexed proposalId);
    event ChainSupported(uint256 chainId);
    event ChainRemoved(uint256 chainId);

    constructor(
        address _lzEndpoint,
        uint256 _minVotingPeriod,
        uint256[] memory _supportedChains
    ) {
        lzEndpoint = ILayerZeroEndpoint(_lzEndpoint);
        minVotingPeriod = _minVotingPeriod;
        supportedChains = _supportedChains;
        
        _setupRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _setupRole(BRIDGE_ROLE, msg.sender);
        _setupRole(EXECUTOR_ROLE, msg.sender);
    }

    function createProposal(
        address[] memory targets,
        uint256[] memory values,
        bytes[] memory calldatas,
        string memory description,
        uint256 votingPeriod
    ) external returns (uint256) {
        require(votingPeriod >= minVotingPeriod, "Voting period too short");
        require(
            targets.length == values.length &&
            targets.length == calldatas.length,
            "Invalid proposal length"
        );

        proposalCount++;
        CrossChainProposal storage newProposal = proposals[proposalCount];
        newProposal.id = proposalCount;
        newProposal.sourceChainId = getChainId();
        newProposal.sourceProposer = msg.sender;
        newProposal.description = description;
        newProposal.targets = targets;
        newProposal.values = values;
        newProposal.calldatas = calldatas;
        newProposal.startTimestamp = block.timestamp;
        newProposal.endTimestamp = block.timestamp.add(votingPeriod);

        emit ProposalCreated(
            proposalCount,
            newProposal.sourceChainId,
            msg.sender,
            description
        );

        // Notify other chains about the new proposal
        for (uint256 i = 0; i < supportedChains.length; i++) {
            if (supportedChains[i] != getChainId()) {
                _sendProposalToChain(proposalCount, supportedChains[i]);
            }
        }

        return proposalCount;
    }

    function receiveVotes(
        uint256 proposalId,
        uint256 sourceChainId,
        uint256 votes,
        bytes32 voteHash
    ) external onlyRole(BRIDGE_ROLE) {
        require(proposals[proposalId].id != 0, "Proposal doesn't exist");
        require(!proposals[proposalId].executed, "Proposal already executed");
        require(!proposals[proposalId].canceled, "Proposal canceled");
        
        proposals[proposalId].chainVotes[sourceChainId] = votes;
        chainVoteHashes[proposalId][sourceChainId] = voteHash;

        emit VotesReceived(proposalId, sourceChainId, votes, voteHash);
    }

    function executeProposal(uint256 proposalId) external nonReentrant onlyRole(EXECUTOR_ROLE) {
        CrossChainProposal storage proposal = proposals[proposalId];
        require(proposal.id != 0, "Proposal doesn't exist");
        require(!proposal.executed, "Proposal already executed");
        require(!proposal.canceled, "Proposal canceled");
        require(block.timestamp > proposal.endTimestamp, "Voting period not ended");
        require(_quorumReached(proposalId), "Quorum not reached");

        proposal.executed = true;

        for (uint256 i = 0; i < proposal.targets.length; i++) {
            (bool success, ) = proposal.targets[i].call{value: proposal.values[i]}(
                proposal.calldatas[i]
            );
            require(success, "Proposal execution failed");
        }

        emit ProposalExecuted(proposalId);
    }

    function cancelProposal(uint256 proposalId) external {
        CrossChainProposal storage proposal = proposals[proposalId];
        require(
            msg.sender == proposal.sourceProposer || hasRole(DEFAULT_ADMIN_ROLE, msg.sender),
            "Not authorized"
        );
        require(!proposal.executed, "Already executed");
        require(!proposal.canceled, "Already canceled");

        proposal.canceled = true;
        emit ProposalCanceled(proposalId);
    }

    function addSupportedChain(uint256 chainId) external onlyRole(DEFAULT_ADMIN_ROLE) {
        supportedChains.push(chainId);
        emit ChainSupported(chainId);
    }

    function removeSupportedChain(uint256 chainId) external onlyRole(DEFAULT_ADMIN_ROLE) {
        for (uint256 i = 0; i < supportedChains.length; i++) {
            if (supportedChains[i] == chainId) {
                supportedChains[i] = supportedChains[supportedChains.length - 1];
                supportedChains.pop();
                emit ChainRemoved(chainId);
                break;
            }
        }
    }

    function _sendProposalToChain(uint256 proposalId, uint256 targetChainId) internal {
        bytes memory payload = abi.encode(
            proposalId,
            getChainId(),
            proposals[proposalId].sourceProposer,
            proposals[proposalId].description
        );

        lzEndpoint.send(
            targetChainId,
            abi.encodePacked(address(this), address(this)),
            payload,
            payable(msg.sender),
            address(0),
            bytes("")
        );
    }

    function _quorumReached(uint256 proposalId) internal view returns (bool) {
        uint256 totalVotes = 0;
        for (uint256 i = 0; i < supportedChains.length; i++) {
            totalVotes = totalVotes.add(proposals[proposalId].chainVotes[supportedChains[i]]);
        }
        return totalVotes >= getQuorumThreshold();
    }

    function getQuorumThreshold() public pure returns (uint256) {
        return 100; // Implement your own quorum logic
    }

    function getChainId() public view returns (uint256) {
        uint256 chainId;
        assembly {
            chainId := chainid()
        }
        return chainId;
    }

    receive() external payable {}
} 