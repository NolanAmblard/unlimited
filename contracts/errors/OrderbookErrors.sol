// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

/// @title Custom errors for Orderbook.sol
/// @author Nolan D. Amblard
contract OrderbookErrors {

    /// @notice Invalid value for sellingToken1. Needed `0` or `1`.
    error SellingTokenNotBool();

    /// @notice Invalid token amount. Token amount must be greater than 0.
    error ZeroTokenAmount();

    /// @notice An error occured when transfering tokens from a user to the escrow.
    error TransferToEscrowError();

    /// @notice Invalid purchase amount. Purchase quantity must be greater than 0.
    error ZeroBuyQuantity();

    /// @notice The quantity of a buy order must not exceed the maximum quantity of a maker's order.
    error QuantityExceedsOrderAmount();

    /// @notice The transaction was reverted due to the user not being enough funds for fees.
    error LackingFundsForFees();

    /// @notice The transaction was reverted due to the user not having enough to pay for the transaction.
    error LackingFundsForTransaction();

    /// @notice The transaction sending the buyer the escrowed tokens was reverted.
    error EscrowToBuyerError();

    /// @notice An account which is not the owner of an order is not able to cancel it.
    error NonOwnerCantCancelOrder();

    /// @notice Cannot execute orderbook logic on an inactive order.
    error InactiveOrder();

    /// @notice Fees cannot be set to more than 50%;
    error InvalidFeeValue();

}