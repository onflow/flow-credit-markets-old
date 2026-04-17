import "FungibleToken"
import "FlowActionsIdea"
import "FlowALPInterfaceIdea"
import "FlowALPTypesIdea"

/// Test-only mock of `FlowALPInterfaceIdea`. Unlike `FlowALP`, this impl
/// actually holds deposited vaults per type and returns them on `withdraw`,
/// so tests can assert on real balance round-trips.
access(all) contract MockALP: FlowALPInterfaceIdea {

    access(all) resource Position: FlowALPInterfaceIdea.ALPPosition {
        access(self) let vaults: @{Type: {FungibleToken.Vault}}

        init() {
            self.vaults <- {}
        }

        access(all) fun deposit(from: @{FungibleToken.Vault}) {
            let type = from.getType()
            let existing <- self.vaults.remove(key: type)
            if existing == nil {
                destroy existing
                self.vaults[type] <-! from
                return
            }
            let held <- existing!
            held.deposit(from: <- from)
            self.vaults[type] <-! held
        }

        access(all) fun withdraw(type: Type, amount: UFix64): @{FungibleToken.Vault} {
            let held <- self.vaults.remove(key: type)
            if held == nil {
                destroy held
                return <- FlowActionsIdea.getEmptyVault(type)
            }
            let h <- held!
            let out <- h.withdraw(amount: amount)
            self.vaults[type] <-! h
            return <- out
        }

        access(all) view fun depositRequiredForMinHealth(type: Type, minHealth: UFix64): UFix64 {
            let _t = type
            let _h = minHealth
            return 0.0
        }

        access(all) view fun withdrawRequiredForMaxHealth(type: Type, maxHealth: UFix64): UFix64 {
            let _t = type
            let _h = maxHealth
            return 0.0
        }

        access(all) view fun withdrawPossibleWithDeposit(type: Type, depositAmount: UFix64, maxHealth: UFix64): UFix64 {
            let _t = type
            let _d = depositAmount
            let _h = maxHealth
            return 0.0
        }

        access(all) view fun debtRepaymentForCollateralWithdrawal(debtType: Type, collateralType: Type, collateralAmount: UFix64, targetHealth: UFix64): UFix64 {
            let _d = debtType
            let _ct = collateralType
            let _c = collateralAmount
            let _h = targetHealth
            return 0.0
        }

        access(all) view fun positionData(type: Type): FlowALPTypesIdea.TokenData {
            let _ = type
            return FlowALPTypesIdea.TokenData(amount: 0.0, direction: FlowALPTypesIdea.Direction.Collateral)
        }
    }

    access(account) fun createPosition(): @{FlowALPInterfaceIdea.ALPPosition} {
        return <- create Position()
    }
}
