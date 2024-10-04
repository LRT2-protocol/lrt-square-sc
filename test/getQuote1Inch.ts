import axios from "axios";
import dotenv from "dotenv";
dotenv.config();

const ONEINCH_API_ENDPOINT = "https://api.1inch.dev/swap/v6.0";
const ONEINCH_API_KEY = process.env.ONEINCH_API_KEY;

export const getData = async () => {
  const args = process.argv;
  const chainId = args[2];
  const fromAddress = args[3];
  const toAddress = args[4];
  const fromAsset = args[5];
  const toAsset = args[6];
  const fromAmount = args[7];

  if (!ONEINCH_API_KEY) throw new Error("Please set ONEINCH_API_KEY in the .env file");

  const data = await getIInchSwapData({
    chainId,
    fromAddress,
    toAddress,
    fromAsset,
    toAsset,
    fromAmount,
  });

  console.log(data);
};

/**
 * Gets the tx.data in the response of 1inch's V5 swap API
 * @param vault The Origin vault contract address. eg OUSD or OETH Vaults
 * @param fromAsset The address of the asset to swap from.
 * @param toAsset The address of the asset to swap to.
 * @param fromAmount The unit amount of fromAsset to swap. eg 1.1 WETH = 1.1e18
 * @param slippage as a percentage. eg 0.5 is 0.5%
 * @param protocols The 1Inch liquidity sources as a comma separated list. eg UNISWAP_V1,UNISWAP_V2,SUSHI,CURVE,ONE_INCH_LIMIT_ORDER
 * See https://api.1inch.io/v5.0/1/liquidity-sources
 */
const getIInchSwapData = async({
  chainId,
  fromAddress,
  toAddress,
  fromAsset,
  toAsset,
  fromAmount,
}: {
  chainId: string;
  fromAddress: string;
  toAddress: string;
  fromAsset: string;
  toAsset: string;
  fromAmount: string;
}) => {
  const params = {
    src: fromAsset,
    dst: toAsset,
    amount: fromAmount.toString(),
    fromAddress: fromAddress,
    receiver: toAddress,
    slippage: 1,
    disableEstimate: true,
    allowPartialFill: false,
  };

  let retries = 5;

  const API_ENDPOINT = `${ONEINCH_API_ENDPOINT}/${chainId}/swap`;

  while (retries > 0) {
    try {
      const response = await axios.get(API_ENDPOINT, {
        params,
        headers: {
          Authorization: `Bearer ${ONEINCH_API_KEY}`,
        },
      });

      if (!response.data.tx || !response.data.tx.data) {
        console.error(response.data);
        throw Error("response is missing tx.data");
      }

      return response.data.tx.data;
    } catch (err: any) {
      if (err.response) {
        console.error("Response data  : ", err.response.data);
        console.error("Response status: ", err.response.status);
      }
      if (err.response?.status == 429) {
        retries = retries - 1;
        // Wait for 2s before next try
        await new Promise((r) => setTimeout(r, 2000));
        continue;
      }
      throw Error(`Call to 1Inch swap API failed: ${err.message}`);
    }
  }

  throw Error(`Call to 1Inch swap API failed: Rate-limited`);
};

getData();
