// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";

contract ProposalSimulator is AccessControl, ReentrancyGuard {
    bytes32 public constant SIMULATOR_ROLE = keccak256("SIMULATOR_ROLE");

    struct SimulationResult {
        bytes32 id;
        bool success;
        bytes returnData;
        uint256 gasUsed;
        string error;
        uint256 timestamp;
        address[] impactedContracts;
        mapping(address => bytes) stateDiff;
    }

    struct SimulationConfig {
        uint256 blockNumber;
        uint256 timestamp;
        address sender;
        uint256 value;
        bool revertOnFailure;
    }

    mapping(bytes32 => SimulationResult) public simulations;
    mapping(address => bool) public whitelistedContracts;
    
    uint256 public constant MAX_GAS_LIMIT = 8000000;
    uint256 public constant MAX_SIMULATION_DURATION = 1 hours;

    event SimulationStarted(
        bytes32 indexed simulationId,
        address[] targets,
        uint256[] values
    );
    event SimulationCompleted(
        bytes32 indexed simulationId,
        bool success,
        uint256 gasUsed
    );
    event ContractStateChanged(
        bytes32 indexed simulationId,
        address indexed contract_,
        bytes oldState,
        bytes newState
    );

    constructor() {
        _setupRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _setupRole(SIMULATOR_ROLE, msg.sender);
    }

    function simulateProposal(
        address[] memory targets,
        uint256[] memory values,
        bytes[] memory calldatas,
        SimulationConfig memory config
    ) external onlyRole(SIMULATOR_ROLE) returns (bytes32) {
        require(
            targets.length == values.length &&
            targets.length == calldatas.length,
            "Length mismatch"
        );

        bytes32 simulationId = keccak256(
            abi.encodePacked(
                block.timestamp,
                targets,
                values,
                calldatas
            )
        );

        SimulationResult storage result = simulations[simulationId];
        result.id = simulationId;
        result.timestamp = block.timestamp;
        result.impactedContracts = new address[](targets.length);

        emit SimulationStarted(simulationId, targets, values);

        uint256 startGas = gasleft();

        for (uint256 i = 0; i < targets.length; i++) {
            require(whitelistedContracts[targets[i]], "Contract not whitelisted");
            
            // Capture pre-execution state
            bytes memory preState = _captureContractState(targets[i]);
            result.stateDiff[targets[i]] = preState;
            result.impactedContracts[i] = targets[i];

            // Simulate the call
            (bool success, bytes memory returnData) = targets[i].call{
                gas: MAX_GAS_LIMIT,
                value: values[i]
            }(calldatas[i]);

            if (!success && config.revertOnFailure) {
                result.success = false;
                result.error = _extractRevertReason(returnData);
                result.gasUsed = startGas - gasleft();
                emit SimulationCompleted(simulationId, false, result.gasUsed);
                return simulationId;
            }

            // Capture post-execution state
            bytes memory postState = _captureContractState(targets[i]);
            emit ContractStateChanged(
                simulationId,
                targets[i],
                preState,
                postState
            );
        }

        result.success = true;
        result.gasUsed = startGas - gasleft();
        emit SimulationCompleted(simulationId, true, result.gasUsed);

        return simulationId;
    }

    function getSimulationResult(bytes32 simulationId)
        external
        view
        returns (
            bool success,
            uint256 gasUsed,
            string memory error,
            address[] memory impactedContracts
        )
    {
        SimulationResult storage result = simulations[simulationId];
        return (
            result.success,
            result.gasUsed,
            result.error,
            result.impactedContracts
        );
    }

    function getStateDiff(bytes32 simulationId, address contract_)
        external
        view
        returns (bytes memory)
    {
        return simulations[simulationId].stateDiff[contract_];
    }

    function whitelistContract(address contract_)
        external
        onlyRole(DEFAULT_ADMIN_ROLE)
    {
        whitelistedContracts[contract_] = true;
    }

    function removeContractWhitelist(address contract_)
        external
        onlyRole(DEFAULT_ADMIN_ROLE)
    {
        whitelistedContracts[contract_] = false;
    }

    function _captureContractState(address contract_)
        internal
        view
        returns (bytes memory)
    {
        // This is a simplified version. In practice, you'd want to:
        // 1. Read all storage slots
        // 2. Capture balance
        // 3. Capture nonce
        // 4. Capture code hash
        bytes memory state;
        assembly {
            let size := extcodesize(contract_)
            state := mload(0x40)
            mstore(0x40, add(state, and(add(add(size, 0x20), 0x1f), not(0x1f))))
            mstore(state, size)
            extcodecopy(contract_, add(state, 0x20), 0, size)
        }
        return state;
    }

    function _extractRevertReason(bytes memory revertData)
        internal
        pure
        returns (string memory)
    {
        if (revertData.length < 68) return "Unknown reason";
        bytes memory revertReason = new bytes(revertData.length - 68);
        for (uint256 i = 68; i < revertData.length; i++) {
            revertReason[i - 68] = revertData[i];
        }
        return string(revertReason);
    }

    receive() external payable {}
} 