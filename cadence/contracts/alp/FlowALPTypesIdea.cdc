// -----------------------------------------------------------------------------
// ⚠️  DISCLAIMER — DRAFT / SUBJECT TO CHANGE
// -----------------------------------------------------------------------------
// These types are placeholders used only to unblock the FlowYieldVaults
// lending-strategy prototype. The enum, struct, and their field shapes will
// almost certainly change once the real ALP design lands. Do not build on
// them outside of this repo.
// -----------------------------------------------------------------------------

access(all) contract FlowALPTypesIdea {

    access(all) enum Direction: UInt8 {
        access(all) case Collateral
        access(all) case Debt
    }

    access(all) struct TokenData {
        access(all) let amount: UFix64
        access(all) let direction: Direction

        view init(amount: UFix64, direction: Direction) {
            self.amount = amount
            self.direction = direction
        }
    }
}
