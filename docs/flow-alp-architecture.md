# FlowALP Mutation Pipeline

## Background

FlowALP is a lending protocol implemented in Cadence on Flow. As a financial protocol, it must be resistant to bugs that cause unauthorized state changes, bypassed risk checks, or accounting drift between on-chain reserves and the internal ledger.

Each operation (deposit, withdraw, liquidate, ...) produces state changes that depend on dynamic conditions — balances, caps, health factors, pause state. Correctness requires that every rule is checked before state is changed, and that only a minimal, auditable set of code paths can ever mutate protocol state. This document describes the pipeline every operation follows to meet that bar.

## Summary

Every operation flows through three components:

```
Orchestrator  →  Validator  →  Mutator
 (builds          (view check,   (apply state changes,
  intent,          panics on      run invariants, return
  enforces         violation)     output resources)
  access control)
```

- **Orchestrator** — a method on `Pool`. Builds an `Intent` from caller arguments and forwards to the Validator and Mutator. Enforces caller-level access control via entitlements.
- **Validator** — a contract-level `view` function. Inspects an `&PoolState` snapshot and panics on any operation-level rule violation.
- **Mutator** — a method on `PoolState`. Performs the state changes for one operation, invokes `checkInvariants`, and returns any output resources. Internally uses `access(self)` appliers — primitive state writers.

Each Mutator corresponds 1:1 with a Validator. Together they are the only way protocol state changes.

## Design

### Goals

**Goal 1: Minimize surface area of code that can mutate state.**

The set of code paths that can change protocol state must be small, explicit, and enumerable at review time. This is achieved through three sub-constraints:

- **1a. Validation runs in `view` context.** Every Validator is declared `view`, which Cadence checks at compile time. Business-rule code provably cannot mutate state.
- **1b. State is encapsulated by type.** All mutable protocol state lives inside a dedicated `PoolState` resource, not on `Pool`. Within `PoolState`, substates are further nested in types that enforce their own rules (e.g. `Reserves` owns the FungibleToken vaults and rejects unsupported-token operations). Each layer owns a narrower slice of state and a correspondingly narrower set of rules.
- **1c. Mutators are separated from appliers.** The state-writing API is two layers:
  - **Mutators** are the operations exposed to the Orchestrator: one per supported operation. Each Mutator corresponds to exactly one Validator.
  - **Appliers** are single-purpose primitive writers (add a delta to a balance, move a vault into Reserves, ...). They are internal helpers; Mutators are the only callers.

  Both are `access(self)` on `PoolState`, so the compiler guarantees code outside `PoolState` cannot invoke them. Mutators are reachable only through the `access(all)` entry points on `PoolState`, which are bound to run Validator-then-Mutator as a single unit.

**Goal 2: Uniformly enforce critical safety invariants after every operation.**

Every Mutator's final action is `checkInvariants` — a `view` method that reads all state and panics on any violation. Because Cadence reverts the transaction on panic, a failed invariant undoes every change produced by the operation. Invariants are a transaction-level property: they must hold at the end of each operation, not between individual applier calls.

### Orchestrator

Methods on `Pool` that take caller-facing arguments (e.g. `positionUUID`, an incoming vault), build an `Intent`, and invoke the matching entry point on `PoolState`. Each Orchestrator is entitlement-gated: `access(Internal)` for user operations routed through a `Position` handle, `access(Admin)` for protocol management, `access(Admin | Liquidate)` for liquidation.

Orchestrators carry no business logic. They exist to shape inputs into an `Intent` and to enforce that the caller is allowed to request the operation at all.

### Validator

Contract-level `view` functions of the form:

```cadence
access(contract) view fun validateDeposit(state: &PoolState, intent: DepositIntent)
```

A Validator reads state through an un-entitled `&PoolState` (and any needed Pool config), checks every operation-level rule (supported token, deposit cap, position exists, post-op health factor, paused state, ...), and panics on violation. It returns nothing on success.

The `view` modifier is the central enforcement mechanism: Cadence rejects any mutation inside a view function at compile time. There is no path by which a Validator can accidentally change state.

### Mutator

`access(all)` methods on `PoolState` that form the API surface exposed to the Orchestrator. Each Mutator is invoked immediately after its matching Validator:

```cadence
access(all) fun deposit(intent: DepositIntent, vault: @{FungibleToken.Vault}) {
    FlowALP.validateDeposit(state: &self as &PoolState, intent: intent)
    // applier calls ...
    self.checkInvariants()
}
```

Mutators carry preconditions that cross-check input resources against the intent (e.g. the deposit Mutator asserts that the incoming vault's type and balance match `DepositIntent`'s declared values — the Validator only saw the intent, not the vault). Mutators return output resources directly.

Internally, a Mutator invokes one or more **appliers** — `access(self)` primitives on `PoolState` such as `applyLedgerDelta`, `applyVaultDeposit`, `applyReserveWithdraw`. Since appliers are `access(self)`, the compiler guarantees they are unreachable from outside `PoolState`. Pool cannot bypass a Mutator to invoke them directly. Grep `access(self) fun` inside `PoolState` to enumerate the complete set of writers.

### Intent

A plain struct (`DepositIntent`, `WithdrawIntent`, ...) describing a requested operation. Intents carry no resources; input resources are passed as separate arguments and cross-checked inside the Mutator. Intents mirror user actions 1:1 and are naturally shaped for logging, events, and audit trails.

### Access-control convention

- Every method on `Pool` is either `view` or entitlement-gated. No `access(all)` non-view methods on `Pool`; no `access(contract)` non-view methods on `Pool`.
- Every state-writing method on `PoolState` (Mutators and appliers) is `access(self)`.
- `PoolState` is an `access(self)` field of `Pool`, so no external reference to `PoolState` ever escapes.

The first rule is lint-checkable and enumerates `Pool`'s external surface by entitlement. The second and third are compiler-enforced: Cadence emits an `access denied` error on any attempt to reach a `PoolState` applier from outside `PoolState`, and no code outside `Pool` can obtain an `&PoolState` reference at all.

## Assumptions

- Transactions are atomic. All mutations within a tx commit or revert together; `checkInvariants` runs once per operation at the end.
- `Pool` is single-instance. One `Pool` per contract deployment at a well-known storage path.
- Position UUIDs are unique and opaque. Each `Position` resource carries its own UUID as the key for its `PositionRecord`.

## Non-Goals

- **Formal verification is not in scope.** Invariant checks plus review are the safety net, not a proof.
- **Entitlement-based gating for internal writers was considered and rejected.** Cadence permits a composite unrestricted access to methods on its own nested resources via `self.field.method(...)`, bypassing any entitlement on the method. `access(self)` is the only compile-time gate that restricts internal callers, which is why `PoolState`'s writers use it.
- **Interface-based read/write separation (`PoolReader` / `PoolWriter`) was considered and rejected.** Interfaces add ceremony without adding safety beyond what `view` and `access(self)` already enforce.
- **Batched / multi-operation transactions are not supported.** Each operation is atomic in isolation; multi-op semantics (e.g. `depositAndBorrow`) will require a composite Intent with its own Validator and Mutator.

## Future Extensions

- **Liquidation.** A `LiquidationIntent` covering borrower, liquidator, repay amount, and seize type; matching `validateLiquidate` (health-factor + close-factor rules) and `liquidate` Mutator.
- **Interest accrual.** Per-token interest indices on `TokenStateRecord`, a new applier to roll them forward, and Validators that compute health factors against the latest indices.
- **Pool config visible to Validators.** Validators currently receive `&PoolState` only. If pause state, risk parameters, etc. need to participate in rule checks, move them into `PoolState` or pass a config snapshot alongside the intent.
- **Lint rule.** CI check flagging any `Pool` method not `view` or entitlement-gated.
- **Observability.** Events on each Mutator invocation, plus a view returning a position's full snapshot.

## Open Questions

- **Where does pause-state live?** Validators need it, but it currently sits on `Pool`'s config. Move into `PoolState`, or pass into Validators explicitly?
- **Should Validators live on `PoolState`?** Contract-level keeps them unit-testable without a `PoolState` instance; `PoolState`-local keeps them closer to their data.
- **Liquidation flagging.** When a position enters liquidation, some invariants (e.g. health factor ≥ 1) must relax. The data shape (flag on `PositionRecord`? separate liquidation log?) is undecided.
- **`PositionRecord.id`** mirrors the dictionary key and may be redundant.
