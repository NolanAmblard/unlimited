// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

/// @title Events for MatchingEngine.sol
/// @author Nolan D. Amblard
contract EventfulOrderbook {

    /// @notice Emitted when a maker order is created.
    /// @dev position == 0 is back of DLL, position == 1 is front
    event MakerOrderCreated(
        uint256 indexed id,
        uint256 indexed position
    );

    /// @notice Emitted when a taker order is executed.
    event TakerOrder(
        uint128 tokenAmt,
        uint8 spendingToken1
    );

    /// @notice Emitted when an immediate or cancel order is executed.
    /// @dev Token amounts are the amounts actually used in the order
    /// @dev This is not necessarily the amount sent into the method
    event IoCOrder(
        uint128 token1Amt,
        uint128 token2Amt,
        uint8 sellingToken1
    );

    /// @notice Emitted when an fill or kill order is executed.
    /// @dev Token amounts are the amounts actually used in the order
    /// @dev This is not necessarily the amount sent into the method
    event FoKOrder(
        uint128 token1Amt,
        uint128 token2Amt,
        uint8 sellingToken1
    );
}
