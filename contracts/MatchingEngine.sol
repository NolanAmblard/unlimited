// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "./Orderbook.sol";
import "./errors/MatchingEngineErrors.sol";
import "./events/EventfulMatchingEngine.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";

/// @title A price-time priority matching engine
/// @author Nolan D. Amblard
/// @author Brian Goldblatt
contract MatchingEngine is 
    OrderBook,
    MatchingEngineErrors,
    ReentrancyGuard,
    EventfulMatchingEngine {
    
    /// @dev Node for doubly linked list
    struct Node {
        uint256 id;  // This may not be necessary to store as the key in the mapping is the id
        uint256 prev;
        uint256 next;
    }

    mapping(uint256 => Node) public bids;  // Doubly linked list (DLL), buying token1 selling Token2
    mapping(uint256 => Node) public asks;  // Doubly linked list, selling Token1 buying token2

    /// @dev Instantiates Orderbook and adds head/tail to bid and ask DLLs
    constructor(
        ERC20 _token1, 
        ERC20 _token2, 
        address _feeAddr, 
        uint128 _takerFee,
        uint128 _makerFee
    ) OrderBook(
        _token1, 
        _token2, 
        _feeAddr, 
        _takerFee,
        _makerFee
    ) {
        bids[0] = Node(0, 0, 0);
        asks[0] = Node(0, 0, 0);
    }

    /// @notice Tries to match a new limit order to existing ones on the order book
    /// @notice If a match(es) is (are) found, the orders are executed as taker orders
    /// @dev returns the amount of token1 and token2 remaining to be put into limit order
    function _buyAmountLessThanRatio(
        uint256 priceRatio,
        uint8 biggerToken,
        uint8 sellingToken1,
        uint128 token1Amt, 
        uint128 token2Amt
    ) internal returns (uint128, uint128) {
        if (sellingToken1 == 1) {  // Search through bids (look through orders that want to buy token1)
            Node memory curr = bids[bids[0].next];
            while (
                curr.id != 0  // If curr.id is 0, then we have gone through all the asks
                && token1Amt != 0
            ) {
                if (biggerToken == 1) {  // The amount of token1 is > the amount of token2 
                    if (orders[curr.id].biggerToken == 1) {  // The best bid also has a token1Amt > token2Amt
                        if (priceRatio >= orders[curr.id].priceRatio) {
                            // example for this situation: 
                            //     proposed ask: 5 token1 -> 1 token2 (ratio = 5)
                            //     existing bid: 1 token2 -> 4 token1 (ratio = 4)
                            token2Amt = uint128(uint256(token1Amt) * 1_000_000_000_000_000
                                / priceRatio);
                            uint128 buyAmt = token2Amt < orders[curr.id].sellingTokenAmt
                                ? token2Amt
                                : orders[curr.id].sellingTokenAmt;
                            if (_buy(curr.id, buyAmt)) {  // If the order was completely filled, remove it
                                bids[bids[curr.id].next].prev = bids[curr.id].prev;
                                bids[bids[curr.id].prev].next = bids[curr.id].next;
                                delete bids[curr.id];
                            }
                            token1Amt -= uint128(uint256(buyAmt) * orders[curr.id].priceRatio
                                / 1_000_000_000_000_000);  // Potentially inefficient and maybe dangerous;
                        } else {
                            break;
                        }
                    } else {  // biggerToken == 1 && orders[curr.id].biggerToken == 2
                        // example for this situation: 
                        //     proposed ask: 5 token1 -> 1 token2 (ratio = 5)
                        //     existing bid: 4 token2 -> 1 token1 (ratio = 4)
                        token2Amt = uint128(uint256(token1Amt) * 1_000_000_000_000_000
                            / priceRatio);
                        uint128 buyAmt = token2Amt < orders[curr.id].sellingTokenAmt
                            ? token2Amt
                            : orders[curr.id].sellingTokenAmt;
                        if (_buy(curr.id, buyAmt)) {  // If the order was completely filled, remove it
                            bids[bids[curr.id].next].prev = bids[curr.id].prev;
                            bids[bids[curr.id].prev].next = bids[curr.id].next;
                            delete bids[curr.id];
                        }
                        token1Amt -= uint128(uint256(buyAmt) * 1_000_000_000_000_000
                            / orders[curr.id].priceRatio);  // Potentially inefficient and maybe dangerous;
                    }
                } else {  // biggerToken == 2
                    if (orders[curr.id].biggerToken == 2) {  // The best bid also has a token1Amt < token2Amt
                        if (priceRatio <= orders[curr.id].priceRatio) {
                            // example for this situation:
                            //     proposed ask: 1 token1 -> 4 token2 (ratio = 4)
                            //     existing bid: 5 token2 -> 1 token1 (ratio = 5)
                            token2Amt = uint128(uint256(token1Amt) * priceRatio
                                / 1_000_000_000_000_000);
                            uint128 buyAmt = token2Amt < orders[curr.id].sellingTokenAmt
                                ? token2Amt
                                : orders[curr.id].sellingTokenAmt;
                            if (_buy(curr.id, buyAmt)) {  // If the order was completely filled, remove it
                                bids[bids[curr.id].next].prev = bids[curr.id].prev;
                                bids[bids[curr.id].prev].next = bids[curr.id].next;
                                delete bids[curr.id];
                            }
                            token1Amt -= uint128(uint256(buyAmt) * 1_000_000_000_000_000
                                / orders[curr.id].priceRatio);  // Potentially inefficient and maybe dangerous;
                        } else {
                            break;
                        }
                    } else {  // biggerToken == 2 && orders[curr.id].biggerToken == 1
                        break;
                    }
                }
                // Get next best bid
                curr = bids[curr.next];
            }
        } else {  // sellingToken1 == 0; Search through asks
            Node memory curr = asks[asks[0].next];
            while (
                curr.id != 0  // If curr.id is 0, then we have gone through all the asks
                && token2Amt != 0
            ) {
                if (biggerToken == 1) {
                    if (orders[curr.id].biggerToken == 1) {
                        if (priceRatio <= orders[curr.id].priceRatio) {
                            // example for this situation: 
                            //     proposed bid: 1 token2 -> 4 token1 (ratio = 4)
                            //     existing ask: 5 token1 -> 1 token2 (ratio = 5)
                            token1Amt = uint128(uint256(token2Amt) * priceRatio
                                / 1_000_000_000_000_000);
                            uint128 buyAmt = token1Amt < orders[curr.id].sellingTokenAmt
                                ? token1Amt
                                : orders[curr.id].sellingTokenAmt;
                            if (_buy(curr.id, buyAmt)) {  // If the order was completely filled, remove it
                                asks[asks[curr.id].next].prev = asks[curr.id].prev;
                                asks[asks[curr.id].prev].next = asks[curr.id].next;
                                delete asks[curr.id];
                            }
                            token2Amt -= uint128(uint256(buyAmt) * 1_000_000_000_000_000
                                / orders[curr.id].priceRatio);  // Potentially inefficient and maybe dangerous;
                        } else {
                            break;
                        }
                    } else {  // biggerToken == 1 && orders[curr.id].biggerToken == 2
                        break;
                    }
                } else {  // biggerToken == 2
                    if (orders[curr.id].biggerToken == 2) {
                        if (priceRatio >= orders[curr.id].priceRatio) {
                            // example for this situation: 
                            //     proposed bid: 5 token2 -> 1 token1 (ratio = 5)
                            //     existing ask: 1 token1 -> 4 token2 (ratio = 4)
                            token1Amt = uint128(uint256(token2Amt) * 1_000_000_000_000_000
                                / priceRatio);
                            uint128 buyAmt = token1Amt < orders[curr.id].sellingTokenAmt
                                ? token1Amt
                                : orders[curr.id].sellingTokenAmt;
                            if (_buy(curr.id, buyAmt)) {  // If the order was completely filled, remove it
                                asks[asks[curr.id].next].prev = asks[curr.id].prev;
                                asks[asks[curr.id].prev].next = asks[curr.id].next;
                                delete asks[curr.id];
                            }
                            token2Amt -= uint128(uint256(buyAmt) * orders[curr.id].priceRatio
                                / 1_000_000_000_000_000);  // Potentially inefficient and maybe dangerous;
                        } else {
                            break;
                        }
                    } else {  // biggerToken == 2 && orders[curr.id].biggerToken == 1
                        // example for this situation: 
                            //     proposed bid: 5 token2 -> 1 token1 (ratio = 5)
                            //     existing ask: 4 token1 -> 1 token2 (ratio = 4)
                        token1Amt = uint128(uint256(token2Amt) * 1_000_000_000_000_000
                            / priceRatio);
                        uint128 buyAmt = token1Amt < orders[curr.id].sellingTokenAmt
                            ? token1Amt
                            : orders[curr.id].sellingTokenAmt;
                        if (_buy(curr.id, buyAmt)) {  // If the order was completely filled, remove it
                            asks[asks[curr.id].next].prev = asks[curr.id].prev;
                            asks[asks[curr.id].prev].next = asks[curr.id].next;
                            delete asks[curr.id];
                        }
                        token2Amt -= uint128(uint256(buyAmt) * 1_000_000_000_000_000
                            / orders[curr.id].priceRatio);  // Potentially inefficient and maybe dangerous;
                    }
                }
                // Get next best ask
                curr = asks[curr.next];
            }
        }
        return (token1Amt, token2Amt);
    }

    /// @notice Creates a maker order and inserts it at the proper position in the orderbook (price/time priority)
    /// @notice If given order can be execute (partially) as a taker order, it will be executed (partially) as one.
    /// @notice For (partial) taker orders, taker fees apply
    /// @dev dllPosition is the position (calculated off-chain) at which this order will be added to the DLL
    /// @dev This calculated position is double-checked and recalculated if need be 
    function makerOrder(
        uint128 token1Amt, 
        uint128 token2Amt, 
        uint8 sellingToken1,
        uint256 dllPosition  // Doubly linked list position, if unknown can be anything (should make 0 for simplicity)
    ) public nonReentrant {
        if (token1Amt == 0 || token2Amt == 0) revert ZeroTokenAmount();
        if (sellingToken1 > 1) revert SellingTokenNotBool();

        // Calculate ratio of inputted token amounts
        // Use a multiplier of 1_000_000_000_000_000 to avoid fractional ratios.
        // TODO: Test if this results in errors
        uint8 biggerToken = 1;  // Flag to keep track of which token has a bigger quantity
        uint256 priceRatio;
        if (token1Amt > token2Amt) {
            priceRatio = token1Amt * 1_000_000_000_000_000 / token2Amt;
        } else {
            biggerToken = 2;
            priceRatio = token2Amt * 1_000_000_000_000_000 / token1Amt;
        }

        // (partially) Convert order to taker if a matching order exists
        (token1Amt, token2Amt) = _buyAmountLessThanRatio(
            priceRatio,
            biggerToken,
            sellingToken1,
            token1Amt,
            token2Amt
        );

        // A higher ratio of token being bought may have been received from _buyAmountLessThanRatio()
        // Recalculate the amount of the token being bought to stay true to the original ratio
        if (sellingToken1 == 1) {  // A higher ratio of token2 may have been spent in _buyAmountLessThanRatio()
            if (token1Amt == 0) return; // Function is exited if entire order was executed as a taker order
            token2Amt = biggerToken == 1
                ? uint128(uint256(token1Amt) * 1_000_000_000_000_000 / priceRatio)
                : uint128(uint256(token1Amt) * priceRatio / 1_000_000_000_000_000);
        } else {  // A higher ratio of token1 may have been spent in _buyAmountLessThanRatio()
            if (token2Amt == 0) return; // Function is exited if entire order was executed as a taker order
            token1Amt = biggerToken == 1
                ? uint128(uint256(token2Amt) * priceRatio / 1_000_000_000_000_000)
                : uint128(uint256(token2Amt) * 1_000_000_000_000_000 / priceRatio);
        }

        // Make the order
        uint256 id = _make(token1Amt,
            token2Amt,
            priceRatio,
            biggerToken,
            sellingToken1
        );

        // Add the order to the sorted list.
        // Check to see if the provided position is correct, if so, insert it
        // If it is incorrect, calculate the correct position and insert it there
        // Note: An order id can never be 0 or 1 allowing the use of dllPosition == 0 and == 1 
        //       as the front and back without error
        if (sellingToken1 == 1) {  // If selling token 1, then add to asks
            if (dllPosition == 1 || asks[dllPosition].prev == 0) {  // Try and add ask to the front
                if (orders[asks[0].next].biggerToken == 1 && biggerToken == 1) {
                    if (priceRatio <= orders[asks[0].next].priceRatio) {  // Proposed position wrong, find correct position
                        dllPosition = _findInsertPosition(priceRatio, biggerToken, 1);  // 1 for ask
                    } else {  // Order is correct
                        _insertFirstOrder(id, 1);  // 1 for ask
                        emit MakerOrderCreated(id, 1);
                        return;
                    }
                } else if (orders[asks[0].next].biggerToken == 2 && biggerToken == 2) {
                    if (priceRatio >= orders[asks[0].next].priceRatio) {  // if ratio >= curr ratio its a worse order
                        dllPosition = _findInsertPosition(priceRatio, biggerToken, 1);  // 1 for ask
                    } else {  // Order is correct
                        _insertFirstOrder(id, 1);  // 1 for ask
                        emit MakerOrderCreated(id, 1);
                        return;
                    }
                } else if (orders[asks[0].next].biggerToken == 1 && biggerToken == 2) {  // Always a worse order
                    dllPosition = _findInsertPosition(priceRatio, biggerToken, 1);  // 1 for ask
                } else {  // orders[asks[0].id].biggerToken == 2 && biggerToken == 1
                    // Proposed position is correct, insert at front
                    _insertFirstOrder(id, 1);  // 1 for ask
                    emit MakerOrderCreated(id, 1);
                    return;
                }
            } else if (dllPosition == 0) {  // Order is proposed to be added to back of orderbook (worst order)
                if (orders[asks[0].prev].biggerToken == 1 && biggerToken == 1) {
                    if (priceRatio > orders[asks[0].prev].priceRatio) {  // The order is better than the current worst order
                        dllPosition = _findInsertPosition(priceRatio, biggerToken, 1);
                    }
                } else if (orders[asks[0].prev].biggerToken == 2 && biggerToken == 2) {
                    if (priceRatio < orders[asks[0].prev].priceRatio) {
                        dllPosition = _findInsertPosition(priceRatio, biggerToken, 1);  // 1 for ask
                    }
                } else if (orders[asks[0].prev].biggerToken == 1 && biggerToken == 2) {
                    dllPosition = _findInsertPosition(priceRatio, biggerToken, 1);  // 1 for ask
                }
                // orders[dllPosition].biggerToken == 2 && biggerToken == 1 is correct
            } else {  // Want worse than previous and better than current id
                if (orders[asks[dllPosition].prev].biggerToken == 1 && biggerToken == 1) {
                    if (priceRatio > orders[asks[dllPosition].prev].priceRatio) {  // If its > prev ratio, its a better order than prev
                        dllPosition = _findInsertPosition(priceRatio, biggerToken, 1);  // 1 for ask
                    }
                    if (orders[dllPosition].biggerToken == 1) {  // If curr biggerToken is 2, the order is properly placed
                        if (priceRatio <= orders[dllPosition].priceRatio) {  // If its <= curr ratio, it's worse than curr
                            dllPosition = _findInsertPosition(priceRatio, biggerToken, 1);  // 1 for ask
                        }
                    }
                } else if (orders[asks[dllPosition].prev].biggerToken == 2 && biggerToken == 2) {
                    if (priceRatio < orders[asks[dllPosition].prev].priceRatio) {   // if ratio < prev ratio, its a better order
                        dllPosition = _findInsertPosition(priceRatio, biggerToken, 1);  // 1 for ask
                    }
                    if (priceRatio >= orders[dllPosition].priceRatio) {  // if ratio >= curr ratio its a worse order
                        dllPosition = _findInsertPosition(priceRatio, biggerToken, 1);  // 1 for ask
                    }
                } else if (orders[asks[dllPosition].prev].biggerToken == 1 && biggerToken == 2) {
                    if (orders[dllPosition].biggerToken == 1) {
                        dllPosition = _findInsertPosition(priceRatio, biggerToken, 1);  // 1 for ask
                    } else if (priceRatio <= orders[dllPosition].priceRatio) {  // if orders[dllPosition].biggerToken == 2
                        dllPosition = _findInsertPosition(priceRatio, biggerToken, 1);  // 1 for ask
                    }
                } else {  // orders[asks[dllPosition].prev].biggerToken == 2 && biggerToken == 1
                    // The proposed order is a better order than the previous order
                    dllPosition = _findInsertPosition(priceRatio, biggerToken, 1);  // 1 for ask
                }
            }
            // Insert ask at dllPosition in DLL
            _insertOrderAtPosition(dllPosition, id, 1);  // 1 for ask
        } else {  // Selling token 2; bids
            if (dllPosition == 1 || bids[dllPosition].prev == 0) {  // Try and add bid to the front
                if (orders[bids[0].next].biggerToken == 1 && biggerToken == 1) {
                    if (priceRatio >= orders[bids[0].next].priceRatio) {  // Proposed position wrong, find correct position
                        dllPosition = _findInsertPosition(priceRatio, biggerToken, 0);  // 0 for bid
                    } else {  // Order is correct
                        _insertFirstOrder(id, 0);  // 0 for bid
                        emit MakerOrderCreated(id, 1);
                        return;
                    }
                } else if (orders[bids[0].next].biggerToken == 2 && biggerToken == 2) {
                    if (priceRatio <= orders[bids[0].next].priceRatio) { 
                        dllPosition = _findInsertPosition(priceRatio, biggerToken, 0);  // 0 for bid
                    } else {  // Order is correct
                        _insertFirstOrder(id, 0);  // 0 for bid
                        emit MakerOrderCreated(id, 1);
                        return;
                    }
                } else if (orders[bids[0].next].biggerToken == 2 && biggerToken == 1) {  // Always a worse order
                    dllPosition = _findInsertPosition(priceRatio, biggerToken, 0);  // 0 for bid
                } else {  // orders[bids[0].id].biggerToken == 1 && biggerToken == 2
                    // Proposed position is correct, insert at front
                    _insertFirstOrder(id, 0);  // 0 for bid
                    emit MakerOrderCreated(id, 1);
                    return;
                }
            } else if (dllPosition == 0) {  // Order is proposed to be added to back of orderbook (worst order)
                if (orders[bids[0].prev].biggerToken == 1 && biggerToken == 1) {
                    if (priceRatio < orders[bids[0].prev].priceRatio) {  // The order is better than the current worst order
                        dllPosition = _findInsertPosition(priceRatio, biggerToken, 0);
                    }
                } else if (orders[bids[0].prev].biggerToken == 2 && biggerToken == 2) {
                    if (priceRatio > orders[bids[0].prev].priceRatio) {
                        dllPosition = _findInsertPosition(priceRatio, biggerToken, 0);  // 0 for bid
                    }
                } else if (orders[bids[0].prev].biggerToken == 2 && biggerToken == 1) {
                    dllPosition = _findInsertPosition(priceRatio, biggerToken, 0);  // 0 for bid
                }
                // orders[dllPosition].biggerToken == 1 && biggerToken == 2 is correct
            } else {  // Want worse than previous and better than current id
                if (orders[bids[dllPosition].prev].biggerToken == 1 && biggerToken == 1) {
                    if (priceRatio < orders[bids[dllPosition].prev].priceRatio) {
                        dllPosition = _findInsertPosition(priceRatio, biggerToken, 0);  // 0 for bid
                    }
                    if (priceRatio >= orders[dllPosition].priceRatio) {
                        dllPosition = _findInsertPosition(priceRatio, biggerToken, 0);  // 0 for bid
                    }
                } else if (orders[bids[dllPosition].prev].biggerToken == 2 && biggerToken == 2) {
                    if (priceRatio > orders[bids[dllPosition].prev].priceRatio) {
                        dllPosition = _findInsertPosition(priceRatio, biggerToken, 0);  // 0 for bid
                    }
                    if (orders[dllPosition].biggerToken == 2) {
                        if (priceRatio <= orders[dllPosition].priceRatio) { 
                            dllPosition = _findInsertPosition(priceRatio, biggerToken, 0);  // 0 for bid
                        }
                    }
                } else if (orders[bids[dllPosition].prev].biggerToken == 2 && biggerToken == 1) {
                    if (orders[dllPosition].biggerToken == 2) {
                        dllPosition = _findInsertPosition(priceRatio, biggerToken, 0);  // 0 for bid
                    } else if (priceRatio >= orders[dllPosition].priceRatio) {
                        dllPosition = _findInsertPosition(priceRatio, biggerToken, 0);  // 0 for bid
                    }
                } else {  // orders[bids[dllPosition].prev].biggerToken == 1 && biggerToken == 2
                    // The proposed order is a better order than the previous order
                    dllPosition = _findInsertPosition(priceRatio, biggerToken, 0);  // 0 for bid
                }
            }
            // Insert bid at dllPosition in DLL
            _insertOrderAtPosition(dllPosition, id, 0);  // 0 for bid
        }
        emit MakerOrderCreated(id, dllPosition);
    }

    /// @notice Finds the position to insert the proposed order into its respective sorted DLL 
    function _findInsertPosition(
        uint256 priceRatio,
        uint8 biggerToken,
        uint8 orderType  // bid == 0, ask == 1
    ) internal view returns (uint256) {
        if (orderType == 0) {  // loop through bids and find insert position
            Node memory curr = bids[bids[0].next];
            while (curr.id != 0) {
                if (orders[curr.id].biggerToken == 1 && biggerToken == 1) {
                    if (priceRatio < orders[curr.id].priceRatio) {
                        return curr.id;
                    }
                } else if (orders[curr.id].biggerToken == 2 && biggerToken == 2) {
                    if (priceRatio > orders[curr.id].priceRatio) {
                        return curr.id;
                    }
                } 
                else if (orders[curr.id].biggerToken == 1 && biggerToken == 2) {
                    return curr.id;
                }
                // if orders[curr.id].biggerToken == 2 && biggerToken == 1 then continue
                curr = bids[curr.next];
            }
        } else {  // loop through asks and find insert position
            Node memory curr = asks[asks[0].next];
            while (curr.id != 0) {
                if (orders[curr.id].biggerToken == 1 && biggerToken == 1) {
                    if (priceRatio > orders[curr.id].priceRatio) {
                        return curr.id;
                    }
                } else if (orders[curr.id].biggerToken == 2 && biggerToken == 2) {
                    if (priceRatio < orders[curr.id].priceRatio) {
                        return curr.id;
                    }
                } 
                else if (orders[curr.id].biggerToken == 2 && biggerToken == 1) {
                    return curr.id;
                }
                // if orders[curr.id].biggerToken == 1 && biggerToken == 2 then continue
                curr = asks[curr.next];
            }
        }
        return 0;  // Order should be added to the back of its respective orderbook
    }

    /// @notice Inserts the proposed order into its respective DLL at the position given
    function _insertOrderAtPosition(
        uint256 insertPos, 
        uint256 id, 
        uint8 orderType  // bid == 0, ask == 1
    ) internal {
        // Note that the case in which insertPos == 0 refers to inserting at the back of the list, not the front
        // The case where the list is empty is addressed in makerOrder()
        if (orderType == 0) {  // Insert bid
            bids[id] = Node(id, bids[insertPos].prev, insertPos);
            bids[bids[insertPos].prev].next = id;
            bids[id].prev = bids[insertPos].prev;
            bids[id].next = insertPos;
            bids[insertPos].prev = id;
        } else {  // Insert ask
            asks[id] = Node(id, asks[insertPos].prev, insertPos);
            asks[asks[insertPos].prev].next = id;
            asks[id].prev = asks[insertPos].prev;
            asks[id].next = insertPos;
            asks[insertPos].prev = id;
        }
    }

    /// @notice Inserts an order into an empty DLL of bids or asks 
    function _insertFirstOrder(
        uint256 id, 
        uint8 orderType  // bid == 0, ask == 1
    ) internal {
        if (orderType == 0) {  // Insert bid
            bids[id] = Node(id, 0, bids[0].next);
            bids[bids[0].next].prev = id;
            bids[id].next = bids[0].next;
            bids[0].next = id;
            bids[id].prev = 0;
        } else {  // Insert ask
            asks[id] = Node(id, 0, asks[0].next);
            asks[asks[0].next].prev = id;
            asks[id].next = asks[0].next;
            asks[0].next = id;
            asks[id].prev = 0;
        }
    }

    /// @notice Executes a taker order for the amount specified
    /// @dev tokenAmt is the amount of the spending token
    function take(
        uint128 tokenAmt,
        uint8 spendingToken1
    ) external nonReentrant {
        if (spendingToken1 == 1) {  // Using token1 to buy token2; search through bids
            Node memory curr = bids[bids[0].next];
            while (
                curr.id != 0  // If curr.id is 0, then we have gone through all the asks
                && tokenAmt != 0
            ) {
                uint128 buyAmt = tokenAmt < orders[curr.id].buyingTokenAmt
                    ? tokenAmt
                    : orders[curr.id].buyingTokenAmt;
                if (_buy(curr.id, buyAmt)) {  // If the order was completely filled, remove it from dll and delete it from array
                    bids[bids[curr.id].next].prev = bids[curr.id].prev;
                    bids[bids[curr.id].prev].next = bids[curr.id].next;
                    delete bids[curr.id];
                }
                tokenAmt -= buyAmt;
                // Get next best bid
                curr = bids[curr.next];
            }
        } else {  // Using token2 to buy token1; Search through asks
            Node memory curr = asks[asks[0].next];
            while (
                curr.id != 0  // If curr.id is 0, then we have gone through all the asks
                && tokenAmt != 0
            ) {
                uint128 buyAmt = tokenAmt < orders[curr.id].buyingTokenAmt
                    ? tokenAmt
                    : orders[curr.id].buyingTokenAmt;
                if (_buy(curr.id, buyAmt)) {  // If the order was completely filled, remove it from dll and delete it from array
                    asks[asks[curr.id].next].prev = asks[curr.id].prev;
                    asks[asks[curr.id].prev].next = asks[curr.id].next;
                    delete asks[curr.id];
                }
                tokenAmt -= buyAmt;
                // Get next best bid
                curr = asks[curr.next];
            }
        }

        emit TakerOrder(tokenAmt, spendingToken1);
    }

    /// @notice Public entrypoint for canceling an order
    /// @dev Removes the order from its respective DLL
    function cancelOrder(
        uint256 id
    ) external nonReentrant {
        if (_cancel(id) == 1) {  // sellingToken1 == 1; remove from asks
            asks[asks[id].next].prev = asks[id].prev;
            asks[asks[id].prev].next = asks[id].next;
            delete asks[id];
        } else {
            bids[bids[id].next].prev = bids[id].prev;
            bids[bids[id].prev].next = bids[id].next;
            delete bids[id];
        }
    }

    /// @notice Executes an immediate or cancel (IoC) order for the amount specified for less than the price specified
    /// @notice IoC orders can execute partial fills
    function immediateOrCancel(
        uint128 token1Amt, 
        uint128 token2Amt, 
        uint8 sellingToken1
    ) external nonReentrant {
        uint8 biggerToken = 1;  // Flag to keep track of which token has a bigger quantity
        uint256 priceRatio;
        if (token1Amt > token2Amt) {
            priceRatio = token1Amt * 1_000_000_000_000_000 / token2Amt;
        } else {
            biggerToken = 2;
            priceRatio = token2Amt * 1_000_000_000_000_000 / token1Amt;
        }

        (uint128 token1AmtNew, uint128 token2AmtNew) = _buyAmountLessThanRatio(
            priceRatio,
            biggerToken,
            sellingToken1,
            token1Amt,
            token2Amt
        );

        emit IoCOrder(
            token1Amt - token1AmtNew,
            token2Amt - token2AmtNew,
            sellingToken1
        );
    }

    /// @notice Attempts to execute a fill or kill (FoC) order for the amount specified for less than the price specified
    /// @notice FoC orders will revert if full amount isn't executed
    function fillOrKill(
        uint128 token1Amt, 
        uint128 token2Amt, 
        uint8 sellingToken1
    ) external nonReentrant {
        uint8 biggerToken = 1;  // Flag to keep track of which token has a bigger quantity
        uint256 priceRatio;
        if (token1Amt > token2Amt) {
            priceRatio = token1Amt * 1_000_000_000_000_000 / token2Amt;
        } else {
            biggerToken = 2;
            priceRatio = token2Amt * 1_000_000_000_000_000 / token1Amt;
        }

        (uint128 token1AmtNew, uint128 token2AmtNew) = _buyAmountLessThanRatio(
            priceRatio,
            biggerToken,
            sellingToken1,
            token1Amt,
            token2Amt
        );

        // If whole quantity of order didn't execute, revert the order
        if (sellingToken1 == 1) {
            if (token1AmtNew != 0) revert FillOrKillNotFilled();
        } else {  // Selling token2
            if (token2AmtNew != 0) revert FillOrKillNotFilled();
        }

        emit FoKOrder(
            token1Amt - token1AmtNew,
            token2Amt - token2AmtNew,
            sellingToken1
        );
    }
}
