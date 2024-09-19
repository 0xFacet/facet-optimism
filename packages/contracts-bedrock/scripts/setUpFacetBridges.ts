import { concatHex, createPublicClient, hexToBigInt, hexToBytes, http, isHex, numberToBytes, toBytes, toHex, toRlp, TransactionReceipt } from 'viem';
import { bytesToBigInt, bytesToHex } from 'viem';
import { readFileSync, writeFileSync } from 'fs-extra';
import { resolve } from 'path';
import { publicActionsL1, publicActionsL2, walletActionsL1 } from 'viem/op-stack'
import { sepolia, optimism } from 'viem/chains'
import { keccak256 } from 'viem'
import { fromRlp } from 'viem'
const { execSync } = require('child_process');

import dotenv from 'dotenv';

dotenv.config(); // Load environment variables from .env file

const l2RPC = process.env.L2_RPC
const l1RPC = process.env.L1_RPC

const publicClientL1 = createPublicClient({
  chain: sepolia,
  transport: http(l1RPC)
}).extend(publicActionsL1())

const publicClientL2 = createPublicClient({
  transport: http(l2RPC)
}).extend(publicActionsL2())

function writeContractAddressesToJson(addresses: { [key: string]: string }) {
  const jsonContent = JSON.stringify(addresses, null, 2);
  const filePath = resolve(__dirname, '../deployments/l2_contract_addresses.json');

  writeFileSync(filePath, jsonContent);
  console.log(`Contract addresses written to ${filePath}`);
}

async function processAndVerifyContracts(data: any) {
  const filePaths = {
    L2CrossDomainMessenger: resolve(__dirname, '../src/L2/L2CrossDomainMessenger.sol'),
    L2StandardBridge: resolve(__dirname, '../src/L2/L2StandardBridge.sol'),
    OptimismMintableERC20Factory: resolve(__dirname, '../src/universal/OptimismMintableERC20Factory.sol')
  };

  const envVarNames = [
    'L2_CROSS_DOMAIN_MESSENGER',
    'L2_STANDARD_BRIDGE',
    'OPTIMISM_MINTABLE_ERC20_FACTORY'
  ];

  const contractAddresses: { [key: string]: string } = {};

  const facetContracts = await Promise.all(data.transactions.map(async (tx: any, index: number) => {
    const ethTx = await getEthTransaction(tx);
    const facetTx = await FacetTransaction.fromEthTransaction(ethTx);
    const contractAddress = await facetTx.getCreatedContractAddress();

    // Determine the contract name based on the index or other logic
    let contractName: keyof typeof filePaths;
    switch (index) {
      case 0:
        contractName = 'L2CrossDomainMessenger';
        break;
      case 1:
        contractName = 'L2StandardBridge';
        break;
      case 2:
        contractName = 'OptimismMintableERC20Factory';
        break;
      default:
        throw new Error('Unexpected contract index');
    }

    // Verify the contract
    verifyContract(`forge verify-contract --rpc-url https://cardinal.facet.org/ --verifier blockscout --verifier-url 'https://cardinal.explorer.facet.org/api/' ${contractAddress} ${filePaths[contractName]}:${contractName}`);

    // Set the environment variable
    process.env[envVarNames[index]] = contractAddress;

    // Store the contract address
    contractAddresses[envVarNames[index]] = contractAddress;

    return contractAddress;
  }));

  // Write contract addresses to JSON file
  writeContractAddressesToJson(contractAddresses);

  return facetContracts;
}

async function main() {
  execSync('direnv allow', { stdio: 'inherit' });

  const facetScriptPath = resolve(__dirname, 'CreateFacetContracts.s.sol');
  execSync(`forge script -vvv ${facetScriptPath} --private-key ${process.env.PK} --rpc-url "$DEPLOY_ETH_RPC_URL" --broadcast`, { stdio: 'inherit' });

  await new Promise(resolve => setTimeout(resolve, 30000));

  const data = getLatestFoundryOutput('CreateFacetContracts');
  await processAndVerifyContracts(data);

  const deployScriptPath = resolve(__dirname, 'deploy/Deploy.s.sol');

  execSync(`forge script -vvv ${deployScriptPath} --private-key ${process.env.PK} --rpc-url "$DEPLOY_ETH_RPC_URL" --broadcast --slow`, { stdio: 'inherit' });

  await new Promise(resolve => setTimeout(resolve, 30000));

  const artifacts = getLatestArtifacts()

  const toVerify = [
    'L1CrossDomainMessenger',
    'L1StandardBridge',
    'L2OutputOracle',
    'OptimismPortal',
  ]

  toVerify.forEach((contractName) => {
    const contractAddress = artifacts[contractName]
    const filePath = resolve(__dirname, `../src/L1/${contractName}.sol`);

    verifyContract(`forge verify-contract --chain 11155111 --compiler-version 0.8.15 ${contractAddress} ${filePath}:${contractName}`)
  })

  process.env.L1_CROSS_DOMAIN_MESSENGER = artifacts.L1CrossDomainMessengerProxy;
  process.env.L1_STANDARD_BRIDGE = artifacts.L1StandardBridgeProxy;

  const initScriptPath = resolve(__dirname, 'InitFacetContracts.s.sol');

  execSync(`forge script -vvv ${initScriptPath} --private-key ${process.env.PK} --rpc-url "$DEPLOY_ETH_RPC_URL" --broadcast --slow`, { stdio: 'inherit' });
}

function getLatestArtifacts() {
  const filePath = resolve(__dirname, `../deployments/artifact.json`);
  const jsonData = readFileSync(filePath, 'utf-8');
  return JSON.parse(jsonData);
}

function getLatestFoundryOutput(scriptName: string) {
  const filePath = resolve(__dirname, `../broadcast/${scriptName}.s.sol/11155111/run-latest.json`);
  const jsonData = readFileSync(filePath, 'utf-8');
  return JSON.parse(jsonData);
}

async function getEthTransaction(ethTxRaw: any): Promise<EthTransaction> {
  const ethReceiptRaw = await publicClientL1.getTransactionReceipt({ hash: ethTxRaw.hash });
  const blockDetails = await publicClientL1.getBlock({ blockHash: ethReceiptRaw.blockHash });

  return {
      from: ethTxRaw.transaction.from,
      to: ethTxRaw.transaction.to,
      input: ethTxRaw.transaction.input,
      hash: ethTxRaw.hash,
      blockHash: ethReceiptRaw.blockHash,
      gasUsed: ethReceiptRaw.gasUsed,
      baseFee: blockDetails.baseFeePerGas!,
      blockNumber: blockDetails.number,
      blockTimestamp: blockDetails.timestamp
  };
}

async function getFacetBlockNumberForTimestamp(ethBlockTimestamp: bigint): Promise<bigint> {
  const firstAttributesTx = await publicClientL2.getTransaction({ blockNumber: 1n, index: 0 });
  const firstAttributes = decodeAttributesCalldata(firstAttributesTx.input);
  const facetBlock1EthTimestamp = firstAttributes.timestamp;

  const timeDifference = ethBlockTimestamp - facetBlock1EthTimestamp;

  const facetBlockNumber = timeDifference / 12n + 1n;

  return facetBlockNumber;
}

function calculateCalldataCost(hexString: `0x${string}`): bigint {
  const bytes = hexToBytes(hexString);
  let zeroCount = 0n;
  let nonZeroCount = 0n;

  for (const byte of bytes) {
    if (byte === 0) {
      zeroCount++;
    } else {
      nonZeroCount++;
    }
  }

  return zeroCount * 4n + nonZeroCount * 16n;
}

function verifyContract(command: string) {
  try {
    execSync(command, { stdio: 'inherit' });
  } catch (error) {
    console.error('Error during verification:', error);
  }
}

function decodeAttributesCalldata(calldata: `0x${string}`) {
  const data = hexToBytes(calldata);

  // Remove the function selector
  const dataWithoutSelector = data.slice(4);

  // Extract slices
  const base_fee_scalar_bytes = dataWithoutSelector.slice(0, 4);
  const blob_base_fee_scalar_bytes = dataWithoutSelector.slice(4, 8);
  const sequence_number_bytes = dataWithoutSelector.slice(8, 16);
  const timestamp_bytes = dataWithoutSelector.slice(16, 24);
  const number_bytes = dataWithoutSelector.slice(24, 32);
  const base_fee_bytes = dataWithoutSelector.slice(32, 64);
  const blob_base_fee_bytes = dataWithoutSelector.slice(64, 96);
  const hash_bytes = dataWithoutSelector.slice(96, 128);
  const batcher_hash_bytes = dataWithoutSelector.slice(128, 160);
  const fct_minted_per_gas_bytes = dataWithoutSelector.slice(160, 192);
  const total_fct_minted_bytes = dataWithoutSelector.slice(192, 224);

  // Convert bytes to values
  const base_fee_scalar = Number(bytesToBigInt(base_fee_scalar_bytes));
  const blob_base_fee_scalar = Number(bytesToBigInt(blob_base_fee_scalar_bytes));
  const sequence_number = bytesToBigInt(sequence_number_bytes);
  const timestamp = bytesToBigInt(timestamp_bytes);
  const number = bytesToBigInt(number_bytes);
  const base_fee = bytesToBigInt(base_fee_bytes);
  const blob_base_fee = bytesToBigInt(blob_base_fee_bytes);
  const hash = bytesToHex(hash_bytes);
  const batcher_hash = bytesToHex(batcher_hash_bytes);
  const fct_minted_per_gas = bytesToBigInt(fct_minted_per_gas_bytes);
  const total_fct_minted = bytesToBigInt(total_fct_minted_bytes);

  return {
    timestamp,
    number,
    base_fee,
    blob_base_fee,
    hash,
    batcher_hash,
    sequence_number,
    blob_base_fee_scalar,
    base_fee_scalar,
    fct_minted_per_gas,
    total_fct_minted,
  };
}

interface EthTransaction {
  from: `0x${string}`;
  to: `0x${string}`;
  input: `0x${string}`;
  hash: `0x${string}`;
  blockHash: `0x${string}`;
  baseFee: bigint;
  gasUsed: bigint;
  blockNumber: bigint;
  blockTimestamp: bigint;
  // Add other necessary fields if needed
}

class FacetTransaction {
  toAddress: `0x${string}` | null;
  value: bigint;
  maxFeePerGas!: bigint | null;
  gasLimit: bigint;
  input: `0x${string}`;
  ethCallIndex: number;
  fromAddress: `0x${string}`;
  l1TxOrigin: `0x${string}`;
  sourceHash!: `0x${string}`;
  blockHash: `0x${string}`;
  ethTransactionHash: `0x${string}`;
  baseFee: bigint;
  l1gasUsed: bigint;
  facetBlockNumber!: bigint;
  mintAmount!: bigint;

  constructor(
    to: `0x${string}` | null,
    value: bigint,
    maxFeePerGas: bigint | null,
    gasLimit: bigint,
    input: `0x${string}`,
    ethTx: EthTransaction
  ) {
    this.toAddress = to;
    this.value = value;
    this.maxFeePerGas = maxFeePerGas;
    this.gasLimit = gasLimit;
    this.input = input;
    this.ethCallIndex = 0;
    this.fromAddress = ethTx.from;
    this.l1TxOrigin = ethTx.from;
    this.blockHash = ethTx.blockHash;
    this.ethTransactionHash = ethTx.hash;
    this.baseFee = ethTx.baseFee;
    this.l1gasUsed = ethTx.gasUsed;
  }

  static async fromEthTransaction(ethTx: EthTransaction): Promise<FacetTransaction> {
    const ethCalldata = ethTx.input;
    const calldataBytes = toBytes(ethCalldata);

    const type = calldataBytes[0];

    if (type !== 0x46) {
      throw new Error(`Invalid transaction type ${type}!`);
    }

    const withoutFirstByte = calldataBytes.slice(1);

    const tx = fromRlp(withoutFirstByte, "hex")

    if (tx.length > 7) {
      throw new Error('Transaction missing fields!');
    }

    const to = isHex(tx[1]) && tx[1] !== '0x' ? tx[1] : null;
    const value = isHex(tx[2]) && tx[2] !== '0x' ? hexToBigInt(tx[2]) : 0n;
    const maxGasFee = isHex(tx[3]) && tx[3] !== '0x' ? hexToBigInt(tx[3]) : null;
    const gasLimit = isHex(tx[4]) && tx[4] !== '0x' ? hexToBigInt(tx[4]) : 0n;
    const data = isHex(tx[5]) && tx[5] !== '0x' ? tx[5] : '0x';

    const facetTx = new FacetTransaction(
      to,
      value,
      maxGasFee,
      gasLimit,
      data,
      ethTx
    );

    facetTx.facetBlockNumber = await getFacetBlockNumberForTimestamp(ethTx.blockTimestamp)

    const currentFacetBlock = await publicClientL2.getBlock({ blockNumber: facetTx.facetBlockNumber })
    const currentAttributesTx = await publicClientL2.getTransaction({ blockNumber: facetTx.facetBlockNumber, index: 0 })
    const currentAttributes = decodeAttributesCalldata(currentAttributesTx.input)

    facetTx.mintAmount = calculateCalldataCost(ethTx.input) * currentAttributes.fct_minted_per_gas

    let calculatedMaxFeePerGas = facetTx.maxFeePerGas ?? 0n

    if (calculatedMaxFeePerGas == 0n || calculatedMaxFeePerGas > currentFacetBlock.baseFeePerGas!) {
      calculatedMaxFeePerGas = currentFacetBlock.baseFeePerGas!
    }

    facetTx.maxFeePerGas = calculatedMaxFeePerGas

    const payload = Uint8Array.from([
      ...toBytes(ethTx.blockHash),
      ...toBytes(ethTx.hash),
      ...numberToBytes(facetTx.ethCallIndex, { size: 32 })
    ]);

    const USER_DEPOSIT_SOURCE_DOMAIN = 0

    facetTx.sourceHash = FacetTransaction.computeSourceHash(payload, USER_DEPOSIT_SOURCE_DOMAIN);

    return facetTx;
  }

  toDepositTx(): DepositTx {
    return {
      SourceHash: this.sourceHash,
      L1TxOrigin: this.l1TxOrigin,
      From: this.fromAddress,
      To: this.toAddress,
      Mint: this.mintAmount,
      Value: this.value,
      GasFeeCap: this.maxFeePerGas!,
      Gas: this.gasLimit,
      IsSystemTransaction: false,
      Data: this.input
    };
  }

  facetTransactionHash(): `0x${string}` {
    return calculateL2TransactionHash(this.toDepositTx())
  }

  getFacetTransactionReceipt(): Promise<TransactionReceipt> {
    return publicClientL2.getTransactionReceipt({ hash: this.facetTransactionHash() })
  }

  async getCreatedContractAddress(): Promise<`0x${string}`> {
    const receipt = await this.getFacetTransactionReceipt()
    return receipt.contractAddress!
  }

  static computeSourceHash(payload: Uint8Array, sourceDomain: number): `0x${string}` {
    const final = Uint8Array.from([
      ...new Uint8Array(32),
      ...keccak256(payload, "bytes")
    ])

    return keccak256(final);
  }
}

interface DepositTx {
  SourceHash: `0x${string}`; // Hex string
  L1TxOrigin: `0x${string}`; // Ethereum address
  From: `0x${string}`; // Ethereum address
  To: `0x${string}` | null; // Ethereum address or null
  Mint: bigint;
  Value: bigint; // BigInt as a hex string
  GasFeeCap: bigint; // BigInt as a hex string
  Gas: bigint; // Gas limit
  IsSystemTransaction: boolean;
  Data: `0x${string}`; // Hex string
}

function calculateL2TransactionHash(tx: DepositTx): `0x${string}` {
  const encodedTx = encodeDepositTx(tx);
  return keccak256(encodedTx);
}

function encodeDepositTx(tx: DepositTx): `0x${string}` {
  const serializedTransaction = [
    tx.SourceHash,
    tx.L1TxOrigin,
    tx.From,
    tx.To ?? '0x',
    tx.Mint ? toHex(tx.Mint) : '0x',
    tx.Value ? toHex(tx.Value) : '0x',
    tx.GasFeeCap ? toHex(tx.GasFeeCap) : '0x',
    tx.Gas ? toHex(tx.Gas) : '0x',
    "0x" as `0x${string}`,
    tx.Data ?? '0x'
  ]

  return concatHex([
    '0x7e',
    toRlp(serializedTransaction),
  ])
}

main().catch((error) => {
    console.error('Error:', error);
    process.exit(1);
});
