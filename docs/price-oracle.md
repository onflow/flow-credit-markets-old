# Flow Credit Markets — Price Oracle

**Status:** Draft
**Owner:** @Jordan Ribbink

> Unless a section explicitly says otherwise, every MUST/SHOULD describes the **mature protocol**. Divergences for the initial deployment are in [Initial Deployment vs. Mature](#initial-deployment-vs-mature-protocol).

---

## Overview

### Problem

FCM must value collateral, assess position solvency, and price liquidations. Every such decision depends on a price for each supported token, denominated in the USD Numeraire. Reading a price from a single on-chain source is unsafe — a source can be stale, manipulated, frozen, or compromised, and operating on a bad price produces incorrect valuations, missed liquidations, or wrongful seizures. The protocol therefore needs a *price-of-truth* abstraction that (a) is robust to single-source failure and (b) gives every caller an unambiguous "I can't answer reliably right now" signal.

### Goal

A minimal `PriceOracle` interface that:

1. Exposes one honest read path: either a reliable price denominated in the oracle's declared unit of account (for FCM, the USD Numeraire), or `nil`.
2. Accommodates multiple independent underlying price sources without leaking that composition to callers.
3. Composes with later safety additions (notably a volatility circuit breaker) without interface change — layers *wrap* the oracle rather than modify it.
4. Fails closed by construction: every documented failure path produces `nil` via a named invariant or nil condition. No documented path returns a wrong value under failure.

### Lifetime

The interface and the requirements on consumers (Caller Contract) are intended to survive unchanged to the mature protocol. Implementation choices (number of sources, staleness bound, presence of a circuit-breaker wrapper, exact aggregation function) will evolve. Divergences for the initial deployment are in Initial Deployment vs. Mature.

## Assumptions

The spec takes the following as given. If any is violated, the conclusions below do not hold.

- **Independent sources exist.** For each supported token in the mature protocol, there exist ≥ 2 independent price sources — uncorrelated in their failure and manipulation modes. Without this, multi-source aggregation buys no safety over a single feed, and the N5 / spread-check layer degenerates.
- **Sources attest `publishTime` truthfully.** A source reports the wall-clock instant at which its value was observed, up to bounded skew. If sources lie about time, staleness checks (N3) are defeated.
- **`block.timestamp` approximates wall-clock time within bounded skew.** The staleness check compares `block.timestamp − reading.publishTime` against a configured bound; the comparison is meaningful only to the skew's precision.
- **Majority-honest sources (Byzantine bound).** Across N sources, fewer than ⌈N/2⌉ are simultaneously compromised or stale. Required for median aggregation to be robust and for the spread check to be a useful signal.

## Nomenclature

| Term | Definition |
| :--- | :--- |
| **USD Numeraire** | A `FungibleToken` type representing USD for which no vault ever exists on-chain. Tokens like pyUSD, USDC, FUSD are *denominated in* the USD Numeraire. FCM prices everything in Numeraire units. |
| **Unit of Account** (UoA) | The `FungibleToken` type in which prices returned by the oracle are denominated. A Cadence `Type`, not a string. For FCM, always the USD Numeraire. |
| **Price Source** (or *source*) | An independent origin of pricing data — e.g., on-chain DEX pool, or a signed off-chain feed bridged onto Flow (Pyth, BandOracle). |
| **Independent sources** | Sources whose failure or manipulation modes are uncorrelated. Two DEX pools fed by the same arbitrageur flow are NOT independent; a DEX and a signed off-chain feed ARE. |
| **Staleness bound** | Maximum age of the newest datum a returned price depends on. Measured against source publish time (I7). |
| **δ_cadence** | Breaker-specific: the interval between scheduled `executeTransaction` invocations. Must satisfy T-I (`δ_cadence < stalenessBound`) and T-II (`historyWindow ≥ K · δ_cadence`). |

## Interface

```cadence
access(all) struct PriceReading {
    access(all) let value: UFix64
    access(all) let publishTime: UFix64
}

access(all) struct interface PriceOracle {
    access(all) view fun unitOfAccount(): Type
    access(all) fun price(ofToken: Type): PriceReading?
}
```

Two methods. The interface is part of this spec; implementations MUST NOT add methods returning a price without the full safety contract.

- `unitOfAccount()` — constant over the struct's lifetime (invariant I). `view`. Single source of truth for the oracle's unit of account; used for the registration handshake (C3).
- `price(ofToken)` — returns non-nil only if every Nil Contract condition holds; no panic under documented failure (I6). Not `view`: implementations may lazily refresh a cache, advance a pull-oracle source, or cross into Flow EVM (e.g., to call a Pyth update). Side effects MUST NOT alter future observations (invariant II). Querying an unsupported token is a normal `nil` (N1).

**`PriceReading` is the only way to observe a price.** `value` and `publishTime` are bundled in one atomic return so callers cannot observe one without the other. The interface MUST NOT offer a separate `publishTimeOf(token: Type)` getter — a two-call pattern reintroduces a race between the reads and defeats I7.

- `value` — number of `unitOfAccount()` units per one unit of the requested token, at `publishTime`.
- `publishTime` — source-attested observation instant (I7). For aggregators, the oldest contributing source's publishTime (min-semantics); for breakers, the publishTime of the last accepted observation, unchanged.

## Semantics

### Unit of account

A non-nil `price(ofToken: T)` is the number of UoA units per one unit of `T`, at the oracle's current time. For FCM, UoA is always the USD Numeraire (`Type<WorldCurrencies.USD>()`). UoA is a type, not a string — the compiler rejects cross-unit mismatches at registration (C3), not at query time.

If an implementation aggregates multiple underlying oracles, all MUST share the same `unitOfAccount()`. Verified on every `price()` call — a UoA mismatch returns `nil` via N4. Construction-time verification alone is insufficient because a source's storage-path target can be replaced after construction.

### Nil Contract

`price()` returns `nil` when the oracle can't produce a price the caller should rely on. Every implementation MUST return `nil` in at least:

- **N1 — Unsupported token.** The oracle is not configured to price `ofToken`.
- **N2 — Source unavailability.** Any required source returns nil, is missing the expected datum, or schema-mismatches. Source panics during the call are irreducible (see I6) and propagate as tx revert; the aggregator MUST structure its code to minimize additional panic surface. No silent fallback to zero / default / stale.
- **N3 — Staleness.** The newest underlying datum's source-attested `publishTime` is older than the implementation's staleness bound.
- **N4 — Internal inconsistency.** Overflow, unexpected zero, schema mismatch, invalid configuration.
- **N5 — Source disagreement** (multi-source only). Spread exceeds the configured threshold.

`nil` is a normal return, not an error. `price()` MUST NOT panic under any of these (I6).

## Invariants

A compliant implementation maintains the following at all times.

- **(I) Identity immutability.** `unitOfAccount()` is fixed at `init` and never mutates at runtime. The set of tokens the oracle is configured to price is also fixed at `init`. Changing either requires replacing the struct.
- **(II) Query idempotence.** `unitOfAccount()` is `view` (compile-time pure). `price()` is not `view` — side effects are permitted — but MUST NOT alter the value of a subsequent `price()` call beyond what a fresh query against live source data would already produce. Repeated `price(ofToken: T)` within the same block MUST return the same result.
- **(III) Reliability of non-nil.** Every non-nil `price(ofToken: T)` at time `t` satisfies every Nil Contract condition at `t`.
- **(IV) No silent substitution.** Non-nil values are freshly computed from sources whose attested publish time is within the staleness bound. Never a default, a cached-last-known-good past bound, or a zero.
- **(V) Source publish-time propagation.** Source-attested `publishTime` values are propagated through aggregation and history without being relabeled with pull time, insertion time, or `block.timestamp`. Type-enforced by `PriceReading.publishTime` being a `let` field set at construction; downstream layers MUST forward it (single-source) or take the `min` across contributing source publishTimes (aggregator).

## Caller Contract

Consumers of `price(ofToken: T)`:

- **C1 — Treat `nil` as a hard stop.** Every decision that depends on the price MUST abort or defer. No substituting a default, stale cache, or last-known-good.
- **C2 — Respect the unit of account.** Returned `UFix64` is in `unitOfAccount()` units (i.e., USD Numeraire). Different-unit conversions are the caller's responsibility.
- **C3 — Verify UoA at registration.** At wire-up, assert: `assert(oracle.unitOfAccount() == Type<WorldCurrencies.USD>(), message: "UoA mismatch")`. Consumers MAY re-check per query for defense-in-depth; aggregators internally do (Semantics → Unit of account).
- **C4 — Assume non-determinism across blocks.** `price()` may return different values across blocks. No reliance on monotonicity or bounded rate-of-change. Same-block repeats DO return the same value (invariant II), so caching within a single transaction is safe; caching across blocks is not. If cross-block stability is needed, wrap the oracle (Extension: Volatility Circuit Breaker).
- **C5 — Read once per operation.** "Operation" = one logical decision (a single position's liquidation check, a single NAV snapshot). Read `price()` once at the start of the operation and use the bound value throughout. Don't re-read inside loops. For operations that span multiple tokens (basket NAV), read each token's oracle once and treat any nil as all-nil (C1 hard stop applied to the whole basket).
- **C6 — Panic awareness.** `price()` may panic in read-through implementations (stateless aggregator, single-source oracle reaching an external contract — see I6). Cadence cannot catch it; the caller's transaction aborts. In the mature protocol, reads route through the circuit breaker, which is structurally panic-free. Until the breaker ships, callers MUST confine `price()` calls to contexts where transaction abort is an acceptable failure mode (not: batch liquidation of many positions; not: multi-token NAV computation where a single source panic reverts everything).

## Implementer Requirements

### I1 — Multi-source independence. SAFETY-CRITICAL.

The mature protocol requires ≥ 2 **independent** sources, with at least one source that is not derived from on-chain liquidity (e.g., Pyth or BandOracle, the two signed off-chain feeds currently available on Flow). A single source — or multiple sources all sharing a failure mode (e.g., all DEX-spot) — can be stale, frozen, or manipulated with no meaningful cross-check; this limitation cannot be fixed by tuning parameters.

If the initial deployment ships a single-source oracle under the shortcut in Initial Deployment vs. Mature, the implementation MUST carry:
1. Prominent header warning in the source file stating that the implementation is INCOMPATIBLE with the mature protocol.
2. Observable `sourceCount` field or `view fun sourceCount(): Int`.
3. An observable init-time marker (event or on-chain state) advertising the single-source deployment so off-chain monitoring can detect it.

These controls make the unsafe configuration *loud*; they do not make it safe.

*Aggregation ≠ dynamic oracle selection.* Multi-source aggregation requires ALL configured sources to produce fresh, agreeing data; any failure ⇒ nil. Dynamic oracle selection (picking among sources based on freshness / deviation) is a disguised fallback chain and explicitly out of scope — distinct from aggregation.

### I2 — No stale-as-fresh.

MUST NOT return a price as current when its underlying datum is older than the staleness bound. When in doubt, nil.

### I3 — No silent degradation.

Any non-steady-state transition from "can produce a price" to "cannot" — source panic caught, arithmetic fault, schema mismatch — MUST be surfaced observably so off-chain monitoring can detect it. The mechanism (event, observable state field, etc.) is not prescribed.

### I4 — Document every nil condition.

Every implementation MUST enumerate its documented nil conditions in a doc comment, with the configuration parameter that governs each. A reviewer reading only the doc comment MUST be able to predict return values for observable inputs.

### I5 — Non-view discipline.

Implementer guidance for achieving invariant II under a non-`view` `price()`. Implementations MAY have side effects — lazy cache refresh, pull-source feed advancement, crossing into Flow EVM (e.g., Pyth update calls), observability signalling — but MUST ensure those side effects do not alter the value of a subsequent `price()` call relative to what a fresh query against live sources would produce, and that same-block repeats return the same result. Persistent state mutation (history append, cache write on the scheduled tick) belongs on entitled methods outside this interface, not on `price()` itself.

### I6 — Panic risk.

Cadence has no `try`/`catch`. A `price()` call that crosses into externally-controlled code (any source call) can panic and abort the caller's transaction; the platform offers no way to wrap it. This is not fixable at the implementer level.

The only structurally panic-free `price()` is one that serves from local state. The circuit breaker does this: its `price()` reads `history.last` off a local resource; all source calls happen in `executeTransaction` (a separate scheduled tx), so upstream panics revert the tick, not the consumer.

Implementers of read-through oracles SHOULD use defensive access (nil-check `borrow()`, no force-unwraps, checked arithmetic) so their OWN code doesn't add panic surface on top of the upstream one. This is hygiene — fewer wasted scheduled ticks, cleaner diagnostics — not a safety guarantee.

Consumer responsibility: see C6.

### I7 — Honor source publish time; never relabel.

Each source datum carries an attested publish time (Pyth `publishTime`, BandOracle's quote timestamp, DEX pool block time of last trade). Staleness and deviation checks MUST use that time, not the aggregator's own pull / insertion time. An implementation that relabels silently launders stale data past the staleness check. A future-dated publish time (clock skew, adversarial) MUST trigger nil via N4.

## Authorities

- **Query path** — any caller. `unitOfAccount()` is compile-time `view`. `price()` is non-`view` (to allow event emission, lazy-refresh patterns, and EVM-side operations — e.g., triggering a Pyth price update on Flow EVM) but bound by invariant II — same-block repeats return the same value, and no side effect may alter a subsequent query's result.
- **Scheduled-tx entitlement** — scoped to the circuit breaker's `CircuitBreaker.executeTransaction` (called by `FlowTransactionScheduler`). Not applicable to the aggregator (stateless). Not callable by public traffic.
- **Deployment** — creating, wiring, and retiring oracles at the protocol layer is outside this interface. Deployed oracles are immutable (invariant I); any change requires redeploy.

## Safety and Liveness

**Safety** — no consumer observes a non-nil price that violates invariants (I)–(V) or any Nil condition.

**Liveness** — under nominal operation with the scheduled update running and healthy sources, consumer queries return fresh, reliable prices.

Both arguments proceed by scenario walk.

### Scenario I — nominal operation

Sources publish new data; the scheduled update pokes on cadence; aggregator (or breaker on top of aggregator) records successful observations; consumer queries read `history.last` and receive non-nil prices. Invariants (I)–(V) hold by construction: UoA and supported set constant (I); same-block `price()` repeats return the same value and no side effect steers a later read (II); observations accepted by the scheduled update only after N3/N5/I7 checks, so non-nil implies reliable (III); substitution is forbidden (IV); publish time propagates through (V).

### Scenario II — transient failure (source nil, spread spike, breaker trip)

A source drops, sources diverge, or the current observation deviates past the breaker's threshold. The scheduled poke fails → `history` is **not** appended (B-IV atomic per-tick). The previous tail entry remains until it ages out via N3; during that window, consumers see the last accepted value (still reliable at its publish time). If the failure resolves within the staleness bound, the next successful poke appends — automatic recovery (T-IV). If the failure persists beyond the bound, `price()` returns nil until resolution. No consumer ever observes a value that violated the trip condition at acceptance time.

### Scenario III — persistent failure (scheduler stall, state-resource destroyed, source permanently compromised)

Scheduled tx stops running (scheduler stall, operator action, bug). `history.last.publishTime` does not advance. Once `now − history.last.publishTime > stalenessBound`, `price()` returns nil via N3 (B-V + T-I). If `CircuitBreaker` is destroyed, the capability borrow returns nil and `price()` returns nil (B-III + capability topology). Consumers fail closed. Recovery requires operator intervention (restart scheduler, redeploy state, swap sources).

### Scenario IV — warm-up

Before the first successful poke of a freshly-deployed breaker, `history` is empty. `price()` returns nil. No bootstrap value, no default. Consumers must tolerate the warm-up window between breaker creation and the first accepted observation.

**Conclusion.** In all four scenarios, safety holds (no non-nil wrong value). Liveness holds trivially in Scenario I, recovers automatically in II and IV, and requires operator action in III. This matches the intended design: failures are transient by default, structural compromise is operator-escalated.

## Extension: Multi-Source Aggregator

Required by the mature protocol. The aggregator is the **per-token price producer**: it pulls current observations from N independent sources, applies safety checks, returns an aggregate.

### Design: stateless, live-query

The aggregator is a pure view over live source capabilities. On each `price()` call: pull, check, aggregate, return. No cache, no history, no scheduled updates at this layer.

Rationale:
- Combining N current observations is a pure function; giving it state would be bolting on work that belongs in a caching/analysis layer above (such as the breaker).
- Consumer efficiency comes from a caching layer above (such as the breaker, which caches as a byproduct of its deviation check). Without one, consumers pay O(N) per query — acceptable at initial scale.
- No stored state, no storage fee, no scheduled-transaction dependency at this layer.

### Sketch

```cadence
access(all) struct AggregatorOracle: PriceOracle {
    // Config units/representations are placeholders — concrete choice deferred to implementation.
    access(self) let _token: Type
    access(self) let _unitOfAccount: Type
    access(self) let sources: [{PriceOracle}]
    access(self) let spreadThreshold: UFix64                // unit TBD at impl
    access(self) let stalenessBound: UFix64                 // seconds

    access(all) view fun unitOfAccount(): Type { return self._unitOfAccount }

    access(all) fun price(ofToken: Type): PriceReading? {
        if ofToken != self._token { return nil }
        // 1. Pull PriceReading from each source (borrow-checked, no force-unwraps per I6).
        // 2. Any source nil → N2 nil.
        // 3. Any source's reading.publishTime older than staleness bound → N3 nil.
        // 4. Spread across source values > threshold → N5 nil.
        // 5. Apply aggregation function to source values (median or mean).
        // 6. Return PriceReading(value: aggregate, publishTime: min(source publishTimes)).
        return nil  // placeholder
    }
}
```

### Aggregation function

Open question (Open Questions). Candidates:

- **Median** — Byzantine-robust to `(N−1)/2` compromised feeds; degenerate at N=2. **Dominant in prior art:** MakerDAO Medianizer, Chainlink OCR, Band all use median.
- **Arithmetic mean** — simpler; biased by outliers; needs tight N5 spread threshold to bound outlier exposure. No major safety-oriented on-chain oracle uses plain mean.
- **Weighted mean** — per-source reliability weights; more parameters. **Prior art:** Pyth uses confidence-weighted aggregation.

At expected source counts (likely 2–3), the choice matters less than the N5 threshold. Decide once source shortlist is concrete.

## Extension: Volatility Circuit Breaker

The volatility circuit breaker (optional in the initial deployment, mature MUST) is a *temporal* safety layer that wraps the aggregator. Complementary to the *spatial* source-spread check (N5): N5 catches **single-source manipulation** (one source disagreeing with the others — caught per-tick by spread); the breaker catches **correlated fast movement of the aggregate itself** (median shifting too quickly, e.g., all sources reflecting a flash-crash or a coordinated manipulation across venues) — which N5 cannot see because every source agrees.

### Design: wrap, don't bake in; aggregate-level layering

Breaker wraps an already-aggregated `PriceOracle`:

```
CircuitBreakerOracle  ← temporal check
  └── AggregatorOracle  ← spatial check (N5)
        ├── Source A
        └── Source B
```

**Why wrap at the aggregate level, not per-source** (short version): under N5, per-source temporal checks are redundant for single-source manipulation — spread already catches it. The remaining threat (correlated fast movement across sources) is mathematically more detectable at the aggregate layer — under iid normality with N sources, aggregate-level trip fires at `k·σ` while per-source-with-FPR-correction fires at `k'·σ > k·σ`. Choice follows from N5 carrying the single-source-manipulation load independently. If N5 is ever weakened, revisit this layering.

### Sketch (struct + resource)

Mutable persistent state (`history`) is a `CircuitBreaker` *resource* stored on a protocol-controlled account. The `CircuitBreakerOracle` *struct* holds a capability to that resource and serves reads on the query path. **Why split:** the `PriceOracle` interface is a struct interface — the query surface must be a cheap-to-copy struct — but mutable state belongs in a resource where entitlements gate writes. Split gives us both: reads through the struct, mutation behind an entitled capability to the resource.

```cadence
// The resource holds state, config, AND acts as the scheduled-transaction
// handler. Implementing TransactionHandler lets FlowTransactionScheduler
// call directly into this resource — no separate handler needed.
access(all) resource CircuitBreaker: FlowTransactionScheduler.TransactionHandler, ViewResolver.Resolver {
    // Immutable identity + config (set at init).
    // Units/representations are placeholders — concrete choice (bps vs fraction vs log-ratio, etc.)
    // is deferred to implementation and calibrated per token.
    access(all) let token: Type
    access(all) let unitOfAccount: Type
    access(all) let upstream: Capability<&{PriceOracle}>     // the oracle being wrapped
    access(all) let deviationThreshold: UFix64               // unit TBD at impl
    access(all) let historyWindow: UFix64                    // seconds
    access(all) let stalenessBound: UFix64                   // seconds

    access(all) var history: [PriceReading]                  // bounded ring buffer

    // Called by FlowTransactionScheduler on the configured cadence.
    // Signature matches FlowTransactionScheduler.TransactionHandler exactly.
    access(FlowTransactionScheduler.Execute)
    fun executeTransaction(id: UInt64, data: AnyStruct?) {
        // 1. Pull PriceReading from self.upstream.
        //    If borrow fails or reading is nil → no-op this tick.
        // 2. reading.publishTime ≤ history.last?.publishTime → no-op (event-driven).
        // 3. Prune history outside [reading.publishTime − self.historyWindow, reading.publishTime].
        // 4. Compute deviation against the remaining window.
        // 5. If deviation > self.deviationThreshold → emit a trip event; DO NOT append.
        //    Else → append reading; emit an acceptance event.
    }

    // ViewResolver.Resolver conformance (required by TransactionHandler).
    access(all) view fun getViews(): [Type] { return [] }
    access(all) fun resolveView(_ view: Type): AnyStruct? { return nil }

    // Single-point read: returns the last reading accepted by executeTransaction
    // (validity at acceptance from B-VI) iff it is still within self.stalenessBound.
    //   - history empty → nil (warm-up).
    //   - history.last.publishTime aged past self.stalenessBound → nil (N3).
    //     This is how failed ticks (panic / stall / persistent trip) surface
    //     to consumers: history stops advancing, staleness fires nil.
    //   - otherwise → history.last.
    access(all) view fun current(): PriceReading? {
        return nil  // placeholder
    }
}

// Queryable shell held by consumers. Forwards to the underlying CircuitBreaker.
access(all) struct CircuitBreakerOracle: PriceOracle {
    access(self) let breaker: Capability<&CircuitBreaker>
    // UoA and token are immutable (Invariant I), so we snapshot at construction.
    // unitOfAccount() and the token-match branch in price() stay panic-free
    // even if the underlying resource is later destroyed.
    access(self) let _unitOfAccount: Type
    access(self) let _token: Type

    init(breaker: Capability<&CircuitBreaker>) {
        // Init-time panic is loud (deployment fails) and acceptable — the oracle
        // never exists in a broken state. Post-init, queries never panic.
        let b = breaker.borrow() ?? panic("CircuitBreakerOracle: capability does not resolve")
        self.breaker = breaker
        self._unitOfAccount = b.unitOfAccount
        self._token = b.token
    }

    access(all) view fun unitOfAccount(): Type {
        return self._unitOfAccount
    }

    access(all) fun price(ofToken: Type): PriceReading? {
        // 1. Wrong token (ofToken != self._token) → N1 nil.
        // 2. Breaker capability no longer resolves → nil.
        // 3. Otherwise forward to breaker.current() — which returns the last
        //    accepted reading if still within the staleness bound, else nil.
        // No staleness check here; single-point guard lives in current().
        return nil  // placeholder
    }
}
```

Note on `unitOfAccount()` and the token check: both read snapshot fields (`_unitOfAccount`, `_token`) captured at struct init. The struct's `init` is the only place that panics — it asserts the capability resolves at construction time. Post-init, the query path cannot panic on a destroyed or broken resource: `price()` borrows gracefully and returns nil, `unitOfAccount()` doesn't borrow at all. This matches invariant I (UoA and token are immutable over the struct's lifetime) — snapshotting is correct by construction.

The `CircuitBreaker` resource serves two purposes at once: it's the stateful time-series analyzer (for the deviation check), and it's the caching layer that makes consumer queries O(1) (query reads `history.last` instead of re-aggregating sources). That dual role is why the breaker makes a stateless aggregator practical at scale.

### Storage and lifecycle

`CircuitBreaker` lives at a deterministic path on a protocol-controlled account (oracle contract account or dedicated operator account). One per wrapped token.

- **Funding.** Protocol treasury funds `MinimumStorageReservation` — same mechanism as scheduled-tx execution. Bounded: `O(maxHistoryEntries × sizeof(PriceReading))`; `maxHistoryEntries` capped at init, never grows.
- **Creation.** Protocol deployment creates the resource at init and issues a public `Capability<&CircuitBreaker>` for the `CircuitBreakerOracle` struct to hold. Scheduled invocation of `executeTransaction` is registered separately via `FlowTransactionScheduler.schedule(...)`, which manages the `Execute`-entitled handle internally. An off-chain-indexable creation event is emitted.
- **Teardown.** Protocol deployment destroys the resource, paired with descheduling the scheduled tx. Downstream borrows return nil → consumers fail-closed. A matching teardown event is emitted.
- **Capability topology enforces invariant II.** The struct's capability is unentitled, and `history` is `access(self)` — no external reference can mutate state regardless of what caller holds the cap.

### Scheduled execution is required

The breaker depends on `FlowTransactionScheduler` calling `executeTransaction` on a documented cadence. Without a running schedule, the most recent accepted observation ages past the staleness bound (N3) and consumers fail-closed.

**Panic behavior in `executeTransaction`.** An upstream-source panic reverts the scheduled tx — history is unchanged (safe) but the tick is lost. Implementations MUST minimize their *own* panic surface here so tick loss only reflects real upstream failure, not self-inflicted bugs. Detection and recovery strategies (inferring a missed tick, rescheduling, health events) are implementation choices and not prescribed.

**Precedent for scheduled-cadence update mechanisms:** MakerDAO OSM's `poke()` (keeper-driven, 1-hour delay), Chainlink Data Feeds (OCR heartbeat + deviation), Pyth Network (caller-pays pull model). Different incentive models, same "external cadence drives state" pattern. Flow's native scheduler is equivalent but protocol-funded (no keeper-network unreliability or caller-pays-to-update complication).

### Metric shape — implementation choice

Not prescribed. Defensible shapes:

- **Last-known-good comparison** — `|Δ log p|` vs last accepted. Minimal state. Liquity-style.
- **EMA reference** — deviation from exponentially-weighted moving average.
- **TWAP reference** — deviation from a time-weighted average window.
- **Sampled-window realized variance** — `σ̂² = (1/(N−1)) Σ r_i²`; trip at `|r|/√Δt > k·σ̂`. Most parameters.

All are heuristics under real (fat-tailed, regime-switching) return distributions; threshold calibration is empirical per token. No on-chain breaker has overcome this. The *structural* guarantees below hold regardless of metric.

### Invariants and timing bounds

- **B-I Fail-closed on trip.** When a deviation check rejects an observation, breaker state is unchanged. Consumers continue to see the previously-accepted value until it ages past the staleness bound (N3). Trip signalling to off-chain monitoring is covered by I3.
- **B-II Publish-time discipline.** Specialization of Invariant V: every observation recorded by the breaker carries a source-attested `publishTime`, never relabeled with pull-time, insertion-time, or `block.timestamp`.
- **B-III Query idempotence.** Specialization of Invariant II / I5: consumer reads cannot mutate breaker state; state mutation is restricted to the scheduled-tick context. Same-block reads return the same value.
- **B-IV Atomic per-tick update.** Each scheduled tick either commits its state transition — new observation, any pruning — in full, or commits nothing. No partial states.
- **B-V History monotonic and window-bounded.** The internal observation log is strictly increasing in `publishTime`; retained entries lie within a configured window ending at the most recent observation.
- **B-VI Per-observation bound.** For every observation served to consumers, the deviation check held at acceptance — `|log(p_curr / reference(history))| ≤ threshold`. Form of `reference` depends on metric; bound holds regardless.
- **B-VII Immutable breaker config.** Extends Invariant I: breaker configuration — deviation threshold, history window, staleness bound, scheduled-tick cadence, aggregator source — is fixed at construction. Changing any requires redeployment.

**Timing:**

- **T-I** `δ_cadence < stalenessBound`. Otherwise `history.last` ages past the staleness bound between ticks even under nominal operation. Scheduler stalls cause N3 nil — fail-closed on outage.
- **T-II** `historyWindow ≥ K · δ_cadence` for `K ≥ 2`. K = 2 is the structural floor — deviation is undefined with a single observation. Practical K is metric-dependent and open (see Metric shape).
- **T-III Event-driven.** Trip evaluation only on publish-time advance; same-time pokes are no-ops.
- **T-IV Automatic recovery.** No persistent "broken" flag. Next non-tripping observation appends to `history` and advances the served reading. Transient failures resolve automatically; structural compromise escalates to operator intervention (different from Liquity's persistent-break model).

**Composite bound (end-to-end):** for every non-nil `p` returned at wall-clock `t` with source publish time `τ`:

```
t − τ  ≤  stalenessBound_breaker  +  stalenessBound_aggregator  +  δ_cadence  +  σ_scheduler  +  ε_skew
```

Components: the breaker's staleness gate, the aggregator's staleness gate, the worst-case wait between scheduled ticks, scheduler-slack (actual inter-tick delay may exceed the nominal cadence), and clock-skew between source-attested `publishTime` and on-chain block time (per Assumptions). Tune so the composite bound is acceptable for risk-critical reads; `σ_scheduler` and `ε_skew` depend on the deployment environment and are bounded rather than tuned.

### What the breaker MUST NOT do

- Return a non-nil value the inner aggregator did not return (breaker is a nil-adding filter, never a substitution).
- Return a stale price in lieu of a live one past the staleness bound.
- Fall back to a different aggregator on trip.

## Initial Deployment vs. Mature Protocol

This spec describes the mature protocol. The initial deployment may diverge as temporary shortcuts — each is well-encapsulated so mature-protocol progression is an implementation change, not a spec change.

- **Single-source oracle (possibly).** If approved under the beta constraints (invite-only, FYV-only, <$1M exposure), the initial deployment may ship with one source carrying the I1 compensating controls. Mature MUST NOT.
- **No volatility circuit breaker.** Optional initially; mature MUST. Progression: wrap the aggregator with `CircuitBreakerOracle`; no interface change.

### What to research before mature launch

- Catalog of acceptable source pairings — which count as "independent" under I1, under what market assumptions.
- Staleness bound and scheduled-tx cadence calibration per source type.
- Breaker metric and parameter defaults per supported token.
- Concrete spread metric for N5.

## Open Questions

- **Single-source for initial deployment?** Protocol lead to decide. The spec accommodates either path; single-source path carries I1 compensating controls.
- **Aggregation function (median vs. mean).** Matters less at low N, more at higher N. Decide once source shortlist is concrete.
- **Staleness bound.** Implementation-defined per source type; must satisfy T-I for the breaker's cadence.
- **Spread metric and threshold for N5.** To be calibrated against source-disagreement noise.
- **Breaker scheduled-tx cadence (`δ_cadence`).** Must satisfy T-I and T-II. Default TBD.
- **Breaker metric shape** (last-known-good / EMA / TWAP / sampled variance) and parameters. Empirical per token.

## Non-Goals

- **Fallback chains / dynamic oracle selection.** Distinct from aggregation; disguised single-source. Out of scope.
- **On-chain calibration of breaker parameters.** Parameters are fixed at deployment.
- **Drop-in conformance to `DeFiActions.PriceOracle`.** The interface is intentionally shape-aligned with `DeFiActions.PriceOracle` — same `unitOfAccount(): Type` + `price(ofToken: Type)` core — but returns `PriceReading?` instead of `UFix64?` for atomicity (I7). Callers SHOULD treat the two as semantically compatible for adapter purposes; formal conformance is not a goal.
- **Interest-rate, yield, or non-price feeds.** Out of scope.

## Known Limitations

Deliberate acknowledgments where the spec's safety model has honest gaps.

- **Lying implementer.** No invariant in this spec prevents a `PriceOracle` implementation from returning a value that is internally self-consistent (correct `unitOfAccount()`, plausible `publishTime`) but semantically wrong (price value lies). The sole defense is multi-source aggregation (I1) with at least one non-on-chain source — a bad source gets dominated by honest peers. This is a governance/audit concern for mature deployment, not a technical enforcement layer.
- **Capability-swap with matching UoA.** Per-call UoA verification catches a source whose storage-path target is re-bound to a different-UoA oracle. It does NOT catch a swap to a different oracle with the same UoA (e.g., WETH/USD swapped to WBTC/USD). Future mitigation: pin source identity (address + path hash or capability controller ID) at construction and re-verify per tick.


