//
//  Match.swift
//  mahjong
//
//  A match is a set number of hands. The deal moves one seat on after every hand,
//  and each hand's payments are added to the players' scores. Highest score wins.
//

import Foundation

nonisolated enum GameLength: Int, CaseIterable, Sendable, Codable {
    /// Everyone deals once.
    case short = 4
    case standard = 8
    case long = 16

    var hands: Int { rawValue }

    var title: String {
        switch self {
        case .short: "Short"
        case .standard: "Standard"
        case .long: "Long"
        }
    }
}

nonisolated struct MatchSettings: Sendable, Codable {
    var length: GameLength = .standard
    /// Whether hands start with the Charleston.
    var charleston = true
}

nonisolated struct Match: Sendable, Codable {
    static let playerCount = 4

    let settings: MatchSettings
    let card: Card
    private(set) var scores = Array(repeating: 0, count: Match.playerCount)
    private(set) var dealer = 0
    private(set) var handsPlayed = 0
    /// Hands each player has won.
    private(set) var wins = Array(repeating: 0, count: Match.playerCount)

    init(settings: MatchSettings = MatchSettings(), card: Card) {
        self.settings = settings
        self.card = card
    }

    func dealRound(using generator: inout some RandomNumberGenerator) -> Round {
        Round.deal(card: card, dealer: dealer, charleston: settings.charleston, using: &generator)
    }

    /// Adds a finished hand to the totals and moves the deal on.
    @discardableResult
    mutating func record(_ round: Round) -> [Int] {
        let payments = round.payments()
        for player in scores.indices {
            scores[player] += payments[player]
        }
        if case .over(.mahjong(let win)) = round.phase {
            wins[win.winner] += 1
        }
        dealer = (dealer + 1) % Match.playerCount
        handsPlayed += 1
        return payments
    }

    var isOver: Bool { handsPlayed >= settings.length.hands }

    /// The player(s) with the highest score once the match is over, or an empty
    /// array while it is still going. More than one player means a tie.
    var winners: [Int] {
        guard isOver, let best = scores.max() else { return [] }
        return scores.indices.filter { scores[$0] == best }
    }
}
