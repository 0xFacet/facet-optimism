#!/bin/bash

# Function to check if we're running in a container
is_container() {
    [ -f /.dockerenv ] || grep -q docker /proc/1/cgroup || [ -f "/usr/local/bin/op-proposer" ]
}

if is_container; then
    echo "Running in a containerized environment, using environment variables"
    L2OO_ADDRESS="$OP_PROPOSER_L2OO_ADDRESS"
    OP_PROPOSER_BIN="/usr/local/bin/op-proposer"
else
    echo "Running in development environment"
    # Check if .envrc exists before sourcing it
    if [ -f .envrc ]; then
        source .envrc
    else
        echo "Warning: .envrc file not found. This might be an issue in a dev environment."
    fi

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

    echo "Building op-proposer..."
    make -C op-proposer op-proposer
    OP_PROPOSER_BIN="./op-proposer/bin/op-proposer"
fi

# Check if L2OO_ADDRESS is set
if [ -z "$L2OO_ADDRESS" ]; then
    echo "Error: L2OutputOracleProxy address is not set"
    exit 1
fi

# Check if the binary exists
if [ ! -f "$OP_PROPOSER_BIN" ]; then
    echo "Error: op-proposer binary not found at $OP_PROPOSER_BIN"
    exit 1
fi

echo "Starting op-proposer..."

# Use the determined binary path
$OP_PROPOSER_BIN \
  --l2oo-address "$L2OO_ADDRESS" \
  --poll-interval 12s \
  --active-sequencer-check-duration 12s \
  --num-confirmations 1 \
  --allow-non-finalized=true \
  --l1-eth-rpc="$OP_PROPOSER_L1_ETH_RPC" \
  --rollup-rpc="$OP_PROPOSER_ROLLUP_RPC" \
  --private-key="$OP_PROPOSER_PRIVATE_KEY" \
  --rpc.port 7545 \
  --log.level=debug
