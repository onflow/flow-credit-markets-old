import "FungibleToken"

/// FlowALP (Automated Lending Protocol)
///
/// OVERVIEW
/// The Pool resource is the protocol's public API and access-control layer. It
/// holds configuration, issues Position resources, and orchestrates operations
/// (deposit, withdraw, liquidate). It delegates all state mutations (including
/// token movemements) to PoolState.
///
/// PoolState is the protocol's state machine. It owns all mutable state —
/// position records, per-token state, and custody (Reserves) — and exposes a
/// narrow, intent-shaped write surface. Every path that mutates protocol state
/// flows through a PoolState method.
///
/// To interact with FlowALP, users create a Position. This causes a
/// PositionRecord to be stored in PoolState, and returns a Position resource to
/// the user. The Position resource represents authorization to interact with
/// the position (deposit/withdraw).
///
/// MODEL CONVENTIONS
/// 1. Types primarily used to persist data in storage are named ".*Record".
///    Record types are mutated only by their own methods: fields are access(self),
///    mutators are access(contract) (or narrower).
/// 2. Every method on Pool is either `view` or entitlement-gated. No method on
///    Pool is `access(all)` non-view. (Lint-checkable convention.)
/// 3. Every state-writing method on PoolState is `access(self)`. The public
///    entry points on PoolState (`deposit`, `withdraw`, `registerPosition`,
///    `registerToken`) are `access(all)` and internally invoke an `access(self)`
///    mutator method which applies state changes and calls `checkInvariants`.
///
/// DESIGN: Orchestrator / Intent / PoolState pipeline
/// Every operation is structured as:
///
///     Pool.someOp:         Internal/Admin/... entitled orchestrator. Builds
///                          an Intent struct and calls the matching PoolState
///                          entry point.
///
///     PoolState.someOp:    access(all) entry point. Calls:
///                            1. a contract-level `view` validator that
///                               inspects an &PoolState and panics on any
///                               rule violation,
///                            2. an `access(self)` mutator method on PoolState
///                               (applyDeposit, applyWithdraw, ...) that
///                               performs all state changes, calls
///                               `checkInvariants`, and returns any output
///                               resources.
///
/// Resource I/O.
/// Intents are plain structs and carry no resources. Input resources are
/// passed alongside the intent; the mutator asserts on entry that the
/// resource matches the intent's declared type and amount. Output resources
/// are returned directly.
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

    /* ---------- Intents ---------- */

    /// Intents are plain structs describing a requested operation. They carry
    /// no resources; any input resources are passed as separate arguments
    /// alongside the intent.

    /// DepositIntent
    access(all) struct DepositIntent {
        access(all) let positionID: UInt64
        access(all) let tokenType: Type
        access(all) let amount: UFix64

        view init(positionID: UInt64, tokenType: Type, amount: UFix64) {
            self.positionID = positionID
            self.tokenType = tokenType
            self.amount = amount
        }
    }

    /// WithdrawIntent
    access(all) struct WithdrawIntent {
        access(all) let positionID: UInt64
        access(all) let tokenType: Type
        access(all) let amount: UFix64

        view init(positionID: UInt64, tokenType: Type, amount: UFix64) {
            self.positionID = positionID
            self.tokenType = tokenType
            self.amount = amount
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

        init(tokenType: Type) {
            self.tokenType = tokenType
        }
    }

    /* ---------- Position State ---------- */

    /// PositionRecord
    ///
    /// Holds all persisted state related to a particular Position. Positions are
    /// uniquely identified by their ID, which is the UUID of the Position resource
    /// granted when the position is opened.
    access(all) struct PositionRecord {
        /// Mirror of the Position resource's UUID; same value PoolState uses as dict key.
        /// TODO: verify this field is needed; remove if not.
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
        /// Called only by `PoolState.applyLedgerDelta` (access(self) on PoolState).
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
    /// Held by PoolState; callers outside PoolState never reach Reserves
    /// directly. Mutating methods are `access(contract)` — only PoolState's
    /// own `access(self)` appliers call them.
    access(all) resource Reserves {
        access(self) var vaults: @{Type: {FungibleToken.Vault}}

        init() {
            self.vaults <- {}
        }

        /// Register a new supported token. Caller supplies an empty vault
        /// of the correct type to establish custody. Fails if already supported.
        access(contract) fun addSupportedToken(emptyVault: @{FungibleToken.Vault}) {
            pre {
                emptyVault.balance == 0.0: "initial vault must be empty"
                !self.isSupported(tokenType: emptyVault.getType()): "token must not already be supported"
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

        /// Withdraw from the appropriate vault. Fails if unsupported or insufficient balance.
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

        init(numeraire: Type) {
            self.numeraire = numeraire
            self.paused = false
        }
    }

    /* ---------- Validators ---------- */

    /// Validators are `view` functions that inspect a read-only `&PoolState`
    /// and panic if the intent violates any operation-level rule. They never
    /// mutate state (enforced by the compiler) and return nothing on success.

    access(contract) view fun validateDeposit(state: &PoolState, intent: DepositIntent) {
        // TODO: enforce
        //   - state not paused (paused is on Pool's config; requires passing config or snapshot)
        //   - intent.tokenType is supported
        //   - intent.positionID refers to an existing position
        //   - intent.amount > 0
        //   - per-token deposit cap not exceeded
        let _s = state
        let _i = intent
    }

    access(contract) view fun validateWithdraw(state: &PoolState, intent: WithdrawIntent) {
        // TODO: enforce
        //   - state not paused
        //   - intent.tokenType is supported
        //   - intent.positionID refers to an existing position
        //   - intent.amount > 0
        //   - post-op health factor ≥ 1
        //   - per-token withdraw / borrow caps not exceeded
        let _s = state
        let _i = intent
    }

    /* ---------- PoolState ---------- */

    /// PoolState
    ///
    /// The protocol's mutable state: per-position ledgers, per-token state, and
    /// custody (Reserves). PoolState exposes two layers:
    ///
    ///   - `access(all)` entry points (`deposit`, `withdraw`, `registerToken`,
    ///     `registerPosition`): the public API. Each runs a `view` validator
    ///     then invokes an `access(self)` mutator. These are what Pool calls.
    ///
    ///   - `access(self)` state-writing methods (`applyDeposit`, `applyWithdraw`,
    ///     `applyLedgerDelta`, `applyVaultDeposit`, `applyReserveWithdraw`,
    ///     `checkInvariants`): the full set of writers. Compiler guarantees
    ///     nothing outside PoolState can invoke them.
    ///
    /// Grep `access(self) fun` inside PoolState to enumerate every writer.
    access(all) resource PoolState {
        /// Positions keyed by the Position resource's UUID.
        access(self) let positions: {UInt64: PositionRecord}
        /// Per-token accounting information.
        access(self) let tokenStates: {Type: TokenStateRecord}
        /// Custody — owns the FungibleToken vaults.
        access(self) let reserves: @Reserves

        init() {
            self.positions = {}
            self.tokenStates = {}
            self.reserves <- create Reserves()
        }

        /* ----- Reads ----- */

        access(all) view fun getReserveBalance(tokenType: Type): UFix64 {
            return self.reserves.getBalance(tokenType: tokenType)
        }

        access(all) view fun getSupportedTokens(): [Type] {
            return self.reserves.getSupportedTokens()
        }

        access(all) view fun getPositionBalance(positionID: UInt64, tokenType: Type): SignedAmount {
            let record = self.positions[positionID]
                ?? panic("unknown position")
            return record.getBalance(tokenType: tokenType)
        }

        access(all) view fun hasPosition(positionID: UInt64): Bool {
            return self.positions[positionID] != nil
        }

        /* ----- Entry points (access(all)) ----- */

        /// Apply a validated deposit operation.
        access(all) fun deposit(intent: DepositIntent, vault: @{FungibleToken.Vault}) {
            FlowALP.validateDeposit(state: &self as &PoolState, intent: intent)
            self.applyDeposit(intent: intent, vault: <- vault)
        }

        /// Apply a validated withdrawal and return the resulting vault.
        access(all) fun withdraw(intent: WithdrawIntent): @{FungibleToken.Vault} {
            FlowALP.validateWithdraw(state: &self as &PoolState, intent: intent)
            return <- self.applyWithdraw(intent: intent)
        }

        /// Register a new position. Called by Pool.openPosition.
        access(all) fun registerPosition(id: UInt64) {
            pre {
                self.positions[id] == nil: "position already exists"
            }
            self.positions[id] = PositionRecord(id: id)
        }

        /// Register support for a new token. Called by Pool's admin handler.
        access(all) fun registerToken(emptyVault: @{FungibleToken.Vault}) {
            let tokenType = emptyVault.getType()
            self.tokenStates[tokenType] = TokenStateRecord(tokenType: tokenType)
            self.reserves.addSupportedToken(emptyVault: <- emptyVault)
        }

        /* ----- State-writing methods (access(self)) -----
         *
         * The complete set of state-writing code. `access(self)` guarantees
         * at the language level that nothing outside PoolState invokes any
         * of these. Grep `access(self) fun` on PoolState to enumerate every
         * writer.
         */

        /// Mutator: apply a deposit. Cross-checks the vault matches the intent,
        /// moves the vault into Reserves, credits the position ledger, checks
        /// invariants. Called by the `deposit` entry point after validation.
        access(self) fun applyDeposit(intent: DepositIntent, vault: @{FungibleToken.Vault}) {
            pre {
                vault.getType() == intent.tokenType: "vault type does not match intent"
                vault.balance == intent.amount: "vault amount does not match intent"
            }
            self.applyVaultDeposit(from: <- vault)
            self.applyLedgerDelta(
                positionID: intent.positionID,
                tokenType: intent.tokenType,
                delta: SignedAmount(direction: BalanceDirection.Credit, quantity: intent.amount),
            )
            self.checkInvariants()
        }

        /// Mutator: apply a withdrawal. Debits the position ledger, withdraws
        /// the vault from Reserves, checks invariants, and returns the vault.
        /// Called by the `withdraw` entry point after validation.
        access(self) fun applyWithdraw(intent: WithdrawIntent): @{FungibleToken.Vault} {
            self.applyLedgerDelta(
                positionID: intent.positionID,
                tokenType: intent.tokenType,
                delta: SignedAmount(direction: BalanceDirection.Debit, quantity: intent.amount),
            )
            let vault <- self.applyReserveWithdraw(tokenType: intent.tokenType, amount: intent.amount)
            self.checkInvariants()
            return <- vault
        }

        /// Composes `delta` into the balance of `tokenType` for the given position.
        access(self) fun applyLedgerDelta(
            positionID: UInt64,
            tokenType: Type,
            delta: SignedAmount,
        ) {
            let record = self.positions[positionID]
                ?? panic("unknown position")
            record.applyDelta(tokenType: tokenType, delta: delta)
            self.positions[positionID] = record
        }

        /// Moves `from` into Reserves.
        access(self) fun applyVaultDeposit(from: @{FungibleToken.Vault}) {
            self.reserves.deposit(from: <- from)
        }

        /// Withdraws a vault from Reserves.
        access(self) fun applyReserveWithdraw(
            tokenType: Type,
            amount: UFix64,
        ): @{FungibleToken.Vault} {
            return <- self.reserves.withdraw(tokenType: tokenType, amount: amount)
        }

        /// Invoked at the end of every mutator. Panics on any violation,
        /// reverting the transaction. Marked `view` so the compiler enforces
        /// that the check cannot mutate.
        ///
        /// TODO: implement
        ///   - for each supported token T:
        ///       Σ(position credits for T) − Σ(position debits for T) == reserves.getBalance(T)
        ///   - for each position P:
        ///       healthFactor(P) ≥ 1  (unless P is flagged for liquidation)
        ///   - pool-level caps respected
        access(self) view fun checkInvariants() {}
    }

    /* ---------- Pool ---------- */

    /// Pool
    ///
    /// Top-level protocol resource. Owns config, lifecycle, access control, and
    /// the nested PoolState. Pool never writes protocol state itself — it
    /// builds intents and calls into PoolState's entry points.
    access(all) resource Pool {
        access(self) let config: PoolConfig
        /// Mutable protocol state. See PoolState.
        access(self) let state: @PoolState
        /// Entitled self-capability copied into each Position. Must be set
        /// by Admin after the Pool is stored. openPosition() panics until set.
        access(self) var selfCap: Capability<auth(Internal) &Pool>?

        init(config: PoolConfig) {
            self.config = config
            self.state <- create PoolState()
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

        /* ----- Public reads (delegate to PoolState) ----- */

        access(all) view fun getReserveBalance(tokenType: Type): UFix64 {
            return self.state.getReserveBalance(tokenType: tokenType)
        }

        access(all) view fun getSupportedTokens(): [Type] {
            return self.state.getSupportedTokens()
        }

        /* ----- Participant / Admin / Liquidate operations ----- */

        /// Mint a new position and return the owner's handle resource.
        access(Participant) fun openPosition(): @Position {
            let cap = self.selfCap ?? panic("pool self-capability not configured")
            let position <- create Position(poolCap: cap)
            self.state.registerPosition(id: position.uuid)
            return <- position
        }

        /// Admin: register a new supported token by supplying an empty vault
        /// of that type.
        access(Admin) fun addSupportedToken(emptyVault: @{FungibleToken.Vault}) {
            self.state.registerToken(emptyVault: <- emptyVault)
        }

        access(Admin) fun pause() {}
        access(Admin) fun unpause() {}

        /* ----- Internal orchestrators invoked by Position ----- */

        /// Orchestrator: builds a DepositIntent and forwards to PoolState.
        /// TODO: consider splitting deposit collateral vs repay debt into distinct methods.
        access(Internal) fun internalDeposit(positionUUID: UInt64, from: @{FungibleToken.Vault}) {
            let intent = DepositIntent(
                positionID: positionUUID,
                tokenType: from.getType(),
                amount: from.balance,
            )
            self.state.deposit(intent: intent, vault: <- from)
        }

        /// Orchestrator: builds a WithdrawIntent and forwards to PoolState.
        /// TODO: consider splitting withdraw collateral vs borrow debt into distinct methods.
        access(Internal) fun internalWithdraw(
            positionUUID: UInt64,
            tokenType: Type,
            amount: UFix64
        ): @{FungibleToken.Vault} {
            let intent = WithdrawIntent(
                positionID: positionUUID,
                tokenType: tokenType,
                amount: amount,
            )
            return <- self.state.withdraw(intent: intent)
        }

        /// Manually liquidate an unhealthy position.
        /// TODO: implement via the orchestrator pattern. Introduce a
        /// LiquidationIntent covering both borrower and liquidator sides; a
        /// `view` validateLiquidate enforces health-factor + close-factor rules;
        /// applyLiquidate consumes the repay vault, applies ledger changes,
        /// withdraws the seized vault, checks invariants, and returns it.
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
    }

    /* ---------- Position Resource ---------- */

    /// Position
    ///
    /// The user-held handle for a position. Its Cadence-assigned `uuid` is
    /// the key under which PoolState stores the corresponding PositionRecord.
    /// The resource itself stores no funds; all custody lives in PoolState.
    ///
    /// Position holds a private, entitled capability to Pool and exposes
    /// operation methods (deposit, withdraw) that forward to Pool's
    /// Internal-gated methods, binding `self.uuid` into each call.
    access(all) resource Position {
        /// Permissioned reference to the Pool which created this Position.
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
