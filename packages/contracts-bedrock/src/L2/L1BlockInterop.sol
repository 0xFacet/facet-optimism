// SPDX-License-Identifier: MIT
pragma solidity 0.8.15;

import { L1Block } from "src/L2/L1Block.sol";
import { EnumerableSetLib } from "@solady/utils/EnumerableSetLib.sol";

/// @notice Thrown when a non-depositor account attempts to set L1 block values.
error NotDepositor();

/// @notice Thrown when dependencySetSize does not match the length of the dependency set.
error DependencySetSizeMismatch();

/// @notice Error when a chain ID is not in the interop dependency set.
error NotDependency();

/// @notice Enum representing different types of configurations that can be set on L1Block.
/// @custom:value GAS_PAYING_TOKEN   Represents the config type for the gas paying token.
/// @custom:value ADD_DEPENDENCY     Represents the config type for adding a chain to the interchain dependency set.
/// @custom:value REMOVE_DEPENDENCY  Represents the config type for removing a chain from the interchain dependency set.
enum ConfigType {
    GAS_PAYING_TOKEN,
    ADD_DEPENDENCY,
    REMOVE_DEPENDENCY
}

/// @custom:proxied
/// @custom:predeploy 0x4200000000000000000000000000000000000015
/// @title L1BlockInterop
/// @notice Interop extenstions of L1Block.
contract L1BlockInterop is L1Block {
    using EnumerableSetLib for EnumerableSetLib.Uint256Set;

    /// @notice Event emitted when a new dependency is added to the interop dependency set.
    event DependencyAdded(uint256 indexed chainId);

    /// @notice Event emitted when a dependency is removed from the interop dependency set.
    event DependencyRemoved(uint256 indexed chainId);

    /// @notice The interop dependency set, containing the chain IDs in it.
    EnumerableSetLib.Uint256Set public dependencySet;

    /// @custom:semver 1.4.0+interop
    function version() public pure override returns (string memory) {
        return string.concat(super.version(), "+interop");
    }

    /// @notice Returns true if a chain ID is in the interop dependency set and false otherwise.
    ///         The chain's chain ID is always considered to be in the dependency set.
    /// @param _chainId The chain ID to check.
    /// @return True if the chain ID to check is in the interop dependency set. False otherwise.
    function isInDependencySet(uint256 _chainId) public view returns (bool) {
        return _chainId == block.chainid || dependencySet.contains(_chainId);
    }

    /// @notice Returns the size of the interop dependency set.
    /// @return The size of the interop dependency set.
    function dependencySetSize() external view returns (uint8) {
        return uint8(dependencySet.length());
    }

    /// @notice Sets static configuration options for the L2 system. Can only be called by the special
    ///         depositor account.
    /// @param _type  The type of configuration to set.
    /// @param _value The encoded value with which to set the configuration.
    function setConfig(ConfigType _type, bytes calldata _value) external {
        if (msg.sender != DEPOSITOR_ACCOUNT()) revert NotDepositor();

        // For ADD_DEPENDENCY config type
        if (_type == ConfigType.ADD_DEPENDENCY) {
            uint256 chainId = abi.decode(_value, (uint256));

            dependencySet.add(chainId);

            emit DependencyAdded(chainId);
            return;
        }

        // For REMOVE_DEPENDENCY config type
        if (_type == ConfigType.REMOVE_DEPENDENCY) {
            uint256 chainId = abi.decode(_value, (uint256));

            if (!dependencySet.remove(chainId)) revert NotDependency();
        }
    }
}
