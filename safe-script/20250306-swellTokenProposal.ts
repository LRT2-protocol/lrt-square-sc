import { ethers } from "ethers";
import fs from "fs";

import { MetaTransactionData } from "@safe-global/safe-core-sdk-types";

import {
  KING_PRICE_PROVIDER,
  KING_PROTOCOL_PROXY,
  KING_SAFE_WALLET,
} from "./lib/const";
import { proposeBatch } from "./lib/proposeBatch";
import { ReturnType, TokenConfig } from "./lib/types";

const priceProviderJson = JSON.parse(
  fs.readFileSync("out/PriceProvider.sol/PriceProvider.json", "utf-8"),
);
const priceProviderAbi = priceProviderJson.abi;
const priceProviderInterface = new ethers.utils.Interface(priceProviderAbi);

const swellToken = "0x0a6e7ba5042b38349e437ec6db6214aec7b35676";
const swellTokenConfig: TokenConfig = {
  oracle: "0x2a638b1203a3B62FF003598B7165Fc5cd5b13B00",
  priceFunctionCalldata: "0x",
  isChainlinkType: true,
  oraclePriceDecimals: 18,
  maxStaleness: 2 * 24 * 60 * 60,
  dataType: ReturnType.Uint256,
  isBaseTokenEth: true,
};

const value = "0";

/* Set swell token config */
const setTokenConfigData = priceProviderInterface.encodeFunctionData(
  "setTokenConfig",
  [[swellToken], [swellTokenConfig]],
);

/* Whitelist swell token */
const registerTokenAbi = [
  "function registerToken(address _token, uint64 _positionWeightLimit) external",
];
const registerTokenIface = new ethers.utils.Interface(registerTokenAbi);
const registerTokenData = registerTokenIface.encodeFunctionData(
  "registerToken",
  [swellToken, 150_000_000],
);

/* Whitelist King Protocol wallet */
const setDepositorsAbi = [
  "function setDepositors(address[] memory depositors, bool[] memory isDepositor) external onlyGovernor",
];
const setDepositorsIface = new ethers.utils.Interface(setDepositorsAbi);
const setDepositorsData = setDepositorsIface.encodeFunctionData(
  "setDepositors",
  [[KING_SAFE_WALLET], [true]],
);

const transactions: MetaTransactionData[] = [
  {
    to: KING_PRICE_PROVIDER,
    data: setTokenConfigData,
    value,
  },
  {
    to: KING_PROTOCOL_PROXY,
    data: registerTokenData,
    value,
  },
  {
    to: KING_PROTOCOL_PROXY,
    data: setDepositorsData,
    value,
  },
];

console.log(transactions);

(async () => await proposeBatch(transactions))();
