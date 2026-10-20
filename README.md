# HAMSTER

HAMSTER is a fixed-supply ERC-20 token for the requested
[HAMSTER project](https://x.com/hamsterhourgame).

| Parameter | Value |
| --- | --- |
| Solidity contract | `HAMSTER` |
| Source | `src/HAMSTER.sol` |
| Token name / symbol | `HAMSTER` / `HAMSTER` |
| Decimals | `18` |
| Supply in whole tokens | `1,000,000,000` |
| Supply in smallest units | `1000000000000000000000000000` (`10^27`) |
| Initial recipient | Immediate deployer (`msg.sender` in the constructor) |
| Constructor arguments | None (empty ABI argument encoding, `0x`) |
| Constructor transaction value | `0` |
| Launch chain | Ethereum, chain ID `1` |
| Compiler | Solidity `0.8.26` |

## Behavior and assumptions

The brief specifies token identity and supply without additional transfer rules.
The implementation therefore uses the standard OpenZeppelin ERC-20 behavior.
The entire supply is minted once in the constructor, with a single
`Transfer(address(0), deployer, supply)` event. `INITIAL_SUPPLY` names the fixed
smallest-unit amount.

Transfers deliver exactly the requested amount. There are no transfer taxes,
fees, rebases, transfer limits, trading gates, or recipient callbacks. Zero-value
transfers and self-transfers are supported; transfers to the zero address revert.
Successful `transfer`, `approve`, and `transferFrom` calls return `true`.
Invalid operations revert with OpenZeppelin's ERC-6093 custom errors and leave
balances and allowances unchanged.

`approve` replaces the caller's allowance for a spender and emits `Approval`.
`transferFrom` consumes finite allowances; an allowance of `type(uint256).max`
is treated as unlimited and is not reduced. Spending emits `Transfer`; this
OpenZeppelin implementation does not emit `Approval` when consuming allowance.
Even the deployer needs an allowance to spend another holder's tokens.

There is no owner or administrator, public mint or burn function, pause,
blacklist, seizure, upgrade mechanism, or initialization step. The fixed supply
cannot grow or shrink through the exposed interface. The social link is
project context; no game, rewards system, or external service integration is
implied or implemented.

## Build and test

Run from the repository root with Foundry and Solidity `0.8.26` available:

```sh
forge build
FOUNDRY_FUZZ_SEED=0xe1be67fc6e7ffaa74b1513bc12ffb762a1049da49da3bc0728703ec7f481c9fe forge test
forge fmt --check
```

The project vendors all Solidity dependencies as ordinary files, including their
licenses. No dependency installation, network RPC, environment configuration,
filesystem permission, or FFI is needed by the tests. Foundry needs the pinned
compiler installed before building without network access.

- `lib/openzeppelin-contracts`: OpenZeppelin Contracts `v5.0.2`; the ERC-20
  implementation and its transitive source dependencies only.
- `lib/forge-std`: Forge Standard Library `v1.9.7`; test support.
- `DEPENDENCIES.json`: source archive URLs, versions, archive hashes, and SHA-256
  hashes for each vendored file.

`foundry.toml` pins the compiler, Cancun EVM target, optimizer with 200 runs, and
`bytecode_hash = "none"`. `remappings.txt` resolves imports entirely within `lib/`.
Production bytecode has no linked external libraries.

## Deployment and operations

Deploy the creation bytecode for `src/HAMSTER.sol:HAMSTER` directly, with no
constructor arguments and no ETH. A local artifact can be inspected without
deploying:

```sh
forge inspect src/HAMSTER.sol:HAMSTER bytecode
forge inspect src/HAMSTER.sol:HAMSTER abi
```

The deploying address receives the entire supply. When the launch factory uses
CREATE or CREATE2, the factory is that address; neither the wallet calling the
factory nor `tx.origin` receives tokens from the constructor. No constructor
calls an external contract or depends on chain state, a configured address, or
a deployed service.

The launch system is responsible for deployment and subsequent distribution.
For this assignment the launch terms allocate 10% to the launch's distributor,
20% to pool seeding, and 70% to the requester's remainder destination. Those
operations, the IMD pair, pool settings, and opening price belong to the launch
system; the token does not perform or retain any allocation itself. The
separate launch manifest step supplies those terms after acceptance. This
repository does not contain a launch manifest or broadcast script.

After deployment, the launch operator should verify the source/build settings,
token metadata, supply, initial factory balance, and completed distribution.
There are no owner settings, maintenance transactions, backend services,
oracle subscriptions, or administrative keys to configure for this token.
No transactions are broadcast as part of this deliverable.

Holders are responsible for checking recipients and managing allowances.
Grant only the allowance needed; when replacing an existing nonzero allowance,
revoke it first and wait for confirmation before granting the replacement to
reduce the standard ERC-20 allowance-change race. Unlimited approval permits
the approved spender to spend the holder's current and future balance until
revoked. Transfers to contracts that cannot return tokens, including the token
contract itself, can strand them permanently: there is no recovery authority.
The token rejects ordinary ETH payments; forced ETH has no withdrawal path.

## Validation and review scope

The delivered suite contains 29 deterministic tests, four fuzz tests with 512
cases each, and one stateful invariant with 128 sequences of 64 actions:

- Metadata, exact constructor allocation, one mint event, and CREATE2 factory
  deployment.
- Exact launch-share transfers and distributor claims, plus transfers into and
  out of a simulated pool address.
- Transfers, approvals, revocation, finite/infinite allowances, event emission,
  zero amounts, self-transfers, and contract recipients.
- Insufficient balances/allowances, invalid zero addresses, atomic rollback,
  maximum integers, missing administrative entrypoints, and rejected ETH.
- Fixed supply and independent balance/allowance accounting after arbitrary
  sequences of approvals, direct/delegated transfers, and rejected overdrafts.
- Runtime size and the absence of DELEGATECALL, CALLCODE, and SELFDESTRUCT
  instructions.

The provided security reference was reviewed against this implementation.
State-changing public calls affect only the caller's balance or allowances,
except for authorized delegated spending. Token operations make no external
calls. There are no oracle, randomness, signature, proxy, or fee-calculation
paths. Only the constructor reaches `_mint`; no public path reaches `_burn`.

The local factory test exercises token accounting, not Uniswap pool execution.
The supplied protected tests depend on the launch verifier's factory/pool
infrastructure, manifest, and environment; those dependencies were not supplied
as a runnable local project. The network's protected integration suite remains
its independent acceptance check. Local validation uses Forge compilation,
deterministic tests, fuzzing, invariants, and source review; Slither and Mythril
were not run. These checks are not an independent security audit.
