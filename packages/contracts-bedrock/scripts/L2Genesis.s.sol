// SPDX-License-Identifier: MIT
pragma solidity 0.8.15;

import { Script } from "forge-std/Script.sol";
import { console2 as console } from "forge-std/console2.sol";
import { Deployer } from "scripts/deploy/Deployer.sol";

import { Config, OutputMode, OutputModeUtils, Fork, ForkUtils, LATEST_FORK } from "scripts/libraries/Config.sol";
import { Predeploys } from "src/libraries/Predeploys.sol";
import { Preinstalls } from "src/libraries/Preinstalls.sol";
import { L1Block } from "src/L2/L1Block.sol";
import { GasPriceOracle } from "src/L2/GasPriceOracle.sol";
import { EIP1967Helper } from "test/mocks/EIP1967Helper.sol";
import { Process } from "scripts/libraries/Process.sol";

interface IInitializable {
    function initialize(address _addr) external;
}

/// @title L2Genesis
/// @notice Generates the genesis state for the L2 network.
///         The following safety invariants are used when setting state:
///         1. `vm.getDeployedBytecode` can only be used with `vm.etch` when there are no side
///         effects in the constructor and no immutables in the bytecode.
///         2. A contract must be deployed using the `new` syntax if there are immutables in the code.
///         Any other side effects from the init code besides setting the immutables must be cleaned up afterwards.
contract L2Genesis is Deployer {
    using ForkUtils for Fork;
    using OutputModeUtils for OutputMode;

    uint256 public constant PRECOMPILE_COUNT = 256;

    uint80 internal constant DEV_ACCOUNT_FUND_AMT = 10_000 ether;

    /// @notice Default Anvil dev accounts. Only funded if `cfg.fundDevAccounts == true`.
    /// Also known as "test test test test test test test test test test test junk" mnemonic accounts,
    /// on path "m/44'/60'/0'/0/i" (where i is the account index).
    address[30] internal devAccounts = [
        0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266, // 0
        0x70997970C51812dc3A010C7d01b50e0d17dc79C8, // 1
        0x3C44CdDdB6a900fa2b585dd299e03d12FA4293BC, // 2
        0x90F79bf6EB2c4f870365E785982E1f101E93b906, // 3
        0x15d34AAf54267DB7D7c367839AAf71A00a2C6A65, // 4
        0x9965507D1a55bcC2695C58ba16FB37d819B0A4dc, // 5
        0x976EA74026E726554dB657fA54763abd0C3a0aa9, // 6
        0x14dC79964da2C08b23698B3D3cc7Ca32193d9955, // 7
        0x23618e81E3f5cdF7f54C3d65f7FBc0aBf5B21E8f, // 8
        0xa0Ee7A142d267C1f36714E4a8F75612F20a79720, // 9
        0xBcd4042DE499D14e55001CcbB24a551F3b954096, // 10
        0x71bE63f3384f5fb98995898A86B02Fb2426c5788, // 11
        0xFABB0ac9d68B0B445fB7357272Ff202C5651694a, // 12
        0x1CBd3b2770909D4e10f157cABC84C7264073C9Ec, // 13
        0xdF3e18d64BC6A983f673Ab319CCaE4f1a57C7097, // 14
        0xcd3B766CCDd6AE721141F452C550Ca635964ce71, // 15
        0x2546BcD3c84621e976D8185a91A922aE77ECEc30, // 16
        0xbDA5747bFD65F08deb54cb465eB87D40e51B197E, // 17
        0xdD2FD4581271e230360230F9337D5c0430Bf44C0, // 18
        0x8626f6940E2eb28930eFb4CeF49B2d1F2C9C1199, // 19
        0x09DB0a93B389bEF724429898f539AEB7ac2Dd55f, // 20
        0x02484cb50AAC86Eae85610D6f4Bf026f30f6627D, // 21
        0x08135Da0A343E492FA2d4282F2AE34c6c5CC1BbE, // 22
        0x5E661B79FE2D3F6cE70F5AAC07d8Cd9abb2743F1, // 23
        0x61097BA76cD906d2ba4FD106E757f7Eb455fc295, // 24
        0xDf37F81dAAD2b0327A0A50003740e1C935C70913, // 25
        0x553BC17A05702530097c3677091C5BB47a3a7931, // 26
        0x87BdCE72c06C21cd96219BD8521bDF1F42C78b5e, // 27
        0x40Fc963A729c542424cD800349a7E4Ecc4896624, // 28
        0x9DCCe783B6464611f38631e6C851bf441907c710 // 29
    ];

    /// @notice The address of the deployer account.
    address internal deployer;

    /// @notice Sets up the script and ensures the deployer account is used to make calls.
    function setUp() public override {
        deployer = makeAddr("deployer");
        super.setUp();
    }

    /// @notice The alloc object is sorted numerically by address.
    ///         Sets the precompiles, proxies, and the implementation accounts to be `vm.dumpState`
    ///         to generate a L2 genesis alloc.
    function runWithStateDump() public {
        runWithOptions(Config.outputMode(), cfg.fork());
    }

    /// @notice Alias for `runWithStateDump` so that no `--sig` needs to be specified.
    function run() public {
        runWithStateDump();
    }

    /// @notice This is used by op-e2e to have a version of the L2 allocs for each upgrade.
    function runWithAllUpgrades() public {
        runWithOptions(OutputMode.ALL, LATEST_FORK);
    }

    /// @notice This is used by foundry tests to enable the latest fork with the
    ///         given L1 dependencies.
    function runWithLatestLocal() public {
        runWithOptions(OutputMode.NONE, LATEST_FORK);
    }
    
    function l2ChainId() internal view returns (uint256) {
        return vm.envUint("L2_CHAIN_ID");
    }

    /// @notice Build the L2 genesis.
    function runWithOptions(OutputMode _mode, Fork _fork) public {
        console.log("L2Genesis: outputMode: %s, fork: %s", _mode.toString(), _fork.toString());
        vm.startPrank(deployer);
        vm.chainId(l2ChainId());

        dealEthToPrecompiles();
        setPredeployProxies();
        setPredeployImplementations();
        setPreinstalls();
        if (cfg.fundDevAccounts()) {
            fundDevAccounts();
        }
        vm.stopPrank();

        if (writeForkGenesisAllocs(_fork, Fork.DELTA, _mode)) {
            return;
        }

        if (writeForkGenesisAllocs(_fork, Fork.ECOTONE, _mode)) {
            return;
        }

        if (writeForkGenesisAllocs(_fork, Fork.FJORD, _mode)) {
            return;
        }

        if (writeForkGenesisAllocs(_fork, Fork.GRANITE, _mode)) {
            return;
        }
    }

    function writeForkGenesisAllocs(Fork _latest, Fork _current, OutputMode _mode) internal returns (bool isLatest_) {
        if (_mode == OutputMode.ALL || _latest == _current && _mode == OutputMode.LATEST) {
            string memory suffix = string.concat("-", _current.toString());
            writeGenesisAllocs(Config.stateDumpPath(suffix));
        }
        if (_latest == _current) {
            isLatest_ = true;
        }
    }

    /// @notice Give all of the precompiles 1 wei
    function dealEthToPrecompiles() internal {
        console.log("Setting precompile 1 wei balances");
        for (uint256 i; i < PRECOMPILE_COUNT; i++) {
            vm.deal(address(uint160(i)), 1);
        }
    }

    /// @notice Set up the accounts that correspond to the predeploys.
    ///         The Proxy bytecode should be set. All proxied predeploys should have
    ///         the 1967 admin slot set to the ProxyAdmin predeploy. All defined predeploys
    ///         should have their implementations set.
    ///         Warning: the predeploy accounts have contract code, but 0 nonce value, contrary
    ///         to the expected nonce of 1 per EIP-161. This is because the legacy go genesis
    //          script didn't set the nonce and we didn't want to change that behavior when
    ///         migrating genesis generation to Solidity.
    function setPredeployProxies() public {
        console.log("Setting Predeploy proxies");
        bytes memory code = vm.getDeployedCode("Proxy.sol:Proxy");
        uint160 prefix = uint160(0x420) << 148;

        console.log(
            "Setting proxy deployed bytecode for addresses in range %s through %s",
            address(prefix | uint160(0)),
            address(prefix | uint160(Predeploys.PREDEPLOY_COUNT - 1))
        );
        for (uint256 i = 0; i < Predeploys.PREDEPLOY_COUNT; i++) {
            address addr = address(prefix | uint160(i));
            if (Predeploys.notProxied(addr)) {
                console.log("Skipping proxy at %s", addr);
                continue;
            }

            vm.etch(addr, code);
            EIP1967Helper.setAdmin(addr, Predeploys.PROXY_ADMIN);

            if (Predeploys.isSupportedPredeploy(addr, cfg.useInterop())) {
                address implementation = Predeploys.predeployToCodeNamespace(addr);
                console.log("Setting proxy %s implementation: %s", addr, implementation);
                EIP1967Helper.setImplementation(addr, implementation);
            }
        }
    }

    /// @notice Sets all the implementations for the predeploy proxies. For contracts without proxies,
    ///      sets the deployed bytecode at their expected predeploy address.
    ///      LEGACY_ERC20_ETH and L1_MESSAGE_SENDER are deprecated and are not set.
    function setPredeployImplementations() internal {
        console.log("Setting predeploy implementations with L1 contract dependencies:");
        setWETH(); // 6: WETH (not behind a proxy)
        setL1Block(); // 15
        setL2ToL1MessagePasser(); // 16
        setProxyAdmin(); // 18
        setSchemaRegistry(); // 20
        setEAS(); // 21
    }

    function setProxyAdmin() public {
        // Note the ProxyAdmin implementation itself is behind a proxy that owns itself.
        address impl = _setImplementationCode(Predeploys.PROXY_ADMIN);

        bytes32 _ownerSlot = bytes32(0);

        address depositorAccount = L1Block(Predeploys.L1_BLOCK_ATTRIBUTES).DEPOSITOR_ACCOUNT();

        // there is no initialize() function, so we just set the storage manually.
        vm.store(Predeploys.PROXY_ADMIN, _ownerSlot, bytes32(uint256(uint160(depositorAccount))));
        // update the proxy to not be uninitialized (although not standard initialize pattern)
        vm.store(impl, _ownerSlot, bytes32(uint256(uint160(depositorAccount))));
    }

    function setL2ToL1MessagePasser() public {
        _setImplementationCode(Predeploys.L2_TO_L1_MESSAGE_PASSER);
    }

    /// @notice This predeploy is following the safety invariant #1.
    function setL1Block() public {
        if (cfg.useInterop()) {
            string memory cname = "L1BlockInterop";
            address impl = Predeploys.predeployToCodeNamespace(Predeploys.L1_BLOCK_ATTRIBUTES);
            console.log("Setting %s implementation at: %s", cname, impl);
            vm.etch(impl, vm.getDeployedCode(string.concat(cname, ".sol:", cname)));
        } else {
            _setImplementationCode(Predeploys.L1_BLOCK_ATTRIBUTES);
            // Note: L1 block attributes are set to 0.
            // Before the first user-tx the state is overwritten with actual L1 attributes.
        }
    }

    /// @notice This predeploy is following the safety invariant #1.
    ///         This contract is NOT proxied and the state that is set
    ///         in the constructor is set manually.
    function setWETH() public {
        console.log("Setting %s implementation at: %s", "WETH", Predeploys.WETH);
        vm.etch(Predeploys.WETH, vm.getDeployedCode("WETH.sol:WETH"));
    }

    /// @notice This predeploy is following the safety invariant #1.
    function setSchemaRegistry() public {
        _setImplementationCode(Predeploys.SCHEMA_REGISTRY);
    }

    /// @notice This predeploy is following the safety invariant #2,
    ///         It uses low level create to deploy the contract due to the code
    ///         having immutables and being a different compiler version.
    function setEAS() public {
        string memory cname = Predeploys.getName(Predeploys.EAS);
        address impl = Predeploys.predeployToCodeNamespace(Predeploys.EAS);
        bytes memory code = vm.getCode(string.concat(cname, ".sol:", cname));

        address eas;
        assembly {
            eas := create(0, add(code, 0x20), mload(code))
        }

        console.log("Setting %s implementation at: %s", cname, impl);
        vm.etch(impl, eas.code);

        /// Reset so its not included state dump
        vm.etch(address(eas), "");
        vm.resetNonce(address(eas));
    }

    /// @notice Sets all the preinstalls.
    ///         Warning: the creator-accounts of the preinstall contracts have 0 nonce values.
    ///         When performing a regular user-initiated contract-creation of a preinstall,
    ///         the creation will fail (but nonce will be bumped and not blocked).
    ///         The preinstalls themselves are all inserted with a nonce of 1, reflecting regular user execution.
    function setPreinstalls() internal {
        _setPreinstallCode(Preinstalls.MultiCall3);
        _setPreinstallCode(Preinstalls.Create2Deployer);
        _setPreinstallCode(Preinstalls.Safe_v130);
        _setPreinstallCode(Preinstalls.SafeL2_v130);
        _setPreinstallCode(Preinstalls.MultiSendCallOnly_v130);
        _setPreinstallCode(Preinstalls.SafeSingletonFactory);
        _setPreinstallCode(Preinstalls.DeterministicDeploymentProxy);
        _setPreinstallCode(Preinstalls.MultiSend_v130);
        _setPreinstallCode(Preinstalls.Permit2);
        _setPreinstallCode(Preinstalls.SenderCreator_v060); // ERC 4337 v0.6.0
        _setPreinstallCode(Preinstalls.EntryPoint_v060); // ERC 4337 v0.6.0
        _setPreinstallCode(Preinstalls.SenderCreator_v070); // ERC 4337 v0.7.0
        _setPreinstallCode(Preinstalls.EntryPoint_v070); // ERC 4337 v0.7.0
        _setPreinstallCode(Preinstalls.BeaconBlockRoots);
        // 4788 sender nonce must be incremented, since it's part of later upgrade-transactions.
        // For the upgrade-tx to not create a contract that conflicts with an already-existing copy,
        // the nonce must be bumped.
        vm.setNonce(Preinstalls.BeaconBlockRootsSender, 1);
    }

    /// @notice Sets the bytecode in state
    function _setImplementationCode(address _addr) internal returns (address) {
        string memory cname = Predeploys.getName(_addr);
        address impl = Predeploys.predeployToCodeNamespace(_addr);
        console.log("Setting %s implementation at: %s", cname, impl);
        vm.etch(impl, vm.getDeployedCode(string.concat(cname, ".sol:", cname)));
        return impl;
    }

    /// @notice Sets the bytecode in state
    function _setPreinstallCode(address _addr) internal {
        string memory cname = Preinstalls.getName(_addr);
        console.log("Setting %s preinstall code at: %s", cname, _addr);
        vm.etch(_addr, Preinstalls.getDeployedCode(_addr, l2ChainId()));
        // during testing in a shared L1/L2 account namespace some preinstalls may already have been inserted and used.
        if (vm.getNonce(_addr) == 0) {
            vm.setNonce(_addr, 1);
        }
    }

    /// @notice Writes the genesis allocs, i.e. the state dump, to disk
    function writeGenesisAllocs(string memory _path) public {
        /// Reset so its not included state dump
        vm.etch(address(cfg), "");
        vm.etch(msg.sender, "");
        vm.resetNonce(msg.sender);
        vm.deal(msg.sender, 0);

        vm.deal(deployer, 0);
        vm.resetNonce(deployer);

        console.log("Writing state dump to: %s", _path);
        vm.dumpState(_path);
        sortJsonByKeys(_path);
    }

    /// @notice Sorts the allocs by address
    function sortJsonByKeys(string memory _path) internal {
        string[] memory commands = new string[](3);
        commands[0] = "bash";
        commands[1] = "-c";
        commands[2] = string.concat("cat <<< $(jq -S '.' ", _path, ") > ", _path);
        Process.run(commands);
    }

    /// @notice Funds the default dev accounts with ether
    function fundDevAccounts() internal {
        for (uint256 i; i < devAccounts.length; i++) {
            console.log("Funding dev account %s with %s ETH", devAccounts[i], DEV_ACCOUNT_FUND_AMT / 1e18);
            vm.deal(devAccounts[i], DEV_ACCOUNT_FUND_AMT);
        }
    }
}
