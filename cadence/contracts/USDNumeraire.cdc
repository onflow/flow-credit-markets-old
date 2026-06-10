import "OffchainCurrency.cdc"
import "FungibleTokenMetadataViews"
import "MetadataViews"

/// USD represents the actual US Dollar currency, not any stablecoin pegged to the US Dollar.
/// It is the default numeraire (unit of account) for the ALP, as well as for most price oracles.
/// As an off-chain currency, vaults of USD cannot be created.
access(all) contract USD: OffchainCurrency {
    /// Gets a list of the metadata views that this contract supports
    access(all) view fun getContractViews(resourceType _: Type?): [Type] {
        return [Type<FungibleTokenMetadataViews.FTDisplay>(),
                Type<FungibleTokenMetadataViews.TotalSupply>()]
    }

    /// Get a Metadata View from the contract
    ///
    /// @param view: The Type of the desired view.
    /// @return A structure representing the requested view.
    ///
    access(all) fun resolveContractView(resourceType _: Type?, viewType: Type): AnyStruct? {
        switch viewType {
            case Type<FungibleTokenMetadataViews.FTDisplay>():
                return FungibleTokenMetadataViews.FTDisplay(
                    name: "US Dollar",
                    symbol: "USD",
                    description: "Token type representing the US Dollar. Cannot be held or traded.",
                    externalURL: MetadataViews.ExternalURL(""),
                    logos: MetadataViews.Medias([]),
                    socials: {}
                )
            case Type<FungibleTokenMetadataViews.TotalSupply>():
                /// No supply of this currency exists on-chain.
                return FungibleTokenMetadataViews.TotalSupply(totalSupply: 0.0)
        }
        return nil
    }
}
