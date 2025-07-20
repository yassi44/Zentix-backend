import { HardhatUserConfig } from "hardhat/config";
import "@nomicfoundation/hardhat-toolbox";
import * as dotenv from "dotenv";
dotenv.config();

const PRIVATE_KEY = process.env.PRIVATE_KEY || "";
const SEPOLIA_RPC_URL = process.env.SEPOLIA_RPC_URL || "";
const ETHERSCAN_API_KEY = process.env.ETHERSCAN_API_KEY || "";
const HOLESKY_RPC_URL = process.env.HOLESKY_RPC_URL || "";

const config: HardhatUserConfig = {
  solidity: "0.8.28",
  networks: {
    localhost: {
      url: "http://127.0.0.1:8545",
      chainId: 31337
    },
    sepolia: {
      url: SEPOLIA_RPC_URL,
      accounts: [`0x${PRIVATE_KEY}`],
      chainId: 11155111
    },
    holesky: {
      url: HOLESKY_RPC_URL,
      accounts: [`0x${PRIVATE_KEY}`],
      chainId: 17000
    }
  },
  etherscan: {
    apiKey: {
      sepolia: ETHERSCAN_API_KEY,
      holesky: ETHERSCAN_API_KEY
    }
  },
  solcover: {
    skipFiles: [
      'contracts/mocks/',
    ]
  }
};

export default config;