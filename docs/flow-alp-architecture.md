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
       pre:  validateXxx → Bool           — phase 2: operation-level rule check
       body: apply ledger / reserves      — phase 3: intent state change
       post: invariantsHold → Bool        — phase 4: universal post-state check
```

- **Orchestrator** — a method on `Pool`. Builds an `Intent`, calls `applyTimeBasedMutations` to bring state up to date, then invokes the Mutator. Enforces caller-level access control via entitlements.
- **Validator** — a contract-level `view` function returning `Bool`. Invoked from the Mutator's `pre` block against the time-advanced state; a `false` result aborts the operation before any state change.
- **Mutator** — an `access(all)` method on `PoolState`. Corresponds 1:1 with a Validator. Validate (pre) → apply (body) → invariants (post); returns any output resources.

`applyTimeBasedMutations` is a separate `PoolState` entry point that writes state but does not correspond to a Validator — it has no intent, it just advances time-dependent quantities (e.g. interest indices).

## Design

### Goals

**Goal 1: Minimize surface area of code that can mutate state.**

The set of code paths that can change protocol state should be small and explicit. This is achieved through three sub-constraints:

- **1a. Validation runs in `view` context.** Every Validator is declared `view`, which Cadence checks at compile time. Business-rule code provably cannot mutate state. The main reason for this is to **discourage mixing state validations with state mutations**.
- **1b. State is encapsulated by type.** All mutable protocol state lives inside a dedicated `PoolState` resource, not on `Pool`. Within `PoolState`, substates are further nested in types that enforce their own rules.
- **1c. Mutators are separated from appliers.** The state-writing API is two layers:
  - **Mutators** are the intent operations exposed to the Orchestrator: one per supported operation. Each Mutator corresponds to exactly one Validator.
  - **Appliers** are single-purpose primitive writers (add a delta to a balance, move a vault into Reserves, advance an interest index, ...). Only Mutators and `applyTimeBasedMutations` call appliers.

  Appliers are `access(self)` on `PoolState`, so the compiler guarantees code outside `PoolState` cannot invoke them. Mutators are reachable only through `access(all)` entry points on `PoolState`, which are themselves only reachable through `Pool`'s orchestrators (since `PoolState` is stored as an `access(self)` field of `Pool`).

**Goal 2: Uniformly enforce critical safety invariants after every operation.**

Every Mutator declares `self.invariantsHold()` as its `post` condition — a `view` method that reads all state and returns `true` iff every invariant holds. A `false` result trips the post-condition, panicking and reverting the transaction. Invariants are a transaction-level property: they must hold at the end of each operation, not between individual applier calls.

### Orchestrator

Methods on `Pool` that:
1. Build an `Intent` from caller arguments.
2. Call `self.state.applyTimeBasedMutations()` to advance time-dependent state.
3. Invoke the matching Mutator on `PoolState` with the intent (and any input resources).

Each Orchestrator is entitlement-gated: `access(Internal)` for user operations routed through a `Position` handle, `access(Admin)` for protocol management, `access(Admin | Liquidate)` for liquidation. Orchestrators carry no business logic; their job is to shape inputs, advance state to the current block, and forward to the Mutator.

### Time-based mutations

`applyTimeBasedMutations` is an `access(all)` method on `PoolState` that performs time-based state update: advances per-token interest indices, rolls forward utilization, etc. It has no intent and no paired Validator — its preconditions (e.g. monotonic block timestamp) are internal to its implementation. Applying time-based mutations should never violate state invariants.

`applyTimeBasedMutations` is idempotent within a block: after the first call in a given block, subsequent calls are no-ops because no time has elapsed.

Every intent-based Orchestrator calls `applyTimeBasedMutations` before invoking its Mutator so that validation runs against the time-advanced state (for example, a withdrawal's health-factor check must reflect the latest interest on outstanding debt).

### Validator

Contract-level `view` functions of the form:

```cadence
access(contract) view fun validateDeposit(state: &PoolState, intent: DepositIntent): Bool
```

A Validator is invoked from the Mutator's `pre` block and runs after `applyTimeBasedMutations`. It reads state through an un-entitled `&PoolState` (and any needed Pool config), checks operation-level rules, and returns `true` iff every rule passes. A `false` result aborts the Mutator before its body runs. The `view` modifier is the central enforcement mechanism: Cadence rejects any mutation inside a view function at compile time.

**What belongs in a Validator.** A check is the Validator's responsibility if at least one of the following is true:

1. **It cannot be expressed as a universal post-state property.**
   - Operation-mode checks (e.g. "pool is paused").
   - Per-request limits (e.g. "this individual deposit is within the per-tx cap"). A per-tx cap cannot be derived from the post-state alone — the post-state only shows the new total, not the size of *this* request.
2. **It is cheap to compute and lets us exit early** before doing expensive work or committing resources. Early checks such as "position exists" or "token type is supported" avoid downstream panics and wasted work on requests that are guaranteed to fail.

### Mutator

`access(all)` methods on `PoolState` that form the API surface exposed to the Orchestrator for intent-based operations. The Orchestrator has already called `applyTimeBasedMutations` by the time a Mutator is invoked. Each Mutator's three phases (validate, apply, invariants) are expressed in Cadence's pre/body/post structure:

```cadence
access(all) fun applyDeposit(intent: DepositIntent, vault: @{FungibleToken.Vault}) {
    pre {
        FlowALP.validateDeposit(state: &self as &PoolState, intent: intent):
            "deposit validation failed"
        vault.getType() == intent.tokenType:
            "vault type does not match intent"
        vault.balance == intent.amount:
            "vault amount does not match intent"
    }
    post {
        self.invariantsHold(): "post-state invariants violated"
    }
    self.applyVaultDeposit(from: <- vault)
    self.applyLedgerDelta(/* ... */)
}
```

- **Validate (pre)** — call the matching contract-level `view` Validator. Cross-checks that need the input resource (e.g. "incoming vault's type and balance match the intent" — the Validator only saw the intent, not the vault) stay inline in the same `pre` block.
- **Apply (body)** — invoke one or more appliers — `access(self)` primitives on `PoolState` (`applyLedgerDelta`, `applyVaultDeposit`, `applyReserveWithdraw`).
- **Invariants (post)** — call `self.invariantsHold()`.

### Invariants

`invariantsHold` is an `access(self) view` method on `PoolState`, invoked as the Mutator's `post` condition. It reads the full state and returns `true` iff every invariant holds. A `false` result trips the post-condition, panicking and reverting the transaction.

**What belongs in Invariants.** An invariant is a universal property of state that must hold after *every* operation, regardless of which operation ran. Invariants catch bugs in any code path, giving defense-in-depth beyond per-operation validation.

- **Accounting integrity**: for each supported token T, Σ(position credits for T) − Σ(position debits for T) = Reserves balance for T. (obviously this would be more complicated with interest and fees)
- **Pool-wide caps**: total borrowed per token ≤ pool cap for that token.

**Rule of thumb.** If a check is expressible as a post-state property that must hold after *any* operation, it belongs in Invariants. Otherwise, it belongs in the Validator. Where a check is expressible either way (e.g. "this position's HF ≥ 1 after a withdrawal"), prefer Invariants — the single universal check covers every future operation without being restated.

### Intent

A plain struct (`DepositIntent`, `WithdrawIntent`, ...) describing a requested operation. Intents carry no resources; input resources are passed as separate arguments and cross-checked inside the Mutator. Intents mirror user actions 1:1, and primarily exist to encapsulate data associated with a user action through the pipeline.

### Access-control convention

- Every method on `Pool` is either `view` or entitlement-gated. No `access(all)` non-view methods on `Pool`; no `access(contract)` non-view methods on `Pool`.
- State-writing methods on `PoolState` are either:
  - `access(all)` Mutators / entry points (`applyTimeBasedMutations`, `applyDeposit`, `applyWithdraw`, `registerPosition`, `registerToken`), invoked only through `Pool`'s orchestrators, OR
  - `access(self)` internals (appliers and `invariantsHold`), invoked only from within `PoolState`.
- `PoolState` is an `access(self)` field of `Pool`, so no external reference to `PoolState` ever escapes.

The first rule is lint-checkable and enumerates `Pool`'s external surface by entitlement. The second and third are compiler-enforced: Cadence emits an `access denied` error on any attempt to reach a `PoolState` internal writer from outside `PoolState`, and no code outside `Pool` can obtain an `&PoolState` reference at all. External callability of the `access(all)` entry points is bounded by that last property.

## Future Extensions

- **Liquidation.** A `LiquidationIntent` covering borrower, liquidator, repay amount, and seize type; matching `validateLiquidate` (health-factor + close-factor rules) and `liquidate` Mutator.
- **Interest accrual implementation.** Per-token interest indices on `TokenStateRecord`, written by `applyTimeBasedMutations`, and Validators/Invariants that compute health factors against the latest indices.
- **Pool config visible to Validators.** Validators currently receive `&PoolState` only. If pause state, risk parameters, etc. need to participate in rule checks, move them into `PoolState` or pass a config snapshot alongside the intent.
- **Keeper-triggered time-based mutations.** Since `applyTimeBasedMutations` is already `access(all)` on `PoolState`, a thin Orchestrator on `Pool` could expose it publicly for off-cycle use by keeper bots or indexers.
- **Lint rule.** CI check flagging any `Pool` method not `view` or entitlement-gated, and any intent-based Orchestrator that invokes a Mutator without first calling `applyTimeBasedMutations`.
- **Observability.** Events on each Mutator invocation, plus a view returning a position's full snapshot.

## Open Questions

- **Should Validators live on `PoolState`?** Contract-level keeps them unit-testable without a `PoolState` instance (if we add an interface type in between); `PoolState`-local keeps them closer to their data.
