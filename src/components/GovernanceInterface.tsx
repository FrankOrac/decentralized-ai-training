import React, { useState, useEffect } from 'react';
import {
  Box,
  Button,
  VStack,
  HStack,
  Table,
  Thead,
  Tbody,
  Tr,
  Th,
  Td,
  Modal,
  ModalOverlay,
  ModalContent,
  ModalHeader,
  ModalBody,
  ModalCloseButton,
  FormControl,
  FormLabel,
  Input,
  Textarea,
  useDisclosure,
  Badge,
  Text,
  Progress,
  useToast,
  Heading,
  Stat,
  StatLabel,
  StatNumber,
  StatHelpText,
  Grid
} from '@chakra-ui/react';
import { ethers } from 'ethers';
import { useWeb3 } from '../hooks/useWeb3';

interface Proposal {
  id: number;
  description: string;
  proposer: string;
  startBlock: number;
  endBlock: number;
  forVotes: number;
  againstVotes: number;
  executed: boolean;
  canceled: boolean;
}

interface SystemParameters {
  votingPeriod: number;
  votingDelay: number;
  proposalThreshold: string;
  quorumPercentage: number;
  executionDelay: number;
}

export function GovernanceInterface() {
  const { contract, account, blockNumber } = useWeb3();
  const toast = useToast();
  const { isOpen, onOpen, onClose } = useDisclosure();
  
  const [proposals, setProposals] = useState<Proposal[]>([]);
  const [parameters, setParameters] = useState<SystemParameters | null>(null);
  const [loading, setLoading] = useState(false);
  const [newProposal, setNewProposal] = useState({
    description: '',
    target: '',
    value: '0',
    calldata: ''
  });

  useEffect(() => {
    if (contract) {
      fetchProposals();
      fetchParameters();
    }
  }, [contract, blockNumber]);

  const fetchProposals = async () => {
    try {
      const proposalCount = await contract.proposalCount();
      const fetchedProposals = [];
      
      for (let i = 1; i <= proposalCount; i++) {
        const proposal = await contract.proposals(i);
        fetchedProposals.push({
          id: i,
          description: proposal.description,
          proposer: proposal.proposer,
          startBlock: proposal.startBlock.toNumber(),
          endBlock: proposal.endBlock.toNumber(),
          forVotes: proposal.forVotes.toNumber(),
          againstVotes: proposal.againstVotes.toNumber(),
          executed: proposal.executed,
          canceled: proposal.canceled
        });
      }
      
      setProposals(fetchedProposals);
    } catch (error) {
      console.error('Error fetching proposals:', error);
      toast({
        title: 'Error fetching proposals',
        status: 'error',
        duration: 5000
      });
    }
  };

  const fetchParameters = async () => {
    try {
      const params = await contract.parameters();
      setParameters({
        votingPeriod: params.votingPeriod.toNumber(),
        votingDelay: params.votingDelay.toNumber(),
        proposalThreshold: ethers.utils.formatEther(params.proposalThreshold),
        quorumPercentage: params.quorumPercentage.toNumber(),
        executionDelay: params.executionDelay.toNumber()
      });
    } catch (error) {
      console.error('Error fetching parameters:', error);
    }
  };

  const handleCreateProposal = async () => {
    try {
      setLoading(true);
      const tx = await contract.propose(
        [newProposal.target],
        [ethers.utils.parseEther(newProposal.value)],
        [newProposal.calldata],
        newProposal.description
      );
      await tx.wait();
      
      toast({
        title: 'Proposal created successfully',
        status: 'success',
        duration: 5000
      });
      
      onClose();
      fetchProposals();
    } catch (error) {
      console.error('Error creating proposal:', error);
      toast({
        title: 'Error creating proposal',
        description: error.message,
        status: 'error',
        duration: 5000
      });
    } finally {
      setLoading(false);
    }
  };

  const handleVote = async (proposalId: number, support: boolean) => {
    try {
      setLoading(true);
      const tx = await contract.castVote(proposalId, support);
      await tx.wait();
      
      toast({
        title: 'Vote cast successfully',
        status: 'success',
        duration: 5000
      });
      
      fetchProposals();
    } catch (error) {
      console.error('Error casting vote:', error);
      toast({
        title: 'Error casting vote',
        description: error.message,
        status: 'error',
        duration: 5000
      });
    } finally {
      setLoading(false);
    }
  };

  const getProposalStatus = (proposal: Proposal) => {
    if (proposal.canceled) return 'Canceled';
    if (proposal.executed) return 'Executed';
    if (blockNumber < proposal.startBlock) return 'Pending';
    if (blockNumber <= proposal.endBlock) return 'Active';
    return 'Closed';
  };

  const getStatusColor = (status: string) => {
    switch (status) {
      case 'Executed': return 'green';
      case 'Active': return 'blue';
      case 'Pending': return 'yellow';
      case 'Canceled': return 'red';
      default: return 'gray';
    }
  };

  return (
    <Box p={6}>
      <VStack spacing={6} align="stretch">
        <HStack justify="space-between">
          <Heading size="lg">Governance Dashboard</Heading>
          <Button colorScheme="blue" onClick={onOpen}>
            Create Proposal
          </Button>
        </HStack>

        {parameters && (
          <Grid templateColumns="repeat(3, 1fr)" gap={6}>
            <Stat>
              <StatLabel>Voting Period</StatLabel>
              <StatNumber>{parameters.votingPeriod} blocks</StatNumber>
              <StatHelpText>≈ {(parameters.votingPeriod * 13) / 3600} hours</StatHelpText>
            </Stat>
            <Stat>
              <StatLabel>Proposal Threshold</StatLabel>
              <StatNumber>{parameters.proposalThreshold} ETH</StatNumber>
            </Stat>
            <Stat>
              <StatLabel>Quorum</StatLabel>
              <StatNumber>{parameters.quorumPercentage}%</StatNumber>
            </Stat>
          </Grid>
        )}

        <Box overflowX="auto">
          <Table variant="simple">
            <Thead>
              <Tr>
                <Th>ID</Th>
                <Th>Description</Th>
                <Th>Proposer</Th>
                <Th>Status</Th>
                <Th>Votes</Th>
                <Th>Actions</Th>
              </Tr>
            </Thead>
            <Tbody>
              {proposals.map((proposal) => {
                const status = getProposalStatus(proposal);
                const totalVotes = proposal.forVotes + proposal.againstVotes;
                const forPercentage = totalVotes > 0 
                  ? (proposal.forVotes / totalVotes) * 100 
                  : 0;

                return (
                  <Tr key={proposal.id}>
                    <Td>{proposal.id}</Td>
                    <Td>{proposal.description}</Td>
                    <Td>{`${proposal.proposer.slice(0, 6)}...${proposal.proposer.slice(-4)}`}</Td>
                    <Td>
                      <Badge colorScheme={getStatusColor(status)}>
                        {status}
                      </Badge>
                    </Td>
                    <Td>
                      <VStack align="stretch" spacing={2}>
                        <Progress
                          value={forPercentage}
                          colorScheme="green"
                          size="sm"
                        />
                        <Text fontSize="sm">
                          For: {proposal.forVotes} | Against: {proposal.againstVotes}
                        </Text>
                      </VStack>
                    </Td>
                    <Td>
                      {status === 'Active' && (
                        <HStack spacing={2}>
                          <Button
                            size="sm"
                            colorScheme="green"
                            onClick={() => handleVote(proposal.id, true)}
                            isLoading={loading}
                          >
                            Vote For
                          </Button>
                          <Button
                            size="sm"
                            colorScheme="red"
                            onClick={() => handleVote(proposal.id, false)}
                            isLoading={loading}
                          >
                            Vote Against
                          </Button>
                        </HStack>
                      )}
                    </Td>
                  </Tr>
                );
              })}
            </Tbody>
          </Table>
        </Box>

        <Modal isOpen={isOpen} onClose={onClose}>
          <ModalOverlay />
          <ModalContent>
            <ModalHeader>Create New Proposal</ModalHeader>
            <ModalCloseButton />
            <ModalBody pb={6}>
              <VStack spacing={4}>
                <FormControl>
                  <FormLabel>Description</FormLabel>
                  <Textarea
                    value={newProposal.description}
                    onChange={(e) => setNewProposal({
                      ...newProposal,
                      description: e.target.value
                    })}
                  />
                </FormControl>

                <FormControl>
                  <FormLabel>Target Address</FormLabel>
                  <Input
                    value={newProposal.target}
                    onChange={(e) => setNewProposal({
                      ...newProposal,
                      target: e.target.value
                    })}
                  />
                </FormControl>

                <FormControl>
                  <FormLabel>Value (ETH)</FormLabel>
                  <Input
                    type="number"
                    value={newProposal.value}
                    onChange={(e) => setNewProposal({
                      ...newProposal,
                      value: e.target.value
                    })}
                  />
                </FormControl>

                <FormControl>
                  <FormLabel>Calldata (hex)</FormLabel>
                  <Input
                    value={newProposal.calldata}
                    onChange={(e) => setNewProposal({
                      ...newProposal,
                      calldata: e.target.value
                    })}
                  />
                </FormControl>

                <Button
                  colorScheme="blue"
                  width="full"
                  onClick={handleCreateProposal}
                  isLoading={loading}
                >
                  Create Proposal
                </Button>
              </VStack>
            </ModalBody>
          </ModalContent>
        </Modal>
      </VStack>
    </Box>
  );
}
