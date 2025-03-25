// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";

contract MultiSigProposal is AccessControl, ReentrancyGuard {
    using ECDSA for bytes32;

    bytes32 public constant PROPOSER_ROLE = keccak256("PROPOSER_ROLE");
    bytes32 public constant SIGNER_ROLE = keccak256("SIGNER_ROLE");

    struct Proposal {
        uint256 id;
        address proposer;
        address[] targets;
        uint256[] values;
        bytes[] calldatas;
        string description;
        uint256 startTime;
        uint256 endTime;
        bool executed;
        bool canceled;
        uint256 requiredSignatures;
        mapping(address => bool) hasSignedApproval;
        uint256 signatureCount;
    }

    struct SignerConfig {
        uint256 weight;
        uint256 lastActiveTime;
        bool isActive;
    }

    mapping(uint256 => Proposal) public proposals;
    mapping(address => SignerConfig) public signerConfigs;
    
    uint256 public proposalCount;
    uint256 public minSignatures;
    uint256 public proposalDuration;
    uint256 public constant MAX_SIGNERS = 50;

    event ProposalCreated(
        uint256 indexed proposalId,
        address indexed proposer,
        address[] targets,
        uint256[] values,
        string description
    );
    event ProposalSigned(
        uint256 indexed proposalId,
        address indexed signer
    );
    event ProposalExecuted(
        uint256 indexed proposalId
    );
    event ProposalCanceled(
        uint256 indexed proposalId
    );
    event SignerConfigUpdated(
        address indexed signer,
        uint256 weight,
        bool isActive
    );

    constructor(
        uint256 _minSignatures,
        uint256 _proposalDuration
    ) {
        require(_minSignatures > 0, "Invalid min signatures");
        minSignatures = _minSignatures;
        proposalDuration = _proposalDuration;

        _setupRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _setupRole(PROPOSER_ROLE, msg.sender);
        _setupRole(SIGNER_ROLE, msg.sender);

        // Initialize default signer config
        signerConfigs[msg.sender] = SignerConfig({
            weight: 1,
            lastActiveTime: block.timestamp,
            isActive: true
        });
    }

    function createProposal(
        address[] memory targets,
        uint256[] memory values,
        bytes[] memory calldatas,
        string memory description,
        uint256 requiredSignatures
    ) external onlyRole(PROPOSER_ROLE) returns (uint256) {
        require(
            targets.length == values.length &&
            targets.length == calldatas.length,
            "Length mismatch"
        );
        require(
            requiredSignatures >= minSignatures,
            "Invalid required signatures"
        );

        proposalCount++;
        Proposal storage newProposal = proposals[proposalCount];
        newProposal.id = proposalCount;
        newProposal.proposer = msg.sender;
        newProposal.targets = targets;
        newProposal.values = values;
        newProposal.calldatas = calldatas;
        newProposal.description = description;
        newProposal.startTime = block.timestamp;
        newProposal.endTime = block.timestamp + proposalDuration;
        newProposal.requiredSignatures = requiredSignatures;

        emit ProposalCreated(
            proposalCount,
            msg.sender,
            targets,
            values,
            description
        );

        return proposalCount;
    }

    function signProposal(uint256 proposalId)
        external
        onlyRole(SIGNER_ROLE)
    {
        require(signerConfigs[msg.sender].isActive, "Signer not active");
        
        Proposal storage proposal = proposals[proposalId];
        require(!proposal.executed, "Proposal already executed");
        require(!proposal.canceled, "Proposal canceled");
        require(
            block.timestamp <= proposal.endTime,
            "Proposal expired"
        );
        require(
            !proposal.hasSignedApproval[msg.sender],
            "Already signed"
        );

        proposal.hasSignedApproval[msg.sender] = true;
        proposal.signatureCount = proposal.signatureCount.add(
            signerConfigs[msg.sender].weight
        );
        signerConfigs[msg.sender].lastActiveTime = block.timestamp;

        emit ProposalSigned(proposalId, msg.sender);
    }

    function executeProposal(uint256 proposalId)
        external
        nonReentrant
    {
        Proposal storage proposal = proposals[proposalId];
        require(!proposal.executed, "Proposal already executed");
        require(!proposal.canceled, "Proposal canceled");
        require(
            proposal.signatureCount >= proposal.requiredSignatures,
            "Insufficient signatures"
        );

        proposal.executed = true;

        for (uint256 i = 0; i < proposal.targets.length; i++) {
            (bool success, ) = proposal.targets[i].call{value: proposal.values[i]}(
                proposal.calldatas[i]
            );
            require(success, "Proposal execution failed");
        }

        emit ProposalExecuted(proposalId);
    }

    function cancelProposal(uint256 proposalId)
        external
    {
        Proposal storage proposal = proposals[proposalId];
        require(
            msg.sender == proposal.proposer ||
            hasRole(DEFAULT_ADMIN_ROLE, msg.sender),
            "Not authorized"
        );
        require(!proposal.executed, "Proposal already executed");
        require(!proposal.canceled, "Proposal already canceled");

        proposal.canceled = true;
        emit ProposalCanceled(proposalId);
    }

    function updateSignerConfig(
        address signer,
        uint256 weight,
        bool isActive
    ) external onlyRole(DEFAULT_ADMIN_ROLE) {
        require(weight > 0, "Invalid weight");
        require(
            getRoleMemberCount(SIGNER_ROLE) <= MAX_SIGNERS,
            "Too many signers"
        );

        signerConfigs[signer] = SignerConfig({
            weight: weight,
            lastActiveTime: block.timestamp,
            isActive: isActive
        });

        if (isActive && !hasRole(SIGNER_ROLE, signer)) {
            grantRole(SIGNER_ROLE, signer);
        } else if (!isActive && hasRole(SIGNER_ROLE, signer)) {
            revokeRole(SIGNER_ROLE, signer);
        }

        emit SignerConfigUpdated(signer, weight, isActive);
    }

    function getProposalSignatures(uint256 proposalId)
        external
        view
        returns (address[] memory signers)
    {
        Proposal storage proposal = proposals[proposalId];
        address[] memory allSigners = new address[](getRoleMemberCount(SIGNER_ROLE));
        uint256 count = 0;

        for (uint256 i = 0; i < getRoleMemberCount(SIGNER_ROLE); i++) {
            address signer = getRoleMember(SIGNER_ROLE, i);
            if (proposal.hasSignedApproval[signer]) {
                allSigners[count] = signer;
                count++;
            }
        }

        signers = new address[](count);
        for (uint256 i = 0; i < count; i++) {
            signers[i] = allSigners[i];
        }

        return signers;
    }

    receive() external payable {}
} 