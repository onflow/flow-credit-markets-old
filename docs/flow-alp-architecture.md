# FlowALP Mutation Pipeline

## Background

FlowALP is a lending protocol implemented in Cadence on Flow. As a financial protocol, it must be resistant to unauthorized state changes, bypassed risk checks, or accounting drift between on-chain reserves and the internal ledger.

Each operation (deposit, withdraw, liquidate, ...) produces state changes that depend on **time-constant pool state** — balances, health factors, etc. and **time-dependent pool state** such as interest indices. Correctness requires that time-dependent state is rolled forward, every rule is checked against the updated state, the intent's changes are applied, and universal invariants hold at the end. This document describes the pipeline for state mutations to satisfy these requirements.

## Summary

Every user-intent operation flows through four phases across three components. The Orchestrator calls two `PoolState` entry points in sequence: first `applyTimeBasedMutations` to advance time-dependent state, then the intent-specific Mutator, which runs validate → apply → invariants.

```
Pool:
  1. PoolState.applyTimeBasedMutations()  — phase 1: time-based state update
  2. PoolState.<Mutator>(intent):
       validate                           — phase 2: operation-level rule check
       apply                              — phase 3: intent state change
       checkInvariants                    — phase 4: universal post-state check
```

- **Orchestrator** — a method on `Pool`. Builds an `Intent`, calls `applyTimeBasedMutations` to bring state up to date, then invokes the Mutator. Enforces caller-level access control via entitlements.
- **Validator** — a contract-level `view` function. Runs inside the Mutator against the time-advanced state; panics on any rule violation.
- **Mutator** — an `access(all)` method on `PoolState`. Corresponds 1:1 with a Validator. Runs validate → apply → invariants; returns any output resources.

`applyTimeBasedMutations` is a separate `PoolState` entry point that writes state but does not correspond to a Validator — it has no intent, it just advances time-dependent quantities (e.g. interest indices).

## Design

### Goals

**Goal 1: Minimize surface area of code that can mutate state.**

The set of code paths that can change protocol state should be small and explicit. This is achieved through three sub-constraints:

- **1a. Validation runs in `view` context.** Every Validator is declared `view`, which Cadence checks at compile time. Business-rule code provably cannot mutate state.
- **1b. State is encapsulated by type.** All mutable protocol state lives inside a dedicated `PoolState` resource, not on `Pool`. Within `PoolState`, substates are further nested in types that enforce their own rules (e.g. `Reserves` owns the FungibleToken vaults and rejects unsupported-token operations). Each layer owns a narrower slice of state and a correspondingly narrower set of rules.
- **1c. Mutators are separated from appliers.** The state-writing API is two layers:
  - **Mutators** are the intent operations exposed to the Orchestrator: one per supported operation. Each Mutator corresponds to exactly one Validator.
  - **Appliers** are single-purpose primitive writers (add a delta to a balance, move a vault into Reserves, advance an interest index, ...). Only Mutators and `applyTimeBasedMutations` call appliers.

  Appliers are `access(self)` on `PoolState`, so the compiler guarantees code outside `PoolState` cannot invoke them. Mutators are reachable only through `access(all)` entry points on `PoolState`, which are themselves only reachable through `Pool`'s orchestrators (since `PoolState` is stored as an `access(self)` field of `Pool`).

**Goal 2: Uniformly enforce critical safety invariants after every operation.**

Every Mutator's final action is `checkInvariants` — a `view` method that reads all state and panics on any violation. Because Cadence reverts the transaction on panic, a failed invariant undoes every change produced by the operation. Invariants are a transaction-level property: they must hold at the end of each operation, not between individual applier calls.

### Orchestrator

Methods on `Pool` that:
1. Build an `Intent` from caller arguments.
2. Call `self.state.applyTimeBasedMutations()` to advance time-dependent state.
3. Invoke the matching Mutator on `PoolState` with the intent (and any input resources).

Each Orchestrator is entitlement-gated: `access(Internal)` for user operations routed through a `Position` handle, `access(Admin)` for protocol management, `access(Admin | Liquidate)` for liquidation. Orchestrators carry no business logic; their job is to shape inputs, advance state to the current block, and forward to the Mutator.

Placing the `applyTimeBasedMutations` call at the Orchestrator level — rather than inside the Mutator — makes the time-advance-then-act sequence visible at the dispatch site and keeps the Mutator's responsibility narrow (intent handling only). It also lets admin operations that do not depend on time-advanced state skip this step.

### Time-based mutations

`applyTimeBasedMutations` is an `access(all)` method on `PoolState` that performs time-based state update: advances per-token interest indices, rolls forward utilization, etc. It has no intent and no paired Validator — its preconditions (e.g. monotonic block timestamp) are internal to its implementation. Applying time-based mutations should never violate state invariants.

`applyTimeBasedMutations` is idempotent within a block: after the first call in a given block, subsequent calls are no-ops because no time has elapsed.

Every intent-based Orchestrator calls `applyTimeBasedMutations` before invoking its Mutator so that validation runs against the time-advanced state (for example, a withdrawal's health-factor check must reflect the latest interest on outstanding debt).

### Validator

Contract-level `view` functions of the form:

```cadence
access(contract) view fun validateDeposit(state: &PoolState, intent: DepositIntent)
```

A Validator runs inside the Mutator, after `applyTimeBasedMutations`. It reads state through an un-entitled `&PoolState` (and any needed Pool config), checks operation-level rules, and panics on violation. The `view` modifier is the central enforcement mechanism: Cadence rejects any mutation inside a view function at compile time.

**What belongs in a Validator.** A check is the Validator's responsibility if at least one of the following is true:

1. **It cannot be expressed as a universal post-state property.**
   - Operation-mode checks (e.g. "pool is paused").
   - Per-request limits (e.g. "this individual deposit is within the per-tx cap"). A per-tx cap cannot be derived from the post-state alone — the post-state only shows the new total, not the size of *this* request.
2. **It is cheap to compute and lets us exit early** before doing expensive work or committing resources. Early checks such as "position exists" or "token type is supported" avoid downstream panics and wasted work on requests that are guaranteed to fail.

### Mutator

`access(all)` methods on `PoolState` that form the API surface exposed to the Orchestrator for intent-based operations. The Orchestrator has already called `applyTimeBasedMutations` by the time a Mutator is invoked. The Mutator runs three phases:

```cadence
access(all) fun deposit(intent: DepositIntent, vault: @{FungibleToken.Vault}) {
    FlowALP.validateDeposit(state: &self as &PoolState, intent: intent)  // validate
    self.applyDeposit(intent: intent, vault: <- vault)                   // apply + invariants
}
```

- **Validate** — call the matching contract-level `view` Validator.
- **Apply** — an internal `access(self)` helper (`applyDeposit`, `applyWithdraw`, ...) invokes one or more appliers — `access(self)` primitives on `PoolState` (`applyLedgerDelta`, `applyVaultDeposit`, `applyReserveWithdraw`). Mutators carry preconditions that cross-check input resources against the intent (e.g. the deposit path asserts that the incoming vault's type and balance match `DepositIntent`'s declared values — the Validator only saw the intent, not the vault).
- **Invariants** — the apply helper ends with `self.checkInvariants()`.

### Invariants

`checkInvariants` is a `view` method on `PoolState`, invoked as the Mutator's final phase. It reads the full state and panics on any violation, reverting the transaction.

**What belongs in Invariants.** An invariant is a universal property of state that must hold after *every* operation, regardless of which operation ran. Invariants catch bugs in any code path, giving defense-in-depth beyond per-operation validation.

- **Accounting integrity**: for each supported token T, Σ(position credits for T) − Σ(position debits for T) = Reserves balance for T.
- **Solvency**: every position has health factor ≥ 1, unless flagged for liquidation.
- **Pool-wide caps**: total borrowed per token ≤ pool cap for that token.

**Rule of thumb.** If a check is expressible as a post-state property that must hold after *any* operation, it belongs in Invariants. Otherwise, it belongs in the Validator. Where a check is expressible either way (e.g. "this position's HF ≥ 1 after a withdrawal"), prefer Invariants — the single universal check covers every future operation without being restated.

### Intent

A plain struct (`DepositIntent`, `WithdrawIntent`, ...) describing a requested operation. Intents carry no resources; input resources are passed as separate arguments and cross-checked inside the Mutator. Intents mirror user actions 1:1 and are naturally shaped for logging, events, and audit trails.

### Access-control convention

- Every method on `Pool` is either `view` or entitlement-gated. No `access(all)` non-view methods on `Pool`; no `access(contract)` non-view methods on `Pool`.
- State-writing methods on `PoolState` are either:
  - `access(all)` entry points (`applyTimeBasedMutations`, the intent Mutators, `registerPosition`, `registerToken`), invoked only through `Pool`'s orchestrators, OR
  - `access(self)` internals (apply helpers, appliers, `checkInvariants`), invoked only from within `PoolState`.
- `PoolState` is an `access(self)` field of `Pool`, so no external reference to `PoolState` ever escapes.

The first rule is lint-checkable and enumerates `Pool`'s external surface by entitlement. The second and third are compiler-enforced: Cadence emits an `access denied` error on any attempt to reach a `PoolState` internal writer from outside `PoolState`, and no code outside `Pool` can obtain an `&PoolState` reference at all. External callability of the `access(all)` entry points is bounded by that last property.

## Assumptions

- Transactions are atomic. All mutations within a tx commit or revert together; `checkInvariants` runs once per operation at the end.
- `Pool` is single-instance. One `Pool` per contract deployment at a well-known storage path.
- Position UUIDs are unique and opaque. Each `Position` resource carries its own UUID as the key for its `PositionRecord`.
- `applyTimeBasedMutations` is idempotent within a block: after the first call in a given block, subsequent calls are no-ops because no time has elapsed.

## Non-Goals

- **Formal verification is not in scope.** Invariant checks plus review are the safety net, not a proof.
- **Entitlement-based gating for internal writers was considered and rejected.** Cadence permits a composite unrestricted access to methods on its own nested resources via `self.field.method(...)`, bypassing any entitlement on the method. `access(self)` is the only compile-time gate that restricts internal callers, which is why `PoolState`'s internal writers use it.
- **Interface-based read/write separation (`PoolReader` / `PoolWriter`) was considered and rejected.** Interfaces add ceremony without adding safety beyond what `view` and `access(self)` already enforce.
- **Batched / multi-operation transactions are not supported.** Each operation is atomic in isolation; multi-op semantics (e.g. `depositAndBorrow`) will require a composite Intent with its own Validator and Mutator.

## Future Extensions

- **Liquidation.** A `LiquidationIntent` covering borrower, liquidator, repay amount, and seize type; matching `validateLiquidate` (health-factor + close-factor rules) and `liquidate` Mutator.
- **Interest accrual implementation.** Per-token interest indices on `TokenStateRecord`, written by `applyTimeBasedMutations`, and Validators/Invariants that compute health factors against the latest indices.
- **Pool config visible to Validators.** Validators currently receive `&PoolState` only. If pause state, risk parameters, etc. need to participate in rule checks, move them into `PoolState` or pass a config snapshot alongside the intent.
- **Keeper-triggered time-based mutations.** Since `applyTimeBasedMutations` is already `access(all)` on `PoolState`, a thin Orchestrator on `Pool` could expose it publicly for off-cycle use by keeper bots or indexers.
- **Lint rule.** CI check flagging any `Pool` method not `view` or entitlement-gated, and any intent-based Orchestrator that invokes a Mutator without first calling `applyTimeBasedMutations`.
- **Observability.** Events on each Mutator invocation, plus a view returning a position's full snapshot.

## Open Questions

- **Where does pause-state live?** Validators need it, but it currently sits on `Pool`'s config. Move into `PoolState`, or pass into Validators explicitly?
- **Should Validators live on `PoolState`?** Contract-level keeps them unit-testable without a `PoolState` instance; `PoolState`-local keeps them closer to their data.
- **Liquidation flagging.** When a position enters liquidation, some invariants (e.g. health factor ≥ 1) must relax. The data shape (flag on `PositionRecord`? separate liquidation log?) is undecided.
- **`PositionRecord.id`** mirrors the dictionary key and may be redundant.
