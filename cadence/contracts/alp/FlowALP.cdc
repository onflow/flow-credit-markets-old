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

    /// Enables opening and interacting with positions (withdraw/deposit/...)
    /// In the mature protocol, these actions will be publicly accessible.
    access(all) entitlement Participant

    /// Enables manual liquidation. This is gated as a safety precaution.
    /// In the mature protocol, liquidation should be a publicly accessible operation.
    access(all) entitlement Liquidate

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
        /// Mirror of the Position resource's UUID; same value the Pool uses
        /// as dict key. Kept for self-describing logs/events (?)
        ///
        /// TODO: verify if this is needed
        access(all) let id: UInt64

        /// Set of credit and debit balances associated with this position.
        /// TODO(jord): currently these are non-scaled as there is no interest accrual.
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
            }
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

        init(config: PoolConfig) {
            self.config = config
            self.tokenStates = {}
            self.reserves <- create Reserves()
            self.positions = {}
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
            let position <- create Position()
            self.positions[position.uuid] = PositionRecord(id: position.uuid)
            return <- position
        }

        /// Deposit tokens into a position.
        /// TODO: detailed documentation
        access(Participant) fun deposit(position: &Position, from: @{FungibleToken.Vault}) {
            pre {
                self.reserves.isSupported(tokenType: from.getType())
            }
            let _pid = position.uuid
            destroy from // placeholder — real impl routes to the reserve vault
        }

        /// Withdraw tokens from a position.
        /// TODO: detailed documentation
        access(all) fun withdraw(
            position: auth(FungibleToken.Withdraw) &Position,
            tokenType: Type,
            amount: UFix64
        ): @{FungibleToken.Vault} {
            pre {
                self.reserves.isSupported(tokenType: tokenType)
            }
            let _pid = position.uuid
            let _token = tokenType
            let _amt = amount
            panic("not implemented")
        }

        /// Manually liquidate an unhealthy position.
        /// TODO: detailed documentation
        access(Admin | Liquidate) fun liquidate(
            positionUUID: UInt64,
            repay: @{FungibleToken.Vault},
            seizeType: Type, /* will need more params here */
        ): @{FungibleToken.Vault} {
            pre {
                self.reserves.isSupported(tokenType: repay.getType())
                self.reserves.isSupported(tokenType: seizeType)
            }
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
    /// resource (or an authorized reference) is proof of ownership for withdrawals.
    /// The resource itself stores no funds; all custody lives in the pool.
    ///
    /// TODO(jord): get feedback on this approach. Alternative is Position holds a
    ///             reference to the pool and can provide withdraw etc. functions itself.
    access(all) resource Position {}

    init() {
        self.PoolStoragePath = /storage/FlowALPPool
        self.PoolPublicPath = /public/FlowALPPool
        self.AdminStoragePath = /storage/FlowALPAdmin
    }
}
