// SPDX-License-Identifier: MIT
pragma solidity 0.8.15;

import "forge-std/Script.sol";
import { L2StandardBridge } from "../src/L2/L2StandardBridge.sol";
import { L2CrossDomainMessenger } from "../src/L2/L2CrossDomainMessenger.sol";
import { OptimismMintableERC20Factory } from "../src/universal/OptimismMintableERC20Factory.sol";
import { LibFacet } from "../src/libraries/LibFacet.sol";
import { LibRLP } from "../src/libraries/LibRLP.sol";
import { JSONParserLib } from "@solady/utils/JSONParserLib.sol";

contract CreateFacetContracts is Script {
    using LibRLP for LibRLP.List;

    modifier broadcast() {
        vm.startBroadcast(msg.sender);
        _;
        vm.stopBroadcast();
    }

    uint256 deployerNonce;

    function run() external {
        deployerNonce = getL2Nonce();
        createContracts();
    }

    function compAddr(address deployer, uint256 nonce) pure internal returns (address) {
        return address(uint160(uint256(keccak256(LibRLP.p(deployer).p(nonce).p('facet').encode()))));
    }

    function getNextContractAddressAndIncrementNonce() internal returns (address) {
        address addr = compAddr(msg.sender, deployerNonce);
        deployerNonce++;
        return addr;
    }

    function getL2Nonce() internal returns (uint256) {
        // Store the current fork ID
        uint256 originalFork = vm.activeFork();

        // Create and select the L2 fork
        uint256 l2Fork = vm.createFork(vm.envString("L2_RPC"));
        vm.selectFork(l2Fork);

        // Construct the JSON string for the RPC parameters
        string memory params = string(abi.encodePacked(
            "[\"",
            vm.toString(msg.sender), // Address of the message sender
            "\", \"",
            "latest",                // Block number
            "\"]"
        ));

        // Perform the RPC call to get the nonce
        bytes memory returnData = vm.rpc(
            "eth_getTransactionCount", // RPC method for getting nonce
            params                     // JSON string parameters
        );

        // Convert the returned hex string to a uint256
        uint256 nonce = JSONParserLib.parseUintFromHex(vm.toString(returnData));

        // Log the nonce
        console.log("Nonce of", msg.sender, ":", nonce);

        // Switch back to the original fork
        vm.selectFork(originalFork);

        return nonce;
    }

    function createContracts() internal broadcast {
        console.log("First contract address:", getNextContractAddressAndIncrementNonce());
        console.log("Second contract address:", getNextContractAddressAndIncrementNonce());
        console.log("Third contract address:", getNextContractAddressAndIncrementNonce());

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
}
