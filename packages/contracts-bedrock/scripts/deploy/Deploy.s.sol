// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import { VmSafe } from "forge-std/Vm.sol";
import { Script } from "forge-std/Script.sol";

import { console2 as console } from "forge-std/console2.sol";
import { stdJson } from "forge-std/StdJson.sol";

import { GnosisSafe as Safe } from "safe-contracts/GnosisSafe.sol";
import { OwnerManager } from "safe-contracts/base/OwnerManager.sol";
import { GnosisSafeProxyFactory as SafeProxyFactory } from "safe-contracts/proxies/GnosisSafeProxyFactory.sol";
import { Enum as SafeOps } from "safe-contracts/common/Enum.sol";

import { Deployer } from "scripts/deploy/Deployer.sol";

import { ProxyAdmin } from "src/universal/ProxyAdmin.sol";
import { AddressManager } from "src/legacy/AddressManager.sol";
import { Proxy } from "src/universal/Proxy.sol";
import { L1StandardBridge } from "src/L1/L1StandardBridge.sol";
import { StandardBridge } from "src/universal/StandardBridge.sol";
import { OptimismPortal } from "src/L1/OptimismPortal.sol";
import { OptimismPortal2 } from "src/L1/OptimismPortal2.sol";
import { OptimismPortalInterop } from "src/L1/OptimismPortalInterop.sol";
import { L1ChugSplashProxy } from "src/legacy/L1ChugSplashProxy.sol";
import { ResolvedDelegateProxy } from "src/legacy/ResolvedDelegateProxy.sol";
import { L2CrossDomainMessenger } from "src/L2/L2CrossDomainMessenger.sol";
import { L1CrossDomainMessenger } from "src/L1/L1CrossDomainMessenger.sol";
import { L2OutputOracle } from "src/L1/L2OutputOracle.sol";
import { OptimismMintableERC20Factory } from "src/universal/OptimismMintableERC20Factory.sol";
import { SuperchainConfig } from "src/L1/SuperchainConfig.sol";
import { SystemConfig } from "src/L1/SystemConfig.sol";
import { SystemConfigInterop } from "src/L1/SystemConfigInterop.sol";
import { ResourceMetering } from "src/L1/ResourceMetering.sol";
import { DataAvailabilityChallenge } from "src/L1/DataAvailabilityChallenge.sol";
import { Constants } from "src/libraries/Constants.sol";
import { DisputeGameFactory } from "src/dispute/DisputeGameFactory.sol";
import { FaultDisputeGame } from "src/dispute/FaultDisputeGame.sol";
import { PermissionedDisputeGame } from "src/dispute/PermissionedDisputeGame.sol";
import { DelayedWETH } from "src/dispute/weth/DelayedWETH.sol";
import { AnchorStateRegistry } from "src/dispute/AnchorStateRegistry.sol";
import { PreimageOracle } from "src/cannon/PreimageOracle.sol";
import { MIPS } from "src/cannon/MIPS.sol";
import { L1ERC721Bridge } from "src/L1/L1ERC721Bridge.sol";
import { ProtocolVersions, ProtocolVersion } from "src/L1/ProtocolVersions.sol";
import { StorageSetter } from "src/universal/StorageSetter.sol";
import { Predeploys } from "src/libraries/Predeploys.sol";
import { Chains } from "scripts/libraries/Chains.sol";
import { Config } from "scripts/libraries/Config.sol";

import { IBigStepper } from "src/dispute/interfaces/IBigStepper.sol";
import { IPreimageOracle } from "src/cannon/interfaces/IPreimageOracle.sol";
import { AlphabetVM } from "test/mocks/AlphabetVM.sol";
import "src/dispute/lib/Types.sol";
import { ChainAssertions } from "scripts/deploy/ChainAssertions.sol";
import { Types } from "scripts/libraries/Types.sol";
import { LibStateDiff } from "scripts/libraries/LibStateDiff.sol";
import { EIP1967Helper } from "test/mocks/EIP1967Helper.sol";
import { ForgeArtifacts } from "scripts/libraries/ForgeArtifacts.sol";
import { Process } from "scripts/libraries/Process.sol";

/// @title Deploy
/// @notice Script used to deploy a bedrock system. The entire system is deployed within the `run` function.
///         To add a new contract to the system, add a public function that deploys that individual contract.
///         Then add a call to that function inside of `run`. Be sure to call the `save` function after each
///         deployment so that hardhat-deploy style artifacts can be generated using a call to `sync()`.
///         The `CONTRACT_ADDRESSES_PATH` environment variable can be set to a path that contains a JSON file full of
///         contract name to address pairs. That enables this script to be much more flexible in the way it is used.
///         This contract must not have constructor logic because it is set into state using `etch`.
contract Deploy is Deployer {
    using stdJson for string;

    /// @notice FaultDisputeGameParams is a struct that contains the parameters necessary to call
    ///         the function _setFaultGameImplementation. This struct exists because the EVM needs
    ///         to finally adopt PUSHN and get rid of stack too deep once and for all.
    ///         Someday we will look back and laugh about stack too deep, today is not that day.
    struct FaultDisputeGameParams {
        AnchorStateRegistry anchorStateRegistry;
        DelayedWETH weth;
        GameType gameType;
        Claim absolutePrestate;
        IBigStepper faultVm;
        uint256 maxGameDepth;
        Duration maxClockDuration;
    }

    ////////////////////////////////////////////////////////////////
    //                        Modifiers                           //
    ////////////////////////////////////////////////////////////////

    /// @notice Modifier that wraps a function in broadcasting.
    modifier broadcast() {
        vm.startBroadcast(msg.sender);
        _;
        vm.stopBroadcast();
    }

    /// @notice Modifier that will only allow a function to be called on devnet.
    modifier onlyDevnet() {
        uint256 chainid = block.chainid;
        if (chainid == Chains.LocalDevnet || chainid == Chains.GethDevnet) {
            _;
        }
    }

    /// @notice Modifier that will only allow a function to be called on a public
    ///         testnet or devnet.
    modifier onlyTestnetOrDevnet() {
        uint256 chainid = block.chainid;
        if (
            chainid == Chains.Goerli || chainid == Chains.Sepolia || chainid == Chains.LocalDevnet
                || chainid == Chains.GethDevnet
        ) {
            _;
        }
    }

    /// @notice Modifier that wraps a function with statediff recording.
    ///         The returned AccountAccess[] array is then written to
    ///         the `snapshots/state-diff/<name>.json` output file.
    modifier stateDiff() {
        vm.startStateDiffRecording();
        _;
        VmSafe.AccountAccess[] memory accesses = vm.stopAndReturnStateDiff();
        console.log(
            "Writing %d state diff account accesses to snapshots/state-diff/%s.json",
            accesses.length,
            vm.toString(block.chainid)
        );
        string memory json = LibStateDiff.encodeAccountAccesses(accesses);
        string memory statediffPath =
            string.concat(vm.projectRoot(), "/snapshots/state-diff/", vm.toString(block.chainid), ".json");
        vm.writeJson({ json: json, path: statediffPath });
    }

    ////////////////////////////////////////////////////////////////
    //                        Accessors                           //
    ////////////////////////////////////////////////////////////////

    /// @notice The create2 salt used for deployment of the contract implementations.
    ///         Using this helps to reduce config across networks as the implementation
    ///         addresses will be the same across networks when deployed with create2.
    function _implSalt() internal view returns (bytes32) {
        return keccak256(bytes(Config.implSalt()));
    }

    /// @notice Returns the proxy addresses. If a proxy is not found, it will have address(0).
    function _proxies() internal view returns (Types.ContractSet memory proxies_) {
        proxies_ = Types.ContractSet({
            L1CrossDomainMessenger: mustGetAddress("L1CrossDomainMessengerProxy"),
            L1StandardBridge: mustGetAddress("L1StandardBridgeProxy"),
            L2OutputOracle: mustGetAddress("L2OutputOracleProxy"),
            DisputeGameFactory: getAddress("DisputeGameFactoryProxy"),
            DelayedWETH: getAddress("DelayedWETHProxy"),
            PermissionedDelayedWETH: getAddress("PermissionedDelayedWETHProxy"),
            AnchorStateRegistry: getAddress("AnchorStateRegistryProxy"),
            OptimismMintableERC20Factory: getAddress("OptimismMintableERC20FactoryProxy"),
            OptimismPortal: mustGetAddress("OptimismPortalProxy"),
            OptimismPortal2: getAddress("OptimismPortalProxy"),
            SystemConfig: mustGetAddress("SystemConfigProxy"),
            L1ERC721Bridge: getAddress("L1ERC721BridgeProxy"),
            ProtocolVersions: getAddress("ProtocolVersionsProxy"),
            SuperchainConfig: mustGetAddress("SuperchainConfigProxy")
        });
    }

    /// @notice Returns the proxy addresses, not reverting if any are unset.
    function _proxiesUnstrict() internal view returns (Types.ContractSet memory proxies_) {
        proxies_ = Types.ContractSet({
            L1CrossDomainMessenger: getAddress("L1CrossDomainMessengerProxy"),
            L1StandardBridge: getAddress("L1StandardBridgeProxy"),
            L2OutputOracle: getAddress("L2OutputOracleProxy"),
            DisputeGameFactory: getAddress("DisputeGameFactoryProxy"),
            DelayedWETH: getAddress("DelayedWETHProxy"),
            PermissionedDelayedWETH: getAddress("PermissionedDelayedWETHProxy"),
            AnchorStateRegistry: getAddress("AnchorStateRegistryProxy"),
            OptimismMintableERC20Factory: getAddress("OptimismMintableERC20FactoryProxy"),
            OptimismPortal: getAddress("OptimismPortalProxy"),
            OptimismPortal2: getAddress("OptimismPortalProxy"),
            SystemConfig: getAddress("SystemConfigProxy"),
            L1ERC721Bridge: getAddress("L1ERC721BridgeProxy"),
            ProtocolVersions: getAddress("ProtocolVersionsProxy"),
            SuperchainConfig: getAddress("SuperchainConfigProxy")
        });
    }

    ////////////////////////////////////////////////////////////////
    //            State Changing Helper Functions                 //
    ////////////////////////////////////////////////////////////////

    /// @notice Gets the address of the SafeProxyFactory and Safe singleton for use in deploying a new GnosisSafe.
    function _getSafeFactory() internal returns (SafeProxyFactory safeProxyFactory_, Safe safeSingleton_) {
        if (getAddress("SafeProxyFactory") != address(0)) {
            // The SafeProxyFactory is already saved, we can just use it.
            safeProxyFactory_ = SafeProxyFactory(getAddress("SafeProxyFactory"));
            safeSingleton_ = Safe(getAddress("SafeSingleton"));
            return (safeProxyFactory_, safeSingleton_);
        }

        // These are the standard create2 deployed contracts. First we'll check if they are deployed,
        // if not we'll deploy new ones, though not at these addresses.
        address safeProxyFactory = 0xa6B71E26C5e0845f74c812102Ca7114b6a896AB2;
        address safeSingleton = 0xd9Db270c1B5E3Bd161E8c8503c55cEABeE709552;

        safeProxyFactory.code.length == 0
            ? safeProxyFactory_ = new SafeProxyFactory()
            : safeProxyFactory_ = SafeProxyFactory(safeProxyFactory);

        safeSingleton.code.length == 0 ? safeSingleton_ = new Safe() : safeSingleton_ = Safe(payable(safeSingleton));

        save("SafeProxyFactory", address(safeProxyFactory_));
        save("SafeSingleton", address(safeSingleton_));
    }

    /// @notice Make a call from the Safe contract to an arbitrary address with arbitrary data
    function _callViaSafe(Safe _safe, address _target, bytes memory _data) internal {
        // This is the signature format used when the caller is also the signer.
        bytes memory signature = abi.encodePacked(uint256(uint160(msg.sender)), bytes32(0), uint8(1));

        _safe.execTransaction({
            to: _target,
            value: 0,
            data: _data,
            operation: SafeOps.Operation.Call,
            safeTxGas: 0,
            baseGas: 0,
            gasPrice: 0,
            gasToken: address(0),
            refundReceiver: payable(address(0)),
            signatures: signature
        });
    }

    /// @notice Call from the Safe contract to the Proxy Admin's upgrade and call method
    function _upgradeAndCallViaSafe(address _proxy, address _implementation, bytes memory _innerCallData) internal {
        address proxyAdmin = mustGetAddress("ProxyAdmin");

        bytes memory data =
            abi.encodeCall(ProxyAdmin.upgradeAndCall, (payable(_proxy), _implementation, _innerCallData));

        Safe safe = Safe(mustGetAddress("SystemOwnerSafe"));
        _callViaSafe({ _safe: safe, _target: proxyAdmin, _data: data });
    }

    /// @notice Transfer ownership of the ProxyAdmin contract to the final system owner
    function transferProxyAdminOwnership() public broadcast {
        ProxyAdmin proxyAdmin = ProxyAdmin(mustGetAddress("ProxyAdmin"));
        address owner = proxyAdmin.owner();
        address safe = mustGetAddress("SystemOwnerSafe");
        if (owner != safe) {
            proxyAdmin.transferOwnership(safe);
            console.log("ProxyAdmin ownership transferred to Safe at: %s", safe);
        }
    }

    /// @notice Transfer ownership of a Proxy to the ProxyAdmin contract
    ///         This is expected to be used in conjusting with deployERC1967ProxyWithOwner after setup actions
    ///         have been performed on the proxy.
    /// @param _name The name of the proxy to transfer ownership of.
    function transferProxyToProxyAdmin(string memory _name) public broadcast {
        Proxy proxy = Proxy(mustGetAddress(_name));
        address proxyAdmin = mustGetAddress("ProxyAdmin");
        proxy.changeAdmin(proxyAdmin);
        console.log("Proxy %s ownership transferred to ProxyAdmin at: %s", _name, proxyAdmin);
    }

    ////////////////////////////////////////////////////////////////
    //                    SetUp and Run                           //
    ////////////////////////////////////////////////////////////////

    /// @notice Deploy all of the L1 contracts necessary for a full Superchain with a single Op Chain.
    function run() public {
        console.log("Deploying a fresh OP Stack including SuperchainConfig");
        _run();
    }

    function runWithStateDump() public {
        vm.chainId(cfg.l1ChainID());
        _run();
        vm.dumpState(Config.stateDumpPath(""));
    }

    /// @notice Deploy all L1 contracts and write the state diff to a file.
    function runWithStateDiff() public stateDiff {
        _run();
    }

    /// @notice Internal function containing the deploy logic.
    function _run() internal virtual {
        console.log("start of L1 Deploy!");
        deploySafe("SystemOwnerSafe");
        console.log("deployed Safe!");
        setupSuperchain();
        console.log("set up superchain!");
        setupOpChain();
        console.log("set up op chain!");
    }

    ////////////////////////////////////////////////////////////////
    //           High Level Deployment Functions                  //
    ////////////////////////////////////////////////////////////////

    /// @notice Deploy a full system with a new SuperchainConfig
    ///         The Superchain system has 2 singleton contracts which lie outside of an OP Chain:
    ///         1. The SuperchainConfig contract
    ///         2. The ProtocolVersions contract
    function setupSuperchain() public {
        console.log("Setting up Superchain");

        // Deploy a new ProxyAdmin and AddressManager
        // This proxy will be used on the SuperchainConfig and ProtocolVersions contracts, as well as the contracts
        // in the OP Chain system.
        deployAddressManager();
        deployProxyAdmin();
        transferProxyAdminOwnership();

        // Deploy the SuperchainConfigProxy
        deployERC1967Proxy("SuperchainConfigProxy");
        deploySuperchainConfig();
        initializeSuperchainConfig();
    }

    /// @notice Deploy a new OP Chain, with an existing SuperchainConfig provided
    function setupOpChain() public {
        console.log("Deploying OP Chain");

        // Ensure that the requisite contracts are deployed
        mustGetAddress("SuperchainConfigProxy");
        mustGetAddress("SystemOwnerSafe");
        mustGetAddress("AddressManager");
        mustGetAddress("ProxyAdmin");

        deployProxies();
        deployImplementations();
        initializeImplementations();
    }

    /// @notice Deploy all of the proxies
    function deployProxies() public {
        console.log("Deploying proxies");

        deployERC1967Proxy("OptimismPortalProxy");
        deployERC1967Proxy("SystemConfigProxy");
        deployL1StandardBridgeProxy();
        deployL1CrossDomainMessengerProxy();

        // Both the DisputeGameFactory and L2OutputOracle proxies are deployed regardless of whether fault proofs is
        // enabled to prevent a nastier refactor to the deploy scripts. In the future, the L2OutputOracle will be
        // removed. If fault proofs are not enabled, the DisputeGameFactory proxy will be unused.
        // deployERC1967Proxy("DisputeGameFactoryProxy");
        deployERC1967Proxy("L2OutputOracleProxy");

        transferAddressManagerOwnership(); // to the ProxyAdmin
    }

    /// @notice Deploy all of the implementations
    function deployImplementations() public {
        console.log("Deploying implementations");
        deployL1CrossDomainMessenger();
        // deployOptimismMintableERC20Factory();
        deploySystemConfig();
        deployL1StandardBridge();
        // deployL1ERC721Bridge();
        deployOptimismPortal();
        deployL2OutputOracle();
        // Fault proofs
        // deployOptimismPortal2();
        // deployDisputeGameFactory();
        // deployDelayedWETH();
        // deployPreimageOracle();
        // deployMips();
        // deployAnchorStateRegistry();
    }

    /// @notice Initialize all of the implementations
    function initializeImplementations() public {
        console.log("Initializing implementations");
        // Selectively initialize either the original OptimismPortal or the new OptimismPortal2. Since this will upgrade
        // the proxy, we cannot initialize both.
        initializeOptimismPortal();

        initializeSystemConfig();
        initializeL1StandardBridge();
        initializeL1CrossDomainMessenger();
        initializeL2OutputOracle();
    }

    ////////////////////////////////////////////////////////////////
    //              Non-Proxied Deployment Functions              //
    ////////////////////////////////////////////////////////////////

    /// @notice Deploy the Safe
    function deploySafe(string memory _name) public broadcast returns (address addr_) {
        address[] memory owners = new address[](0);
        addr_ = deploySafe(_name, owners, 1, true);
    }

    /// @notice Deploy a new Safe contract. If the keepDeployer option is used to enable further setup actions, then
    ///         the removeDeployerFromSafe() function should be called on that safe after setup is complete.
    ///         Note this function does not have the broadcast modifier.
    /// @param _name The name of the Safe to deploy.
    /// @param _owners The owners of the Safe.
    /// @param _threshold The threshold of the Safe.
    /// @param _keepDeployer Wether or not the deployer address will be added as an owner of the Safe.
    function deploySafe(
        string memory _name,
        address[] memory _owners,
        uint256 _threshold,
        bool _keepDeployer
    )
        public
        returns (address addr_)
    {
        bytes32 salt = keccak256(abi.encode(_name, _implSalt()));
        console.log("Deploying safe: %s with salt %s", _name, vm.toString(salt));
        (SafeProxyFactory safeProxyFactory, Safe safeSingleton) = _getSafeFactory();

        if (_keepDeployer) {
            address[] memory expandedOwners = new address[](_owners.length + 1);
            // By always adding msg.sender first we know that the previousOwner will be SENTINEL_OWNERS, which makes it
            // easier to call removeOwner later.
            expandedOwners[0] = msg.sender;
            for (uint256 i = 0; i < _owners.length; i++) {
                expandedOwners[i + 1] = _owners[i];
            }
            _owners = expandedOwners;
        }

        bytes memory initData = abi.encodeCall(
            Safe.setup, (_owners, _threshold, address(0), hex"", address(0), address(0), 0, payable(address(0)))
        );
        addr_ = address(safeProxyFactory.createProxyWithNonce(address(safeSingleton), initData, uint256(salt)));

        save(_name, addr_);
        console.log("New safe: %s deployed at %s\n    Note that this safe is owned by the deployer key", _name, addr_);
    }

    /// @notice If the keepDeployer option was used with deploySafe(), this function can be used to remove the deployer.
    ///         Note this function does not have the broadcast modifier.
    function removeDeployerFromSafe(string memory _name, uint256 _newThreshold) public {
        Safe safe = Safe(mustGetAddress(_name));

        // The sentinel address is used to mark the start and end of the linked list of owners in the Safe.
        address sentinelOwners = address(0x1);

        // Because deploySafe() always adds msg.sender first (if keepDeployer is true), we know that the previousOwner
        // will be sentinelOwners.
        _callViaSafe({
            _safe: safe,
            _target: address(safe),
            _data: abi.encodeCall(OwnerManager.removeOwner, (sentinelOwners, msg.sender, _newThreshold))
        });
        console.log("Removed deployer owner from ", _name);
    }

    /// @notice Deploy the AddressManager
    function deployAddressManager() public broadcast returns (address addr_) {
        console.log("Deploying AddressManager");
        AddressManager manager = new AddressManager();
        require(manager.owner() == msg.sender);

        save("AddressManager", address(manager));
        console.log("AddressManager deployed at %s", address(manager));
        addr_ = address(manager);
    }

    /// @notice Deploy the ProxyAdmin
    function deployProxyAdmin() public broadcast returns (address addr_) {
        console.log("Deploying ProxyAdmin");
        ProxyAdmin admin = new ProxyAdmin({ _owner: msg.sender });
        require(admin.owner() == msg.sender);

        AddressManager addressManager = AddressManager(mustGetAddress("AddressManager"));
        if (admin.addressManager() != addressManager) {
            admin.setAddressManager(addressManager);
        }

        require(admin.addressManager() == addressManager);

        save("ProxyAdmin", address(admin));
        console.log("ProxyAdmin deployed at %s", address(admin));
        addr_ = address(admin);
    }

    ////////////////////////////////////////////////////////////////
    //                Proxy Deployment Functions                  //
    ////////////////////////////////////////////////////////////////

    /// @notice Deploy the L1StandardBridgeProxy using a ChugSplashProxy
    function deployL1StandardBridgeProxy() public broadcast returns (address addr_) {
        console.log("Deploying proxy for L1StandardBridge");
        address proxyAdmin = mustGetAddress("ProxyAdmin");
        L1ChugSplashProxy proxy = new L1ChugSplashProxy(proxyAdmin);

        require(EIP1967Helper.getAdmin(address(proxy)) == proxyAdmin);

        save("L1StandardBridgeProxy", address(proxy));
        console.log("L1StandardBridgeProxy deployed at %s", address(proxy));
        addr_ = address(proxy);
    }

    /// @notice Deploy the L1CrossDomainMessengerProxy using a ResolvedDelegateProxy
    function deployL1CrossDomainMessengerProxy() public broadcast returns (address addr_) {
        console.log("Deploying proxy for L1CrossDomainMessenger");
        AddressManager addressManager = AddressManager(mustGetAddress("AddressManager"));
        ResolvedDelegateProxy proxy = new ResolvedDelegateProxy(addressManager, "OVM_L1CrossDomainMessenger");

        save("L1CrossDomainMessengerProxy", address(proxy));
        console.log("L1CrossDomainMessengerProxy deployed at %s", address(proxy));

        addr_ = address(proxy);
    }

    /// @notice Deploys an ERC1967Proxy contract with the ProxyAdmin as the owner.
    /// @param _name The name of the proxy contract to be deployed.
    /// @return addr_ The address of the deployed proxy contract.
    function deployERC1967Proxy(string memory _name) public returns (address addr_) {
        addr_ = deployERC1967ProxyWithOwner(_name, mustGetAddress("ProxyAdmin"));
    }

    /// @notice Deploys an ERC1967Proxy contract with a specified owner.
    /// @param _name The name of the proxy contract to be deployed.
    /// @param _proxyOwner The address of the owner of the proxy contract.
    /// @return addr_ The address of the deployed proxy contract.
    function deployERC1967ProxyWithOwner(
        string memory _name,
        address _proxyOwner
    )
        public
        broadcast
        returns (address addr_)
    {
        console.log(string.concat("Deploying ERC1967 proxy for ", _name));
        Proxy proxy = new Proxy({ _admin: _proxyOwner });

        require(EIP1967Helper.getAdmin(address(proxy)) == _proxyOwner);

        save(_name, address(proxy));
        console.log("   at %s", address(proxy));
        addr_ = address(proxy);
    }

    ////////////////////////////////////////////////////////////////
    //             Implementation Deployment Functions            //
    ////////////////////////////////////////////////////////////////

    /// @notice Deploy the SuperchainConfig contract
    function deploySuperchainConfig() public broadcast {
        SuperchainConfig superchainConfig = new SuperchainConfig{ salt: _implSalt() }();

        require(superchainConfig.guardian() == address(0));
        bytes32 initialized = vm.load(address(superchainConfig), bytes32(0));
        require(initialized != 0);

        save("SuperchainConfig", address(superchainConfig));
        console.log("SuperchainConfig deployed at %s", address(superchainConfig));
    }

    /// @notice Deploy the L1CrossDomainMessenger
    function deployL1CrossDomainMessenger() public broadcast returns (address addr_) {
        console.log("Deploying L1CrossDomainMessenger implementation");
        L1CrossDomainMessenger messenger = new L1CrossDomainMessenger{ salt: _implSalt() }();

        save("L1CrossDomainMessenger", address(messenger));
        console.log("L1CrossDomainMessenger deployed at %s", address(messenger));

        // Override the `L1CrossDomainMessenger` contract to the deployed implementation. This is necessary
        // to check the `L1CrossDomainMessenger` implementation alongside dependent contracts, which
        // are always proxies.
        Types.ContractSet memory contracts = _proxiesUnstrict();
        contracts.L1CrossDomainMessenger = address(messenger);

        addr_ = address(messenger);
    }

    /// @notice Deploy the OptimismPortal
    function deployOptimismPortal() public broadcast returns (address addr_) {
        console.log("Deploying OptimismPortal implementation");
        if (cfg.useInterop()) {
            console.log("Attempting to deploy OptimismPortal with interop, this config is a noop");
        }
        addr_ = address(new OptimismPortal{ salt: _implSalt() }());
        save("OptimismPortal", addr_);
        console.log("OptimismPortal deployed at %s", addr_);

        // Override the `OptimismPortal` contract to the deployed implementation. This is necessary
        // to check the `OptimismPortal` implementation alongside dependent contracts, which
        // are always proxies.
        Types.ContractSet memory contracts = _proxiesUnstrict();
        contracts.OptimismPortal = addr_;
        ChainAssertions.checkOptimismPortal({ _contracts: contracts, _cfg: cfg, _isProxy: false });
    }

    /// @notice Deploy the L2OutputOracle
    function deployL2OutputOracle() public broadcast returns (address addr_) {
        console.log("Deploying L2OutputOracle implementation");
        L2OutputOracle oracle = new L2OutputOracle{ salt: _implSalt() }();

        save("L2OutputOracle", address(oracle));
        console.log("L2OutputOracle deployed at %s", address(oracle));

        // Override the `L2OutputOracle` contract to the deployed implementation. This is necessary
        // to check the `L2OutputOracle` implementation alongside dependent contracts, which
        // are always proxies.
        Types.ContractSet memory contracts = _proxiesUnstrict();
        contracts.L2OutputOracle = address(oracle);
        ChainAssertions.checkL2OutputOracle({
            _contracts: contracts,
            _cfg: cfg,
            _l2OutputOracleStartingTimestamp: 0,
            _isProxy: false
        });

        addr_ = address(oracle);
    }

    /// @notice Deploy the SystemConfig
    function deploySystemConfig() public broadcast returns (address addr_) {
        console.log("Deploying SystemConfig implementation");
        if (cfg.useInterop()) {
            addr_ = address(new SystemConfigInterop{ salt: _implSalt() }());
        } else {
            addr_ = address(new SystemConfig{ salt: _implSalt() }());
        }
        save("SystemConfig", addr_);
        console.log("SystemConfig deployed at %s", addr_);

        // Override the `SystemConfig` contract to the deployed implementation. This is necessary
        // to check the `SystemConfig` implementation alongside dependent contracts, which
        // are always proxies.
        Types.ContractSet memory contracts = _proxiesUnstrict();
        contracts.SystemConfig = addr_;
        ChainAssertions.checkSystemConfig({ _contracts: contracts, _cfg: cfg, _isProxy: false });
    }

    /// @notice Deploy the L1StandardBridge
    function deployL1StandardBridge() public broadcast returns (address addr_) {
        console.log("Deploying L1StandardBridge implementation");

        L1StandardBridge bridge = new L1StandardBridge{ salt: _implSalt() }();

        save("L1StandardBridge", address(bridge));
        console.log("L1StandardBridge deployed at %s", address(bridge));

        // Override the `L1StandardBridge` contract to the deployed implementation. This is necessary
        // to check the `L1StandardBridge` implementation alongside dependent contracts, which
        // are always proxies.
        Types.ContractSet memory contracts = _proxiesUnstrict();
        contracts.L1StandardBridge = address(bridge);

        addr_ = address(bridge);
    }

    /// @notice Transfer ownership of the address manager to the ProxyAdmin
    function transferAddressManagerOwnership() public broadcast {
        console.log("Transferring AddressManager ownership to ProxyAdmin");
        AddressManager addressManager = AddressManager(mustGetAddress("AddressManager"));
        address owner = addressManager.owner();
        address proxyAdmin = mustGetAddress("ProxyAdmin");
        if (owner != proxyAdmin) {
            addressManager.transferOwnership(proxyAdmin);
            console.log("AddressManager ownership transferred to %s", proxyAdmin);
        }

        require(addressManager.owner() == proxyAdmin);
    }

    ////////////////////////////////////////////////////////////////
    //                    Initialize Functions                    //
    ////////////////////////////////////////////////////////////////

    /// @notice Initialize the SuperchainConfig
    function initializeSuperchainConfig() public broadcast {
        address payable superchainConfigProxy = mustGetAddress("SuperchainConfigProxy");
        address payable superchainConfig = mustGetAddress("SuperchainConfig");
        _upgradeAndCallViaSafe({
            _proxy: superchainConfigProxy,
            _implementation: superchainConfig,
            _innerCallData: abi.encodeCall(SuperchainConfig.initialize, (cfg.superchainConfigGuardian(), false))
        });

        ChainAssertions.checkSuperchainConfig({ _contracts: _proxiesUnstrict(), _cfg: cfg, _isPaused: false });
    }

    function initializeSystemConfig() public broadcast {
        console.log("Upgrading and initializing SystemConfig proxy");
        address systemConfigProxy = mustGetAddress("SystemConfigProxy");
        address systemConfig = mustGetAddress("SystemConfig");

        bytes32 batcherHash = bytes32(uint256(uint160(cfg.batchSenderAddress())));

        address customGasTokenAddress = Constants.ETHER;
        if (cfg.useCustomGasToken()) {
            customGasTokenAddress = cfg.customGasTokenAddress();
        }

        _upgradeAndCallViaSafe({
            _proxy: payable(systemConfigProxy),
            _implementation: systemConfig,
            _innerCallData: abi.encodeCall(
                SystemConfig.initialize,
                (
                    cfg.finalSystemOwner(),
                    cfg.basefeeScalar(),
                    cfg.blobbasefeeScalar(),
                    batcherHash,
                    uint64(cfg.l2GenesisBlockGasLimit()),
                    cfg.p2pSequencerAddress(),
                    Constants.DEFAULT_RESOURCE_CONFIG(),
                    cfg.batchInboxAddress(),
                    SystemConfig.Addresses({
                        l1CrossDomainMessenger: mustGetAddress("L1CrossDomainMessengerProxy"),
                        l1ERC721Bridge: getAddress("L1ERC721BridgeProxy"),
                        l1StandardBridge: mustGetAddress("L1StandardBridgeProxy"),
                        disputeGameFactory: getAddress("DisputeGameFactoryProxy"),
                        optimismPortal: mustGetAddress("OptimismPortalProxy"),
                        optimismMintableERC20Factory: getAddress("OptimismMintableERC20FactoryProxy"),
                        gasPayingToken: customGasTokenAddress
                    })
                )
            )
        });

        SystemConfig config = SystemConfig(systemConfigProxy);
        string memory version = config.version();
        console.log("SystemConfig version: %s", version);

        ChainAssertions.checkSystemConfig({ _contracts: _proxies(), _cfg: cfg, _isProxy: true });
    }

    /// @notice Initialize the L1StandardBridge
    function initializeL1StandardBridge() public broadcast {
        console.log("Upgrading and initializing L1StandardBridge proxy");
        ProxyAdmin proxyAdmin = ProxyAdmin(mustGetAddress("ProxyAdmin"));
        address l1StandardBridgeProxy = mustGetAddress("L1StandardBridgeProxy");
        address l1StandardBridge = mustGetAddress("L1StandardBridge");
        address l1CrossDomainMessengerProxy = mustGetAddress("L1CrossDomainMessengerProxy");
        address superchainConfigProxy = mustGetAddress("SuperchainConfigProxy");
        address systemConfigProxy = mustGetAddress("SystemConfigProxy");

        uint256 proxyType = uint256(proxyAdmin.proxyType(l1StandardBridgeProxy));
        Safe safe = Safe(mustGetAddress("SystemOwnerSafe"));
        if (proxyType != uint256(ProxyAdmin.ProxyType.CHUGSPLASH)) {
            _callViaSafe({
                _safe: safe,
                _target: address(proxyAdmin),
                _data: abi.encodeCall(ProxyAdmin.setProxyType, (l1StandardBridgeProxy, ProxyAdmin.ProxyType.CHUGSPLASH))
            });
        }
        require(uint256(proxyAdmin.proxyType(l1StandardBridgeProxy)) == uint256(ProxyAdmin.ProxyType.CHUGSPLASH));

        _upgradeAndCallViaSafe({
            _proxy: payable(l1StandardBridgeProxy),
            _implementation: l1StandardBridge,
            _innerCallData: abi.encodeCall(
                L1StandardBridge.initialize,
                (
                    L1CrossDomainMessenger(l1CrossDomainMessengerProxy),
                    SuperchainConfig(superchainConfigProxy),
                    SystemConfig(systemConfigProxy),
                    StandardBridge(payable(vm.envAddress("L2StandardBridge")))
                )
            )
        });

        string memory version = L1StandardBridge(payable(l1StandardBridgeProxy)).version();
        console.log("L1StandardBridge version: %s", version);
    }

    /// @notice initializeL1CrossDomainMessenger
    function initializeL1CrossDomainMessenger() public broadcast {
        console.log("Upgrading and initializing L1CrossDomainMessenger proxy");
        ProxyAdmin proxyAdmin = ProxyAdmin(mustGetAddress("ProxyAdmin"));
        address l1CrossDomainMessengerProxy = mustGetAddress("L1CrossDomainMessengerProxy");
        address l1CrossDomainMessenger = mustGetAddress("L1CrossDomainMessenger");
        address superchainConfigProxy = mustGetAddress("SuperchainConfigProxy");
        address optimismPortalProxy = mustGetAddress("OptimismPortalProxy");
        address systemConfigProxy = mustGetAddress("SystemConfigProxy");

        uint256 proxyType = uint256(proxyAdmin.proxyType(l1CrossDomainMessengerProxy));
        Safe safe = Safe(mustGetAddress("SystemOwnerSafe"));
        if (proxyType != uint256(ProxyAdmin.ProxyType.RESOLVED)) {
            _callViaSafe({
                _safe: safe,
                _target: address(proxyAdmin),
                _data: abi.encodeCall(ProxyAdmin.setProxyType, (l1CrossDomainMessengerProxy, ProxyAdmin.ProxyType.RESOLVED))
            });
        }
        require(uint256(proxyAdmin.proxyType(l1CrossDomainMessengerProxy)) == uint256(ProxyAdmin.ProxyType.RESOLVED));

        string memory contractName = "OVM_L1CrossDomainMessenger";
        string memory implName = proxyAdmin.implementationName(l1CrossDomainMessenger);
        if (keccak256(bytes(contractName)) != keccak256(bytes(implName))) {
            _callViaSafe({
                _safe: safe,
                _target: address(proxyAdmin),
                _data: abi.encodeCall(ProxyAdmin.setImplementationName, (l1CrossDomainMessengerProxy, contractName))
            });
        }
        require(
            keccak256(bytes(proxyAdmin.implementationName(l1CrossDomainMessengerProxy)))
                == keccak256(bytes(contractName))
        );

        _upgradeAndCallViaSafe({
            _proxy: payable(l1CrossDomainMessengerProxy),
            _implementation: l1CrossDomainMessenger,
            _innerCallData: abi.encodeCall(
                L1CrossDomainMessenger.initialize,
                (
                    SuperchainConfig(superchainConfigProxy),
                    OptimismPortal(payable(optimismPortalProxy)),
                    SystemConfig(systemConfigProxy),
                    L2CrossDomainMessenger(vm.envAddress("L2CrossDomainMessenger"))
                )
            )
        });

        L1CrossDomainMessenger messenger = L1CrossDomainMessenger(l1CrossDomainMessengerProxy);
        string memory version = messenger.version();
        console.log("L1CrossDomainMessenger version: %s", version);
    }

    /// @notice Initialize the L2OutputOracle
    function initializeL2OutputOracle() public broadcast {
        console.log("Upgrading and initializing L2OutputOracle proxy");
        address l2OutputOracleProxy = mustGetAddress("L2OutputOracleProxy");
        address l2OutputOracle = mustGetAddress("L2OutputOracle");

        _upgradeAndCallViaSafe({
            _proxy: payable(l2OutputOracleProxy),
            _implementation: l2OutputOracle,
            _innerCallData: abi.encodeCall(
                L2OutputOracle.initialize,
                (
                    cfg.l2OutputOracleSubmissionInterval(),
                    cfg.l2BlockTime(),
                    cfg.l2OutputOracleStartingBlockNumber(),
                    cfg.l2OutputOracleStartingTimestamp(),
                    cfg.l2OutputOracleProposer(),
                    cfg.l2OutputOracleChallenger(),
                    cfg.finalizationPeriodSeconds()
                )
            )
        });

        L2OutputOracle oracle = L2OutputOracle(l2OutputOracleProxy);
        string memory version = oracle.version();
        console.log("L2OutputOracle version: %s", version);

        ChainAssertions.checkL2OutputOracle({
            _contracts: _proxies(),
            _cfg: cfg,
            _l2OutputOracleStartingTimestamp: cfg.l2OutputOracleStartingTimestamp(),
            _isProxy: true
        });
    }

    /// @notice Initialize the OptimismPortal
    function initializeOptimismPortal() public broadcast {
        console.log("Upgrading and initializing OptimismPortal proxy");
        address optimismPortalProxy = mustGetAddress("OptimismPortalProxy");
        address optimismPortal = mustGetAddress("OptimismPortal");
        address l2OutputOracleProxy = mustGetAddress("L2OutputOracleProxy");
        address systemConfigProxy = mustGetAddress("SystemConfigProxy");
        address superchainConfigProxy = mustGetAddress("SuperchainConfigProxy");

        _upgradeAndCallViaSafe({
            _proxy: payable(optimismPortalProxy),
            _implementation: optimismPortal,
            _innerCallData: abi.encodeCall(
                OptimismPortal.initialize,
                (
                    L2OutputOracle(l2OutputOracleProxy),
                    SystemConfig(systemConfigProxy),
                    SuperchainConfig(superchainConfigProxy)
                )
            )
        });

        OptimismPortal portal = OptimismPortal(payable(optimismPortalProxy));
        string memory version = portal.version();
        console.log("OptimismPortal version: %s", version);

        ChainAssertions.checkOptimismPortal({ _contracts: _proxies(), _cfg: cfg, _isProxy: true });
    }
}
