// SPDX-License-Identifier: MIT
pragma solidity 0.8.15;

import { WETH98 } from "src/dispute/weth/WETH98.sol";
import { ISemver } from "src/universal/ISemver.sol";

/// @title WETH contract that reads the name and symbol from the L1Block contract.
///        Allows for nice rendering of token names for chains using custom gas token.
contract WFCT is WETH98, ISemver {
    /// @custom:semver 1.0.0
    string public constant version = "1.0.0";

    function name() external pure override returns (string memory) {
        return "Wrapped Facet Compute Token";
    }

    function symbol() external pure override returns (string memory) {
        return "WFCT";
    }
}
