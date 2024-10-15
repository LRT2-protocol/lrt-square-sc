import dotenv from "dotenv";
import { ethers } from "ethers";
import SafeApiKit from "@safe-global/api-kit";
import { MetaTransactionData } from "@safe-global/safe-core-sdk-types";
import Safe from "@safe-global/protocol-kit";

dotenv.config();

const privateKey: string = process.env.PRIVATE_KEY || "";
if (!privateKey) throw new Error("PRIVATE_KEY not found in .env");

const MAINNET_RPC: string = process.env.MAINNET_RPC || "";
if (!MAINNET_RPC) throw new Error("MAINNET_RPC not found in .env");

const provider = new ethers.providers.JsonRpcProvider(MAINNET_RPC)
const owner = new ethers.Wallet(privateKey, provider);

const apiKit = new SafeApiKit({chainId: 1n});
const safeAddress = "0xF46D3734564ef9a5a16fC3B1216831a28f78e2B5";

export async function propose(
    destination: string,
    data: string, 
    value: string
) {
    const safeTransactionData: MetaTransactionData = {
        to: destination,
        data: data,
        value: value
    };
    
    const protocolKitOwner1 = await Safe.init({
        provider: MAINNET_RPC,
        signer: privateKey,
        safeAddress
    });
      
    // Create a Safe transaction with the provided parameters
    const safeTransaction = await protocolKitOwner1.createTransaction({ transactions: [safeTransactionData] });
      
    // Deterministic hash based on transaction parameters
    const safeTxHash = await protocolKitOwner1.getTransactionHash(safeTransaction);
    // Sign transaction to verify that the transaction is coming from owner 1
    const senderSignature = await protocolKitOwner1.signHash(safeTxHash);
    
    await apiKit.proposeTransaction({
        safeAddress,
        safeTransactionData: safeTransaction.data,
        safeTxHash,
        senderAddress: owner.address,
        senderSignature: senderSignature.data
    });  
    
    const pendingTransactions = (await apiKit.getPendingTransactions(safeAddress)).results;  
    console.log(pendingTransactions);
}
