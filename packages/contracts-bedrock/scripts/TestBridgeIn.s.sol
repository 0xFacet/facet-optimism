// SPDX-License-Identifier: MIT
pragma solidity 0.8.15;

import "forge-std/Script.sol";
import { L2StandardBridge } from "../src/L2/L2StandardBridge.sol";
import { L1StandardBridge } from "../src/L1/L1StandardBridge.sol";
import { L2CrossDomainMessenger } from "../src/L2/L2CrossDomainMessenger.sol";
import { L1CrossDomainMessenger } from "../src/L1/L1CrossDomainMessenger.sol";
import { OptimismMintableERC20Factory } from "../src/universal/OptimismMintableERC20Factory.sol";
import { ERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import { FoundryFacetSender } from "./FoundryFacetSender.sol";

contract FaucetTestingToken is ERC20 {
    /// @notice Creates the ERC20 with standard parameters.
    constructor()
        ERC20("FaucetTestingToken", "FAUCET")
    {}

    /// @notice Mints the sender 1000 tokens.
    function faucet() external {
        _mint(msg.sender, 1000e18);
    }
}

contract TestBridgeIn is Script, FoundryFacetSender {
    modifier broadcast() {
        vm.startBroadcast(msg.sender);
        _;
        vm.stopBroadcast();
    }

    L1StandardBridge public constant bridge = L1StandardBridge(payable(0x3F5992b77455856B9Bc729809f58D135B28aDe4A));
    address public immutable l2BridgeRecipient = msg.sender;
    address public immutable remoteToken = 0xD0e9b6D999ee78b7F25B6917540A29Ed1981EFFd;

    function run() external broadcast {
        FaucetTestingToken testToken = FaucetTestingToken(0x5589BB8228C07c4e15558875fAf2B859f678d129);

        testToken.faucet();

        testToken.approve(address(bridge), type(uint256).max);

        bridge.bridgeERC20To({
            _to: 0xC2172a6315c1D7f6855768F843c420EbB36eDa97,
            _localToken: address(testToken),
            _remoteToken: remoteToken,
            _amount: 11 ether,
            _minGasLimit: 100_000,
            _extraData: ""
        });
    }
}
