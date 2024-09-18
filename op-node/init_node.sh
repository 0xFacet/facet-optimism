#!/bin/bash

./bin/op-node --l1 $L1_ETH_RPC --l2 $L2_ENGINE_RPC --l1.beacon.ignore=true --rpc.addr=0.0.0.0 --rpc.port=9545 --rollup.config "./rollup-config.json" --p2p.disable --rpc.enable-admin --sequencer.stopped=true --sequencer.enabled=false --l1.epoch-poll-interval=12s --l2.enginekind=geth
