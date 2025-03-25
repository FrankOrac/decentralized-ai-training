// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "./interfaces/ILayerZeroEndpoint.sol";
import "./SecurityMonitor.sol";
import "./IncidentResponsePlaybook.sol";

contract CrossChainIncidentCoordinator is AccessControl, ReentrancyGuard {
    bytes32 public constant COORDINATOR_ROLE = keccak256("COORDINATOR_ROLE");
    
    struct ChainConfig {
        uint16 chainId;
        address securityMonitor;
        address playbook;
        bool isActive;
        uint256 gasLimit;
    }

    struct CrossChainIncident {
        bytes32 id;
        uint16[] affectedChains;
        mapping(uint16 => bytes32) chainIncidentIds;
        uint256 severity;
        uint256 timestamp;
        bool isResolved;
        mapping(uint16 => bool) chainResolutions;
    }

    struct IncidentCorrelation {
        bytes32[] relatedIncidents;
        uint256 correlationScore;
        string correlationType;
        uint256 lastUpdate;
    }

    ILayerZeroEndpoint public immutable lzEndpoint;
    
    mapping(uint16 => ChainConfig) public chainConfigs;
    mapping(bytes32 => CrossChainIncident) public crossChainIncidents;
    mapping(bytes32 => IncidentCorrelation) public correlations;
    mapping(bytes32 => bytes32[]) public incidentCorrelations;
    
    event CrossChainIncidentReported(
        bytes32 indexed incidentId,
        uint16[] chains,
        uint256 severity
    );
    event IncidentCorrelated(
        bytes32 indexed incidentId,
        bytes32 indexed correlatedIncidentId,
        uint256 correlationScore
    );
    event ChainResolutionConfirmed(
        bytes32 indexed incidentId,
        uint16 chainId
    );
    event CrossChainIncidentResolved(
        bytes32 indexed incidentId,
        uint256 resolutionTime
    );

    constructor(address _lzEndpoint) {
        lzEndpoint = ILayerZeroEndpoint(_lzEndpoint);
        _setupRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _setupRole(COORDINATOR_ROLE, msg.sender);
    }

    function configureChain(
        uint16 chainId,
        address securityMonitor,
        address playbook,
        uint256 gasLimit
    ) external onlyRole(DEFAULT_ADMIN_ROLE) {
        require(securityMonitor != address(0), "Invalid security monitor");
        require(playbook != address(0), "Invalid playbook");

        chainConfigs[chainId] = ChainConfig({
            chainId: chainId,
            securityMonitor: securityMonitor,
            playbook: playbook,
            isActive: true,
            gasLimit: gasLimit
        });
    }

    function reportCrossChainIncident(
        uint16[] calldata chains,
        bytes32[] calldata localIncidentIds,
        uint256 severity
    ) external onlyRole(COORDINATOR_ROLE) returns (bytes32) {
        require(chains.length > 1, "Minimum 2 chains required");
        require(chains.length == localIncidentIds.length, "Array length mismatch");

        bytes32 crossChainIncidentId = keccak256(
            abi.encodePacked(
                chains,
                block.timestamp,
                msg.sender
            )
        );

        CrossChainIncident storage incident = crossChainIncidents[crossChainIncidentId];
        incident.id = crossChainIncidentId;
        incident.affectedChains = chains;
        incident.severity = severity;
        incident.timestamp = block.timestamp;

        for (uint16 i = 0; i < chains.length; i++) {
            require(chainConfigs[chains[i]].isActive, "Chain not configured");
            incident.chainIncidentIds[chains[i]] = localIncidentIds[i];

            // Notify other chains
            bytes memory payload = abi.encode(
                crossChainIncidentId,
                localIncidentIds[i],
                severity
            );

            bytes memory path = abi.encodePacked(
                chainConfigs[chains[i]].securityMonitor,
                address(this)
            );

            lzEndpoint.send{value: 0}(
                chains[i],
                path,
                payload,
                payable(msg.sender),
                address(0),
                bytes("")
            );
        }

        // Analyze for correlations
        _analyzeCorrelations(crossChainIncidentId);

        emit CrossChainIncidentReported(crossChainIncidentId, chains, severity);
        return crossChainIncidentId;
    }

    function confirmChainResolution(
        bytes32 crossChainIncidentId,
        uint16 chainId
    ) external onlyRole(COORDINATOR_ROLE) {
        CrossChainIncident storage incident = crossChainIncidents[crossChainIncidentId];
        require(incident.id == crossChainIncidentId, "Incident not found");
        require(!incident.chainResolutions[chainId], "Already resolved");

        incident.chainResolutions[chainId] = true;
        emit ChainResolutionConfirmed(crossChainIncidentId, chainId);

        bool allResolved = true;
        for (uint16 i = 0; i < incident.affectedChains.length; i++) {
            if (!incident.chainResolutions[incident.affectedChains[i]]) {
                allResolved = false;
                break;
            }
        }

        if (allResolved) {
            incident.isResolved = true;
            emit CrossChainIncidentResolved(
                crossChainIncidentId,
                block.timestamp - incident.timestamp
            );
        }
    }

    function _analyzeCorrelations(bytes32 newIncidentId) internal {
        CrossChainIncident storage newIncident = crossChainIncidents[newIncidentId];
        
        // Look for similar incidents in the last 24 hours
        bytes32[] memory recentIncidents = _getRecentIncidents(24 hours);
        
        for (uint256 i = 0; i < recentIncidents.length; i++) {
            if (recentIncidents[i] == newIncidentId) continue;
            
            CrossChainIncident storage existingIncident = crossChainIncidents[recentIncidents[i]];
            
            uint256 correlationScore = _calculateCorrelationScore(
                newIncident,
                existingIncident
            );

            if (correlationScore >= 70) { // 70% similarity threshold
                IncidentCorrelation storage correlation = correlations[newIncidentId];
                correlation.relatedIncidents.push(recentIncidents[i]);
                correlation.correlationScore = correlationScore;
                correlation.correlationType = _determineCorrelationType(
                    newIncident,
                    existingIncident
                );
                correlation.lastUpdate = block.timestamp;

                incidentCorrelations[recentIncidents[i]].push(newIncidentId);

                emit IncidentCorrelated(
                    newIncidentId,
                    recentIncidents[i],
                    correlationScore
                );
            }
        }
    }

    function _calculateCorrelationScore(
        CrossChainIncident storage incident1,
        CrossChainIncident storage incident2
    ) internal view returns (uint256) {
        uint256 score = 0;
        uint256 totalFactors = 4;

        // Compare severity (20%)
        if (incident1.severity == incident2.severity) {
            score += 20;
        } else {
            uint256 severityDiff = incident1.severity > incident2.severity ? 
                incident1.severity - incident2.severity : 
                incident2.severity - incident1.severity;
            if (severityDiff <= 2) score += 10;
        }

        // Compare affected chains (30%)
        uint256 commonChains = 0;
        for (uint256 i = 0; i < incident1.affectedChains.length; i++) {
            for (uint256 j = 0; j < incident2.affectedChains.length; j++) {
                if (incident1.affectedChains[i] == incident2.affectedChains[j]) {
                    commonChains++;
                    break;
                }
            }
        }
        score += (commonChains * 30) / incident1.affectedChains.length;

        // Compare timing (30%)
        uint256 timeDiff = incident1.timestamp > incident2.timestamp ? 
            incident1.timestamp - incident2.timestamp : 
            incident2.timestamp - incident1.timestamp;
        if (timeDiff < 1 hours) score += 30;
        else if (timeDiff < 6 hours) score += 20;
        else if (timeDiff < 12 hours) score += 10;

        // Resolution status (20%)
        if (incident1.isResolved == incident2.isResolved) {
            score += 20;
        }

        return score;
    }

    function _determineCorrelationType(
        CrossChainIncident storage incident1,
        CrossChainIncident storage incident2
    ) internal pure returns (string memory) {
        if (incident1.severity == incident2.severity) {
            return "IDENTICAL_SEVERITY";
        } else if (incident1.affectedChains.length == incident2.affectedChains.length) {
            return "SIMILAR_SCOPE";
        } else {
            return "TEMPORAL_CORRELATION";
        }
    }

    function _getRecentIncidents(uint256 timeWindow)
        internal
        view
        returns (bytes32[] memory)
    {
        uint256 count = 0;
        bytes32[] memory temp = new bytes32[](100); // Arbitrary limit

        // Iterate through recent incidents
        // This is a simplified version - in production, you'd want to maintain an index
        for (uint256 i = 0; i < temp.length; i++) {
            bytes32 incidentId = bytes32(i); // Placeholder - need proper indexing
            CrossChainIncident storage incident = crossChainIncidents[incidentId];
            
            if (incident.timestamp > 0 && 
                block.timestamp - incident.timestamp <= timeWindow) {
                temp[count] = incidentId;
                count++;
            }
        }

        bytes32[] memory recent = new bytes32[](count);
        for (uint256 i = 0; i < count; i++) {
            recent[i] = temp[i];
        }

        return recent;
    }

    receive() external payable {}
} 