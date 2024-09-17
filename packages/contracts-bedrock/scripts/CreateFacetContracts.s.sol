// SPDX-License-Identifier: MIT
pragma solidity 0.8.15;

import "forge-std/Script.sol";
import { L2StandardBridge } from "../src/L2/L2StandardBridge.sol";
import { L2CrossDomainMessenger } from "../src/L2/L2CrossDomainMessenger.sol";
import { OptimismMintableERC20Factory } from "../src/universal/OptimismMintableERC20Factory.sol";
import { LibFacet } from "../src/libraries/LibFacet.sol";

contract PrintCreationCode is Script {
    modifier broadcast() {
        vm.startBroadcast(msg.sender);
        _;
        vm.stopBroadcast();
    }

    function run() external broadcast {
        LibFacet.sendFacetTransaction({
            value: 0,
            gasLimit: 5_000_000,
            data: type(L2CrossDomainMessenger).creationCode
        });

        LibFacet.sendFacetTransaction({
            value: 0,
            gasLimit: 5_000_000,
            data: type(L2StandardBridge).creationCode
        });

        LibFacet.sendFacetTransaction({
            value: 0,
            gasLimit: 5_000_000,
            data: type(OptimismMintableERC20Factory).creationCode
        });
    }

    // uint256 sepoliaFork = vm.createFork("https://...");

    // // Select the Sepolia fork
    // vm.selectFork(sepoliaFork);

    // // Construct the JSON string for the RPC parameters
    // string memory params = string(abi.encodePacked(
    //     "[\"",
    //     "0x742d35Cc6634C0532925a3b844Bc454e4438f44e", // Address to check
    //     "\", \"",
    //     "latest",                                    // Block number
    //     "\"]"
    // ));

    // // Perform the RPC call on the Sepolia fork
    // bytes memory returnData = vm.rpc(
    //     "eth_getBalance", // RPC method
    //     params            // JSON string parameters
    // );

    // console.log("Balance:", vm.toString(returnData));
}
