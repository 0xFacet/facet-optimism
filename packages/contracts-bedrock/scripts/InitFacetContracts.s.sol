// SPDX-License-Identifier: MIT
pragma solidity ^0.8.15;

import "forge-std/Script.sol";
import { L2StandardBridge } from "../src/L2/L2StandardBridge.sol";
import { L1StandardBridge } from "../src/L1/L1StandardBridge.sol";
import { L2CrossDomainMessenger } from "../src/L2/L2CrossDomainMessenger.sol";
import { L1CrossDomainMessenger } from "../src/L1/L1CrossDomainMessenger.sol";
import { OptimismMintableERC20Factory } from "../src/universal/OptimismMintableERC20Factory.sol";
import { Proxy } from "src/universal/Proxy.sol";
import { FacetScript } from "lib/facet-sol/src/foundry-utils/FacetScript.sol";

contract InitFacetContracts is Script, FacetScript {
    struct Deployment {
        address implementation;
        address proxy;
    }

    mapping(string => Deployment) public deployments;
    
    function setUp() public override {
        super.setUp();
        // string memory root = vm.projectRoot();
        string memory path = vm.envString("L2_DEPLOYMENT_OUTFILE");
        string memory json = vm.readFile(path);

        string[] memory keys = new string[](3);
        keys[0] = "L2CrossDomainMessenger";
        keys[1] = "L2StandardBridge";
        keys[2] = "OptimismMintableERC20Factory";

        for (uint i = 0; i < keys.length; i++) {
            string memory key = keys[i];
            address implementation = abi.decode(vm.parseJson(json, string.concat(".", key)), (address));
            address proxy = abi.decode(vm.parseJson(json, string.concat(".", key, "Proxy")), (address));

            deployments[key] = Deployment({
                implementation: implementation,
                proxy: proxy
            });

            console.log("Deployment:", key);
            console.log("  Implementation:", implementation);
            console.log("  Proxy:", proxy);
        }
    }

    function upgradeToAndCall(string memory deploymentName, bytes memory data) public {
        Deployment memory deployment = deployments[deploymentName];

        address proxy = deployment.proxy;
        address impl = deployment.implementation;

        sendFacetTransactionFoundry({
            to: proxy,
            gasLimit: 5_000_000,
            data: abi.encodeCall(
                Proxy.upgradeToAndCall,
                (impl, data)
            )
        });
    }

    function run() external broadcast {
        bytes memory messengerInitData = abi.encodeCall(
            L2CrossDomainMessenger.initialize,
            (
                L1CrossDomainMessenger(vm.envAddress("L1CrossDomainMessenger"))
            )
        );

        upgradeToAndCall("L2CrossDomainMessenger", messengerInitData);

        bytes memory bridgeInitData = abi.encodeCall(
            L2StandardBridge.initialize,
            (
                L1StandardBridge(payable(vm.envAddress("L1StandardBridge"))),
                L2CrossDomainMessenger(vm.envAddress("L2CrossDomainMessenger"))
            )
        );

        upgradeToAndCall("L2StandardBridge", bridgeInitData);

        bytes memory factoryInitData = abi.encodeCall(
            OptimismMintableERC20Factory.initialize,
            (
                vm.envAddress("L2StandardBridge")
            )
        );

        upgradeToAndCall("OptimismMintableERC20Factory", factoryInitData);

        sendFacetTransactionFoundry({
            to: deployments["OptimismMintableERC20Factory"].proxy,
            gasLimit: 5_000_000,
            data: abi.encodeCall(OptimismMintableERC20Factory.createOptimismMintableERC20, (
                0x5589BB8228C07c4e15558875fAf2B859f678d129,
                'Test Name',
                'TEST'
            ))
        });

        transferProxyAdminOwnership("L2CrossDomainMessenger");
        transferProxyAdminOwnership("L2StandardBridge");
        transferProxyAdminOwnership("OptimismMintableERC20Factory");
    }

    function transferProxyAdminOwnership(string memory implName) public {
        address proxy = deployments[implName].proxy;

        sendFacetTransactionFoundry({
            to: proxy,
            gasLimit: 5_000_000,
            data: abi.encodeCall(
                Proxy.changeAdmin,
                (vm.envAddress("GS_ADMIN_ADDRESS"))
            )
        });
    }
}
