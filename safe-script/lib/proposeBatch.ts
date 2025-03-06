import dotenv from "dotenv";
import { ethers } from "ethers";

import SafeApiKit from "@safe-global/api-kit";
import Safe from "@safe-global/protocol-kit";
import { MetaTransactionData } from "@safe-global/safe-core-sdk-types";

import { PRIVATE_KEY, MAINNET_RPC } from "./const";

dotenv.config();

const provider = new ethers.providers.JsonRpcProvider(MAINNET_RPC);
const owner = new ethers.Wallet(PRIVATE_KEY, provider);

const apiKit = new SafeApiKit({ chainId: 1n });
const safeAddress = "0xF46D3734564ef9a5a16fC3B1216831a28f78e2B5";

export async function proposeBatch(transactions: MetaTransactionData[]) {
  const protocolKitOwner1 = await Safe.init({
    provider: MAINNET_RPC,
    signer: PRIVATE_KEY,
    safeAddress,
  });

  const safeTransaction = await protocolKitOwner1.createTransaction({
    transactions,
  });
  const safeTxHash =
    await protocolKitOwner1.getTransactionHash(safeTransaction);

  const senderSignature = await protocolKitOwner1.signHash(safeTxHash);

  await apiKit.proposeTransaction({
    safeAddress,
    safeTransactionData: safeTransaction.data,
    safeTxHash,
    senderAddress: owner.address,
    senderSignature: senderSignature.data,
  });

  const pendingTransactions = (await apiKit.getPendingTransactions(safeAddress))
    .results;
  console.log("Pending transactions:", pendingTransactions);
}
