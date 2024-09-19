#!/bin/bash

# Read the L2OutputOracleProxy address from the JSON file
L2OO_ADDRESS=$(jq -r '.L2OutputOracleProxy' './packages/contracts-bedrock/deployments/artifact.json')

direnv allow

make -C op-proposer op-proposer

./op-proposer/bin/op-proposer --l2oo-address "$L2OO_ADDRESS" --poll-interval 12s --active-sequencer-check-duration 12s --num-confirmations 1 --allow-non-finalized=true --log.level=debug
