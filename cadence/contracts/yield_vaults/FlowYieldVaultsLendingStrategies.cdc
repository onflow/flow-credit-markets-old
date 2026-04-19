import "FungibleToken"
import "FlowActionsIdea"
import "FlowALPInterfaceIdea"
import "FlowALPHealthWatcherIdea"
import "FlowYieldVaultsInterfaces"
import "FlowALPHealthWatcher"

/// Factory for `LendingStrategy` instances and their `LendingStrategyVault`
/// yield vaults. Strategy structs are stored in the registry of
/// `FlowYieldVaults`; this contract only constructs them.
///
/// An ALP position and a health watcher are attached to each yield vault at
/// creation time. While the real ALP / health-watcher designs are in flux
/// this contract wires the vault up to the `Mock*` implementations directly.
access(all) contract FlowYieldVaultsLendingStrategies {

    /// Emitted when a new lending strategy is constructed.
    access(all) event LendingStrategyCreated()
    /// Emitted when a new lending strategy yield vault is constructed.
    access(all) event LendingStrategyVaultCreated()

    /// Parameters of a single lending-based yield strategy:
    /// deposit collateral, borrow debt, swap debt → yield-bearing token.
    access(all) struct LendingStrategy: FlowYieldVaultsInterfaces.Strategy {
        access(all) let collateralTokenType: Type
        access(all) let debtTokenType: Type
        access(all) let yieldTokenType: Type
        access(all) let alpContractName: String
        access(all) let collateralDebtSwapper: {FlowActionsIdea.Swapper}
        access(all) let debtYieldSwapper: {FlowActionsIdea.Swapper}
        access(all) let minHealth: UFix64
        access(all) let maxHealth: UFix64

        init(
            collateralDebtSwapper: {FlowActionsIdea.Swapper},
            debtYieldSwapper: {FlowActionsIdea.Swapper},
            yieldTokenType: Type,
            debtTokenType: Type,
            collateralTokenType: Type,
            alpContractName: String,
            minHealth: UFix64,
            maxHealth: UFix64
        ) {
            self.collateralDebtSwapper = collateralDebtSwapper
            self.debtYieldSwapper = debtYieldSwapper
            self.yieldTokenType = yieldTokenType
            self.debtTokenType = debtTokenType
            self.collateralTokenType = collateralTokenType
            self.alpContractName = alpContractName
            self.minHealth = minHealth
            self.maxHealth = maxHealth
        }

        /// Creates a new yield vault backed by this strategy.
        /// The returned vault captures a copy of this strategy's parameters,
        /// an ALP position, and a health watcher.
        access(all) fun createYieldVault(name _: String): @{FlowYieldVaultsInterfaces.YieldVault} {
            let watcher <- FlowALPHealthWatcher.createWatcher()
            let vault <- create LendingStrategyVault(
                strategy: self,
                watcher: <- watcher
            )
            emit LendingStrategyVaultCreated()
            return <- vault
        }
    }

    /// Yield vault produced by a `LendingStrategy`.
    /// Holds the strategy parameters, an ALP position, a health watcher,
    /// and the yield token balance.
    access(all) resource LendingStrategyVault: FlowYieldVaultsInterfaces.YieldVault {
        access(self) let strategy: LendingStrategy
        access(self) let alpPosition: @{FlowALPInterfaceIdea.ALPPosition}
        access(self) let watcher: @{FlowALPHealthWatcherIdea.Watcher}
        access(self) let yieldTokens: @{FungibleToken.Vault}

        /// Deposits collateral into the strategy.
        /// TODO: put into ALP, take max loan, swap debt → yield, store yield.
        access(all) fun deposit(from collateral: @{FungibleToken.Vault}) {
            self.alpPosition.deposit(from: <- collateral)
            let debt <- self.withdrawMaxDebt()
            let yield <- self.strategy.debtYieldSwapper.swap(
                zeroForOne: true,
                inVault: <- debt
            )
            self.yieldTokens.deposit(from: <- yield)
        }

        /// Withdraws `amount` of yield tokens.
        access(FungibleToken.Withdraw) fun withdraw(amount: UFix64): @{FungibleToken.Vault} {
            let debtDepositRequired = self.depositRequiredForWithdrawal(amount: amount)
            if debtDepositRequired > 0.0 {
                let debt <- self.swapYieldToDebt(debtAmount: debtDepositRequired)
                self.alpPosition.deposit(from: <- debt)
            }
            let collateral <- self.withdrawCollateral(amount: amount)
            return <- collateral
        }

        access(all) fun rebalance() {

        }

        view access(all) fun isAvailableToWithdraw(amount _: UFix64): Bool {
            let possibleDebt = self.strategy.debtYieldSwapper.quoteExactInput(
                zeroForOne: false,
                amountIn: self.yieldTokens.balance
            )
            // in case theres is still debt remaining we have to swap some collateral back to debt
            let collateralWithdrawPossible = self.alpPosition.withdrawPossibleWithDeposit(
                type: self.strategy.collateralTokenType,
                depositAmount: self.yieldTokens.balance,
                maxHealth: self.strategy.maxHealth
            )
            return possibleDebt <= collateralWithdrawPossible
        }

        view access(all) fun getSupportedVaultTypes(): {Type: Bool} {
            return {
                self.strategy.collateralTokenType: true
            }
        }

        view access(all) fun isSupportedVaultType(type: Type): Bool {
            return type == self.strategy.collateralTokenType
        }

        access(self) fun withdrawMaxDebt(): @{FungibleToken.Vault} {
            let amount = self.alpPosition.withdrawRequiredForMaxHealth(
                type: self.strategy.debtTokenType,
                maxHealth: self.strategy.maxHealth
            )
            return <- self.alpPosition.withdraw(
                type: self.strategy.debtTokenType,
                amount: amount
            )
        }

        access(self) fun withdrawCollateral(amount: UFix64): @{FungibleToken.Vault} {
            post {
                result.balance == amount: "Withdraw did not result in the expected amount of collateral"
            }
            return <- self.alpPosition.withdraw(
                type: self.strategy.collateralTokenType,
                amount: amount
            )
        }

        access(self) fun depositRequiredForWithdrawal(amount: UFix64): UFix64 {
            return self.alpPosition.debtRepaymentForCollateralWithdrawal(
                debtType: self.strategy.debtTokenType,
                collateralType: self.strategy.collateralTokenType,
                collateralAmount: amount,
                targetHealth: self.strategy.minHealth
            )
        }

        access(self) fun swapYieldToDebt(debtAmount: UFix64): @{FungibleToken.Vault} {
            post {
                result.balance == debtAmount: "Swap did not result in the expected amount of debt"
            }
            let yieldAmountNeeded = self.strategy.debtYieldSwapper.quoteExactOutput(zeroForOne: false, amountOut: debtAmount)
            let yield <- self.yieldTokens.withdraw(amount: yieldAmountNeeded)
            return <- self.strategy.debtYieldSwapper.swap(
                zeroForOne: false,
                inVault: <- yield
            )
        }

        init(
            strategy: LendingStrategy,
            watcher: @{FlowALPHealthWatcherIdea.Watcher}
        ) {
            self.strategy = strategy
            self.alpPosition <- FlowYieldVaultsLendingStrategies.createALPPosition(contractName: strategy.alpContractName)
            self.watcher <- watcher
            self.yieldTokens <- FlowActionsIdea.getEmptyVault(strategy.yieldTokenType)
        }
    }

    /// Constructs a new `LendingStrategy` and emits `LendingStrategyCreated`.
    /// The returned struct is expected to be passed to
    /// `FlowYieldVaults.Admin.registerStrategy` by the caller.
    access(all) fun createLendingStrategy(
        collateralDebtSwapper: {FlowActionsIdea.Swapper},
        debtYieldSwapper: {FlowActionsIdea.Swapper},
        yieldTokenType: Type,
        debtTokenType: Type,
        collateralTokenType: Type,
        alpContractName: String,
        minHealth: UFix64,
        maxHealth: UFix64
    ): LendingStrategy {
        let strategy = LendingStrategy(
            collateralDebtSwapper: collateralDebtSwapper,
            debtYieldSwapper: debtYieldSwapper,
            yieldTokenType: yieldTokenType,
            debtTokenType: debtTokenType,
            collateralTokenType: collateralTokenType,
            alpContractName: alpContractName,
            minHealth: minHealth,
            maxHealth: maxHealth
        )
        emit LendingStrategyCreated()
        return strategy
    }

    access(contract) fun createALPPosition(contractName: String): @{FlowALPInterfaceIdea.ALPPosition} {
        let alp = self.account.contracts.borrow<&{FlowALPInterfaceIdea}>(name: contractName)
            ?? panic("FlowALP contract '\(contractName)' not found on this account")
        return <- alp.createPosition()
    }
}
