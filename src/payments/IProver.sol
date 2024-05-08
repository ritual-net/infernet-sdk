// SPDX-License-Identifier: BSD-3-Clause-Clear
pragma solidity ^0.8.4;

/// @title IProver
/// @notice Basic interface for prover contracts to: (1) expose proving fees and `Wallet` address, (2) expose function to begin proof validation journey
interface IProver {
    /// @notice Gets prover contract's associated `Wallet` address
    /// @dev Does not necessarily have to conform to the exact `Wallet` spec. since this address does not need to authorize the coordinator for spend
    /// @return `Wallet` address to receive proof payment
    function getWallet() external view returns (address);

    /// @notice Checks if `token` is accepted payment method by prover contract
    /// @param token token address
    /// @return `true` if `token` is supported, else `false`
    function isSupportedToken(address token) external view returns (bool);

    /// @notice Gets proving fee denominated in `token`
    /// @dev Function `isSupportedToken` is called first
    /// @return proving fee denominated in `token`
    function fee(address token) external view returns (uint256);

    /// @notice Request proof validation from prover contract
    /// @dev Prover contract has to call `validateProof` on coordinator after a proof validation request
    /// @dev By this point, prover contract has been paid for proof validation
    function requestProofValidation(uint32 subscriptionId, uint32 interval, address node, bytes calldata proof)
        external;

    /// @notice Enforce ETH deposits to `IProver`-implementing contract
    /// @dev A prover may still choose to not support ETH by returning `false` for `isSupportedToken(address(0))`
    receive() external payable;
}
