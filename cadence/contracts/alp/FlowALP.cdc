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
/// is tracked with the TokenStateRecord type.
///
/// The Reserves resource holds all funds and manage deposits and withdrawals.
///
/// MODEL CONVENTIONS
/// 1. Types which are primarily used to persist data in storage are named ".*Record".
///    Record types are mutated only by their own methods: fields are access(self),
///    mutators are access(contract) (or narrower).
///
access(all) contract FlowALP {

    /* ---------- Storage Paths ---------- */

    access(all) let PoolStoragePath: StoragePath
    access(all) let PoolPublicPath: PublicPath
    access(all) let AdminStoragePath: StoragePath

    /* ---------- Entitlements ---------- */

    /// Admin operations: pause/unpause, configuration, risk parameters,
    /// adding supported tokens, liquidation overrides, etc. Held by the
    /// deployer (or a governance resource) — never granted to end users.
    access(all) entitlement Admin

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

    /* ---------- Token State ---------- */

    /// TokenStateRecord
    ///
    /// Live per-token state held inside the pool.
    access(all) struct TokenStateRecord {
        access(self) var tokenType: Type

        init(
            tokenType: Type,
        ) {
            self.tokenType = tokenType
        }
    }

    /* ---------- Position State ---------- */

    /// PositionRecord
    ///
    /// Internal per-position state held by the pool, keyed by the Position
    /// resource's UUID. Stores scaled balances — the true balance is
    /// recovered by multiplying the scaled balance by the current interest
    /// index for its direction. Scaled storage means interest accrues
    /// "for free" across time without touching per-position state.
    access(all) struct PositionRecord {
        /// Mirror of the Position resource's UUID; same value the Pool uses
        /// as dict key. Kept for self-describing logs/events.
        /// TODO(jord): above was AI reasoning - is is correct?
        access(all) let id: UInt64
        /// Set of credit and debit balances associated with this position.
        access(self) var balances: {Type: SignedAmount}

        init(id: UInt64) {
            self.id = id
            self.balances = {}
        }
    }

    /* ---------- Reserves ---------- */

    /// Reserves
    ///
    /// Custody component that owns the FungibleToken vaults backing the Pool.
    ///
    /// Mutating methods are access(contract), so only FlowALP contract
    /// code (in practice, Pool methods) can move funds.
    access(all) resource Reserves {
        access(self) var vaults: @{Type: {FungibleToken.Vault}}

        init() {
            self.vaults <- {}
        }

        /// Register a new supported token. Caller supplies an empty vault
        /// of the correct type to establish custody. Fails if already
        /// supported.
        access(contract) fun addSupportedToken(emptyVault: @{FungibleToken.Vault}) {
            pre { emptyVault.balance == 0.0: "initial vault must be empty" }
            let tokenType = emptyVault.getType()
            assert(self.vaults[tokenType] == nil, message: "token type already supported")
            let prior <- self.vaults[tokenType] <- emptyVault
            destroy prior
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

        access(all) view fun getBalance(tokenType: Type): UFix64 {
            if let vaultRef = &self.vaults[tokenType] as &{FungibleToken.Vault}? {
                return vaultRef.balance
            }
            return 0.0
        }

        access(all) view fun getSupportedTokens(): [Type] {
            return self.vaults.keys
        }

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
        /// Health factor below which a position becomes eligible for liquidation.
        access(self) var liquidationTriggerHF: UFix128
        /// Health factor a position must be restored to (or below) after
        /// liquidation; caps how much collateral can be seized.
        access(self) var liquidationTargetHF: UFix128
        /// When paused, the pool rejects deposits, withdrawals, and liquidations.
        access(self) var paused: Bool

        init(
            defaultToken: Type,
            liquidationTriggerHF: UFix128,
            liquidationTargetHF: UFix128
        ) {
            self.numeraire = defaultToken
            self.liquidationTriggerHF = liquidationTriggerHF
            self.liquidationTargetHF = liquidationTargetHF
            self.paused = false
        }
    }

    /// The Pool orchestrates per-token accounting (tokenStates), per-position
    /// records, and custody (reserves). Users interact with it indirectly via
    /// their Position resource (which proves ownership) plus the public
    /// capability.
    access(all) resource Pool {
        access(self) var config: PoolConfig
        access(self) var tokenStates: {Type: TokenStateRecord}
        /// Custody — owns the FungibleToken vaults. See Reserves.
        access(self) let reserves: @Reserves
        /// Positions keyed by the Position resource's UUID.
        access(self) var positions: {UInt64: PositionRecord}

        init(config: PoolConfig) {
            self.config = config
            self.tokenStates = {}
            self.reserves <- create Reserves()
            self.positions = {}
        }

        /* --- reserves passthrough reads --- */

        access(all) view fun getReserveBalance(tokenType: Type): UFix64 {
            return self.reserves.getBalance(tokenType: tokenType)
        }

        access(all) view fun getSupportedTokens(): [Type] {
            return self.reserves.getSupportedTokens()
        }

        /// Mint a new position and return the owner's handle resource. The
        /// Position's UUID (assigned by Cadence at creation) is the key
        /// under which its PositionRecord is stored in the pool.
        /// TODO(jord): this must be made non-public
        access(all) fun openPosition(): @Position {
            let position <- create Position()
            self.positions[position.uuid] = PositionRecord(id: position.uuid)
            return <- position
        }

        /// Deposit tokens into a position. Public: anyone holding a
        /// reference can add collateral to any position (doing so can only
        /// help the owner). The reference itself identifies the target
        /// position via its UUID.
        access(all) fun deposit(position: &Position, from: @{FungibleToken.Vault}) {
            let _pid = position.uuid
            destroy from // placeholder — real impl routes to the reserve vault
        }

        /// Withdraw tokens from a position. Ownership is enforced upstream
        /// by Position.withdraw — this Pool method accepts any `&Position`
        /// and trusts that the caller chain holds the owning resource.
        /// Withdrawal may increase debt (Credit → Debit flip) if the
        /// position still has sufficient health afterwards.
        access(all) fun withdraw(
            position: &Position,
            tokenType: Type,
            amount: UFix64
        ): @{FungibleToken.Vault} {
            let _pid = position.uuid
            let _token = tokenType
            let _amt = amount
            panic("not implemented")
        }

        /// Manually liquidate an unhealthy position. Takes the target
        /// position's UUID rather than a reference, since the liquidator
        /// does not hold the owner's Position resource. The liquidator
        /// repays `repay` of the position's debt (in the vault's token)
        /// and receives `seizeType` collateral at a liquidation bonus.
        /// The position's post-liquidation health factor must not exceed
        /// the configured liquidationTargetHF.
        access(all) fun liquidate(
            positionUUID: UInt64,
            repay: @{FungibleToken.Vault},
            seizeType: Type
        ): @{FungibleToken.Vault} {
            let _pid = positionUUID
            let _seize = seizeType
            destroy repay
            panic("not implemented")
        }

        access(Admin) fun pause() {}

        access(Admin) fun unpause() {}

    }

    /* ---------- Position Resource ---------- */

    /// Position
    ///
    /// The user-held handle for a position. Holds no fields — its identity
    /// is its Cadence-assigned `uuid`, and that UUID is the key under which
    /// the Pool stores the corresponding PositionRecord. Holding this
    /// resource is proof of ownership for withdrawals. The resource itself
    /// stores no funds; all custody lives in the pool.
    access(all) resource Position {

        /// Deposit to this position. Depending on the pre-deposit state,
        /// this can either add collateral or pay down debt.
        access(all) fun deposit(from: @{FungibleToken.Vault}) {
            destroy from
        }

        /// Withdraw from this position. Depending on the pre-deposit state,
        /// this can either reduce collateral or add debt.
        access(all) fun withdraw(tokenType: Type, amount: UFix64): @{FungibleToken.Vault} {
            let _token = tokenType
            let _amt = amount
            panic("not implemented")
        }
    }

    init() {
        self.PoolStoragePath = /storage/FlowALPPool
        self.PoolPublicPath = /public/FlowALPPool
        self.AdminStoragePath = /storage/FlowALPAdmin
    }
}
