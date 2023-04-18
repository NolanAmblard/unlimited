// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

/// @title Events for Orderbook.sol
/// @author Nolan D. Amblard
/// @author Brian Goldblatt
contract EventfulOrderbook {

    /// @notice Emitted when an offer is created
    /// @dev tokType representative boolean. 0 buy, 1 sell
    event OfferCreate(
        ERC20 token1,
        ERC20 token2,
        uint8 tok1Type,
        uint128 tok1Amt,
        uint128 tok2Amt,
        uint256 indexed id,
        address indexed maker
    );

    /// @notice Emitted when an offer is updated due to a partial fill
    event OfferUpdate(
        uint256 indexed id,
        uint128 tok1Amt,
        uint128 tok2Amt
    );

    /// @notice Emitted when a taker fee is paid during the order fill process
    event TakerFeePaid(
        uint256 indexed id,
        address indexed taker,
        ERC20 tokPaid,
        uint128 feePaid
    );

    /// @notice Emitted when a maker fee is paid during the order fill process
    event MakerFeePaid(
        uint256 indexed id,
        address indexed maker,
        ERC20 tokPaid,
        uint128 feePaid
    );

    /// @notice Emitted when all or part of an order is executed
    event OfferTake(
        uint8 tok1Type,
        ERC20 token1,
        ERC20 token2,
        uint128 tok1Amt,
        uint128 tok2Amt,
        uint256 indexed id,
        address indexed maker,
        address indexed taker
    );

    /// @notice Emitted when an order is deleted (completely filled or cancelled)
    event DeleteOffer(
        uint256 indexed id,
        address indexed maker,
        ERC20 token1,
        ERC20 token2
    );

    /// @notice Emitted when an order is cancelled
    event OrderCancelled(
        uint256 indexed id,
        address indexed maker,
        ERC20 token1,
        ERC20 token2
    );
}