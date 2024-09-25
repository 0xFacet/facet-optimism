// SPDX-License-Identifier: MIT
pragma solidity 0.8.15;

import { LibFacet } from "../src/libraries/LibFacet.sol";

abstract contract FoundryFacetSender {
    function sendFacetTransactionFoundry(
        bytes memory to,
        uint256 value,
        uint256 maxFeePerGas,
        uint256 gasLimit,
        bytes memory data
    ) internal {
        bytes memory payload = LibFacet.prepareFacetTransaction(
            to,
            value,
            maxFeePerGas,
            gasLimit,
            data
        );

        (bool success, ) = LibFacet.facetInboxAddress.call(payload);
        require(success, "Facet transaction failed");
    }

    function sendFacetTransactionFoundry(
        address to,
        uint256 value,
        uint256 maxFeePerGas,
        uint256 gasLimit,
        bytes memory data
    ) internal {
        sendFacetTransactionFoundry(abi.encodePacked(to), value, maxFeePerGas, gasLimit, data);
    }

    function sendFacetTransactionFoundry(
        uint256 value,
        uint256 maxFeePerGas,
        uint256 gasLimit,
        bytes memory data
    ) internal {
        sendFacetTransactionFoundry(bytes(''), value, maxFeePerGas, gasLimit, data);
    }

    function sendFacetTransactionFoundry(
        uint256 value,
        uint256 gasLimit,
        bytes memory data
    ) internal {
        sendFacetTransactionFoundry(bytes(''), value, 0, gasLimit, data);
    }

    function sendFacetTransactionFoundry(
        address to,
        uint256 value,
        uint256 gasLimit,
        bytes memory data
    ) internal {
        sendFacetTransactionFoundry(abi.encodePacked(to), value, 0, gasLimit, data);
    }

    function sendFacetTransactionFoundry(
        bytes memory data,
        address to,
        uint256 maxFeePerGas,
        uint256 gasLimit
    ) internal {
        sendFacetTransactionFoundry(to, 0, maxFeePerGas, gasLimit, data);
    }

    function sendFacetTransactionFoundry(
        bytes memory data,
        uint256 maxFeePerGas,
        uint256 gasLimit
    ) internal {
        sendFacetTransactionFoundry(0, maxFeePerGas, gasLimit, data);
    }

    function sendFacetTransactionFoundry(
        uint256 gasLimit,
        bytes memory data
    ) internal {
        sendFacetTransactionFoundry(bytes(''), 0, 0, gasLimit, data);
    }

    function sendFacetTransactionFoundry(
        address to,
        uint256 gasLimit,
        bytes memory data
    ) internal {
        sendFacetTransactionFoundry(to, 0, gasLimit, data);
    }
}
