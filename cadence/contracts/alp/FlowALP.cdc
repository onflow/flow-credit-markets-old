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
/// DESIGN: Orchestrator / Intent pipeline
/// Top-level Pool API methods (e.g. `internalDeposit`, `internalWithdraw`,
/// `liquidate`) act as orchestrators. Each orchestrator is a thin coordinator
/// that:
///
///     1. builds an Intent struct describing the requested operation,
///     2. calls a contract-level validator function with the intent and a
///        read-only `&Pool`,
///     3. calls a contract-level mutator function with the intent, any
///        input resources, and an `auth(MutateState) &Pool`,
///     4. returns any output resources produced by the mutator.
///
/// Validators are `view` functions that read Pool state and panic on any
/// operation-level rule violation (supported tokens, caps, health factors,
/// paused state, ...). They do not construct or return any state-change
/// artifact — they are pure yes/no gates.
///
/// Mutators apply all state changes for the operation, including any
/// movements into or out of Reserves, and then call `Pool.checkInvariants`.
/// They return any output resources (e.g. the vault produced by a withdraw)
/// to the orchestrator. An invariant violation panics and reverts the tx.
///
/// Access-control convention.
/// The `MutateState` entitlement gates the small set of Pool methods that
/// write state (the "appliers") and the invariant check. An
/// `auth(MutateState) &Pool` is produced only inside Pool's orchestrator
/// methods — it is never stored and never escapes the operation.
///
/// Every method on Pool is either:
///   - `view` (reads only; compiler-enforced non-mutation), OR
///   - entitlement-gated (`access(Admin)`, `access(Internal)`,
///     `access(MutateState)`, `access(Admin | Liquidate)`, ...).
///
/// No method on Pool is `access(all)` non-view or `access(contract)` non-view.
/// This is a lint-checkable convention: see Makefile target `lint-pool-access`.
///
/// Resource I/O.
/// Intents are plain structs and carry no resources. Input resources (e.g. the
/// incoming vault for a deposit) are passed as separate arguments to the
/// mutator alongside the intent; the mutator asserts on entry that the
/// resource matches the intent's declared type and amount. Output resources
/// are returned directly by the mutator.
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

    /// Gates the low-level state-writing methods on Pool (the "appliers") and
    /// the invariant check. An `auth(MutateState) &Pool` is produced only
    /// inside a Pool orchestrator method and passed to a contract-level
    /// mutator function. It is never stored and MUST NEVER escape an operation.
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

    /* ---------- Intents ---------- */

    /// Intents are plain structs describing a requested operation. They carry
    /// no resources; any input resources are passed as separate arguments to
    /// the mutator alongside the intent. An intent is built by the orchestrator,
    /// inspected by the validator, and consumed by the mutator — all within a
    /// single operation and never exposed outside the contract.

    /// DepositIntent
    ///
    /// Describes a deposit of `amount` of `tokenType` into position `positionID`.
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
    ///
    /// Describes a withdrawal of `amount` of `tokenType` from position `positionID`.
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

    /// Validators are `view` functions that inspect a read-only `&Pool` and
    /// panic if the intent violates any operation-level rule. They never
    /// mutate state (enforced by the compiler) and return nothing on success.

    /// validateDeposit
    access(contract) view fun validateDeposit(pool: &Pool, intent: DepositIntent) {
        // TODO: enforce
        //   - pool not paused
        //   - intent.tokenType is supported
        //   - intent.positionID refers to an existing position
        //   - intent.amount > 0
        //   - per-token deposit cap not exceeded
        let _p = pool
        let _i = intent
    }

    /// validateWithdraw
    access(contract) view fun validateWithdraw(pool: &Pool, intent: WithdrawIntent) {
        // TODO: enforce
        //   - pool not paused
        //   - intent.tokenType is supported
        //   - intent.positionID refers to an existing position
        //   - intent.amount > 0
        //   - post-op health factor ≥ 1
        //   - per-token withdraw / borrow caps not exceeded
        let _p = pool
        let _i = intent
    }

    /* ---------- Mutators ---------- */

    /// Mutators apply all state changes for an operation, then call
    /// `Pool.checkInvariants`. They require `auth(MutateState) &Pool` —
    /// obtained only inside a Pool orchestrator method and never stored.
    /// Input resources are passed alongside the intent; the mutator asserts
    /// on entry that the resource matches the intent's declared fields.
    /// Output resources are returned directly.

    /// applyDeposit
    ///
    /// Moves the incoming vault into Reserves and credits the position.
    access(contract) fun applyDeposit(
        pool: auth(MutateState) &Pool,
        intent: DepositIntent,
        vault: @{FungibleToken.Vault},
    ) {
        pre {
            vault.getType() == intent.tokenType: "vault type does not match intent"
            vault.balance == intent.amount: "vault amount does not match intent"
        }
        pool.applyVaultDeposit(from: <- vault)
        pool.applyLedgerDelta(
            positionID: intent.positionID,
            tokenType: intent.tokenType,
            delta: SignedAmount(direction: BalanceDirection.Credit, quantity: intent.amount),
        )
        pool.checkInvariants()
    }

    /// applyWithdraw
    ///
    /// Debits the position and withdraws a vault from Reserves. The vault is
    /// returned to the orchestrator as a direct effect.
    access(contract) fun applyWithdraw(
        pool: auth(MutateState) &Pool,
        intent: WithdrawIntent,
    ): @{FungibleToken.Vault} {
        pool.applyLedgerDelta(
            positionID: intent.positionID,
            tokenType: intent.tokenType,
            delta: SignedAmount(direction: BalanceDirection.Debit, quantity: intent.amount),
        )
        let vault <- pool.applyReserveWithdraw(tokenType: intent.tokenType, amount: intent.amount)
        pool.checkInvariants()
        return <- vault
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
        /// Orchestrator: builds a DepositIntent, validates, then applies.
        /// TODO: consider splitting deposit collateral vs repay debt into distinct methods.
        access(Internal) fun internalDeposit(positionUUID: UInt64, from: @{FungibleToken.Vault}) {
            let intent = DepositIntent(
                positionID: positionUUID,
                tokenType: from.getType(),
                amount: from.balance,
            )
            FlowALP.validateDeposit(pool: &self as &Pool, intent: intent)
            FlowALP.applyDeposit(
                pool: &self as auth(MutateState) &Pool,
                intent: intent,
                vault: <- from,
            )
        }

        /// Internal withdraw invoked by a Position. See internalDeposit.
        ///
        /// Orchestrator: builds a WithdrawIntent, validates, then applies.
        /// The mutator returns the withdrawn vault; the orchestrator forwards
        /// it to the caller unchanged.
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
            FlowALP.validateWithdraw(pool: &self as &Pool, intent: intent)
            return <- FlowALP.applyWithdraw(
                pool: &self as auth(MutateState) &Pool,
                intent: intent,
            )
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

        /* ----- Appliers (MutateState-gated) -----
         *
         * The full set of methods on Pool that write state. Only mutator
         * functions (invoked from an orchestrator with auth(MutateState) &Pool)
         * may call these. Every writer lives here; to enumerate the write
         * surface, grep `access(MutateState)` on Pool.
         */

        /// Composes `delta` into the balance of `tokenType` for the given position.
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

        /// Moves `from` into Reserves.
        access(MutateState) fun applyVaultDeposit(from: @{FungibleToken.Vault}) {
            self.reserves.deposit(from: <- from)
        }

        /// Withdraws a vault from Reserves.
        access(MutateState) fun applyReserveWithdraw(
            tokenType: Type,
            amount: UFix64,
        ): @{FungibleToken.Vault} {
            return <- self.reserves.withdraw(tokenType: tokenType, amount: amount)
        }

        /// Invoked at the end of every mutator, after all state changes for
        /// the operation have settled. Panics on any violation, reverting
        /// the transaction. Marked `view` so the compiler enforces that the
        /// check itself cannot mutate.
        ///
        /// TODO: implement
        ///   - for each supported token T:
        ///       Σ(position credits for T) − Σ(position debits for T) == reserves.getBalance(T)
        ///   - for each position P:
        ///       healthFactor(P) ≥ 1  (unless P is flagged for liquidation)
        ///   - pool-level caps respected
        access(MutateState) view fun checkInvariants() {}
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
