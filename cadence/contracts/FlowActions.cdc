import "Burner"
import "ViewResolver"
import "FlowToken"
import "FungibleToken"
import "FlowTransactionScheduler"

access(all) contract FlowActions {

    /* --- FIELDS --- */

    /// The current ID assigned to UniqueIdentifiers as they are initialized
    /// It is incremented by 1 every time a UniqueIdentifier is created so each ID is only ever used once
    access(self) var currentID: UInt64
    /// The AuthenticationToken Capability required to create a UniqueIdentifier
    access(self) let authTokenCap: Capability<auth(Identify) &AuthenticationToken>
    /// The StoragePath for the AuthenticationToken resource
    access(self) let AuthTokenStoragePath: StoragePath

    /* --- INTERFACE-LEVEL EVENTS --- */

    /// Emitted when value is deposited to a Sink
    access(all) event Deposited(
        type: String,
        amount: UFix64,
        fromUUID: UInt64,
        uniqueID: UInt64?,
        sinkType: String
    )
    /// Emitted when value is withdrawn from a Source
    access(all) event Withdrawn(
        type: String,
        amount: UFix64,
        withdrawnUUID: UInt64,
        uniqueID: UInt64?,
        sourceType: String
    )
    /// Emitted when a Swapper executes a Swap
    access(all) event Swapped(
        inVault: String,
        outVault: String,
        inAmount: UFix64,
        outAmount: UFix64,
        inUUID: UInt64,
        outUUID: UInt64,
        uniqueID: UInt64?,
        swapperType: String
    )
    /// Emitted when a Flasher executes a flash loan
    access(all) event Flashed(
        requestedAmount: UFix64,
        borrowType: String,
        uniqueID: UInt64?,
        flasherType: String
    )
    /// Emitted when an IdentifiableResource's UniqueIdentifier is aligned with another DFA component
    access(all) event UpdatedID(
        oldID: UInt64?,
        newID: UInt64?,
        component: String,
        uuid: UInt64?
    )
    /// Emitted when an AutoBalancer is created
    access(all) event CreatedAutoBalancer(
        lowerThreshold: UFix64,
        upperThreshold: UFix64,
        vaultType: String,
        vaultUUID: UInt64,
        uuid: UInt64,
        uniqueID: UInt64?
    )
    /// Emitted when AutoBalancer.rebalance() is called
    access(all) event Rebalanced(
        amount: UFix64,
        value: UFix64,
        unitOfAccount: String,
        isSurplus: Bool,
        vaultType: String,
        vaultUUID: UInt64,
        balancerUUID: UInt64,
        address: Address?,
        uniqueID: UInt64?
    )
    /// Emitted when an AutoBalancer fails to self-schedule a recurring rebalance
    access(all) event FailedRecurringSchedule(
        whileExecuting: UInt64,
        balancerUUID: UInt64,
        address: Address?,
        error: String,
        uniqueID: UInt64?
    )

    /// Emitted when Liquidator.liquidate is called
    access(all) event Liquidated()

    /* --- CONSTRUCTS --- */

    access(all) entitlement Identify

    /// AuthenticationToken
    ///
    /// A resource intended to ensure UniqueIdentifiers are only created by the FlowActions contract
    ///
    access(all) resource AuthenticationToken {}

    /// UniqueIdentifier
    ///
    /// This construct enables protocols to trace stack operations via FlowActions interface-level events, identifying
    /// them by UniqueIdentifier IDs. IdentifiableResource Implementations should ensure that access to them is
    /// encapsulated by the structures they are used to identify.
    ///
    access(all) struct UniqueIdentifier {
        /// The ID value of this UniqueIdentifier
        access(all) let id: UInt64
        /// The AuthenticationToken Capability required to create this UniqueIdentifier. Since this is a struct which
        /// can be created in any context, this authorized Capability ensures that the UniqueIdentifier can only be
        /// created by the FlowActions contract, thus preventing forged UniqueIdentifiers from being created.
        access(self) let authCap: Capability<auth(Identify) &AuthenticationToken>

        access(contract) view init(_ id: UInt64, _ authCap: Capability<auth(Identify) &AuthenticationToken>) {
            pre {
                authCap.check(): "Invalid AuthenticationToken Capability provided"
            }
            self.id = id
            self.authCap = authCap
        }
    }

    /// ComponentInfo
    ///
    /// A struct containing minimal information about a FlowActions component and its inner components
    ///
    access(all) struct ComponentInfo {
        /// The type of the component
        access(all) let type: Type
        /// The UniqueIdentifier.id of the component
        access(all) let id: UInt64?
        /// The inner component types of the serving component
        access(all) let innerComponents: [ComponentInfo]
        init(
            type: Type,
            id: UInt64?,
            innerComponents: [ComponentInfo]
        ) {
            self.type = type
            self.id = id
            self.innerComponents = innerComponents
        }
    }

    /// Extend entitlement allowing for the authorized copying of UniqueIdentifiers from existing components
    access(all) entitlement Extend

    /// IdentifiableResource
    ///
    /// A resource interface containing a UniqueIdentifier and convenience getters about it
    ///
    access(all) struct interface IdentifiableStruct {
        /// An optional identifier allowing protocols to identify stacked connector operations by defining a protocol-
        /// specific Identifier to associated connectors on construction
        access(contract) var uniqueID: UniqueIdentifier?
        /// Convenience method returning the inner UniqueIdentifier's id or `nil` if none is set.
        ///
        /// NOTE: This interface method may be spoofed if the function is overridden, so callers should not rely on it
        /// for critical identification unless the implementation itself is known and trusted
        access(all) view fun id(): UInt64? {
            return self.uniqueID?.id
        }
        /// Returns a ComponentInfo struct containing information about this component and a list of ComponentInfo for
        /// each inner component in the stack.
        access(all) fun getComponentInfo(): ComponentInfo
        /// Returns a copy of the struct's UniqueIdentifier, used in extending a stack to identify another connector in
        /// a FlowActions stack. See FlowActions.align() for more information.
        access(contract) view fun copyID(): UniqueIdentifier? {
            post {
                result?.id == self.uniqueID?.id:
                "UniqueIdentifier of \(self.getType().identifier) was not successfully copied"
            }
        }
        /// Sets the UniqueIdentifier of this component to the provided UniqueIdentifier, used in extending a stack to
        /// identify another connector in a FlowActions stack. See FlowActions.align() for more information.
        access(contract) fun setID(_ id: UniqueIdentifier?) {
            post {
                self.uniqueID?.id == id?.id:
                "UniqueIdentifier of \(self.getType().identifier) was not successfully set"
                FlowActions.emitUpdatedID(
                    oldID: before(self.uniqueID?.id),
                    newID: self.uniqueID?.id,
                    component: self.getType().identifier,
                    uuid: nil // no UUID for structs
                ): "Unknown error emitting FlowActions.UpdatedID from IdentifiableStruct \(self.getType().identifier) with ID ".concat(self.id()?.toString() ?? "UNASSIGNED")
            }
        }
    }

    /// IdentifiableResource
    ///
    /// A resource interface containing a UniqueIdentifier and convenience getters about it
    ///
    access(all) resource interface IdentifiableResource {
        /// An optional identifier allowing protocols to identify stacked connector operations by defining a protocol-
        /// specific Identifier to associated connectors on construction
        access(contract) var uniqueID: UniqueIdentifier?
        /// Convenience method returning the inner UniqueIdentifier's id or `nil` if none is set.
        ///
        /// NOTE: This interface method may be spoofed if the function is overridden, so callers should not rely on it
        /// for critical identification unless the implementation itself is known and trusted
        access(all) view fun id(): UInt64? {
            return self.uniqueID?.id
        }
        /// Returns a ComponentInfo struct containing information about this component and a list of ComponentInfo for
        /// each inner component in the stack.
        access(all) fun getComponentInfo(): ComponentInfo
        /// Returns a copy of the struct's UniqueIdentifier, used in extending a stack to identify another connector in
        /// a FlowActions stack. See FlowActions.align() for more information.
        access(contract) view fun copyID(): UniqueIdentifier? {
            post {
                result?.id == self.uniqueID?.id:
                "UniqueIdentifier of \(self.getType().identifier) was not successfully copied"
            }
        }
        /// Sets the UniqueIdentifier of this component to the provided UniqueIdentifier, used in extending a stack to
        /// identify another connector in a FlowActions stack. See FlowActions.align() for more information.
        access(contract) fun setID(_ id: UniqueIdentifier?) {
            post {
                self.uniqueID?.id == id?.id:
                "UniqueIdentifier of \(self.getType().identifier) was not successfully set"
                FlowActions.emitUpdatedID(
                    oldID: before(self.uniqueID?.id),
                    newID: self.uniqueID?.id,
                    component: self.getType().identifier,
                    uuid: self.uuid
                ): "Unknown error emitting FlowActions.UpdatedID from IdentifiableStruct \(self.getType().identifier) with ID ".concat(self.id()?.toString() ?? "UNASSIGNED")
            }
        }
    }

    /// Sink
    ///
    /// A Sink Connector (or just “Sink”) is analogous to the Fungible Token Receiver interface that accepts deposits of
    /// funds. It differs from the standard Receiver interface in that it is a struct interface (instead of resource
    /// interface) and allows for the graceful handling of Sinks that have a limited capacity on the amount they can
    /// accept for deposit. Implementations should therefore favor graceful fallback on unexpected conditions, executing
    /// no-ops instead of reverting.
    /// - A Sink should prioritize liveness where possible, and not panic, for example if it has no funds or cannot
    ///   access funds.
    /// - A sink should only panic if not panicking would cause the Sink to have an inconsistent internal state
    ///   (unsafe or undefined for the Sink to continue in this state).
    access(all) struct interface Sink : IdentifiableStruct {
        /// Returns the Vault type accepted by this Sink
        access(all) view fun getSinkType(): Type
        /// Returns an estimate of how much can be withdrawn from the depositing Vault for this Sink to reach capacity
        access(all) fun minimumCapacity(): UFix64
        /// Deposits up to the Sink's capacity from the provided Vault
        access(all) fun depositCapacity(from: auth(FungibleToken.Withdraw) &{FungibleToken.Vault}) {
            pre {
                from.getType() == self.getSinkType():
                "Invalid vault provided for deposit - \(from.getType().identifier) is not \(self.getSinkType().identifier)"
            }
            post {
                FlowActions.emitDeposited(
                    type: from.getType().identifier,
                    beforeBalance: before(from.balance),
                    afterBalance: from.balance,
                    fromUUID: from.uuid,
                    uniqueID: self.uniqueID?.id,
                    sinkType: self.getType().identifier
                ): "Unknown error emitting FlowActions.Withdrawn from Sink \(self.getType().identifier) with ID ".concat(self.id()?.toString() ?? "UNASSIGNED")
            }
        }
    }

    /// Source
    ///
    /// A Source Connector (or just “Source”) is analogous to the Fungible Token Provider interface that provides funds
    /// on demand. It differs from the standard Provider interface in that it is a struct interface (instead of resource
    /// interface) and allows for graceful handling of the case that the Source might not know exactly the total amount
    /// of funds available to be withdrawn. Implementations should therefore avoid the possibility of reversion with
    /// graceful fallback on unexpected conditions, executing no-ops or returning an empty Vault instead of reverting.
    ///
    access(all) struct interface Source : IdentifiableStruct {
        /// Returns the Vault type the Source claims to offer.
        /// CAUTION: Untrusted Source implementations may return a different Vault type than claimed in `withdrawAvailable`.
        /// Users MUST validate the type of all withdrawn funds.
        access(all) view fun getSourceType(): Type
        /// Returns an estimate of how much of the associated Vault Type can be provided by this Source.
        access(all) fun minimumAvailable(): UFix64
        /// Withdraws the lesser of maxAmount or minimumAvailable(). If none is available, an empty Vault should be returned.
        /// CAUTION: Untrusted Source implementations may return a different Vault type than claimed in `getSourceType`.
        /// Users MUST validate the type of all withdrawn funds.
        access(FungibleToken.Withdraw) fun withdrawAvailable(maxAmount: UFix64): @{FungibleToken.Vault} {
            post {
                FlowActions.emitWithdrawn(
                    type: result.getType().identifier,
                    amount: result.balance,
                    withdrawnUUID: result.uuid,
                    uniqueID: self.uniqueID?.id ?? nil,
                    sourceType: self.getType().identifier
                ): "Unknown error emitting FlowActions.Withdrawn from Source \(self.getType().identifier) with ID ".concat(self.id()?.toString() ?? "UNASSIGNED")
            }
        }
    }

    /// Quote
    ///
    /// An interface for an estimate to be returned by a Swapper when asking for a swap estimate. This may be helpful
    /// for passing additional parameters to a Swapper relevant to the use case. Implementations may choose to add
    /// fields relevant to their Swapper implementation and downcast in swap() and/or swapBack() scope.
    /// By convention, a Quote with inAmount==outAmount==0 indicates no estimated swap price is available.
    ///
    access(all) struct interface Quote {
        /// The quoted pre-swap Vault type
        access(all) let inType: Type
        /// The quoted post-swap Vault type
        access(all) let outType: Type
        /// The quoted amount of pre-swap currency
        access(all) let inAmount: UFix64
        /// The quoted amount of post-swap currency for the defined inAmount
        access(all) let outAmount: UFix64
    }

    /// Swapper
    ///
    /// A basic interface for a struct that swaps between tokens. Implementations may choose to adapt this interface
    /// to fit any given swap protocol or set of protocols.
    ///
    access(all) struct interface Swapper : IdentifiableStruct {
        /// The type of Vault this Swapper accepts when performing a swap
        access(all) view fun inType(): Type
        /// The type of Vault this Swapper provides when performing a swap
        access(all) view fun outType(): Type
        /// Provides a quote for how many input tokens can be swapped for `forDesired` output tokens.
        /// The reverse flag simply inverts inType/outType and inAmount/outAmount in the quote.
        /// Interpretation:
        /// - reverse=false -> I want to provide `quote.inAmount` `swapper.inType()` tokens and receive `forDesired` `swapper.outType()` tokens.
        /// - reverse=true -> I want to provide `quote.inAmount` `swapper.outType()` tokens and receive `forDesired` `swapper.inType()` tokens.
        access(all) fun quoteIn(forDesired: UFix64, reverse: Bool): {Quote}
        /// The estimated amount delivered out for a provided input balance
        /// Provides a quote for how many output tokens can be swapped for `forProvided` input tokens.
        /// The reverse flag simply inverts inType/outType and inAmount/outAmount in the quote.
        /// Interpretation:
        /// - reverse=false -> I want to provide `forProvided` `swapper.inType()` tokens and receive `quote.outAmount` `swapper.outType()` tokens.
        /// - reverse=true -> I want to provide `forProvided` `swapper.outType()` tokens and receive `quote.outAmount` `swapper.inType()` tokens.
        access(all) fun quoteOut(forProvided: UFix64, reverse: Bool): {Quote}
        /// Performs a swap taking a Vault of type inVault, outputting a resulting outVault. Implementations may choose
        /// to swap along a pre-set path or an optimal path of a set of paths or even set of contained Swappers adapted
        /// to use multiple Flow swap protocols.
        access(all) fun swap(quote: {Quote}?, inVault: @{FungibleToken.Vault}): @{FungibleToken.Vault} {
            pre {
                inVault.getType() == self.inType():
                "Invalid vault provided for swap - \(inVault.getType().identifier) is not \(self.inType().identifier)"
                (quote?.inType ?? inVault.getType()) == inVault.getType():
                "Quote.inType type \(quote!.inType.identifier) does not match the provided inVault \(inVault.getType().identifier)"
            }
            post {
                result.getType() == self.outType():
                "Invalid swap() result - \(result.getType().identifier) is not \(self.outType().identifier)"
                emit Swapped(
                    inVault: before(inVault.getType().identifier),
                    outVault: result.getType().identifier,
                    inAmount: before(inVault.balance),
                    outAmount: result.balance,
                    inUUID: before(inVault.uuid),
                    outUUID: result.uuid,
                    uniqueID: self.uniqueID?.id ?? nil,
                    swapperType: self.getType().identifier
                )
            }
        }
        /// Performs a swap taking a Vault of type outVault, outputting a resulting inVault. Implementations may choose
        /// to swap along a pre-set path or an optimal path of a set of paths or even set of contained Swappers adapted
        /// to use multiple Flow swap protocols.
        access(all) fun swapBack(quote: {Quote}?, residual: @{FungibleToken.Vault}): @{FungibleToken.Vault} {
            pre {
                residual.getType() == self.outType():
                "Invalid vault provided for swapBack - \(residual.getType().identifier) is not \(self.outType().identifier)"
            }
            post {
                result.getType() == self.inType():
                "Invalid swapBack() result - \(result.getType().identifier) is not \(self.inType().identifier)"
                emit Swapped(
                    inVault: before(residual.getType().identifier),
                    outVault: result.getType().identifier,
                    inAmount: before(residual.balance),
                    outAmount: result.balance,
                    inUUID: before(residual.uuid),
                    outUUID: result.uuid,
                    uniqueID: self.uniqueID?.id ?? nil,
                    swapperType: self.getType().identifier
                )
            }
        }
    }

    /// SwapperProvider
    ///
    /// An interface for a wrapper around one or more Swappers.
    /// For example, a DEX which supports multiple trading pairs is conceptually a SwapperProvider which
    /// can provide a Swapper for each of its supported trading pairs.
    ///
    access(all) struct interface SwapperProvider {
        /// Returns a Swapper for the given trade pair, if the pair is supported.
        /// Otherwise returns nil.
        access(all) fun getSwapper(inType: Type, outType: Type): {FlowActions.Swapper}?
    }

    /// PriceOracle
    ///
    /// An interface for a price oracle adapter. Implementations should adapt this interface to various price feed
    /// oracles deployed on Flow
    ///
    access(all) struct interface PriceOracle : IdentifiableStruct {
        /// Returns the asset type serving as the price basis - e.g. USD in FLOW/USD
        access(all) view fun unitOfAccount(): Type
        /// Returns the latest price data for a given asset denominated in unitOfAccount() if available, otherwise `nil`
        /// should be returned. Callers should note that although an optional is supported, implementations may choose
        /// to revert.
        access(all) fun price(ofToken: Type): UFix64? {
            post {
                result == nil || result! > 0.0:
                "PriceOracle must return a price greater than 0.0 if available"
            }
        }
    }

    /// Flasher
    ///
    /// An interface for a flash loan adapter. Implementations should adapt this interface to various flash loan
    /// protocols deployed on Flow
    ///
    access(all) struct interface Flasher : IdentifiableStruct {
        /// Returns the asset type this Flasher can issue as a flash loan
        access(all) view fun borrowType(): Type
        /// Returns the estimated fee for a flash loan of the specified amount
        access(all) fun calculateFee(loanAmount: UFix64): UFix64
        /// Performs a flash loan of the specified amount. The callback function is passed the fee amount, a Vault
        /// containing the loan, and the data. The callback function should return a Vault containing the loan + fee.
        access(all) fun flashLoan(
            amount: UFix64,
            data: AnyStruct?,
            callback: fun(UFix64, @{FungibleToken.Vault}, AnyStruct?): @{FungibleToken.Vault} // fee, loan, data
        ) {
            post {
                emit Flashed(
                    requestedAmount: amount,
                    borrowType: self.borrowType().identifier,
                    uniqueID: self.uniqueID?.id ?? nil,
                    flasherType: self.getType().identifier
                )
            }
        }
    }

    /// Liquidator
    ///
    /// A Liquidator connector enables the liquidation of funds. The general use case is withdrawing all
    /// available funds from a connected liquidity source.
    ///
    access(all) struct interface Liquidator : IdentifiableStruct {
        /// Returns the type this Liquidator provides on liquidation
        access(all) view fun getLiquidationType(): Type
        /// Returns the amount available for liquidation
        access(all) fun liquidationAmount(): UFix64
        /// Liquidates available funds. It's up to the implementation to cast and utilize the provided data
        /// if any is provided.
        access(FungibleToken.Withdraw) fun liquidate(data: AnyStruct?): @{FungibleToken.Vault} {
            post {
                result.getType() == self.getLiquidationType():
                "Invalid liquidation - expected \(self.getLiquidationType().identifier) but returned \(result.getType().identifier)"
                emit Liquidated()
            }
        }
    }

    /// Creates a new UniqueIdentifier used for identifying action stacks
    ///
    /// @return a new UniqueIdentifier
    ///
    access(all) fun createUniqueIdentifier(): UniqueIdentifier {
        let id = UniqueIdentifier(self.currentID, self.authTokenCap)
        self.currentID = self.currentID + 1
        return id
    }

    /// Derives the path identifier for an AutoBalancer for a given vault type
    access(all) view fun deriveAutoBalancerPathIdentifier(vaultType: Type): String? {
        if !vaultType.isSubtype(of: Type<@{FungibleToken.Vault}>()) {
            return nil
        }
        return "DeFiActionAutoBalancer_\(vaultType.identifier)"
    }

    /// Aligns the UniqueIdentifier of the provided component with the provided component, setting the UniqueIdentifier of
    /// the provided component to the UniqueIdentifier of the provided component. Parameters are AnyStruct to allow for
    /// alignment of both IdentifiableStruct and IdentifiableResource. However, note that the provided component must
    /// be an auth(Extend) &{IdentifiableStruct} or auth(Extend) &{IdentifiableResource} to be aligned.
    ///
    /// @param toUpdate: The component to update the UniqueIdentifier of. Must be an auth(Extend) &{IdentifiableStruct}
    ///     or auth(Extend) &{IdentifiableResource}
    /// @param with: The component to align the UniqueIdentifier of the provided component with. Must be an
    ///     auth(Identify) &{IdentifiableStruct} or auth(Identify) &{IdentifiableResource}
    ///
    access(all) fun alignID(toUpdate: AnyStruct, with: AnyStruct) {
        let maybeISToUpdate = toUpdate as? auth(Extend) &{IdentifiableStruct}
        let maybeIRToUpdate = toUpdate as? auth(Extend) &{IdentifiableResource}
        let maybeISWith = with as? auth(Identify) &{IdentifiableStruct}
        let maybeIRWith = with as? auth(Identify) &{IdentifiableResource}

        if maybeISToUpdate != nil && maybeISWith != nil {
            maybeISToUpdate!.setID(maybeISWith!.copyID())
        } else if maybeISToUpdate != nil && maybeIRWith != nil {
            maybeISToUpdate!.setID(maybeIRWith!.copyID())
        } else if maybeIRToUpdate != nil && maybeISWith != nil {
            maybeIRToUpdate!.setID(maybeISWith!.copyID())
        } else if maybeIRToUpdate != nil && maybeIRWith != nil {
            maybeIRToUpdate!.setID(maybeIRWith!.copyID())
        }
        return
    }

    /* --- INTERNAL CONDITIONAL EVENT EMITTERS --- */

    /// Emits Deposited event if a change in balance is detected
    access(self) view fun emitDeposited(
        type: String,
        beforeBalance: UFix64,
        afterBalance: UFix64,
        fromUUID: UInt64,
        uniqueID: UInt64?,
        sinkType: String
    ): Bool {
        if beforeBalance == afterBalance {
            return true
        }
        emit Deposited(
            type: type,
            amount: beforeBalance > afterBalance ? beforeBalance - afterBalance : afterBalance - beforeBalance,
            fromUUID: fromUUID,
            uniqueID: uniqueID,
            sinkType: sinkType
        )
        return true
    }

    /// Emits Withdrawn event if a change in balance is detected
    access(self) view fun emitWithdrawn(
        type: String,
        amount: UFix64,
        withdrawnUUID: UInt64,
        uniqueID: UInt64?,
        sourceType: String
    ): Bool {
        if amount == 0.0 {
            return true
        }
        emit Withdrawn(
            type: type,
            amount: amount,
            withdrawnUUID: withdrawnUUID,
            uniqueID: uniqueID,
            sourceType: sourceType
        )
        return true
    }

    /// Emits Aligned event if a change in UniqueIdentifier is detected
    access(self) view fun emitUpdatedID(
        oldID: UInt64?,
        newID: UInt64?,
        component: String,
        uuid: UInt64?
    ): Bool {
        if oldID == newID {
            return true
        }
        emit UpdatedID(
            oldID: oldID,
            newID: newID,
            component: component,
            uuid: uuid
        )
        return true
    }

    init() {
        self.currentID = 0
        self.AuthTokenStoragePath = /storage/authToken

        self.account.storage.save(<-create AuthenticationToken(), to: self.AuthTokenStoragePath)
        self.authTokenCap = self.account.capabilities.storage.issue<auth(Identify) &AuthenticationToken>(self.AuthTokenStoragePath)

        assert(self.authTokenCap.check(), message: "Failed to issue AuthenticationToken Capability")
    }
}