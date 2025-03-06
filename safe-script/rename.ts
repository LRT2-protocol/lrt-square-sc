import { ethers } from "ethers";

import { MetaTransactionData } from "@safe-global/safe-core-sdk-types";

import {
  KING_PROTOCOL_PROXY,
  KING_PROTOCOL_CORE_IMPL,
  KING_PROTOCOL_DUMMY_IMPL,
} from "./lib/const";
import { proposeBatch } from "./lib/proposeBatch";

export async function rename() {
  const adminAbi = [
    "function upgradeToAndCall(address newImplementation, bytes memory data) external",
  ];
  const adminIface = new ethers.utils.Interface(adminAbi);

  const dummyAbi = [
    "function setInfo(string memory _name, string memory _symbol) external",
  ];
  const dummyIface = new ethers.utils.Interface(dummyAbi);

  const upgradeToDummyData = adminIface.encodeFunctionData("upgradeToAndCall", [
    KING_PROTOCOL_DUMMY_IMPL,
    "0x",
  ]);

  const setInfoData = dummyIface.encodeFunctionData("setInfo", [
    "King Protocol",
    "KING",
  ]);

  const upgradeToCoreData = adminIface.encodeFunctionData("upgradeToAndCall", [
    KING_PROTOCOL_CORE_IMPL,
    "0x",
  ]);

  const transactions: MetaTransactionData[] = [
    {
      to: KING_PROTOCOL_PROXY,
      data: upgradeToDummyData,
      value: "0",
    },
    {
      to: KING_PROTOCOL_PROXY,
      data: setInfoData,
      value: "0",
    },
    {
      to: KING_PROTOCOL_PROXY,
      data: upgradeToCoreData,
      value: "0",
    },
  ];

  await proposeBatch(transactions);
}

rename().catch((err) => {
  console.error(err);
  process.exitCode = 1;
});
