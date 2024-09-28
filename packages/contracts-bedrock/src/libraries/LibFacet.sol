// SPDX-License-Identifier: MIT
pragma solidity ^0.8.15;

import { LibString } from "@solady/utils/LibString.sol";
import { LibRLP } from "./LibRLP.sol";
import "forge-std/console2.sol";

library LibFacet {
    using LibRLP for LibRLP.List;

    address constant facetInboxAddress = 0x00000000000000000000000000000000000FacE7;
    bytes32 constant facetEventSignature = 0x00000000000000000000000000000000000000000000000000000000000face7;
    uint8 constant facetTxType = 0x46;

    function sendFacetTransaction(
        address to,
        uint256 value,
        uint256 maxFeePerGas,
        uint256 gasLimit,
        bytes memory data
    ) internal {
        sendFacetTransaction(abi.encodePacked(to), value, maxFeePerGas, gasLimit, data);
    }

    function sendFacetTransaction(
        uint256 value,
        uint256 maxFeePerGas,
        uint256 gasLimit,
        bytes memory data
    ) internal {
        sendFacetTransaction(bytes(''), value, maxFeePerGas, gasLimit, data);
    }

    function sendFacetTransaction(
        uint256 value,
        uint256 gasLimit,
        bytes memory data
    ) internal {
        sendFacetTransaction(bytes(''), value, 0, gasLimit, data);
    }

    function sendFacetTransaction(
        address to,
        uint256 value,
        uint256 gasLimit,
        bytes memory data
    ) internal {
        sendFacetTransaction(abi.encodePacked(to), value, 0, gasLimit, data);
    }

    function sendFacetTransaction(
        bytes memory data,
        address to,
        uint256 maxFeePerGas,
        uint256 gasLimit
    ) internal {
        sendFacetTransaction(to, 0, maxFeePerGas, gasLimit, data);
    }

    // Overload for sendFacetTransaction without 'to' and without value
    function sendFacetTransaction(
        bytes memory data,
        uint256 maxFeePerGas,
        uint256 gasLimit
    ) internal {
        sendFacetTransaction(0, maxFeePerGas, gasLimit, data);
    }

    // Overload for sendFacetTransaction without 'to', 'value', and 'maxFeePerGas'
    function sendFacetTransaction(
        uint256 gasLimit,
        bytes memory data
    ) internal {
        sendFacetTransaction(bytes(''), 0, 0, gasLimit, data);
    }

    // Overload for sendFacetTransaction with address, without value and maxFeePerGas
    function sendFacetTransaction(
        address to,
        uint256 gasLimit,
        bytes memory data
    ) internal {
        sendFacetTransaction(to, 0, gasLimit, data);
    }

    function prepareFacetTransaction(
        bytes memory to,
        uint256 value,
        uint256 maxFeePerGas,
        uint256 gasLimit,
        bytes memory data
    ) internal view returns (bytes memory) {
        uint256 chainId;

        if (block.chainid == 1) {
            chainId = 0xface7;
        } else if (block.chainid == 11155111) {
            chainId = 0xface7a;
        } else {
            revert("Unsupported chainId");
        }

        LibRLP.List memory list;

        list.p(chainId);
        list.p(to);
        list.p(value);
        list.p(maxFeePerGas);
        list.p(gasLimit);
        list.p(data);

        return abi.encodePacked(facetTxType, list.encode());
    }

    function sendFacetTransaction(
        bytes memory to,
        uint256 value,
        uint256 maxFeePerGas,
        uint256 gasLimit,
        bytes memory data
    ) internal {
        bytes memory payload = prepareFacetTransaction(to, value, maxFeePerGas, gasLimit, data);

        assembly {
            log1(add(payload, 32), mload(payload), facetEventSignature)
        }
    }
    
    function saferSendFacetTransaction(
        bytes memory to,
        uint256 value,
        uint256 maxFeePerGas,
        uint256 gasLimit,
        bytes memory data
    ) internal {
        if (alreadyCalled()) {
            revert("Already called");
        }

        sendFacetTransaction(to, value, maxFeePerGas, gasLimit, data);
    }
    
    bytes32 constant perTxNonceSlot = 0x921b3be6b4a61c5e824a33c83976193e48fd69e9fb9b930d3253f0536a64e84b;
    
    function alreadyCalled() internal view returns (bool) {
        uint256 value;
        uint256 gasBefore = gasleft();

        assembly {
            value := sload(perTxNonceSlot)
        }

        uint256 gasAfter = gasleft();
        uint256 gasUsed = gasBefore - gasAfter;

        if (gasUsed == 117) {
            return true;
        } else if (gasUsed == 2117) {
            return false;
        } else {
            revert(string.concat("Invalid gasUsed: ", LibString.toString(gasUsed)));
        }
    }
}
