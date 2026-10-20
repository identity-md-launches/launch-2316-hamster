// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

/// @title HAMSTER
/// @notice A fixed-supply ERC-20 with 18 decimals and no administrative powers.
contract HAMSTER is ERC20 {
    /// @notice One billion tokens expressed in the smallest token unit.
    uint256 public constant INITIAL_SUPPLY = 1_000_000_000 * 10 ** 18;

    /// @notice Mints the entire supply once to the immediate deployer.
    /// @dev When deployed through the launch factory, the factory receives the supply.
    constructor() ERC20("HAMSTER", "HAMSTER") {
        _mint(msg.sender, INITIAL_SUPPLY);
    }
}
