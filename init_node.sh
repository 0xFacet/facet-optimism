#!/bin/bash


# Function to check if we're running in a container
is_container() {
    [ -f /.dockerenv ] || grep -q docker /proc/1/cgroup || [ -f "/usr/local/bin/op-node" ]
}

# Function to get rollup config path
get_rollup_config() {
    if is_container; then
        if [ "$L1_NETWORK" = "mainnet" ]; then
            echo "/app/op-node/facet-mainnet-rollup-config.json"
        else
            echo "/app/op-node/facet-sepolia-rollup-config.json"
        fi
    else
        if [ "$L1_NETWORK" = "mainnet" ]; then
            echo "./op-node/facet-mainnet-rollup-config.json"
        else
            echo "./op-node/facet-sepolia-rollup-config.json"
        fi
    fi
}
# Check if we're running in a Docker container
if is_container; then
    echo "Running in Docker environment, skipping env file sourcing"
    OP_NODE_BIN="/usr/local/bin/op-node"
    ROLLUP_CONFIG=$(get_rollup_config $L1_NETWORK)
else
    # Check if .envrc exists before allowing it
    if [ -f .envrc ]; then
        source .envrc
    else
        echo "Warning: .envrc file not found. If you're in a dev environment, this might be an issue."
    fi
    
    echo "Building op-node..."
    make -C op-node op-node
    
    OP_NODE_BIN="./op-node/bin/op-node"
    ROLLUP_CONFIG=$(get_rollup_config $L1_NETWORK)
fi

# Verify rollup config exists
if [ ! -f "$ROLLUP_CONFIG" ]; then
    echo "Error: Rollup config not found at $ROLLUP_CONFIG"
    exit 1
fi

echo "Using rollup config: $ROLLUP_CONFIG"

ADDITIONAL_FLAGS=${ADDITIONAL_FLAGS:-""}

# Check if the binary exists
if [ ! -f "$OP_NODE_BIN" ]; then
    echo "Error: op-node binary not found at $OP_NODE_BIN"
    exit 1
fi

$OP_NODE_BIN \
  --l1.beacon.ignore=true \
  --rpc.addr=0.0.0.0 \
  --rpc.port=${PORT:-9545} \
  --rollup.config "$ROLLUP_CONFIG" \
  --p2p.disable \
  --sequencer.stopped=true \
  --sequencer.enabled=false \
  --l1.epoch-poll-interval=12s \
  --l2.enginekind=geth \
  --syncmode execution-layer \
  --l2 $OP_NODE_L2_ENGINE_RPC \
  --l1 $OP_NODE_L1_ETH_RPC \
  $ADDITIONAL_FLAGS
