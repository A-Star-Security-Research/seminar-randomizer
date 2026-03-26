import { defineConfig } from "hardhat/config";
import hardhatEthers from "@nomicfoundation/hardhat-ethers";
import hardhatVerify from "@nomicfoundation/hardhat-verify";
import hardhatIgnitionEthers from "@nomicfoundation/hardhat-ignition-ethers";
import hardhatUpgrades from "@openzeppelin/hardhat-upgrades";
import * as dotenv from "dotenv";
import { createRequire } from "node:module";
const require = createRequire(import.meta.url);
const solcPath = require.resolve("solc/soljson.js");

dotenv.config();

export default defineConfig({
  plugins: [hardhatEthers, hardhatVerify, hardhatIgnitionEthers, hardhatUpgrades],
  solidity: {
    version: "0.8.28",
    settings: {
      optimizer: {
        enabled: true,
        runs: 200
      },
      viaIR: true,
    }
  },
  networks: {
    sepolia: {
      url: process.env.SEPOLIA_RPC_URL || "",
      accounts: process.env.PRIVATE_KEY !== undefined ? [process.env.PRIVATE_KEY] : [],
      type: "http",
      chainType: "l1",
    },
  },
  verify: {
    etherscan: {
      apiKey: process.env.ETHERSCAN_API_KEY,
    },
  },

});
