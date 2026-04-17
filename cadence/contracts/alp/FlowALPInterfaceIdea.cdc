import "FungibleToken"
import "FlowALPTypesIdea"

// -----------------------------------------------------------------------------
// ⚠️  DISCLAIMER — DRAFT / SUBJECT TO CHANGE
// -----------------------------------------------------------------------------
// This interface is a placeholder shim so the FlowYieldVaults lending-strategy
// prototype has something to talk to. Method signatures, return types, and the
// set of methods themselves will change once the real ALP design lands. It
// exists today only to let the yield-vaults layer compile and be tested.
// Do not build on this interface outside of this repo.
// -----------------------------------------------------------------------------

access(all) contract interface FlowALPInterfaceIdea {

    access(all) resource interface ALPPosition {
        access(all) fun deposit(from: @{FungibleToken.Vault})
        access(all) fun withdraw(type: Type, amount: UFix64): @{FungibleToken.Vault}

        /// Amount of `type` to DEPOSIT/REPAY to bring health back up to `minHealth`.
        /// Returns 0.0 if health is already at or above `minHealth`.
        view access(all) fun depositRequiredForMinHealth(type: Type, minHealth: UFix64): UFix64

        /// Amount of `type` available to WITHDRAW/BORROW while keeping health at `maxHealth`.
        /// Returns 0.0 if health is already at or below `maxHealth`.
        view access(all) fun withdrawRequiredForMaxHealth(type: Type, maxHealth: UFix64): UFix64

        view access(all) fun withdrawPossibleWithDeposit(type: Type, depositAmount: UFix64, maxHealth: UFix64): UFix64


        /// Debt repayment required to offset a planned collateral withdrawal
        /// while maintaining `targetHealth`.
        view access(all) fun debtRepaymentForCollateralWithdrawal(debtType: Type, collateralType: Type, collateralAmount: UFix64, targetHealth: UFix64): UFix64

        /// Current balance and direction (collateral vs debt) for `type`.
        view access(all) fun positionData(type: Type): FlowALPTypesIdea.TokenData
    }

    access(account) fun createPosition(): @{ALPPosition}
}
