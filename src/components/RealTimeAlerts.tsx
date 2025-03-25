import React, { useState, useEffect, useCallback, useRef } from "react";
import {
  Box,
  VStack,
  HStack,
  Text,
  Badge,
  Button,
  useToast,
  Collapse,
  IconButton,
  Table,
  Thead,
  Tbody,
  Tr,
  Th,
  Td,
  Drawer,
  DrawerBody,
  DrawerHeader,
  DrawerOverlay,
  DrawerContent,
  DrawerCloseButton,
  useDisclosure,
  Switch,
  FormControl,
  FormLabel,
} from "@chakra-ui/react";
import {
  ChevronDownIcon,
  ChevronUpIcon,
  BellIcon,
  SettingsIcon,
} from "@chakra-ui/icons";
import { useContract } from "../hooks/useContract";
import { useWeb3React } from "@web3-react/core";
import { ethers } from "ethers";
import { format } from "date-fns";

interface Alert {
  id: string;
  modelType: string;
  timestamp: number;
  score: number;
  isAnomaly: boolean;
  evidence: string;
  status: "new" | "investigating" | "resolved";
}

interface AlertSettings {
  modelType: string;
  enabled: boolean;
  threshold: number;
  notificationMethod: "all" | "critical" | "none";
}

export const RealTimeAlerts: React.FC = () => {
  const [alerts, setAlerts] = useState<Alert[]>([]);
  const [settings, setSettings] = useState<AlertSettings[]>([]);
  const [isSubscribed, setIsSubscribed] = useState<boolean>(true);
  const [selectedAlert, setSelectedAlert] = useState<string | null>(null);
  const [loading, setLoading] = useState<boolean>(true);

  const toast = useToast();
  const { isOpen, onOpen, onClose } = useDisclosure();
  const websocketRef = useRef<WebSocket | null>(null);

  const { contract: anomalyDetector } = useContract("AnomalyDetector");
  const { account } = useWeb3React();

  // Initialize WebSocket connection
  useEffect(() => {
    if (isSubscribed && account) {
      const ws = new WebSocket(process.env.REACT_APP_WS_ENDPOINT!);

      ws.onopen = () => {
        ws.send(
          JSON.stringify({
            type: "subscribe",
            account,
            models: settings.filter((s) => s.enabled).map((s) => s.modelType),
          })
        );
      };

      ws.onmessage = (event) => {
        const data = JSON.parse(event.data);
        if (data.type === "anomaly") {
          handleNewAlert(data.alert);
        }
      };

      ws.onerror = (error) => {
        console.error("WebSocket error:", error);
        toast({
          title: "Connection Error",
          description: "Failed to connect to alert service",
          status: "error",
          duration: 5000,
        });
      };

      websocketRef.current = ws;
      return () => ws.close();
    }
  }, [isSubscribed, account, settings]);

  const handleNewAlert = useCallback(
    (alert: Alert) => {
      setAlerts((prev) => [alert, ...prev].slice(0, 100)); // Keep last 100 alerts

      const alertSetting = settings.find(
        (s) => s.modelType === alert.modelType
      );
      if (
        alertSetting?.notificationMethod === "all" ||
        (alertSetting?.notificationMethod === "critical" &&
          alert.score > alertSetting.threshold)
      ) {
        toast({
          title: "New Anomaly Detected",
          description: `${alert.modelType}: Score ${alert.score}`,
          status: "warning",
          duration: 10000,
          isClosable: true,
        });
      }
    },
    [settings, toast]
  );

  const fetchHistoricalAlerts = useCallback(async () => {
    try {
      setLoading(true);
      const filter = anomalyDetector.filters.AnomalyDetected();
      const events = await anomalyDetector.queryFilter(filter, -10000);

      const historicalAlerts = await Promise.all(
        events.map(async (event) => {
          const result = await anomalyDetector.detectionResults(
            event.args.detectionId
          );
          return {
            id: event.args.detectionId,
            modelType: event.args.modelType,
            timestamp: result.timestamp.toNumber(),
            score: event.args.score.toNumber(),
            isAnomaly: event.args.isAnomaly,
            evidence: ethers.utils.toUtf8String(result.evidence),
            status: "resolved",
          };
        })
      );

      setAlerts((prev) => [...historicalAlerts, ...prev]);
      setLoading(false);
    } catch (error) {
      console.error("Error fetching historical alerts:", error);
      toast({
        title: "Error",
        description: "Failed to fetch historical alerts",
        status: "error",
        duration: 5000,
      });
      setLoading(false);
    }
  }, [anomalyDetector, toast]);

  useEffect(() => {
    fetchHistoricalAlerts();
  }, [fetchHistoricalAlerts]);

  const handleStatusChange = async (
    alertId: string,
    status: Alert["status"]
  ) => {
    try {
      setAlerts((prev) =>
        prev.map((alert) =>
          alert.id === alertId ? { ...alert, status } : alert
        )
      );

      if (status === "resolved") {
        await anomalyDetector.reportFalsePositive(alertId);
      }
    } catch (error) {
      console.error("Error updating alert status:", error);
      toast({
        title: "Error",
        description: "Failed to update alert status",
        status: "error",
        duration: 5000,
      });
    }
  };

  const handleSettingChange = (
    modelType: string,
    field: keyof AlertSettings,
    value: any
  ) => {
    setSettings((prev) =>
      prev.map((setting) =>
        setting.modelType === modelType
          ? { ...setting, [field]: value }
          : setting
      )
    );

    // Reconnect WebSocket with new settings if necessary
    if (
      field === "enabled" &&
      websocketRef.current?.readyState === WebSocket.OPEN
    ) {
      websocketRef.current.send(
        JSON.stringify({
          type: "updateSubscription",
          models: settings.filter((s) => s.enabled).map((s) => s.modelType),
        })
      );
    }
  };

  return (
    <Box p={6}>
      <VStack spacing={6} align="stretch">
        <HStack justify="space-between">
          <Text fontSize="2xl" fontWeight="bold">
            Real-Time Alerts
          </Text>
          <HStack>
            <Switch
              isChecked={isSubscribed}
              onChange={(e) => setIsSubscribed(e.target.checked)}
              colorScheme="green"
            />
            <Text>Live Updates</Text>
            <IconButton
              aria-label="Settings"
              icon={<SettingsIcon />}
              onClick={onOpen}
            />
          </HStack>
        </HStack>

        <Table variant="simple">
          <Thead>
            <Tr>
              <Th>Time</Th>
              <Th>Model</Th>
              <Th>Score</Th>
              <Th>Status</Th>
              <Th>Actions</Th>
            </Tr>
          </Thead>
          <Tbody>
            {alerts.map((alert) => (
              <React.Fragment key={alert.id}>
                <Tr
                  cursor="pointer"
                  onClick={() =>
                    setSelectedAlert(
                      selectedAlert === alert.id ? null : alert.id
                    )
                  }
                  bg={alert.status === "new" ? "yellow.50" : undefined}
                >
                  <Td>
                    {format(alert.timestamp * 1000, "yyyy-MM-dd HH:mm:ss")}
                  </Td>
                  <Td>{alert.modelType}</Td>
                  <Td>
                    <Badge
                      colorScheme={
                        alert.score > 80
                          ? "red"
                          : alert.score > 50
                          ? "yellow"
                          : "green"
                      }
                    >
                      {alert.score}
                    </Badge>
                  </Td>
                  <Td>
                    <Badge
                      colorScheme={
                        alert.status === "new"
                          ? "yellow"
                          : alert.status === "investigating"
                          ? "blue"
                          : "green"
                      }
                    >
                      {alert.status}
                    </Badge>
                  </Td>
                  <Td>
                    <IconButton
                      aria-label="Toggle details"
                      icon={
                        selectedAlert === alert.id ? (
                          <ChevronUpIcon />
                        ) : (
                          <ChevronDownIcon />
                        )
                      }
                      size="sm"
                      variant="ghost"
                    />
                  </Td>
                </Tr>
                <Tr>
                  <Td colSpan={5} p={0}>
                    <Collapse in={selectedAlert === alert.id}>
                      <Box p={4} bg="gray.50">
                        <VStack align="stretch" spacing={4}>
                          <Text fontWeight="bold">Evidence:</Text>
                          <Text>{alert.evidence}</Text>
                          <HStack>
                            <Button
                              size="sm"
                              colorScheme="blue"
                              isDisabled={alert.status === "investigating"}
                              onClick={() =>
                                handleStatusChange(alert.id, "investigating")
                              }
                            >
                              Investigate
                            </Button>
                            <Button
                              size="sm"
                              colorScheme="green"
                              isDisabled={alert.status === "resolved"}
                              onClick={() =>
                                handleStatusChange(alert.id, "resolved")
                              }
                            >
                              Resolve
                            </Button>
                          </HStack>
                        </VStack>
                      </Box>
                    </Collapse>
                  </Td>
                </Tr>
              </React.Fragment>
            ))}
          </Tbody>
        </Table>
      </VStack>

      <Drawer isOpen={isOpen} placement="right" onClose={onClose}>
        <DrawerOverlay />
        <DrawerContent>
          <DrawerCloseButton />
          <DrawerHeader>Alert Settings</DrawerHeader>
          <DrawerBody>
            <VStack spacing={6} align="stretch">
              {settings.map((setting) => (
                <Box
                  key={setting.modelType}
                  p={4}
                  borderWidth={1}
                  borderRadius="md"
                >
                  <VStack align="stretch" spacing={4}>
                    <Text fontWeight="bold">{setting.modelType}</Text>
                    <FormControl display="flex" alignItems="center">
                      <FormLabel mb={0}>Enabled</FormLabel>
                      <Switch
                        isChecked={setting.enabled}
                        onChange={(e) =>
                          handleSettingChange(
                            setting.modelType,
                            "enabled",
                            e.target.checked
                          )
                        }
                      />
                    </FormControl>
                    <FormControl>
                      <FormLabel>Threshold</FormLabel>
                      <input
                        type="range"
                        min="0"
                        max="100"
                        value={setting.threshold}
                        onChange={(e) =>
                          handleSettingChange(
                            setting.modelType,
                            "threshold",
                            parseInt(e.target.value)
                          )
                        }
                      />
                    </FormControl>
                    <FormControl>
                      <FormLabel>Notifications</FormLabel>
                      <select
                        value={setting.notificationMethod}
                        onChange={(e) =>
                          handleSettingChange(
                            setting.modelType,
                            "notificationMethod",
                            e.target.value
                          )
                        }
                      >
                        <option value="all">All Alerts</option>
                        <option value="critical">Critical Only</option>
                        <option value="none">None</option>
                      </select>
                    </FormControl>
                  </VStack>
                </Box>
              ))}
            </VStack>
          </DrawerBody>
        </DrawerContent>
      </Drawer>
    </Box>
  );
};
