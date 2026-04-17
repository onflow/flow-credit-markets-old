import "FungibleToken"
import "FlowActionsIdea"

access(all) contract MockSwapper {

    access(all) struct Swapper: FlowActionsIdea.Swapper {
        access(all) let token0: Type
        access(all) let token1: Type
        access(all) let fee: UInt32

        init(token0: Type, token1: Type) {
            self.token0 = token0
            self.token1 = token1
            self.fee = 0
        }

        access(all) view fun quoteExactInput(zeroForOne _: Bool, amountIn: UFix64): UFix64 {
            return amountIn
        }

        access(all) view fun quoteExactOutput(zeroForOne _: Bool, amountOut: UFix64): UFix64 {
            return amountOut
        }

        access(all) fun swap(zeroForOne _: Bool, inVault: @{FungibleToken.Vault}): @{FungibleToken.Vault} {
            return <- inVault
        }
    }

    access(all) fun createSwapper(token0: Type, token1: Type): Swapper {
        return Swapper(token0: token0, token1: token1)
    }
}
