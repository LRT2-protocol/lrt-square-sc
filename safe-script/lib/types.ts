export enum ReturnType {
  Int256 = 0,
  Uint256 = 1,
}

export enum Network {
  Ethereum = 0x1,
  Swell = 0x783,
}

export type TokenConfig = {
  oracle: string;
  priceFunctionCalldata: string;
  isChainlinkType: boolean;
  oraclePriceDecimals: number;
  maxStaleness: number;
  dataType: ReturnType;
  isBaseTokenEth: boolean;
};
