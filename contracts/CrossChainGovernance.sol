// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "./interfaces/ILayerZeroEndpoint.sol";

contract CrossChainGovernance is AccessControl, ReentrancyGuard {
    bytes32 public constant GOVERNANCE_ADMIN = keccak256("GOVERNANCE_ADMIN");
    bytes32 public constant RELAYER_ROLE = keccak256("RELAYER_ROLE");

    struct ChainConfig {
        uint16 chainId;
        address governanceContract;
        bool isActive;
        uint256 trustScore;
    }

    struct CrossChainProposal {
        bytes32 id;
        uint16 sourceChain;
        address proposer;
        string title;
        bytes[] actions;
        address[] targets;
        uint256[] values;
        uint256 startTime;
        uint256 endTime;
        mapping(uint16 => bool) chainVoted;
        mapping(uint16 => uint256) chainVotes;
        bool executed;
        bool canceled;
    }

    ILayerZeroEndpoint public endpoint;
    mapping(uint16 => ChainConfig) public chainConfigs;
    mapping(bytes32 => CrossChainProposal) public proposals;
    uint256 public minTrustScore = 70;
    uint256 public proposalThreshold;
    uint256 public constant EXECUTION_DELAY = 2 days;

    event ChainConfigured(
        uint16 indexed chainId,
        address governanceContract,
        uint256 trustScore
    );
    event CrossChainProposalCreated(
        bytes32 indexed proposalId,
        uint16 sourceChain,
        address proposer
    );
    event CrossChainVoteReceived(
        bytes32 indexed proposalId,
        uint16 sourceChain,
        uint256 votes
    );
    event ProposalExecuted(bytes32 indexed proposalId);
    event ProposalCanceled(bytes32 indexed proposalId);

    constructor(address _endpoint) {
        endpoint = ILayerZeroEndpoint(_endpoint);
        _setupRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _setupRole(GOVERNANCE_ADMIN, msg.sender);
    }

    function configureChain(
        uint16 chainId,
        address governanceContract,
        uint256 trustScore
    ) external onlyRole(GOVERNANCE_ADMIN) {
        require(governanceContract != address(0), "Invalid governance contract");
        require(trustScore <= 100, "Trust score must be <= 100");

        chainConfigs[chainId] = ChainConfig({
            chainId: chainId,
            governanceContract: governanceContract,
            isActive: true,
            trustScore: trustScore
        });

        emit ChainConfigured(chainId, governanceContract, trustScore);
    }

    function createCrossChainProposal(
        string memory title,
        bytes[] memory actions,
        address[] memory targets,
        uint256[] memory values,
        uint256 votingPeriod
    ) external returns (bytes32) {
        require(
            actions.length == targets.length && targets.length == values.length,
            "Array length mismatch"
        );

        bytes32 proposalId = keccak256(
            abi.encodePacked(
                title,
            msg.sender,
                block.timestamp
            )
        );

        CrossChainProposal storage proposal = proposals[proposalId];
        proposal.id = proposalId;
        proposal.sourceChain = uint16(endpoint.getChainId());
        proposal.proposer = msg.sender;
        proposal.title = title;
        proposal.actions = actions;
        proposal.targets = targets;
        proposal.values = values;
        proposal.startTime = block.timestamp;
        proposal.endTime = block.timestamp + votingPeriod;

        // Notify other chains about the proposal
        bytes memory payload = abi.encode(proposalId, title, msg.sender);
        _notifyChains(payload);

        emit CrossChainProposalCreated(proposalId, proposal.sourceChain, msg.sender);
        return proposalId;
    }

    function receiveCrossChainVote(
        uint16 sourceChain,
        bytes memory payload
    ) external onlyRole(RELAYER_ROLE) {
        require(chainConfigs[sourceChain].isActive, "Chain not active");
        require(
            chainConfigs[sourceChain].trustScore >= minTrustScore,
            "Insufficient trust score"
        );

        (bytes32 proposalId, uint256 votes) = abi.decode(payload, (bytes32, uint256));
        CrossChainProposal storage proposal = proposals[proposalId];
        
        require(!proposal.chainVoted[sourceChain], "Chain already voted");
        require(block.timestamp <= proposal.endTime, "Voting period ended");

        proposal.chainVoted[sourceChain] = true;
        proposal.chainVotes[sourceChain] = votes;

        emit CrossChainVoteReceived(proposalId, sourceChain, votes);
    }

    function executeProposal(bytes32 proposalId) external nonReentrant {
        CrossChainProposal storage proposal = proposals[proposalId];
        require(!proposal.executed && !proposal.canceled, "Proposal not active");
        require(
            block.timestamp > proposal.endTime + EXECUTION_DELAY,
            "Execution delay not passed"
        );

        uint256 totalVotes = _calculateTotalVotes(proposalId);
        require(totalVotes >= proposalThreshold, "Insufficient votes");

        proposal.executed = true;

        for (uint256 i = 0; i < proposal.actions.length; i++) {
            (bool success,) = proposal.targets[i].call{value: proposal.values[i]}(
                proposal.actions[i]
            );
            require(success, "Action execution failed");
        }

        emit ProposalExecuted(proposalId);
    }

    function cancelProposal(bytes32 proposalId) external {
        CrossChainProposal storage proposal = proposals[proposalId];
        require(
            msg.sender == proposal.proposer ||
            hasRole(GOVERNANCE_ADMIN, msg.sender),
            "Not authorized"
        );
        require(!proposal.executed && !proposal.canceled, "Proposal not active");

        proposal.canceled = true;
        emit ProposalCanceled(proposalId);
    }

    function _notifyChains(bytes memory payload) internal {
        uint256 gasForDestinationLzReceive = 350000;
        bytes memory adapterParams = abi.encodePacked(gasForDestinationLzReceive);

        for (uint16 chainId = 0; chainId < 65535; chainId++) {
            if (chainConfigs[chainId].isActive &&
                chainId != endpoint.getChainId()) {
                endpoint.send(
                    chainId,
                    abi.encodePacked(chainConfigs[chainId].governanceContract),
            payload,
            payable(msg.sender),
            address(0),
                    adapterParams
                );
            }
        }
    }

    function _calculateTotalVotes(bytes32 proposalId)
        internal
        view
        returns (uint256)
    {
        uint256 totalVotes = 0;
        CrossChainProposal storage proposal = proposals[proposalId];

        for (uint16 chainId = 0; chainId < 65535; chainId++) {
            if (proposal.chainVoted[chainId] &&
                chainConfigs[chainId].isActive &&
                chainConfigs[chainId].trustScore >= minTrustScore) {
                totalVotes += proposal.chainVotes[chainId];
            }
        }

        return totalVotes;
    }

    receive() external payable {}
} 