// SPDX-License-Identifier: MIT
pragma solidity 0.8.15;

import "forge-std/Script.sol";
import { L2StandardBridge } from "../src/L2/L2StandardBridge.sol";
import { L2CrossDomainMessenger } from "../src/L2/L2CrossDomainMessenger.sol";
import { OptimismMintableERC20Factory } from "../src/universal/OptimismMintableERC20Factory.sol";
import { LibRLP } from "../src/libraries/LibRLP.sol";
import { JSONParserLib } from "@solady/utils/JSONParserLib.sol";
import { Proxy } from "src/universal/Proxy.sol";
import { EIP1967Helper } from "test/mocks/EIP1967Helper.sol";
import { Artifacts, Deployment } from "./Artifacts.s.sol";
import { ForgeArtifacts } from "scripts/libraries/ForgeArtifacts.sol";
import { FacetScript } from "lib/facet-sol/src/foundry-utils/FacetScript.sol";

contract CreateFacetContracts is Script, Artifacts, FacetScript {
    using LibRLP for LibRLP.List;

    function setUp() public virtual override(FacetScript, Artifacts) {
        vm.setEnv("DEPLOYMENT_OUTFILE", vm.envString("L2_DEPLOYMENT_OUTFILE"));
        Artifacts.setUp();
        FacetScript.setUp();
    }

    function run() external broadcast {
        deployERC1967Proxy("L2CrossDomainMessengerProxy");
        deployERC1967Proxy("L2StandardBridgeProxy");
        deployERC1967Proxy("OptimismMintableERC20FactoryProxy");

        deployImplementation("L2CrossDomainMessenger", type(L2CrossDomainMessenger).creationCode);
        deployImplementation("L2StandardBridge", type(L2StandardBridge).creationCode);
        deployImplementation("OptimismMintableERC20Factory", type(OptimismMintableERC20Factory).creationCode);
    }

    function nextAddress() internal returns (address) {
        address addr = LibRLP.computeAddress(msg.sender, uint256(deployerNonce));
        deployerNonce++;
        return addr;
    }

    function deployImplementation(string memory _name, bytes memory _creationCode) public returns (address addr_) {
        addr_ = nextAddress();
        sendFacetTransactionFoundry({
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

        sendFacetTransactionFoundry({
            gasLimit: 5_000_000,
            data: abi.encodePacked(
                type(Proxy).creationCode,
                abi.encode(_proxyOwner)
            )
        });

        save(_name, addr_);
        console.log("   at %s", addr_);
    }
}
