// SPDX-License-Identifier: BSD-3-Clause-Clear
pragma solidity ^0.8.4;

import {DataAttestation} from "./DataAttestor.sol";
import {CallbackConsumer} from "../../src/consumer/Callback.sol";

/// @title BalanceScale
/// @notice E2E developer demo of a balance scale prediction contract
/// @dev Uses simple model trained on UCI balance scale data: https://archive.ics.uci.edu/dataset/12/balance+scale
contract BalanceScale is CallbackConsumer {
    /*//////////////////////////////////////////////////////////////
                               IMMUTABLE
    //////////////////////////////////////////////////////////////*/

    /// @notice EZKL verifier contract address
    address internal immutable VERIFIER;

    /// @notice EZKL attestor contract
    DataAttestation internal immutable ATTESTOR;

    /*//////////////////////////////////////////////////////////////
                                MUTABLE
    //////////////////////////////////////////////////////////////*/

    /// @notice Data currently being verified
    /// @dev Used atomically in `_receiveCompute()` callback to remove need for dynamic loading in attestor contract
    int256[4] public currentData;

    /// @notice Subscription ID => associated balance scale weights
    /// @dev format: [right-distance, right-weight, left-distance, left-weight]
    mapping(uint32 => int256[4]) public data;

    /// @notice SubscriptionID => returned prediction output
    /// @dev 0 = scale tipped left, 1 = scale tipped right, 2 = balanced
    mapping(uint32 => int256) public predictions;

    /*//////////////////////////////////////////////////////////////
                                 ERRORS
    //////////////////////////////////////////////////////////////*/

    /// @notice Thrown if inputs to compute container are recorded incorrectly
    /// @dev 4-byte signature `0x6364fc0e`
    error InputsIncorrect();

    /// @notice Thrown if proof verification fails
    /// @dev 4-byte signature `0xd30ec238`
    error ProofIncorrect();

    /*//////////////////////////////////////////////////////////////
                              CONSTRUCTOR
    //////////////////////////////////////////////////////////////*/

    /// @notice Initialize new BalanceScale
    /// @param coordinator coordinator address
    /// @param attestor EZKL attestor address
    /// @param verifier EZKL verifier address
    constructor(address coordinator, address attestor, address verifier) CallbackConsumer(coordinator) {
        // Initiate attestor contract
        ATTESTOR = DataAttestation(attestor);
        // Set verifier address
        VERIFIER = verifier;
    }

    /*//////////////////////////////////////////////////////////////
                               FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /// @notice Initiates new prediction by encoding input parameters and kicking off compute request callback
    /// @param input balance scale params: [right-distance, right-weight, left-distance, left-weight]
    function initiatePrediction(int256[4] calldata input) external {
        // Encode features
        bytes memory features = abi.encode(input);

        // Make new callback request
        uint32 id = _requestCompute("BSM", features, 1000 gwei, 1_000_000 wei, 1);

        // Store input data
        data[id] = input;
    }

    /// @notice Inherited function: CallbackConsumer._receiveCompute
    function _receiveCompute(
        uint32 subscriptionId,
        uint32 interval,
        uint16 redundancy,
        address node,
        bytes calldata input,
        bytes calldata output,
        bytes calldata proof
    ) internal override {
        // On callback, first, set currentData = relevant data to verify for subscription
        currentData = data[subscriptionId];

        // Verify off-chain recorded input is correct
        bytes32 hashedInput = keccak256(abi.encode(currentData));
        (bytes32 recordedInput) = abi.decode(input, (bytes32));
        if (hashedInput != recordedInput) {
            revert InputsIncorrect();
        }

        // Attest + verify proof via attestor
        bool verified = ATTESTOR.verifyWithDataAttestation(VERIFIER, proof);

        // Error if proof not verified
        if (!verified) {
            revert ProofIncorrect();
        }

        // Proof begins with 4-byte signature to Verifier (because Verifier is staticall'd from Attestor)
        // Thus, we first strip the first 4-bytes of proof to collect just function data
        // Then, we decode the instances array from the stripped proof
        (, uint256[] memory instances) = abi.decode(proof[4:proof.length], (bytes, uint256[]));

        // Set prediction to predicted result from instances array
        predictions[subscriptionId] = int256(instances[instances.length - 1]);
    }
}
