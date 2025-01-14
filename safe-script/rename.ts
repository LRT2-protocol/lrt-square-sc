import { ethers } from "ethers";
import { proposeBatch } from "./proposeBatch";

export async function rename() {
  const LRT_SQUARED_PROXY = "0x8F08B70456eb22f6109F57b8fafE862ED28E6040";

  const LRT_SQUARED_DUMMY_IMPL = "0x8E029cEDC7Daf4d9cFFe56AC6771dE266F3CCAdc";
  const LRT_SQUARED_CORE_IMPL  = "0x3D987E04fC47ac625F720f169C658307fd9A16A2";

  const adminAbi = [
    "function upgradeToAndCall(address newImplementation, bytes memory data) external"
  ];
  const adminIface = new ethers.utils.Interface(adminAbi);

  const dummyAbi = [
    "function setInfo(string memory _name, string memory _symbol) external"
  ];
  const dummyIface = new ethers.utils.Interface(dummyAbi);

  const upgradeToDummyData = adminIface.encodeFunctionData(
    "upgradeToAndCall",
    [LRT_SQUARED_DUMMY_IMPL, "0x"]
  );

  const setInfoData = dummyIface.encodeFunctionData(
    "setInfo",
    ["King Protocol", "KING"]
  );

  const upgradeToCoreData = adminIface.encodeFunctionData(
    "upgradeToAndCall",
    [LRT_SQUARED_CORE_IMPL, "0x"]
  );

  const transactions = [
    {
      to: LRT_SQUARED_PROXY,
      data: upgradeToDummyData,
      value: "0"
    },
    {
      to: LRT_SQUARED_PROXY,
      data: setInfoData,
      value: "0"
    },
    {
      to: LRT_SQUARED_PROXY,
      data: upgradeToCoreData,
      value: "0"
    }
  ];

  await proposeBatch(transactions);
}

rename().catch((err) => {
  console.error(err);
  process.exitCode = 1;
});
