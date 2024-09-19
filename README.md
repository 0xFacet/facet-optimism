# Welcome to `facet-optimism`!

Facet Optimism provides tools to run an optimistic bridge on Facet using Optimism's technology. It includes modified versions of:

1. Op L1 smart contracts
2. Op L2 smart contracts
3. `op-node`
4. `op-proposer`

Unused components like op-challenger and op-batcher remain unmodified.

## Getting started


Key points:
1. This code is separate from the Facet protocol. It's a set of third-party tools for working with Facet.
2. These tools are read-only for the Facet protocol. The `op-node` here only provides information about Facet and doesn't participate in L2 derivation.

## Installation Instructions

### Basic Setup

1. Use the `facetv1.9.1` branch.
2. Follow [Optimism's instructions](https://docs.optimism.io/builders/chain-operators/tutorials/create-l2-rollup) for setup.
3. Use the provided `rollup-config.json`.
4. Complete the `.envrc` file.
5. Use `http://34.85.131.39:8545` for `OP_NODE_L2_ENGINE_RPC`.

### Deploy the contracts

```bash
cd packages/contracts-bedrock
direnv allow
npx ts-node scripts/setUpFacetBridges.ts
```

This will deploy and verify all the L1 and L2 contracts you need to bridge.
It will also create an L2 token you can bridge into using a public L1 Test Token (`0x5589BB8228C07c4e15558875fAf2B859f678d129`).

### Start `op-node` and `op-proposer`

In one terminal: (Assuming you're still in `packages/contracts-bedrock`)

```
cd ../..
direnv allow
./init_node.sh
```

In another terminal:

```
./init_proposer.sh
```

Now you are posting L2 outputs to the L2 Output Oracle. Make sure your proposer address has enough testnet ether!

From here on out it's *exactly* the same as how you'd bridge with Optimism.

### Bridge a token into Facet

1. Find your `createOptimismMintableERC20` transaction on the [Facet testnet explorer](https://cardinal.explorer.facet.org/).
2. Edit `TestBridgeIn.s.sol` in `packages/contracts-bedrock/`.
3. Run:
   ```bash
   forge script -vvv './scripts/TestBridgeIn.s.sol' --private-key $DEPLOY_ETH_KEY --rpc-url "$DEPLOY_ETH_RPC_URL" --broadcast --tc TestBridgeIn
   ```
4. Verify the balance increase on the L2 explorer.

### Bridge a token out of Facet

1. Visit the `L2StandardBridge` page on the L2 explorer.
2. Use the `bridgeERC20To` function.
3. Submit the transaction.
4. Wait for the output to be posted to the L2 Output Oracle (every 30 blocks by default).

You can bridge out the same token you bridged in.

Now wait for the corresponding output to be posted to the L2 Output Oracle. The default configuration is for this to happen every 30 blocks.

### Prove and finalize the withdrawal

Use the provided example script, adapting it as needed for your specific withdrawal.

```typescript
async function main() {
  const receipt = await publicClientL2.getTransactionReceipt({
    hash: '0x3b1c2629aae57d61b326ea38d01d297a51600cca88bd3a8e5aaa8b9eedf753b0',
  })

  const [withdrawal] = getWithdrawals(receipt)


  const sourceId = 11155111

  const optimism2 = /*#__PURE__*/ defineChain({
    ...chainConfig,
    id: 10,
    name: 'OP Mainnet',
    nativeCurrency: { name: 'Ether', symbol: 'ETH', decimals: 18 },
    rpcUrls: {
      default: {
        http: ['https://mainnet.optimism.io'],
      },
    },
    blockExplorers: {
      default: {
        name: 'Optimism Explorer',
        url: 'https://optimistic.etherscan.io',
        apiUrl: 'https://api-optimistic.etherscan.io/api',
      },
    },
    contracts: {
      ...chainConfig.contracts,
      disputeGameFactory: {
        [sourceId]: {
          address: '0xe5965Ab5962eDc7477C8520243A95517CD252fA9',
        },
      },
      l2OutputOracle: {
        [sourceId]: {
          address: '0x60cecA8aaDe7fbc8221BcFd8202BDb4c7774Fda5',
        },
      },
      multicall3: {
        address: '0xca11bde05977b3631167028862be2a173976ca11',
        blockCreated: 4286263,
      },
      portal: {
        [sourceId]: {
          address: '0x95Af43232Bf5dBD3F3b844f446d5f874fd756B50',
        },
      },
      l1StandardBridge: {
        [sourceId]: {
          address: '0xda187cDdF7F405518b9DD3dCf33016ecb9bb3C93',
        },
      },
    },
    sourceId,
  })

  const output = await publicClientL1.getL2Output({
    l2BlockNumber: receipt.blockNumber,
    targetChain: optimism2 as any,
  })

  console.log({output})

  const args1 = await publicClientL2.buildProveWithdrawal({
    output,
    withdrawal
  })

  const args = {
    ...args1,
    authorizationList: [],
    targetChain: optimism2
  }

  console.log({args})

  const proveHash = await walletClientL1.proveWithdrawal(args as any)

  const proveReceipt = await publicClientL1.waitForTransactionReceipt({
    hash: proveHash
  })

  console.log({proveReceipt})

  // Wait for the challenge period to end
  await new Promise(resolve => setTimeout(resolve, 60000));

  const finalizeHash = await walletClientL1.finalizeWithdrawal({
    targetChain: optimism2,
    withdrawal,
  })

  // Wait until the withdrawal is finalized.
  const finalizeReceipt = await publicClientL1.waitForTransactionReceipt({
    hash: finalizeHash
  })

  console.log(finalizeReceipt)
}
```
