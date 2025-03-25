import { create } from "ipfs-http-client";
import { Buffer } from "buffer";

const projectId = process.env.NEXT_PUBLIC_INFURA_IPFS_PROJECT_ID;
const projectSecret = process.env.NEXT_PUBLIC_INFURA_IPFS_PROJECT_SECRET;
const auth =
  "Basic " + Buffer.from(projectId + ":" + projectSecret).toString("base64");

export const ipfsClient = create({
  host: "ipfs.infura.io",
  port: 5001,
  protocol: "https",
  headers: {
    authorization: auth,
  },
});

export const uploadToIPFS = async (file: File): Promise<string> => {
  try {
    const added = await ipfsClient.add(file);
    return added.path;
  } catch (error) {
    console.error("Error uploading to IPFS:", error);
    throw error;
  }
};
