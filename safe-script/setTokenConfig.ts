import { ethers } from "ethers";
import fs from "fs";
import { propose } from "./propose";

const priceProviderJson = JSON.parse(fs.readFileSync("out/PriceProvider.sol/PriceProvider.json", "utf-8"));
const priceProviderAbi = priceProviderJson.abi;

const priceProviderInterface = new ethers.utils.Interface(priceProviderAbi);

const newToken = "0xfe0c30065b384f05761f15d0cc899d4f9f9cc0eb";
const tokenConfig = {
    oracle: "0x19678515847d8DE85034dAD0390e09c3048d31cd",
    priceFunctionCalldata: "0x",
    isChainlinkType: true,
    oraclePriceDecimals: 8,
    maxStaleness: 2 * 24 * 60 * 60,
    dataType: 0,
    isBaseTokenEth: false
}

const priceProvider = "0x2B90103cdc9Bba6c0dBCAaF961F0B5b1920F19E3";
const value = "0";
const data = priceProviderInterface.encodeFunctionData(
    "setTokenConfig",
    [[newToken], [tokenConfig]]
);

async function proposeSetTokenConfig() {
    await propose(priceProvider, data, value);
}

proposeSetTokenConfig();