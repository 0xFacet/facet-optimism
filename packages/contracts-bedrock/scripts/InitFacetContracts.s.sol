// SPDX-License-Identifier: MIT
pragma solidity ^0.8.15;

import "forge-std/Script.sol";
import { L2StandardBridge } from "../src/L2/L2StandardBridge.sol";
import { L1StandardBridge } from "../src/L1/L1StandardBridge.sol";
import { L2CrossDomainMessenger } from "../src/L2/L2CrossDomainMessenger.sol";
import { L1CrossDomainMessenger } from "../src/L1/L1CrossDomainMessenger.sol";
import { OptimismMintableERC20Factory } from "../src/universal/OptimismMintableERC20Factory.sol";
import { LibFacet } from "../src/libraries/LibFacet.sol";

contract InitFacetContracts is Script {
    modifier broadcast() {
        vm.startBroadcast(msg.sender);
        _;
        vm.stopBroadcast();
    }

    function run() external broadcast {
        LibFacet.sendFacetTransaction({
            to: vm.envAddress("L2_CROSS_DOMAIN_MESSENGER"),
            value: 0,
            gasLimit: 5_000_000,
            data: abi.encodeCall(L2CrossDomainMessenger.setOtherMessenger, (
                L1CrossDomainMessenger(vm.envAddress("L1_CROSS_DOMAIN_MESSENGER"))
            ))
        });

        LibFacet.sendFacetTransaction({
            to: vm.envAddress("L2_STANDARD_BRIDGE"),
            value: 0,
            gasLimit: 5_000_000,
            data: abi.encodeCall(L2StandardBridge.setMessengerAndOtherBridge, (
                L2CrossDomainMessenger(vm.envAddress("L2_CROSS_DOMAIN_MESSENGER")),
                L1StandardBridge(payable(vm.envAddress("L1_STANDARD_BRIDGE")))
            ))
        });

        LibFacet.sendFacetTransaction({
            to: vm.envAddress("OPTIMISM_MINTABLE_ERC20_FACTORY"),
            value: 0,
            gasLimit: 5_000_000,
            data: abi.encodeCall(OptimismMintableERC20Factory.setBridge, (
                vm.envAddress("L2_STANDARD_BRIDGE")
            ))
        });

        LibFacet.sendFacetTransaction({
            to: vm.envAddress("OPTIMISM_MINTABLE_ERC20_FACTORY"),
            value: 0,
            gasLimit: 5_000_000,
            data: abi.encodeCall(OptimismMintableERC20Factory.createOptimismMintableERC20, (
                0x5589BB8228C07c4e15558875fAf2B859f678d129,
                'Test Name',
                'TEST'
            ))
        });
    }
}
