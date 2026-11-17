//
//  Store.swift
//  mahjong
//
//  In-app purchases. Apple handles the payment; the app only learns what is owned.
//
//  - This year's card on its own.
//  - The full game: your history (and any later extras) plus this year's card.
//  - An upgrade to the full game for people who already bought this year's card.
//  - Optional tips.
//
//  Each year's card and full game are their own products, so buying one year never
//  gives you the next year's card. Past years' cards are free and need nothing.
//

import Foundation
import StoreKit
import UIKit

/// What is for sale and what is owned, worked out from product identifiers alone so
/// it can be tested without the App Store.
nonisolated enum StoreOffers {
    /// The full game's extras on their own, for people who own this year's card.
    static let upgradeID = "mahjong.upgrade"
    static let tipIDs = ["mahjong.tip.small", "mahjong.tip.medium", "mahjong.tip.large"]

    /// One year's card on its own.
    static func cardID(_ year: Int) -> String { "mahjong.card.\(year)" }
    /// One year's card together with the full game.
    static func fullGameID(_ year: Int) -> String { "mahjong.fullgame.\(year)" }

    /// The products that could be on sale while `year` is this year's card.
    static func productIDs(currentYear year: Int?) -> [String] {
        var ids = [upgradeID] + tipIDs
        if let year { ids += [cardID(year), fullGameID(year)] }
        return ids
    }

    /// History and other extras: bought on their own, or with any year's full game.
    static func hasFullGame(owned: Set<String>) -> Bool {
        owned.contains(upgradeID) || owned.contains { $0.hasPrefix("mahjong.fullgame.") }
    }

    static func ownsCard(_ year: Int, owned: Set<String>) -> Bool {
        owned.contains(cardID(year)) || owned.contains(fullGameID(year))
    }

    /// What to offer, best first, given what is owned. With no card for sale the full
    /// game is just the extras.
    static func offers(owned: Set<String>, currentYear year: Int?) -> [String] {
        let full = hasFullGame(owned: owned)
        guard let year else { return full ? [] : [upgradeID] }
        switch (ownsCard(year, owned: owned), full) {
        case (true, true): return []
        case (true, false): return [upgradeID]
        case (false, true): return [cardID(year)]
        case (false, false): return [fullGameID(year), cardID(year)]
        }
    }
}

final class Store {

    enum Outcome: Equatable {
        case success
        /// Waiting on something outside the app, such as Ask to Buy approval.
        case pending
        case cancelled
        case failed
    }

    private static let ownedKey = "ownedProducts"

    private let defaults: UserDefaults
    private var updates: Task<Void, Never>?

    /// The year of the card that is for sale: the newest League card in the app.
    let currentYear: Int?
    /// Products the App Store returned, by identifier.
    private(set) var products: [String: Product] = [:]
    /// Tip products, cheapest first.
    private(set) var tips: [Product] = []
    /// True once the product list has been requested, whether or not anything came back.
    private(set) var hasLoaded = false
    /// Identifiers of everything owned. Cached so the menu is right before the store answers.
    private(set) var owned: Set<String>

    #if DEBUG
    /// For screenshots and manual testing: pretend everything is or is not owned.
    var debugOverride: Bool?
    #endif

    /// What counts as owned: the real purchases, or everything or nothing when
    /// pretending for a test.
    private var effectiveOwned: Set<String> {
        #if DEBUG
        if let debugOverride {
            return debugOverride ? Set(StoreOffers.productIDs(currentYear: currentYear)) : []
        }
        #endif
        return owned
    }

    /// History and other full-game extras.
    var hasFullGame: Bool { StoreOffers.hasFullGame(owned: effectiveOwned) }

    func ownsCard(_ year: Int) -> Bool { StoreOffers.ownsCard(year, owned: effectiveOwned) }

    /// Nothing left to buy except tips.
    var ownsEverything: Bool {
        hasFullGame && (currentYear.map(ownsCard) ?? true)
    }

    /// What to offer now, best first, with prices when the App Store has answered.
    var offers: [(id: String, product: Product?)] {
        StoreOffers.offers(owned: effectiveOwned, currentYear: currentYear).map { ($0, products[$0]) }
    }

    /// Detail of the most recent failure, for the diagnostic line on the store screen.
    private(set) var lastProblem: String?
    private var lastOwnershipCheck = "not checked"

    /// One line describing what the store currently knows. Shown only on request.
    var diagnostics: String {
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "?"
        var parts = [
            "build \(build)",
            "products \(products.count)",
            "owned \(owned.sorted().joined(separator: ","))",
            lastOwnershipCheck,
        ]
        if let lastProblem { parts.append(lastProblem) }
        return parts.joined(separator: " · ")
    }

    /// Called whenever products or ownership change, so the screen can redraw.
    var onChange: (() -> Void)?

    init(currentYear: Int?, defaults: UserDefaults = .standard) {
        self.currentYear = currentYear
        self.defaults = defaults
        owned = Set(defaults.stringArray(forKey: Store.ownedKey) ?? [])
    }

    deinit {
        updates?.cancel()
    }

    /// Starts watching for purchases made elsewhere, then loads products and ownership.
    func start() {
        updates = Task { [weak self] in
            for await update in Transaction.updates {
                await self?.handle(update)
            }
        }
        Task { await refresh() }
    }

    func refresh() async {
        if let loaded = try? await Product.products(for: StoreOffers.productIDs(currentYear: currentYear)) {
            products = Dictionary(loaded.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
            tips = loaded.filter { StoreOffers.tipIDs.contains($0.id) }.sorted { $0.price < $1.price }
        }
        hasLoaded = true
        await refreshOwnership()
        onChange?()
    }

    /// Reads what the App Store says is owned. This is the source of truth.
    private func refreshOwnership() async {
        var found: Set<String> = []
        var seen = 0
        for await entitlement in Transaction.currentEntitlements {
            seen += 1
            if let id = ownedID(entitlement) { found.insert(id) }
        }
        lastOwnershipCheck = "entitlements \(seen)"
        setOwned(found)
    }

    /// The product a live, verified purchase is for.
    private func ownedID(_ result: VerificationResult<Transaction>) -> String? {
        switch result {
        case .verified(let transaction):
            return transaction.revocationDate == nil ? transaction.productID : nil
        case .unverified(_, let error):
            lastProblem = "unverified: \(error)"
            return nil
        }
    }

    /// Buys a product. Pass the window's scene so the App Store knows where to
    /// show its payment sheet; without it the sheet can fail to appear.
    func buy(_ product: Product, in scene: UIScene? = nil) async -> Outcome {
        lastProblem = nil
        do {
            let result: Product.PurchaseResult
            if #available(iOS 17.0, *), let scene {
                result = try await product.purchase(confirmIn: scene)
            } else {
                result = try await product.purchase()
            }
            switch result {
            case .success(let verification):
                switch verification {
                case .verified(let transaction):
                    if !StoreOffers.tipIDs.contains(transaction.productID) {
                        setOwned(owned.union([transaction.productID]))
                    }
                    await transaction.finish()
                    onChange?()
                    return .success
                case .unverified(_, let error):
                    lastProblem = "unverified: \(error)"
                    onChange?()
                    return .failed
                }
            case .pending:
                lastProblem = "pending"
                return .pending
            case .userCancelled:
                lastProblem = "cancelled"
                return .cancelled
            @unknown default:
                lastProblem = "unknown purchase result"
                return .failed
            }
        } catch {
            lastProblem = "error: \(error)"
            return .failed
        }
    }

    /// Asks the App Store to re-send past purchases, for a new or restored device.
    /// Returns whether anything is owned afterwards.
    func restore() async -> Bool {
        try? await AppStore.sync()
        await refreshOwnership()
        onChange?()
        return !owned.isEmpty
    }

    /// Shows Apple's sheet for typing in an offer code. A redeemed code arrives as
    /// an ordinary purchase, so it shows up in the usual ownership check.
    func redeemCode(in scene: UIWindowScene) async -> Bool {
        lastProblem = nil
        let before = owned
        do {
            try await AppStore.presentOfferCodeRedeemSheet(in: scene)
        } catch {
            lastProblem = "redeem error: \(error)"
            onChange?()
            return false
        }
        await refreshOwnership()
        onChange?()
        return owned != before
    }

    private func handle(_ update: VerificationResult<Transaction>) async {
        guard case .verified(let transaction) = update else { return }
        if !StoreOffers.tipIDs.contains(transaction.productID) {
            if transaction.revocationDate == nil {
                setOwned(owned.union([transaction.productID]))
            } else {
                setOwned(owned.subtracting([transaction.productID]))
            }
        }
        await transaction.finish()
        onChange?()
    }

    private func setOwned(_ value: Set<String>) {
        owned = value
        defaults.set(value.sorted(), forKey: Store.ownedKey)
    }
}
