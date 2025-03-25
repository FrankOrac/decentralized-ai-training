import {
  Box,
  Button,
  FormControl,
  FormLabel,
  Input,
  Stack,
  Textarea,
  Table,
  Thead,
  Tbody,
  Tr,
  Th,
  Td,
  Badge,
  useToast,
  Modal,
  ModalOverlay,
  ModalContent,
  ModalHeader,
  ModalBody,
  ModalCloseButton,
  useDisclosure,
} from "@chakra-ui/react";
import { useState, useEffect } from "react";
import { useWeb3 } from "../context/Web3Context";

export function DisputeInterface() {
  const { contract, account } = useWeb3();
  const [disputes, setDisputes] = useState([]);
  const [newDispute, setNewDispute] = useState({
    taskId: "",
    reason: "",
    evidence: "",
  });
  const { isOpen, onOpen, onClose } = useDisclosure();
  const toast = useToast();

  useEffect(() => {
    if (contract) {
      fetchDisputes();
    }
  }, [contract]);

  const fetchDisputes = async () => {
    try {
      const disputeCount = await contract.disputeCount();
      const fetchedDisputes = [];

      for (let i = 1; i <= disputeCount; i++) {
        const dispute = await contract.getDisputeDetails(i);
        fetchedDisputes.push({
          id: i,
          ...dispute,
        });
      }

      setDisputes(fetchedDisputes);
    } catch (error) {
      console.error("Error fetching disputes:", error);
    }
  };

  const handleCreateDispute = async () => {
    try {
      const tx = await contract.createDispute(
        newDispute.taskId,
        newDispute.reason,
        newDispute.evidence
      );
      await tx.wait();

      toast({
        title: "Dispute Created",
        description: "Your dispute has been submitted successfully",
        status: "success",
      });

      onClose();
      fetchDisputes();
    } catch (error: any) {
      toast({
        title: "Error",
        description: error.message,
        status: "error",
      });
    }
  };

  const handleVote = async (disputeId: number, support: boolean) => {
    try {
      const tx = await contract.castVote(disputeId, support, "");
      await tx.wait();

      toast({
        title: "Vote Cast",
        description: "Your vote has been recorded successfully",
        status: "success",
      });

      fetchDisputes();
    } catch (error: any) {
      toast({
        title: "Error",
        description: error.message,
        status: "error",
      });
    }
  };

  return (
    <Box p={6}>
      <Stack spacing={6}>
        <Button colorScheme="blue" onClick={onOpen}>
          Create New Dispute
        </Button>

        <Table variant="simple">
          <Thead>
            <Tr>
              <Th>ID</Th>
              <Th>Task ID</Th>
              <Th>Status</Th>
              <Th>Votes For</Th>
              <Th>Votes Against</Th>
              <Th>Actions</Th>
            </Tr>
          </Thead>
          <Tbody>
            {disputes.map((dispute: any) => (
              <Tr key={dispute.id}>
                <Td>{dispute.id}</Td>
                <Td>{dispute.taskId.toString()}</Td>
                <Td>
                  <Badge
                    colorScheme={
                      dispute.status === 2
                        ? "green"
                        : dispute.status === 3
                        ? "red"
                        : "yellow"
                    }
                  >
                    {
                      ["Pending", "UnderReview", "Resolved", "Rejected"][
                        dispute.status
                      ]
                    }
                  </Badge>
                </Td>
                <Td>{dispute.votesFor.toString()}</Td>
                <Td>{dispute.votesAgainst.toString()}</Td>
                <Td>
                  {dispute.status === 1 && (
                    <Stack direction="row" spacing={2}>
                      <Button
                        size="sm"
                        colorScheme="green"
                        onClick={() => handleVote(dispute.id, true)}
                      >
                        Support
                      </Button>
                      <Button
                        size="sm"
                        colorScheme="red"
                        onClick={() => handleVote(dispute.id, false)}
                      >
                        Reject
                      </Button>
                    </Stack>
                  )}
                </Td>
              </Tr>
            ))}
          </Tbody>
        </Table>

        <Modal isOpen={isOpen} onClose={onClose}>
          <ModalOverlay />
          <ModalContent>
            <ModalHeader>Create New Dispute</ModalHeader>
            <ModalCloseButton />
            <ModalBody>
              <Stack spacing={4}>
                <FormControl>
                  <FormLabel>Task ID</FormLabel>
                  <Input
                    value={newDispute.taskId}
                    onChange={(e) =>
                      setNewDispute({
                        ...newDispute,
                        taskId: e.target.value,
                      })
                    }
                  />
                </FormControl>

                <FormControl>
                  <FormLabel>Reason</FormLabel>
                  <Input
                    value={newDispute.reason}
                    onChange={(e) =>
                      setNewDispute({
                        ...newDispute,
                        reason: e.target.value,
                      })
                    }
                  />
                </FormControl>

                <FormControl>
                  <FormLabel>Evidence</FormLabel>
                  <Textarea
                    value={newDispute.evidence}
                    onChange={(e) =>
                      setNewDispute({
                        ...newDispute,
                        evidence: e.target.value,
                      })
                    }
                  />
                </FormControl>

                <Button colorScheme="blue" onClick={handleCreateDispute}>
                  Submit Dispute
                </Button>
              </Stack>
            </ModalBody>
          </ModalContent>
        </Modal>
      </Stack>
    </Box>
  );
}
