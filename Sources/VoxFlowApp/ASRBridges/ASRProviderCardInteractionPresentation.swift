import Foundation

struct ASRProviderCardInteractionPresentation: Equatable {
    enum Region: Hashable {
        case icon
        case name
        case status
        case tags
        case blank
        case variantPicker
        case downloadButton
        case deleteButton
        case repairButton
        case externalLinks
    }

    enum CardTapBehavior: Equatable {
        case selectProvider
        case showUnavailableFeedback
        case ignore
    }

    let providerID: String
    let isSelectionEnabled: Bool
    let cardTapBehavior: CardTapBehavior
    let selectionPassthroughRegions: Set<Region>
    let controlOnlyRegions: Set<Region>

    var handlesCardTap: Bool {
        cardTapBehavior != .ignore
    }

    init(provider: ASRProviderDescriptor) {
        AppLogger.general.debug("Init ASRProviderCardInteractionPresentation providerID=\(provider.id)")
        providerID = provider.id
        isSelectionEnabled = provider.isAvailable && !provider.isDefault
        if provider.isDefault {
            cardTapBehavior = .ignore
        } else if provider.localModelAction == .download || provider.localModelAction == .resume || provider.localModelAction == .repair {
            cardTapBehavior = .ignore
        } else if provider.isAvailable {
            cardTapBehavior = .selectProvider
        } else {
            cardTapBehavior = .showUnavailableFeedback
        }
        selectionPassthroughRegions = [.icon, .name, .status, .tags, .blank]
        controlOnlyRegions = [.variantPicker, .downloadButton, .deleteButton, .repairButton, .externalLinks]
        AppLogger.general.debug(
            "ASRProviderCardInteractionPresentation initialized id=\(provider.id) selectionEnabled=\(isSelectionEnabled) tapBehavior=\(cardTapBehavior)"
        )
    }

    func isSelectionPassthroughRegion(_ region: Region) -> Bool {
        selectionPassthroughRegions.contains(region)
    }
}
