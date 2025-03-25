import React, { createContext, useContext, useEffect, useState } from "react";
import { ethers } from "ethers";
import AITrainingNetwork from "../artifacts/contracts/AITrainingNetwork.sol/AITrainingNetwork.json";

interface Web3ContextType {
  account: string | null;
  contract: ethers.Contract | null;
  provider: ethers.providers.Web3Provider | null;
  connectWallet: () => Promise<void>;
  loading: boolean;
}

const Web3Context = createContext<Web3ContextType>({} as Web3ContextType);

export function Web3Provider({ children }: { children: React.ReactNode }) {
  const [account, setAccount] = useState<string | null>(null);
  const [contract, setContract] = useState<ethers.Contract | null>(null);
  const [provider, setProvider] =
    useState<ethers.providers.Web3Provider | null>(null);
  const [loading, setLoading] = useState(true);

  const connectWallet = async () => {
    try {
      if (typeof window.ethereum === "undefined") {
        alert("Please install MetaMask!");
        return;
      }

      const provider = new ethers.providers.Web3Provider(window.ethereum);
      const accounts = await provider.send("eth_requestAccounts", []);

      setAccount(accounts[0]);
      setProvider(provider);

      const signer = provider.getSigner();
      const contract = new ethers.Contract(
        process.env.NEXT_PUBLIC_CONTRACT_ADDRESS!,
        AITrainingNetwork.abi,
        signer
      );

      setContract(contract);
    } catch (error) {
      console.error("Error connecting wallet:", error);
    } finally {
      setLoading(false);
    }
  };

  useEffect(() => {
    connectWallet();
  }, []);

  return (
    <Web3Context.Provider
      value={{
        account,
        contract,
        provider,
        connectWallet,
        loading,
      }}
    >
      {children}
    </Web3Context.Provider>
  );
}

export const useWeb3 = () => useContext(Web3Context);
