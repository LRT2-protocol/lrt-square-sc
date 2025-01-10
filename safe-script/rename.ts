import { ethers } from "ethers";
import { propose } from "./propose";

async function rename() {
  const LRT_SQUARED_PROXY = "0x8F08B70456eb22f6109F57b8fafE862ED28E6040";

  const LRT_SQUARED_DUMMY_IMPL = "";
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
  await propose(LRT_SQUARED_PROXY, upgradeToDummyData, "0");

  const setInfoData = dummyIface.encodeFunctionData(
    "setInfo",
    ["KINGToken", "KING"]
  );

  await propose(LRT_SQUARED_PROXY, setInfoData, "0");

  const upgradeToCoreData = adminIface.encodeFunctionData(
    "upgradeToAndCall",
    [LRT_SQUARED_CORE_IMPL, "0x"]
  );
  await propose(LRT_SQUARED_PROXY, upgradeToCoreData, "0");
}

rename().catch((err) => {
  console.error(err);
  process.exitCode = 1;
});
