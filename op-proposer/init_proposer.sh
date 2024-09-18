#!/bin/bash

./bin/op-proposer --l1-eth-rpc $L1_ETH_RPC --rollup-rpc $ROLLUP_RPC --l2oo-address $L2_OUTPUT_ORACLE --private-key $PROPOSER_PRIVATE_KEY --poll-interval 12s --active-sequencer-check-duration 12s --num-confirmations 1 --allow-non-finalized=true --log.level=debug
