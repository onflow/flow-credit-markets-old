import "FungibleToken"

/// FlowALP (Automated Lending Protocol)
///
/// OVERVIEW
/// The Pool resource is the core container of state and logic for FlowALP. It holds deposits,
/// maintains position and ledger state, and provides core functionality.
///
/// To interact with FlowALP, users create a Position. This causes a PositionRecord to be stored in the Pool,
/// and returns a Position resource to the user. The Position resource represents authorization to interact with the position,
/// for example withdrawing/depositing funds.
///
/// The Pool supports a limited set of tokens. Each supported token has associated information, which
/// is tracked with the TokenStateRecord type. Tokens are identified by their Type.
///
/// The Reserves resource holds all funds and manage deposits and withdrawals.
///
/// MODEL CONVENTIONS
/// 1. Types which are primarily used to persist data in storage are named ".*Record".
///    Record types are mutated only by their own methods: fields are access(self),
///    mutators are access(contract) (or narrower).
///
/// DESIGN: Validator / StateMutation pipeline
/// All state changes flow through a two-phase pipeline. Operations on the Pool are
/// structured as:
///
///     mutations <- validateXxx(&pool, args)     // Phase 1: validate
///     pool.applyMutations(<- mutations)         // Phase 2: apply
///     // ... any resource output effects ...
///     pool.checkInvariants()                    // Phase 3: invariants
///
/// Phase 1 — Validation (read-only w.r.t. Pool state).
///   Validators are contract-level functions that receive an un-entitled `&Pool`
///   as a live read-only snapshot. They enforce all operation-level business rules
///   (supported tokens, caps, health factors, paused state, ...) and panic on any
///   rejected operation. On success they return `@[{StateMutation}]` — a list of
///   resource-typed mutations describing the state changes to apply.
///
/// Phase 2 — Application.
///   `Pool.applyMutations` consumes the list, invoking each mutation's `apply()`
///   with an `auth(MutateState) &Pool`. The `MutateState` entitlement gates the small set
///   of Pool methods that actually write state; since validators are the only
///   constructors of concrete mutation types (each has an `access(contract)` init),
///   only validated mutations can trigger a write.
///
/// Phase 3 — Invariants.
///   `Pool.checkInvariants` is called once at the end of each operation, after
///   all mutations have been applied and any direct resource effects (e.g. the
///   vault returned by a withdraw) have resolved. It verifies pool-level and
///   position-level invariants; any violation panics and reverts the tx.
///
/// Resource I/O.
///   Resources flowing *into* the Pool are modeled as mutations (e.g. `VaultDeposit`
///   carries the incoming vault and deposits it into Reserves on apply). Resources
///   flowing *out* of the Pool (e.g. the vault produced by a withdraw) are NOT
///   modeled as mutations — they are direct effects performed by the operation
///   body between `applyMutations` and `checkInvariants`. The invariant check
///   (Σ ledger = reserves, per supported token) is what binds the two consistent.
///
/// Composability.
///   Mutations are composable deltas, not idempotent absolute writes. A single
///   operation may produce multiple deltas for the same (positionID, tokenType),
///   and multi-leg operations (e.g. liquidation) may emit heterogeneous lists.
///
access(all) contract FlowALP {

    /* ---------- Storage Paths ---------- */

    access(all) let PoolStoragePath: StoragePath
    access(all) let PoolPublicPath: PublicPath

    /* ---------- Entitlements ---------- */

    /// Admin operations: pause/unpause, configuration, risk parameters,
    /// adding supported tokens, liquidation overrides, etc. Held by the
    /// deployer (or a governance resource) — never granted to end users.
    access(all) entitlement Admin

    /// Enables opening and interacting with positions (withdraw/deposit/...)
    /// In the mature protocol, these actions will be publicly accessible.
    access(all) entitlement Participant

    /// Enables manual liquidation. This is gated as a safety precaution.
    /// In the mature protocol, liquidation should be a publicly accessible operation.
    access(all) entitlement Liquidate

    /// Grants access to internal methods, for use by co-operating internal components.
    /// This entitlement MUST NEVER be granted externally.
    access(all) entitlement Internal

    /// Gates the low-level state-writing methods on Pool.
    /// An `auth(MutateState) &Pool` is produced only inside `Pool.applyMutations`,
    /// which passes it to each `StateMutation.apply`. No capability with this
    /// entitlement is ever stored or shared; it MUST NEVER escape the pipeline.
    access(all) entitlement MutateState

    /* ---------- Value Types ---------- */

    /// Direction of a signed balance. A position's balance for a given
    /// token is either a Credit (the position has lent / deposited net)
    /// or a Debit (the position has borrowed / withdrawn net).
    access(all) enum BalanceDirection: UInt8 {
        access(all) case Credit
        access(all) case Debit
    }

    /// A directional value: a Credit/Debit direction paired with an unsigned
    /// magnitude. Used for balances, deposits, withdrawals, and any other
    /// quantity that can apply in either direction.
    access(all) struct SignedAmount {
        access(all) let direction: BalanceDirection
        access(all) let quantity: UFix64

        view init(direction: BalanceDirection, quantity: UFix64) {
            self.direction = quantity == 0.0 ? BalanceDirection.Credit : direction
            self.quantity = quantity
        }
    }

    /* ---------- State Mutations ---------- */

    /// StateMutation
    ///
    /// A validated, applicable change to Pool state. Concrete mutations are
    /// resources whose `init` is `access(contract)`, so only validator
    /// functions in this contract can construct them. They are consumed
    /// exactly once by `Pool.applyMutations`, which invokes `apply` with
    /// an `auth(MutateState) &Pool` — the only handle permitted to write state.
    access(all) resource interface StateMutation {
        access(MutateState) fun apply(pool: auth(MutateState) &Pool)
    }

    /// LedgerDelta
    ///
    /// Additive change to a position's balance for a single token. Composable:
    /// multiple deltas for the same (positionID, tokenType) within one
    /// `applyMutations` call are summed in order.
    access(all) resource LedgerDelta: StateMutation {
        access(all) let positionID: UInt64
        access(all) let tokenType: Type
        access(all) let delta: SignedAmount

        access(contract) init(positionID: UInt64, tokenType: Type, delta: SignedAmount) {
            self.positionID = positionID
            self.tokenType = tokenType
            self.delta = delta
        }

        access(MutateState) fun apply(pool: auth(MutateState) &Pool) {
            pool.applyLedgerDelta(
                positionID: self.positionID,
                tokenType: self.tokenType,
                delta: self.delta,
            )
        }
    }

    /// VaultDeposit
    ///
    /// Moves an incoming vault into Reserves. The vault is carried inside the
    /// mutation until apply, at which point it is consumed by the Pool's
    /// MutateState-gated applier.
    access(all) resource VaultDeposit: StateMutation {
        access(self) var vault: @{FungibleToken.Vault}?

        access(contract) init(vault: @{FungibleToken.Vault}) {
            self.vault <- vault
        }

        access(MutateState) fun apply(pool: auth(MutateState) &Pool) {
            let v <- self.vault <- nil
            pool.applyVaultDeposit(from: <- v!)
        }
    }

    /* ---------- Token State ---------- */

    /// TokenStateRecord
    ///
    /// Holds all persisted metadata related to a token supported by the Pool.
    /// Supported tokens are uniquely identified by their Cadence Type (eg. `token.getType()`)
    /// Each supported token must implement the FungibleToken interface.
    access(all) struct TokenStateRecord {
        access(self) var tokenType: Type
        // TODO: total credit/debit balance, borrow/collateral factors, interest indices will live here

        init(
            tokenType: Type,
        ) {
            self.tokenType = tokenType
        }
    }

    /* ---------- Position State ---------- */

    /// PositionRecord
    ///
    /// Holds all persisted state related to a particular Position.
    /// Positions are uniquely identified by their ID, which is the UUID of the Position resource
    /// granted when the position is opened.
    access(all) struct PositionRecord {
        /// Mirror of the Position resource's UUID; same value the Pool uses as dict.
        /// TODO: This field is copied here to enable this struct to be fully self-describing: remove if this property is not needed.
        access(all) let id: UInt64

        /// Set of credit and debit balances associated with this position.
        /// TODO(jord): currently these are non-scaled as there is no interest accrual.
        access(self) var balances: {Type: SignedAmount}

        init(id: UInt64) {
            self.id = id
            self.balances = {}
        }

        access(all) view fun getBalance(tokenType: Type): SignedAmount {
            return self.balances[tokenType]
                ?? SignedAmount(direction: BalanceDirection.Credit, quantity: 0.0)
        }

        /// Compose a delta into the current balance for the given token.
        /// Called only by `Pool.applyLedgerDelta`, which is itself gated by
        /// the `MutateState` entitlement.
        access(contract) fun applyDelta(tokenType: Type, delta: SignedAmount) {
            // TODO: sum `delta` into `balances[tokenType]`, handling
            // direction flips (e.g. a Credit+Debit that crosses zero).
            let _t = tokenType
            let _d = delta
        }
    }

    /* ---------- Reserves ---------- */

    /// Reserves
    ///
    /// Custody component that owns the FungibleToken vaults backing the Pool.
    /// All token movements performed by the Pool are mediated by Reserves.
    access(all) resource Reserves {
        access(self) var vaults: @{Type: {FungibleToken.Vault}}

        init() {
            self.vaults <- {}
        }

        /// Register a new supported token. Caller supplies an empty vault
        /// of the correct type to establish custody. Fails if already
        /// supported.
        access(contract) fun addSupportedToken(emptyVault: @{FungibleToken.Vault}) {
            pre {
                emptyVault.balance == 0.0: "initial vault must be empty"
                self.vaults[emptyVault.getType()] == nil: "token must not already be supported"
            }
            let tokenType = emptyVault.getType()
            self.vaults[tokenType] <-! emptyVault
        }

        /// Deposit into the appropriate vault. Fails if token type unsupported.
        access(contract) fun deposit(from: @{FungibleToken.Vault}) {
            let tokenType = from.getType()
            let vaultRef = (&self.vaults[tokenType] as &{FungibleToken.Vault}?)
                ?? panic("unsupported token type")
            vaultRef.deposit(from: <-from)
        }

        /// Withdraw from the appropriate vault. Fails if unsupported or
        /// insufficient balance.
        access(contract) fun withdraw(tokenType: Type, amount: UFix64): @{FungibleToken.Vault} {
            let vaultRef = (&self.vaults[tokenType] as auth(FungibleToken.Withdraw) &{FungibleToken.Vault}?)
                ?? panic("unsupported token type")
            return <- vaultRef.withdraw(amount: amount)
        }

        /// Returns the current reserve balance of the given token.
        /// If the token is unsupported, returns 0.
        access(all) view fun getBalance(tokenType: Type): UFix64 {
            if let vaultRef = &self.vaults[tokenType] as &{FungibleToken.Vault}? {
                return vaultRef.balance
            }
            return 0.0
        }

        /// Returns the set of supported tokens. Output list has no guaranteed order.
        access(all) view fun getSupportedTokens(): [Type] {
            return self.vaults.keys
        }

        /// Returns true if the given token is supported.
        access(all) view fun isSupported(tokenType: Type): Bool {
            return self.vaults[tokenType] != nil
        }
    }

    /* ---------- Pool Configuration ---------- */

    /// Pool-level configuration. Held inside the Pool resource and mutated
    /// only via the Admin entitlement.
    access(all) struct PoolConfig {
        /// The token used as the pool's numeraire (unit of account).
        access(all) let numeraire: Type
        /// When paused, the pool rejects deposits, withdrawals, and liquidations.
        access(self) var paused: Bool

        init(
            numeraire: Type,
        ) {
            self.numeraire = numeraire
            self.paused = false
        }
    }

    /* ---------- Validators ---------- */

    /// Validators are the sole constructors of StateMutation resources.
    /// Each validator:
    ///   - receives an un-entitled `&Pool` as a read-only snapshot of live state,
    ///   - enforces all operation-level business rules (panicking on violation),
    ///   - returns `@[{StateMutation}]` describing the state changes to apply.
    ///
    /// Validators never mutate Pool state directly; all writes happen in
    /// `Pool.applyMutations`. This separation keeps business rules co-located
    /// and independently testable, and gives auditors a single choke point —
    /// `Pool.applyMutations` — through which all writes flow.

    /// validateDeposit
    ///
    /// Validates a deposit of `vault` into the position identified by `positionID`.
    /// On success returns a VaultDeposit (to move the vault into Reserves) and
    /// a LedgerDelta crediting the position by the vault's amount.
    access(contract) fun validateDeposit(
        pool: &Pool,
        positionID: UInt64,
        vault: @{FungibleToken.Vault},
    ): @[{StateMutation}] {
        // TODO: enforce
        //   - pool not paused
        //   - vault.getType() is supported
        //   - positionID refers to an existing position
        //   - per-token deposit cap not exceeded
        let _p = pool
        let tokenType = vault.getType()
        let amount = vault.balance

        let mutations: @[{StateMutation}] <- []
        mutations.append(<- create VaultDeposit(vault: <- vault))
        mutations.append(<- create LedgerDelta(
            positionID: positionID,
            tokenType: tokenType,
            delta: SignedAmount(direction: BalanceDirection.Credit, quantity: amount),
        ))
        return <- mutations
    }

    /// validateWithdraw
    ///
    /// Validates a withdrawal of `amount` of `tokenType` from the position
    /// identified by `positionID`. On success returns a LedgerDelta debiting
    /// the position. The vault output itself is produced as a direct effect of
    /// the operation (see Pool.internalWithdraw), not as a mutation.
    access(contract) fun validateWithdraw(
        pool: &Pool,
        positionID: UInt64,
        tokenType: Type,
        amount: UFix64,
    ): @[{StateMutation}] {
        // TODO: enforce
        //   - pool not paused
        //   - tokenType is supported
        //   - position exists
        //   - post-op health factor ≥ 1 (using pool snapshot)
        //   - per-token withdraw / borrow caps not exceeded
        let _p = pool
        let mutations: @[{StateMutation}] <- []
        mutations.append(<- create LedgerDelta(
            positionID: positionID,
            tokenType: tokenType,
            delta: SignedAmount(direction: BalanceDirection.Debit, quantity: amount),
        ))
        return <- mutations
    }

    /// Pool
    ///
    /// The Pool is the top-level container implementing the FlowALP protocol.
    /// It orchestrates per-token accounting, per-position records, and custody (reserves).
    access(all) resource Pool {
        access(self) let config: PoolConfig
        /// Tracks global accounting information for each supported token.
        access(self) let tokenStates: {Type: TokenStateRecord}
        /// Custody — owns the FungibleToken vaults. See Reserves.
        access(self) let reserves: @Reserves
        /// Positions keyed by the Position resource's UUID.
        access(self) let positions: {UInt64: PositionRecord}
        /// Entitled self-capability copied into each Position. Must be set
        /// by Admin after the Pool is stored. openPosition() panics until set.
        access(self) var selfCap: Capability<auth(Internal) &Pool>?

        init(config: PoolConfig) {
            self.config = config
            self.tokenStates = {}
            self.reserves <- create Reserves()
            self.positions = {}
            self.selfCap = nil
        }

        /// One-time wiring: Admin issues `auth(Internal) &Pool` against
        /// PoolStoragePath and installs it here so new Positions can hold it.
        access(Admin) fun setSelfCapability(cap: Capability<auth(Internal) &Pool>) {
            pre {
                cap.check(): "pool capability must be valid"
            }
            self.selfCap = cap
        }

        access(all) view fun getReserveBalance(tokenType: Type): UFix64 {
            return self.reserves.getBalance(tokenType: tokenType)
        }

        access(all) view fun getSupportedTokens(): [Type] {
            return self.reserves.getSupportedTokens()
        }

        /// Mint a new position and return the owner's handle resource. The
        /// Position's UUID (assigned by Cadence at creation) is the key
        /// under which its PositionRecord is stored in the pool.
        access(Participant) fun openPosition(): @Position {
            let cap = self.selfCap ?? panic("pool self-capability not configured")
            let position <- create Position(poolCap: cap)
            self.positions[position.uuid] = PositionRecord(id: position.uuid)
            return <- position
        }

        /// Internal deposit method that may only be invoked by a Position resource.
        /// Access control is implemented by:
        ///  1. the Position resource implementation binds its UUID to all pool operations.
        ///  2. Internal-entitled Pool references are only distributed to internal components.
        /// Follows the validator / mutation pipeline: validate → apply → check invariants.
        /// TODO: consider splitting deposit collateral vs repay debt into distinct methods.
        access(Internal) fun internalDeposit(positionUUID: UInt64, from: @{FungibleToken.Vault}) {
            let mutations <- FlowALP.validateDeposit(
                pool: &self as &Pool,
                positionID: positionUUID,
                vault: <- from,
            )
            self.applyMutations(mutations: <- mutations)
            self.checkInvariants()
        }

        /// Internal withdraw invoked by a Position. See internalDeposit.
        /// Follows the validator / mutation pipeline. The produced vault is a
        /// direct effect (not a mutation) — it is taken out of Reserves after
        /// the ledger debit has been applied and before invariants are checked.
        /// TODO: consider splitting withdraw collateral vs borrow debt into distinct methods.
        access(Internal) fun internalWithdraw(
            positionUUID: UInt64,
            tokenType: Type,
            amount: UFix64
        ): @{FungibleToken.Vault} {
            let mutations <- FlowALP.validateWithdraw(
                pool: &self as &Pool,
                positionID: positionUUID,
                tokenType: tokenType,
                amount: amount,
            )
            self.applyMutations(mutations: <- mutations)
            let vault <- self.reserves.withdraw(tokenType: tokenType, amount: amount)
            self.checkInvariants()
            return <- vault
        }

        /// Manually liquidate an unhealthy position.
        /// TODO: implement via the validator / mutation pipeline. The validator
        /// (validateLiquidate — not yet written) emits a heterogeneous list of
        /// LedgerDeltas covering both the borrower and liquidator sides, plus a
        /// VaultDeposit for the repayment. The seized vault is a direct effect,
        /// produced between applyMutations and checkInvariants.
        access(Admin | Liquidate) fun liquidate(
            positionUUID: UInt64,
            repay: @{FungibleToken.Vault},
            seizeType: Type, /* will need more params here */
        ): @{FungibleToken.Vault} {
            let _pid = positionUUID
            let _seize = seizeType
            destroy repay
            panic("not implemented")
        }

        access(Admin) fun pause() {}

        access(Admin) fun unpause() {}

        /* ----- Validator / mutation pipeline internals ----- */

        /// applyMutations is the single choke point through which every
        /// state write flows. It consumes the list produced by a validator,
        /// calling each mutation's `apply` with an `auth(MutateState) &Pool`. The
        /// `MutateState` entitlement is obtained here and nowhere else, so the
        /// low-level appliers below can only be reached via a validated
        /// mutation.
        ///
        /// Invariants are not checked here — the caller is expected to invoke
        /// `checkInvariants` after all mutations and any direct effects (e.g.
        /// vault outputs) have settled.
        access(contract) fun applyMutations(mutations: @[{StateMutation}]) {
            let selfRef = &self as auth(MutateState) &Pool
            while mutations.length > 0 {
                let m <- mutations.removeFirst()
                m.apply(pool: selfRef)
                destroy m
            }
            destroy mutations
        }

        /// Adds `delta` to the balance of `tokenType` for the position
        /// identified by `positionID`. Callable only from LedgerDelta.apply.
        access(MutateState) fun applyLedgerDelta(
            positionID: UInt64,
            tokenType: Type,
            delta: SignedAmount,
        ) {
            let record = self.positions[positionID]
                ?? panic("unknown position")
            record.applyDelta(tokenType: tokenType, delta: delta)
            self.positions[positionID] = record
        }

        /// Moves `from` into Reserves. Callable only from VaultDeposit.apply.
        access(MutateState) fun applyVaultDeposit(from: @{FungibleToken.Vault}) {
            self.reserves.deposit(from: <- from)
        }

        /// checkInvariants is invoked at the end of every operation, after
        /// all mutations and direct effects have settled. Any violation
        /// panics and reverts the transaction.
        ///
        /// TODO: implement
        ///   - for each supported token T:
        ///       Σ(position credits for T) − Σ(position debits for T) == reserves.getBalance(T)
        ///   - for each position P:
        ///       healthFactor(P) ≥ 1  (unless P is flagged for liquidation)
        ///   - pool-level caps respected
        access(self) fun checkInvariants() {}
    }

    /* ---------- Position Resource ---------- */

    /// Position
    ///
    /// The user-held handle for a position. Its Cadence-assigned `uuid` is
    /// the key under which the Pool stores the corresponding PositionRecord.
    /// The resource itself stores no funds; all custody lives in the Pool.
    ///
    /// Position holds a private, entitled capability to the Pool and exposes
    /// operation methods (deposit, withdraw) that forward to the Pool's
    /// Internal-gated methods, binding `self.uuid` into each call.
    access(all) resource Position {
        /// Permissioned reference to the Pool which created this Position's.
        /// CAUTION: This reference must never be exposed outside this Position.
        access(self) let poolCap: Capability<auth(Internal) &Pool>

        init(poolCap: Capability<auth(Internal) &Pool>) {
            pre {
                poolCap.check(): "must be initialized with valid capability"
            }
            self.poolCap = poolCap
        }

        /// Borrows the pool reference using the Position's internal capability.
        access(self) fun borrowPool(): auth(Internal) &Pool {
            let pool = self.poolCap.borrow() ?? panic("pool capability unavailable")
            return pool
        }

        /// Deposits funds into the position.
        /// TODO: consider splitting deposit collateral vs repay debt into distinct methods.
        /// TODO: Detailed documentation and invariants
        access(all) fun deposit(from: @{FungibleToken.Vault}) {
            let pool = self.borrowPool()
            pool.internalDeposit(positionUUID: self.uuid, from: <-from)
        }

        /// Withdraws funds from the position.
        /// TODO: consider splitting withdraw collateral vs borrow debt into distinct methods.
        /// TODO: Detailed documentation and invariants
        access(FungibleToken.Withdraw) fun withdraw(
            tokenType: Type,
            amount: UFix64
        ): @{FungibleToken.Vault} {
            let pool = self.borrowPool()
            return <- pool.internalWithdraw(
                positionUUID: self.uuid,
                tokenType: tokenType,
                amount: amount
            )
        }
    }

    init() {
        self.PoolStoragePath = /storage/FlowALPPool
        self.PoolPublicPath = /public/FlowALPPool
    }
}
