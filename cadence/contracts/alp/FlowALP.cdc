import "FungibleToken"
import "Burner"

access(all) contract FlowALP {

    // access(all) var totalSupply: UFix64

    // access(all) let LPVaultStoragePath: StoragePath
    // access(all) let LPVaultPublicPath:  PublicPath
    // access(all) let AdminStoragePath:   StoragePath
    // access(all) let ReserveStoragePath: StoragePath

    // access(all) event Deposited(amount: UFix64, lpMinted: UFix64)
    // access(all) event Withdrawn(lpBurned: UFix64, amount: UFix64)

    // // -------------------------------------------------------------------------
    // // Value types
    // // -------------------------------------------------------------------------

    // access(all) enum Direction: UInt8 {
    //     access(all) case Collateral
    //     access(all) case Debt
    // }

    // /// Balance and side (Collateral or Debt) for a single token in a position.
    // access(all) struct TokenData {
    //     access(all) let amount:    UFix64
    //     access(all) let direction: Direction

    //     init(amount: UFix64, direction: Direction) {
    //         self.amount    = amount
    //         self.direction = direction
    //     }
    // }

    // /// Pricing and risk parameters for a token.
    // /// Defaults (price=1, CF=1) are used for any token without an explicit config.
    // access(all) struct TokenConfig {
    //     access(all) let price:            UFix64
    //     access(all) let collateralFactor: UFix64   // 0.0–1.0

    //     init(price: UFix64, collateralFactor: UFix64) {
    //         self.price            = price
    //         self.collateralFactor = collateralFactor
    //     }
    // }

    // // -------------------------------------------------------------------------
    // // LP Token
    // // -------------------------------------------------------------------------

    // access(all) resource LPVault: FungibleToken.Vault {

    //     access(all) var balance: UFix64

    //     access(all) event ResourceDestroyed(uuid: UInt64 = self.uuid, balance: UFix64 = self.balance)

    //     init(balance: UFix64) {
    //         self.balance = balance
    //     }

    //     access(contract) fun burnCallback() {
    //         if self.balance > 0.0 {
    //             MockALP.totalSupply = MockALP.totalSupply - self.balance
    //         }
    //         self.balance = 0.0
    //     }

    //     access(all) view fun getViews(): [Type] { return [] }
    //     access(all) fun resolveView(_ t: Type): AnyStruct? { return nil }

    //     access(all) view fun getSupportedVaultTypes(): {Type: Bool} {
    //         return {self.getType(): true}
    //     }

    //     access(all) view fun isSupportedVaultType(type: Type): Bool {
    //         return type == self.getType()
    //     }

    //     access(all) view fun isAvailableToWithdraw(amount: UFix64): Bool {
    //         return amount <= self.balance
    //     }

    //     access(FungibleToken.Withdraw) fun withdraw(amount: UFix64): @LPVault {
    //         self.balance = self.balance - amount
    //         return <-create LPVault(balance: amount)
    //     }

    //     access(all) fun deposit(from: @{FungibleToken.Vault}) {
    //         let lp <- from as! @LPVault
    //         self.balance = self.balance + lp.balance
    //         lp.balance = 0.0
    //         destroy lp
    //     }

    //     access(all) fun createEmptyVault(): @LPVault {
    //         return <-create LPVault(balance: 0.0)
    //     }
    // }

    // // -------------------------------------------------------------------------
    // // Position — per-user resource with independent balances and health math
    // // -------------------------------------------------------------------------

    // access(all) resource Position {

    //     access(self) var balances:     {Type: MockALP.TokenData}
    //     access(self) var tokenConfigs: {Type: MockALP.TokenConfig}

    //     /// The collateral token whose price/CF is used to convert raw token units
    //     /// in debtRepaymentForCollateralWithdrawal.
    //     /// If nil, collateralAmount is treated as an already-priced USD value.
    //     access(self) var primaryCollateralType: Type?

    //     init() {
    //         self.balances             = {}
    //         self.tokenConfigs         = {}
    //         self.primaryCollateralType = nil
    //     }

    //     // --- Setup ---

    //     access(all) fun setBalance(type: Type, data: MockALP.TokenData) {
    //         self.balances[type] = data
    //     }

    //     access(all) fun setTokenConfig(type: Type, config: MockALP.TokenConfig) {
    //         self.tokenConfigs[type] = config
    //     }

    //     access(all) fun setPrimaryCollateralType(_ type: Type) {
    //         self.primaryCollateralType = type
    //     }

    //     // --- Internal helpers ---

    //     access(self) fun _config(_ type: Type): MockALP.TokenConfig {
    //         return self.tokenConfigs[type]
    //             ?? MockALP.TokenConfig(price: 1.0, collateralFactor: 1.0)
    //     }

    //     access(self) fun _effectiveCollateral(): UFix64 {
    //         var total: UFix64 = 0.0
    //         for t in self.balances.keys {
    //             let d = self.balances[t]!
    //             if d.direction == MockALP.Direction.Collateral {
    //                 let cfg = self._config(t)
    //                 total = total + d.amount * cfg.price * cfg.collateralFactor
    //             }
    //         }
    //         return total
    //     }

    //     access(self) fun _effectiveDebt(): UFix64 {
    //         var total: UFix64 = 0.0
    //         for t in self.balances.keys {
    //             let d = self.balances[t]!
    //             if d.direction == MockALP.Direction.Debt {
    //                 let cfg = self._config(t)
    //                 total = total + d.amount * cfg.price
    //             }
    //         }
    //         return total
    //     }

    //     // --- Health ---

    //     access(all) fun getEffectiveCollateral(): UFix64 { return self._effectiveCollateral() }
    //     access(all) fun getEffectiveDebt(): UFix64       { return self._effectiveDebt() }

    //     /// Returns the current health factor.
    //     /// Returns UFix64.max when there is no debt (fully collateralised).
    //     access(all) fun getHealth(): UFix64 {
    //         let ed = self._effectiveDebt()
    //         if ed == 0.0 {
    //             return UFix64.max
    //         }
    //         return self._effectiveCollateral() / ed
    //     }

    //     // --- Core functions ---

    //     /// Calculates the token amount required to bring health back to the nearest bound.
    //     ///
    //     /// - health < minHealth → amount to DEPOSIT (Collateral type) or REPAY (Debt type)
    //     /// - health > maxHealth → amount to WITHDRAW (Collateral type) or BORROW (Debt type)
    //     /// - health within bounds → 0.0
    //     ///
    //     /// Direction is inferred from the token's current position entry.
    //     /// Unknown tokens default to Collateral direction.
    //     access(all) fun balanceToHealthBounds(type: Type, minHealth: UFix64, maxHealth: UFix64): UFix64 {
    //         let ec = self._effectiveCollateral()
    //         let ed = self._effectiveDebt()
    //         if ed == 0.0 {
    //             return 0.0
    //         }

    //         let h   = ec / ed
    //         let cfg = self._config(type)

    //         if h < minHealth {
    //             let isCollateral = self.balances[type]?.direction != MockALP.Direction.Debt

    //             if isCollateral {
    //                 // (ec + Δ × price × CF) / ed = minHealth  →  Δ = (minHealth × ed − ec) / (price × CF)
    //                 let numerator   = minHealth * ed - ec
    //                 let denominator = cfg.price * cfg.collateralFactor
    //                 return numerator > 0.0 && denominator > 0.0 ? numerator / denominator : 0.0
    //             } else {
    //                 // ec / (ed − Δ × price) = minHealth  →  Δ = (ed − ec / minHealth) / price
    //                 if minHealth == 0.0 || cfg.price == 0.0 { return 0.0 }
    //                 let delta = (ed - ec / minHealth) / cfg.price
    //                 return delta > 0.0 ? delta : 0.0
    //             }

    //         } else if h > maxHealth {
    //             let isCollateral = self.balances[type]?.direction != MockALP.Direction.Debt

    //             if isCollateral {
    //                 // (ec − Δ × price × CF) / ed = maxHealth  →  Δ = (ec − maxHealth × ed) / (price × CF)
    //                 let numerator   = ec - maxHealth * ed
    //                 let denominator = cfg.price * cfg.collateralFactor
    //                 return numerator > 0.0 && denominator > 0.0 ? numerator / denominator : 0.0
    //             } else {
    //                 // ec / (ed + Δ × price) = maxHealth  →  Δ = (ec / maxHealth − ed) / price
    //                 if maxHealth == 0.0 || cfg.price == 0.0 { return 0.0 }
    //                 let delta = (ec / maxHealth - ed) / cfg.price
    //                 return delta > 0.0 ? delta : 0.0
    //             }
    //         }

    //         return 0.0
    //     }

    //     /// Calculates the debt repayment required to offset a planned collateral withdrawal
    //     /// while maintaining targetHealth.
    //     ///
    //     /// collateralAmount is in raw collateral token units when primaryCollateralType is set;
    //     /// otherwise it is treated as an already-priced USD-equivalent value.
    //     access(all) fun debtRepaymentForCollateralWithdrawal(
    //         debtType:         Type,
    //         collateralAmount: UFix64,
    //         targetHealth:     UFix64
    //     ): UFix64 {
    //         if targetHealth == 0.0 { return 0.0 }

    //         let ec = self._effectiveCollateral()
    //         let ed = self._effectiveDebt()

    //         let collateralReduction: UFix64
    //         if let colType = self.primaryCollateralType {
    //             let cfg = self._config(colType)
    //             collateralReduction = collateralAmount * cfg.price * cfg.collateralFactor
    //         } else {
    //             collateralReduction = collateralAmount
    //         }

    //         let newEC = ec > collateralReduction ? ec - collateralReduction : 0.0

    //         // targetHealth = newEC / (ed − Δ × debtPrice)  →  Δ = (ed − newEC / targetHealth) / debtPrice
    //         let targetDebt = newEC / targetHealth
    //         if targetDebt >= ed { return 0.0 }

    //         let debtCfg = self._config(debtType)
    //         if debtCfg.price == 0.0 { return 0.0 }
    //         let repayment = (ed - targetDebt) / debtCfg.price
    //         return repayment > 0.0 ? repayment : 0.0
    //     }

    //     /// Returns the current balance and direction for a token.
    //     /// Returns a zero Collateral entry for tokens not in the position.
    //     access(all) fun positionData(type: Type): MockALP.TokenData {
    //         return self.balances[type]
    //             ?? MockALP.TokenData(amount: 0.0, direction: MockALP.Direction.Collateral)
    //     }
    // }

    // // -------------------------------------------------------------------------
    // // Admin — LP operations + position factory
    // // -------------------------------------------------------------------------

    // access(all) resource Admin {

    //     /// Create a fresh empty position for a user.
    //     access(all) fun createPosition(): @Position {
    //         return <-create Position()
    //     }

    //     /// Deposit underlying tokens → mint LP shares 1:1.
    //     access(all) fun deposit(tokens: @{FungibleToken.Vault}): @LPVault {
    //         let amount = tokens.balance

    //         let reserve = MockALP.account.storage
    //             .borrow<&{FungibleToken.Vault}>(from: MockALP.ReserveStoragePath)
    //             ?? panic("reserve vault not found")
    //         reserve.deposit(from: <-tokens)

    //         MockALP.totalSupply = MockALP.totalSupply + amount
    //         let lp <- create LPVault(balance: amount)
    //         emit Deposited(amount: amount, lpMinted: amount)
    //         return <-lp
    //     }

    //     /// Burn LP tokens → return underlying tokens 1:1.
    //     access(all) fun withdraw(lp: @LPVault): @{FungibleToken.Vault} {
    //         let amount = lp.balance
    //         Burner.burn(<-lp)

    //         let reserve = MockALP.account.storage
    //             .borrow<auth(FungibleToken.Withdraw) &{FungibleToken.Vault}>(from: MockALP.ReserveStoragePath)
    //             ?? panic("reserve vault not found")
    //         let tokens <- reserve.withdraw(amount: amount)
    //         emit Withdrawn(lpBurned: amount, amount: amount)
    //         return <-tokens
    //     }
    // }

    // // -------------------------------------------------------------------------
    // // Init
    // // -------------------------------------------------------------------------

    // init(reserveVault: @{FungibleToken.Vault}) {
    //     self.totalSupply = 0.0

    //     let addr = self.account.address
    //     self.LPVaultStoragePath = StoragePath(identifier: "mockALPLPVault_\(addr)")!
    //     self.LPVaultPublicPath  = PublicPath(identifier:  "mockALPLPVault_\(addr)")!
    //     self.AdminStoragePath   = StoragePath(identifier: "mockALPAdmin_\(addr)")!
    //     self.ReserveStoragePath = StoragePath(identifier: "mockALPReserve_\(addr)")!

    //     self.account.storage.save(<-reserveVault, to: self.ReserveStoragePath)
    //     self.account.storage.save(<-create Admin(), to: self.AdminStoragePath)
    //     self.account.storage.save(<-create LPVault(balance: 0.0), to: self.LPVaultStoragePath)

    //     let lpCap = self.account.capabilities.storage.issue<&LPVault>(self.LPVaultStoragePath)
    //     self.account.capabilities.publish(lpCap, at: self.LPVaultPublicPath)
    // }
}
