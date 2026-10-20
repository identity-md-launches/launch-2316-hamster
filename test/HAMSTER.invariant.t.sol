// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Test} from "forge-std/Test.sol";
import {IERC20Errors} from "@openzeppelin/contracts/interfaces/draft-IERC6093.sol";
import {HAMSTER} from "../src/HAMSTER.sol";

/// @dev Tracks an independent balance/allowance model across arbitrary action sequences.
contract HAMSTERHandler is Test {
    uint256 internal constant SUPPLY = 1_000_000_000 * 10 ** 18;
    HAMSTER public immutable token;
    address[4] public actors;
    mapping(address => uint256) public expectedBalance;
    mapping(address => mapping(address => uint256)) public expectedAllowance;

    constructor() {
        token = new HAMSTER();
        for (uint256 i; i < actors.length; ++i) {
            actors[i] = makeAddr(string.concat("holder", vm.toString(i)));
            expectedBalance[actors[i]] = SUPPLY / actors.length;
            assertTrue(token.transfer(actors[i], expectedBalance[actors[i]]));
        }
        // Every actor starts funded. A ring of finite/infinite approvals makes
        // positive delegated transfers reachable from the first random action.
        for (uint256 i; i < actors.length; ++i) {
            _approve(actors[i], actors[(i + 1) % actors.length], i % 2 == 0 ? SUPPLY / 4 : type(uint256).max);
        }
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
        _approve(owner, spender, value);
    }

    function approveBoundary(uint256 ownerSeed, uint256 spenderSeed, uint256 boundarySeed) external {
        uint256[5] memory boundaries = [uint256(0), 1, SUPPLY, type(uint256).max - 1, type(uint256).max];
        _approve(
            actors[ownerSeed % actors.length],
            actors[spenderSeed % actors.length],
            boundaries[boundarySeed % boundaries.length]
        );
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
        _expectFailure(
            owner,
            abi.encodeCall(token.transfer, (actors[0], requested)),
            abi.encodeWithSelector(
                IERC20Errors.ERC20InsufficientBalance.selector, owner, expectedBalance[owner], requested
            )
        );
    }

    function overspendAllowance(uint256 ownerSeed, uint256 spenderSeed, uint256 value) external {
        address owner = actors[ownerSeed % actors.length];
        address spender = actors[spenderSeed % actors.length];
        value = bound(value, 0, SUPPLY);
        _approve(owner, spender, value);
        _expectFailure(
            spender,
            abi.encodeCall(token.transferFrom, (owner, spender, value + 1)),
            abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, spender, value, value + 1)
        );
        // The model retains the approval; the invariant checks rollback of every
        // balance and allowance, including unrelated owner/spender pairs.
    }

    function overdrawFrom(uint256 ownerSeed, uint256 spenderSeed, bool infinite) external {
        address owner = actors[ownerSeed % actors.length];
        address spender = actors[spenderSeed % actors.length];
        uint256 requested = expectedBalance[owner] + 1;
        _approve(owner, spender, infinite ? type(uint256).max : requested);
        _expectFailure(
            spender,
            abi.encodeCall(token.transferFrom, (owner, spender, requested)),
            abi.encodeWithSelector(
                IERC20Errors.ERC20InsufficientBalance.selector, owner, expectedBalance[owner], requested
            )
        );
    }

    function transferToZero(uint256 ownerSeed, uint256 spenderSeed, uint256 value, bool delegated) external {
        address owner = actors[ownerSeed % actors.length];
        address spender = actors[spenderSeed % actors.length];
        value = bound(value, 0, expectedBalance[owner]);
        bytes memory invalidReceiver = abi.encodeWithSelector(IERC20Errors.ERC20InvalidReceiver.selector, address(0));
        if (delegated) {
            _approve(owner, spender, value);
            _expectFailure(spender, abi.encodeCall(token.transferFrom, (owner, address(0), value)), invalidReceiver);
        } else {
            _expectFailure(owner, abi.encodeCall(token.transfer, (address(0), value)), invalidReceiver);
        }
    }

    function approveZeroSpender(uint256 ownerSeed, uint256 value) external {
        address owner = actors[ownerSeed % actors.length];
        _expectFailure(
            owner,
            abi.encodeCall(token.approve, (address(0), value)),
            abi.encodeWithSelector(IERC20Errors.ERC20InvalidSpender.selector, address(0))
        );
    }

    function revoke(uint256 ownerSeed, uint256 spenderSeed) external {
        address owner = actors[ownerSeed % actors.length];
        address spender = actors[spenderSeed % actors.length];
        _approve(owner, spender, 0);
        _expectFailure(
            spender,
            abi.encodeCall(token.transferFrom, (owner, spender, 1)),
            abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, spender, 0, 1)
        );
    }

    function _approve(address owner, address spender, uint256 value) internal {
        vm.prank(owner);
        assertTrue(token.approve(spender, value));
        expectedAllowance[owner][spender] = value;
    }

    function _expectFailure(address caller, bytes memory data, bytes memory expectedError) internal {
        vm.prank(caller);
        (bool succeeded, bytes memory result) = address(token).call(data);
        assertFalse(succeeded, "invalid token operation succeeded");
        assertEq(result, expectedError, "unexpected revert reason");
    }
}

/// forge-config: default.invariant.runs = 256
/// forge-config: default.invariant.depth = 128
/// forge-config: default.invariant.fail-on-revert = true
contract HAMSTERInvariantTest is Test {
    HAMSTERHandler internal handler;
    HAMSTER internal token;

    function setUp() public {
        handler = new HAMSTERHandler();
        token = handler.token();
        bytes4[] memory selectors = new bytes4[](10);
        selectors[0] = HAMSTERHandler.transfer.selector;
        selectors[1] = HAMSTERHandler.approve.selector;
        selectors[2] = HAMSTERHandler.transferFrom.selector;
        selectors[3] = HAMSTERHandler.overdraw.selector;
        selectors[4] = HAMSTERHandler.approveBoundary.selector;
        selectors[5] = HAMSTERHandler.overspendAllowance.selector;
        selectors[6] = HAMSTERHandler.overdrawFrom.selector;
        selectors[7] = HAMSTERHandler.transferToZero.selector;
        selectors[8] = HAMSTERHandler.approveZeroSpender.selector;
        selectors[9] = HAMSTERHandler.revoke.selector;
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
            assertEq(token.allowance(owner, address(0)), 0);
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
        assertEq(token.name(), "HAMSTER");
        assertEq(token.symbol(), "HAMSTER");
        assertEq(token.decimals(), 18);
    }
}
