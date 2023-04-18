// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "./events/EventfulOrderbook.sol";
import "./errors/OrderbookErrors.sol";

/// @title A decentralized orderbook
/// @author Nolan D. Amblard
/// @notice This contract is based on OasisDex
contract OrderBook is 
    EventfulOrderbook,
    OrderbookErrors,
    Ownable {

    ERC20 public token1;
    ERC20 public token2;
    address public feeAddr;
    uint128 public takerFee;
    uint128 public makerFee;

    uint256 private _next_id = 1;  // Start at 1 so that this value is never 0 or 1

    mapping(uint256 => MakeOrder) public orders;
    mapping(uint256 => uint256) public activeOrders;

    /// @dev Custom type for orders
    struct MakeOrder {
        uint128 sellingTokenAmt;
        uint128 buyingTokenAmt;
        address owner;
        uint8 sellingToken1;
        uint8 biggerToken;  // 1 for token1, 2 for token2
        uint256 priceRatio;
    }

    /// @dev Sets the token pair and initial maker/taker fees
    /// @dev Sets the address to which platform fees should be sent to
    constructor(
        ERC20 _token1, 
        ERC20 _token2, 
        address _feeAddr, 
        uint128 _takerFee,
        uint128 _makerFee
    ) {
        token1 = _token1;
        token2 = _token2;

        // The address receiving fees
        feeAddr = _feeAddr;

        // Maker and taker fees in BPS
        // BPS is in terms of 0.01%
        takerFee = _takerFee;
        makerFee = _makerFee;
    }

    /// @dev Reverts transaction if an order is invalid
    modifier isActive(uint256 id) {
        if (!(activeOrders[id] == 1)) revert InactiveOrder();
        _;
    }

    /// @notice Returns current taker fee in BPS (0.01%)
    function getTakerFee() external view returns (uint128) {
        return takerFee;
    }

    /// @notice Lets owner change takerFee in BPS (always <50%)
    /// @notice Owner should be a multisig/something controlled by a DAO to prevent abuse
    function setTakerFee(uint128 _takerFee) external onlyOwner {
        if (_takerFee > 5000) revert InvalidFeeValue();  // Taker fee must not be >50%
        takerFee = _takerFee;
    }

    /// @notice Returns current maker fee in BPS (0.01%)
    function getMakerFee() external view returns (uint128) {
        return makerFee;
    }

    /// @notice Lets owner change makerFee in BPS (always <50%)
    /// @notice Owner should be a multisig/something controlled by a DAO to prevent abuse
    function setMakerFee(uint128 _makerFee) external onlyOwner {
        if (_makerFee > 5000) revert InvalidFeeValue();  // Maker fee must not be >50%
        makerFee = _makerFee;
    }

    /// @notice Returns the two tokens traded in the Orderbook
    function getTokenPair() external view returns (ERC20, ERC20) {
        return (token1, token2);
    }

    /// @notice Returns info on an active offer
    function viewOffer(uint256 id) external view isActive(id) returns (uint128, uint128, address, uint8) {
        return (orders[id].sellingTokenAmt, orders[id].buyingTokenAmt,
            orders[id].owner, orders[id].sellingToken1);
    }

    /// @notice Creates a maker order, sends funds from maker to escrow
    /// @dev Adds created order to orders list
    /// @dev Returns id of created order
    function _make(
        uint128 token1Amt,
        uint128 token2Amt,
        uint256 priceRatio,
        uint8 biggerToken,
        uint8 sellingToken1
    ) internal returns (uint256 id) {
        if (sellingToken1 > 1) revert SellingTokenNotBool();
        if (token1Amt == 0 || token2Amt == 0) revert ZeroTokenAmount();

        MakeOrder memory orderInfo;

        if (sellingToken1 == 1) { // If token1 is the one being sold
            if (!token1.transferFrom(msg.sender, address(this), uint256(token1Amt)))
                revert TransferToEscrowError();
            orderInfo.sellingTokenAmt = token1Amt;
            orderInfo.buyingTokenAmt = token2Amt;
        } else {  // If token2 is the one being sold
            if (!token2.transferFrom(msg.sender, address(this), uint256(token2Amt)))
                revert TransferToEscrowError();
            orderInfo.sellingTokenAmt = token2Amt;
            orderInfo.buyingTokenAmt = token1Amt;
        }

        orderInfo.owner = msg.sender;
        orderInfo.sellingToken1 = sellingToken1;
        orderInfo.priceRatio = priceRatio;
        orderInfo.biggerToken = biggerToken;

        id = ++_next_id;  // Get new order id
        orders[id] = orderInfo;  
        activeOrders[id] = 1;  // Set order to active

        emit OfferCreate(
            token1,
            token2,
            sellingToken1,
            token1Amt,
            token2Amt,
            id,
            msg.sender
        );
    }

    /// @notice Purchases quantity of token offered from orders[id]
    /// @dev Returns whether or not the offer was deleted
    function _buy(
        uint256 id, 
        uint128 quantity  // The quantity of the token being sold to buy
    ) internal isActive(id) returns (bool) {
        if (quantity == 0) revert ZeroBuyQuantity();

        MakeOrder memory _makeOrder = orders[id];  // Consider not using this to save gas??
        if (quantity > _makeOrder.sellingTokenAmt) revert QuantityExceedsOrderAmount();
        uint128 cost = _makeOrder.buyingTokenAmt * quantity / _makeOrder.sellingTokenAmt;

        uint128 _takerFee = cost * takerFee / 10_000;  // Taker fee BPS is 0.01%
        uint128 _makerFee = cost * makerFee / 10_000;  // Taker fee BPS is 0.01%

        ERC20 buyerReceiveToken;
        ERC20 buyerPayToken;

        if (_makeOrder.sellingToken1 == 1) {  // Buyer is using token2 to purchase token1
            buyerReceiveToken = token1;
            buyerPayToken = token2;
        } else {
            buyerReceiveToken = token2;
            buyerPayToken = token1;
        } 

        // Take both taker and maker fee in one tx to save gas
        if (!buyerPayToken.transferFrom(msg.sender, feeAddr, _takerFee + _makerFee))
            revert LackingFundsForFees();
        if (!buyerPayToken.transferFrom(msg.sender, _makeOrder.owner, cost - _makerFee))
            revert LackingFundsForTransaction();
        if (!buyerReceiveToken.transfer(msg.sender, quantity))
            revert EscrowToBuyerError();

        orders[id].sellingTokenAmt -= quantity;
        orders[id].buyingTokenAmt -= cost;

        emit TakerFeePaid(
            id,
            msg.sender,
            buyerPayToken,
            _takerFee
        );

        emit MakerFeePaid(
            id,
            _makeOrder.owner,
            buyerPayToken,  // The token the fee is paid in, not what the maker is selling
            _makerFee
        );

        if (_makeOrder.sellingToken1 == 1) {
            emit OfferTake(
                _makeOrder.sellingToken1,
                token1,
                token2,
                quantity,
                cost,
                id,
                _makeOrder.owner,
                msg.sender
            );
        } else {
            emit OfferTake(
                _makeOrder.sellingToken1,
                token1,
                token2,
                cost,
                quantity,
                id,
                _makeOrder.owner,
                msg.sender
            );
        }

        emit OfferUpdate(
            id,
            orders[id].sellingTokenAmt,
            orders[id].buyingTokenAmt
        );

        if (orders[id].sellingTokenAmt == 0) {
            delete orders[id];
            activeOrders[id] = 0;

            emit DeleteOffer(
                id,
                _makeOrder.owner,
                token1,
                token2
            );

            return true;
        }
        return false;
    }

    /// @notice Cancels an order and refunds maker with remaining token
    /// @dev Returns which token the order was selling
    function _cancel(
        uint256 id
    ) internal isActive(id) returns(uint256 sellingToken1) {
        if (!(msg.sender == orders[id].owner)) revert NonOwnerCantCancelOrder();

        sellingToken1 = orders[id].sellingToken1;
        ERC20 escrowedToken = sellingToken1 == 1 ? token1 : token2;

        if (!escrowedToken.transfer(msg.sender, orders[id].sellingTokenAmt))
            revert EscrowToBuyerError();

        delete orders[id];
        activeOrders[id] = 0;

        emit OrderCancelled(
            id,
            orders[id].owner,
            token1,
            token2
        );

        emit DeleteOffer(
            id,
            orders[id].owner,
            token1,
            token2
        );
    }
}