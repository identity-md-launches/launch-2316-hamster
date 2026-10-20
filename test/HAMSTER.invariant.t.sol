// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Test} from "forge-std/Test.sol";
import {HAMSTER} from "../src/HAMSTER.sol";

/// @dev Tracks an independent balance/allowance model across arbitrary action sequences.
contract HAMSTERHandler is Test {
    HAMSTER public immutable token;
    address[4] public actors;
    mapping(address => uint256) public expectedBalance;
    mapping(address => mapping(address => uint256)) public expectedAllowance;

    constructor() {
        token = new HAMSTER();
        for (uint256 i; i < actors.length; ++i) {
            actors[i] = makeAddr(string.concat("holder", vm.toString(i)));
        }
        expectedBalance[actors[0]] = 1_000_000_000 * 10 ** 18;
        assertTrue(token.transfer(actors[0], expectedBalance[actors[0]]));
    }

    function transfer(uint256 fromSeed, uint256 toSeed, uint256 value) external {
        address from = actors[fromSeed % actors.length];
        address to = actors[toSeed % actors.length];
        value = bound(value, 0, expectedBalance[from]);
        vm.prank(from);
        assertTrue(token.transfer(to, value));
        expectedBalance[from] -= value;
        expectedBalance[to] += value;
    }

    function approve(uint256 ownerSeed, uint256 spenderSeed, uint256 value) external {
        address owner = actors[ownerSeed % actors.length];
        address spender = actors[spenderSeed % actors.length];
        vm.prank(owner);
        assertTrue(token.approve(spender, value));
        expectedAllowance[owner][spender] = value;
    }

    function transferFrom(uint256 ownerSeed, uint256 spenderSeed, uint256 toSeed, uint256 value) external {
        address owner = actors[ownerSeed % actors.length];
        address spender = actors[spenderSeed % actors.length];
        address to = actors[toSeed % actors.length];
        uint256 allowed = expectedAllowance[owner][spender];
        uint256 available = expectedBalance[owner] < allowed ? expectedBalance[owner] : allowed;
        value = bound(value, 0, available);
        vm.prank(spender);
        assertTrue(token.transferFrom(owner, to, value));
        expectedBalance[owner] -= value;
        expectedBalance[to] += value;
        if (allowed != type(uint256).max) {
            expectedAllowance[owner][spender] -= value;
        }
    }

    function overdraw(uint256 ownerSeed) external {
        address owner = actors[ownerSeed % actors.length];
        uint256 requested = expectedBalance[owner] + 1;
        vm.prank(owner);
        (bool succeeded,) = address(token).call(abi.encodeCall(token.transfer, (actors[0], requested)));
        assertFalse(succeeded);
    }
}

contract HAMSTERInvariantTest is Test {
    HAMSTERHandler internal handler;
    HAMSTER internal token;

    function setUp() public {
        handler = new HAMSTERHandler();
        token = handler.token();
        bytes4[] memory selectors = new bytes4[](4);
        selectors[0] = HAMSTERHandler.transfer.selector;
        selectors[1] = HAMSTERHandler.approve.selector;
        selectors[2] = HAMSTERHandler.transferFrom.selector;
        selectors[3] = HAMSTERHandler.overdraw.selector;
        targetContract(address(handler));
        targetSelector(FuzzSelector({addr: address(handler), selectors: selectors}));
    }

    function invariant_SupplyBalancesAndAllowancesMatchModel() public view {
        uint256 sum;
        for (uint256 i; i < 4; ++i) {
            address owner = handler.actors(i);
            uint256 balance = token.balanceOf(owner);
            assertEq(balance, handler.expectedBalance(owner));
            sum += balance;
            for (uint256 j; j < 4; ++j) {
                address spender = handler.actors(j);
                assertEq(token.allowance(owner, spender), handler.expectedAllowance(owner, spender));
            }
        }
        assertEq(sum, 1_000_000_000 * 10 ** 18);
        assertEq(token.totalSupply(), sum);
        assertEq(token.balanceOf(address(0)), 0);
        assertEq(token.balanceOf(address(handler)), 0);
        assertEq(token.balanceOf(address(token)), 0);
    }
}
