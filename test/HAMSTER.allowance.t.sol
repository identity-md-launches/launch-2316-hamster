// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Test} from "forge-std/Test.sol";
import {IERC20Errors} from "@openzeppelin/contracts/interfaces/draft-IERC6093.sol";
import {HAMSTER} from "src/HAMSTER.sol";

/// @dev Complements the existing ERC-20 tests with adversarial allowance sequences.
/// forge-config: default.fuzz.runs = 1000
contract HAMSTERAllowanceTest is Test {
    uint256 internal constant SUPPLY = 1_000_000_000 * 10 ** 18;
    HAMSTER internal token;
    address internal holder;
    address internal recipient;
    address internal spender;
    address internal otherSpender;

    event Approval(address indexed owner, address indexed spender, uint256 value);

    function setUp() public {
        token = new HAMSTER();
        holder = makeAddr("allowance holder");
        recipient = makeAddr("allowance recipient");
        spender = makeAddr("approved spender");
        otherSpender = makeAddr("other spender");
        assertTrue(token.transfer(holder, SUPPLY));
    }

    function test_OneWeiCanBeTransferredAndSpentExactlyOnce() public {
        vm.prank(holder);
        assertTrue(token.transfer(recipient, 1));
        vm.prank(recipient);
        assertTrue(token.approve(spender, 1));
        vm.prank(spender);
        assertTrue(token.transferFrom(recipient, holder, 1));
        assertEq(token.balanceOf(holder), SUPPLY);
        assertEq(token.balanceOf(recipient), 0);
        assertEq(token.allowance(recipient, spender), 0);

        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, spender, 0, 1));
        vm.prank(spender);
        token.transferFrom(recipient, holder, 1);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function test_MaximumMinusOneAllowanceIsFinite() public {
        _approve(type(uint256).max - 1);
        vm.prank(spender);
        assertTrue(token.transferFrom(holder, recipient, 1));
        assertEq(token.allowance(holder, spender), type(uint256).max - 2);
        vm.prank(spender);
        assertTrue(token.transferFrom(holder, recipient, SUPPLY - 1));
        assertEq(token.allowance(holder, spender), type(uint256).max - 1 - SUPPLY);
        assertEq(token.balanceOf(holder), 0);
        assertEq(token.balanceOf(recipient), SUPPLY);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function test_InfiniteApprovalCanBeReplacedWithFiniteApproval() public {
        _approve(type(uint256).max);
        vm.prank(spender);
        assertTrue(token.transferFrom(holder, recipient, 1));
        _approve(2);
        vm.prank(spender);
        assertTrue(token.transferFrom(holder, recipient, 2));
        assertEq(token.allowance(holder, spender), 0);

        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, spender, 0, 1));
        vm.prank(spender);
        token.transferFrom(holder, recipient, 1);
        assertEq(token.balanceOf(recipient), 3);
        assertEq(token.balanceOf(holder), SUPPLY - 3);
    }

    function test_InfiniteApprovalCanBeRevokedAndGrantedAgain() public {
        _approve(type(uint256).max);
        vm.expectEmit(true, true, false, true, address(token));
        emit Approval(holder, spender, 0);
        _approve(0);

        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, spender, 0, 1));
        vm.prank(spender);
        token.transferFrom(holder, recipient, 1);
        assertEq(token.allowance(holder, spender), 0);
        assertEq(token.balanceOf(holder), SUPPLY);
        assertEq(token.balanceOf(recipient), 0);

        _approve(type(uint256).max);
        vm.prank(spender);
        assertTrue(token.transferFrom(holder, recipient, SUPPLY));
        assertEq(token.allowance(holder, spender), type(uint256).max);
        assertEq(token.balanceOf(recipient), SUPPLY);
        assertEq(token.balanceOf(holder), 0);
    }

    function test_InfiniteApprovalDoesNotBypassBalanceCheckForMaximumAmount() public {
        _approve(type(uint256).max);
        vm.expectRevert(
            abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, holder, SUPPLY, type(uint256).max)
        );
        vm.prank(spender);
        token.transferFrom(holder, recipient, type(uint256).max);
        assertEq(token.allowance(holder, spender), type(uint256).max);
        assertEq(token.balanceOf(holder), SUPPLY);
        assertEq(token.balanceOf(recipient), 0);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function test_InfiniteApprovalStillRejectsZeroReceiver() public {
        _approve(type(uint256).max);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidReceiver.selector, address(0)));
        vm.prank(spender);
        token.transferFrom(holder, address(0), SUPPLY);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidReceiver.selector, address(0)));
        vm.prank(spender);
        token.transferFrom(holder, address(0), 0);
        assertEq(token.allowance(holder, spender), type(uint256).max);
        assertEq(token.balanceOf(holder), SUPPLY);
        assertEq(token.balanceOf(address(0)), 0);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function test_ApprovalCannotBeUsedByAnotherSpender() public {
        _approve(type(uint256).max);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, otherSpender, 0, 1));
        vm.prank(otherSpender);
        token.transferFrom(holder, recipient, 1);
        assertEq(token.allowance(holder, spender), type(uint256).max);
        assertEq(token.allowance(holder, otherSpender), 0);
        assertEq(token.balanceOf(holder), SUPPLY);
        assertEq(token.balanceOf(recipient), 0);
    }

    function test_ApprovalCannotBeUsedForAnotherOwner() public {
        vm.prank(holder);
        token.transfer(recipient, 1);
        _approve(type(uint256).max);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, spender, 0, 1));
        vm.prank(spender);
        token.transferFrom(recipient, holder, 1);
        assertEq(token.allowance(holder, spender), type(uint256).max);
        assertEq(token.allowance(recipient, spender), 0);
        assertEq(token.balanceOf(holder), SUPPLY - 1);
        assertEq(token.balanceOf(recipient), 1);
    }

    function test_ZeroApprovalToZeroSpenderRevertsWithoutRevokingOthers() public {
        _approve(type(uint256).max);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidSpender.selector, address(0)));
        vm.prank(holder);
        token.approve(address(0), 0);
        assertEq(token.allowance(holder, address(0)), 0);
        assertEq(token.allowance(holder, spender), type(uint256).max);
        assertEq(token.balanceOf(holder), SUPPLY);
    }

    function test_SelfApprovalAuthorizesTransferFromAndIsConsumed() public {
        vm.prank(holder);
        assertTrue(token.approve(holder, SUPPLY));
        vm.prank(holder);
        assertTrue(token.transferFrom(holder, recipient, SUPPLY));
        assertEq(token.allowance(holder, holder), 0);
        assertEq(token.balanceOf(holder), 0);
        assertEq(token.balanceOf(recipient), SUPPLY);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function testFuzz_TransferRoundTripRestoresBalancesAndPreservesApproval(uint256 amount, uint256 approval) public {
        amount = bound(amount, 1, SUPPLY);
        _approve(approval);
        vm.prank(holder);
        assertTrue(token.transfer(recipient, amount));
        assertEq(token.balanceOf(holder), SUPPLY - amount);
        assertEq(token.balanceOf(recipient), amount);
        assertEq(token.allowance(holder, spender), approval);

        vm.prank(recipient);
        assertTrue(token.transfer(holder, amount));
        assertEq(token.balanceOf(holder), SUPPLY);
        assertEq(token.balanceOf(recipient), 0);
        assertEq(token.allowance(holder, spender), approval);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function testFuzz_IndependentSpendersConsumeOnlyTheirOwnAllowance(uint256 first, uint256 second) public {
        first = bound(first, 1, SUPPLY - 1);
        second = bound(second, 1, SUPPLY - first);
        _approve(first);
        vm.prank(holder);
        assertTrue(token.approve(otherSpender, second));

        vm.prank(spender);
        assertTrue(token.transferFrom(holder, recipient, first));
        assertEq(token.allowance(holder, spender), 0);
        assertEq(token.allowance(holder, otherSpender), second);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, spender, 0, 1));
        vm.prank(spender);
        token.transferFrom(holder, recipient, 1);

        vm.prank(otherSpender);
        assertTrue(token.transferFrom(holder, recipient, second));
        assertEq(token.allowance(holder, otherSpender), 0);
        assertEq(token.balanceOf(holder), SUPPLY - first - second);
        assertEq(token.balanceOf(recipient), first + second);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function testFuzz_ReplacingAllowanceSetsAnAbsoluteLimit(uint256 oldApproval, uint256 newApproval) public {
        newApproval = bound(newApproval, 1, SUPPLY - 1);
        _approve(oldApproval);
        _approve(newApproval);
        assertEq(token.allowance(holder, spender), newApproval);

        vm.expectRevert(
            abi.encodeWithSelector(
                IERC20Errors.ERC20InsufficientAllowance.selector, spender, newApproval, newApproval + 1
            )
        );
        vm.prank(spender);
        token.transferFrom(holder, recipient, newApproval + 1);
        assertEq(token.allowance(holder, spender), newApproval);
        assertEq(token.balanceOf(holder), SUPPLY);
        assertEq(token.balanceOf(recipient), 0);

        vm.prank(spender);
        assertTrue(token.transferFrom(holder, recipient, newApproval));
        assertEq(token.allowance(holder, spender), 0);
        assertEq(token.balanceOf(holder), SUPPLY - newApproval);
        assertEq(token.balanceOf(recipient), newApproval);
    }

    function testFuzz_FailedSpendCanBeRetriedAfterFunding(uint256 balance, uint256 shortfall, bool infinite) public {
        balance = bound(balance, 0, SUPPLY - 1);
        shortfall = bound(shortfall, 1, SUPPLY - balance);
        uint256 requested = balance + shortfall;
        vm.prank(holder);
        assertTrue(token.transfer(recipient, SUPPLY - balance));
        uint256 approval = infinite ? type(uint256).max : requested;
        _approve(approval);

        vm.expectRevert(
            abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, holder, balance, requested)
        );
        vm.prank(spender);
        token.transferFrom(holder, recipient, requested);
        assertEq(token.allowance(holder, spender), approval);
        assertEq(token.balanceOf(holder), balance);
        assertEq(token.balanceOf(recipient), SUPPLY - balance);

        vm.prank(recipient);
        assertTrue(token.transfer(holder, shortfall));
        vm.prank(spender);
        assertTrue(token.transferFrom(holder, recipient, requested));
        assertEq(token.balanceOf(holder), 0);
        assertEq(token.balanceOf(recipient), SUPPLY);
        assertEq(token.allowance(holder, spender), infinite ? type(uint256).max : 0);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function testFuzz_DelegatedSelfTransferCannotCreateTokens(uint256 amount, bool infinite) public {
        amount = bound(amount, 1, SUPPLY);
        _approve(infinite ? type(uint256).max : amount);
        vm.prank(spender);
        assertTrue(token.transferFrom(holder, holder, amount));
        assertEq(token.balanceOf(holder), SUPPLY);
        assertEq(token.balanceOf(spender), 0);
        assertEq(token.balanceOf(recipient), 0);
        assertEq(token.allowance(holder, spender), infinite ? type(uint256).max : 0);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function _approve(uint256 amount) internal {
        vm.prank(holder);
        assertTrue(token.approve(spender, amount));
    }
}
