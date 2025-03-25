// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "./interfaces/ILayerZeroEndpoint.sol";
import "./interfaces/IAutomatedWorkflow.sol";

contract CrossChainWorkflowCoordinator is AccessControl, ReentrancyGuard {
    bytes32 public constant COORDINATOR_ROLE = keccak256("COORDINATOR_ROLE");
    
    struct ChainConfig {
        uint16 chainId;
        address workflowContract;
        bool isActive;
        uint256 gasLimit;
        uint256 nativeFee;
    }

    struct CrossChainWorkflow {
        bytes32 id;
        uint16[] involvedChains;
        mapping(uint16 => bytes32) chainWorkflowIds;
        uint256 startTime;
        uint256 completionTime;
        bool isComplete;
        mapping(uint16 => bool) chainCompletionStatus;
    }

    ILayerZeroEndpoint public immutable lzEndpoint;
    
    mapping(uint16 => ChainConfig) public chainConfigs;
    mapping(bytes32 => CrossChainWorkflow) public crossChainWorkflows;
    mapping(bytes32 => bytes32) public messageToWorkflow;
    
    event CrossChainWorkflowInitiated(
        bytes32 indexed workflowId,
        uint16[] chains
    );
    event ChainWorkflowCompleted(
        bytes32 indexed workflowId,
        uint16 chainId
    );
    event CrossChainWorkflowCompleted(
        bytes32 indexed workflowId,
        uint256 completionTime
    );
    event ChainConfigUpdated(
        uint16 indexed chainId,
        address workflowContract,
        uint256 gasLimit
    );

    constructor(address _lzEndpoint) {
        lzEndpoint = ILayerZeroEndpoint(_lzEndpoint);
        _setupRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _setupRole(COORDINATOR_ROLE, msg.sender);
    }

    function configureChain(
        uint16 chainId,
        address workflowContract,
        uint256 gasLimit,
        uint256 nativeFee
    ) external onlyRole(DEFAULT_ADMIN_ROLE) {
        require(workflowContract != address(0), "Invalid workflow contract");
        require(gasLimit > 0, "Invalid gas limit");

        chainConfigs[chainId] = ChainConfig({
            chainId: chainId,
            workflowContract: workflowContract,
            isActive: true,
            gasLimit: gasLimit,
            nativeFee: nativeFee
        });

        emit ChainConfigUpdated(chainId, workflowContract, gasLimit);
    }

    function initiateCrossChainWorkflow(
        uint16[] calldata chains,
        bytes[] calldata workflowData
    ) external payable onlyRole(COORDINATOR_ROLE) returns (bytes32) {
        require(chains.length > 1, "Minimum 2 chains required");
        require(chains.length == workflowData.length, "Data mismatch");

        uint256 totalFee = 0;
        for (uint16 i = 0; i < chains.length; i++) {
            require(chainConfigs[chains[i]].isActive, "Chain not configured");
            totalFee += chainConfigs[chains[i]].nativeFee;
        }
        require(msg.value >= totalFee, "Insufficient fee");

        bytes32 workflowId = keccak256(
            abi.encodePacked(
                chains,
                block.timestamp,
                msg.sender
            )
        );

        CrossChainWorkflow storage workflow = crossChainWorkflows[workflowId];
        workflow.id = workflowId;
        workflow.involvedChains = chains;
        workflow.startTime = block.timestamp;

        for (uint16 i = 0; i < chains.length; i++) {
            bytes memory payload = abi.encode(
                workflowId,
                workflowData[i]
            );

            bytes memory path = abi.encodePacked(
                chainConfigs[chains[i]].workflowContract,
                address(this)
            );

            lzEndpoint.send{value: chainConfigs[chains[i]].nativeFee}(
                chains[i],
                path,
                payload,
                payable(msg.sender),
                address(0),
                bytes("")
            );
        }

        emit CrossChainWorkflowInitiated(workflowId, chains);
        return workflowId;
    }

    function lzReceive(
        uint16 _srcChainId,
        bytes memory _srcAddress,
        uint64 _nonce,
        bytes memory _payload
    ) external {
        require(msg.sender == address(lzEndpoint), "Invalid endpoint");
        
        (bytes32 workflowId, bytes32 chainWorkflowId, bool isCompleted) = 
            abi.decode(_payload, (bytes32, bytes32, bool));

        CrossChainWorkflow storage workflow = crossChainWorkflows[workflowId];
        require(workflow.id == workflowId, "Invalid workflow");

        if (isCompleted) {
            workflow.chainCompletionStatus[_srcChainId] = true;
            emit ChainWorkflowCompleted(workflowId, _srcChainId);

            bool allComplete = true;
            for (uint16 i = 0; i < workflow.involvedChains.length; i++) {
                if (!workflow.chainCompletionStatus[workflow.involvedChains[i]]) {
                    allComplete = false;
                    break;
                }
            }

            if (allComplete) {
                workflow.isComplete = true;
                workflow.completionTime = block.timestamp;
                emit CrossChainWorkflowCompleted(workflowId, block.timestamp);
            }
        } else {
            workflow.chainWorkflowIds[_srcChainId] = chainWorkflowId;
        }
    }

    function getWorkflowStatus(bytes32 workflowId)
        external
        view
        returns (
            uint16[] memory chains,
            bytes32[] memory chainWorkflowIds,
            bool[] memory completionStatus,
            bool isComplete,
            uint256 startTime,
            uint256 completionTime
        )
    {
        CrossChainWorkflow storage workflow = crossChainWorkflows[workflowId];
        require(workflow.id == workflowId, "Workflow not found");

        chains = workflow.involvedChains;
        chainWorkflowIds = new bytes32[](chains.length);
        completionStatus = new bool[](chains.length);

        for (uint16 i = 0; i < chains.length; i++) {
            chainWorkflowIds[i] = workflow.chainWorkflowIds[chains[i]];
            completionStatus[i] = workflow.chainCompletionStatus[chains[i]];
        }

        return (
            chains,
            chainWorkflowIds,
            completionStatus,
            workflow.isComplete,
            workflow.startTime,
            workflow.completionTime
        );
    }

    receive() external payable {}
} 