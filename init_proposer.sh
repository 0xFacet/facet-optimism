#!/bin/bash

# Source the .envrc file to get the DEPLOYMENT_OUTFILE variable
source .envrc

# Check if DEPLOYMENT_OUTFILE is set
if [ -z "$DEPLOYMENT_OUTFILE" ]; then
    echo "Error: DEPLOYMENT_OUTFILE is not set in .envrc"
    exit 1
fi

# Read the L2OutputOracleProxy address from the JSON file specified in DEPLOYMENT_OUTFILE
L2OO_ADDRESS=$(jq -r '.L2OutputOracleProxy' "$DEPLOYMENT_OUTFILE")

# Check if jq command was successful and L2OO_ADDRESS is not empty
if [ $? -ne 0 ] || [ -z "$L2OO_ADDRESS" ]; then
    echo "Error: Failed to read L2OutputOracleProxy address from $DEPLOYMENT_OUTFILE"
    exit 1
fi

make -C op-proposer op-proposer

./op-proposer/bin/op-proposer --l2oo-address "$L2OO_ADDRESS" --poll-interval 12s --active-sequencer-check-duration 12s --num-confirmations 1 --allow-non-finalized=true --log.level=debug
