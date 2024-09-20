// SPDX-License-Identifier: MIT
pragma solidity 0.8.15;

import "forge-std/Script.sol";
import { L2StandardBridge } from "../src/L2/L2StandardBridge.sol";
import { L2CrossDomainMessenger } from "../src/L2/L2CrossDomainMessenger.sol";
import { OptimismMintableERC20Factory } from "../src/universal/OptimismMintableERC20Factory.sol";
import { LibFacet } from "../src/libraries/LibFacet.sol";
import { LibRLP } from "../src/libraries/LibRLP.sol";
import { JSONParserLib } from "@solady/utils/JSONParserLib.sol";
import { Proxy } from "src/universal/Proxy.sol";
import { EIP1967Helper } from "test/mocks/EIP1967Helper.sol";
import { Artifacts, Deployment } from "./Artifacts.s.sol";
import { ForgeArtifacts } from "scripts/libraries/ForgeArtifacts.sol";

contract CreateFacetContracts is Script, Artifacts {
    using LibRLP for LibRLP.List;

    modifier broadcast() {
        vm.startBroadcast(msg.sender);
        _;
        vm.stopBroadcast();
    }

    uint256 deployerNonce;

    function setUp() public virtual override {
        vm.setEnv("DEPLOYMENT_OUTFILE", vm.envString("L2_DEPLOYMENT_OUTFILE"));
        Artifacts.setUp();
        deployerNonce = getL2Nonce();
    }

    function run() external broadcast {
        deployERC1967Proxy("L2CrossDomainMessengerProxy");
        deployERC1967Proxy("L2StandardBridgeProxy");
        deployERC1967Proxy("OptimismMintableERC20FactoryProxy");

        deployImplementation("L2CrossDomainMessenger", type(L2CrossDomainMessenger).creationCode);
        deployImplementation("L2StandardBridge", type(L2StandardBridge).creationCode);
        deployImplementation("OptimismMintableERC20Factory", type(OptimismMintableERC20Factory).creationCode);
    }

    function compAddr(address deployer, uint256 nonce) pure internal returns (address) {
        return address(uint160(uint256(keccak256(LibRLP.p(deployer).p(nonce).p('facet').encode()))));
    }

    function nextAddress() internal returns (address) {
        address addr = compAddr(msg.sender, deployerNonce);
        deployerNonce++;
        return addr;
    }

    function deployImplementation(string memory _name, bytes memory _creationCode) public returns (address addr_) {
        addr_ = nextAddress();
        LibFacet.sendFacetTransaction({
            gasLimit: 5_000_000,
            data: _creationCode
        });
        save(_name, addr_);
        console.log("   at %s", addr_);
    }

    function deployERC1967Proxy(string memory _name) public returns (address addr_) {
        addr_ = deployERC1967ProxyWithOwner(_name, msg.sender);
    }

    function deployERC1967ProxyWithOwner(
        string memory _name,
        address _proxyOwner
    )
        public
        returns (address addr_)
    {
        console.log(string.concat("Deploying ERC1967 proxy for ", _name));

        addr_ = nextAddress();

        LibFacet.sendFacetTransaction({
            gasLimit: 5_000_000,
            data: abi.encodePacked(
                type(Proxy).creationCode,
                abi.encode(_proxyOwner)
            )
        });

        save(_name, addr_);
        console.log("   at %s", addr_);
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

}
