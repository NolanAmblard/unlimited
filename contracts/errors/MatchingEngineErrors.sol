// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

/// @title Custom errors for MatchingEngine.sol
/// @author Nolan D. Amblard
contract MatchingEngineErrors {

    /// @notice Fill or kill orders must be completely filled
    error FillOrKillNotFilled();

}
