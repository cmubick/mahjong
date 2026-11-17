//
//  Scorepad.swift
//  mahjong
//
//  Every hand is a game of its own. The scorepad keeps the running tally across
//  hands, the way a group keeps one on paper, until it is cleared. The deal moves
//  one seat on after every hand.
//

import Foundation

nonisolated struct Scorepad: Sendable, Codable {
    static let playerCount = 4

    private(set) var scores = Array(repeating: 0, count: Scorepad.playerCount)
    /// Who deals the next hand. Moves on after every hand, and is kept when the pad is cleared.
    private(set) var dealer = 0
    private(set) var handsPlayed = 0
    /// Hands each player has won since the pad was cleared.
    private(set) var wins = Array(repeating: 0, count: Scorepad.playerCount)
    /// When the pad was started or last cleared.
    private(set) var started: Date

    init(started: Date = Date()) {
        self.started = started
    }

    func deal(card: Card, charleston: Bool, using generator: inout some RandomNumberGenerator) -> Round {
        Round.deal(card: card, dealer: dealer, charleston: charleston, using: &generator)
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
        dealer = (dealer + 1) % Scorepad.playerCount
        handsPlayed += 1
        return payments
    }

    /// A fresh sheet: scores and wins back to zero. The deal carries on from where it was.
    mutating func clear(at date: Date = Date()) {
        scores = Array(repeating: 0, count: Scorepad.playerCount)
        wins = Array(repeating: 0, count: Scorepad.playerCount)
        handsPlayed = 0
        started = date
    }
}
