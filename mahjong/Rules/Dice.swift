//
//  Dice.swift
//  mahjong
//
//  Rolling two dice: to choose East at the start of a scorepad, and for East to
//  break the wall at the start of each hand.
//

import Foundation

nonisolated enum Dice {
    /// Two dice.
    static func roll(using generator: inout some RandomNumberGenerator) -> (Int, Int) {
        (Int.random(in: 1...6, using: &generator), Int.random(in: 1...6, using: &generator))
    }

    /// Everyone rolls; the highest total is East. If two or more tie for highest,
    /// everyone rolls again, so the rolls returned are one round with a clear winner.
    static func rollForEast(players: Int = 4, using generator: inout some RandomNumberGenerator)
        -> (rolls: [(Int, Int)], winner: Int, rerolled: Bool) {
        var rerolled = false
        while true {
            let rolls = (0..<players).map { _ in roll(using: &generator) }
            let totals = rolls.map { $0.0 + $0.1 }
            let best = totals.max()!
            let top = totals.indices.filter { totals[$0] == best }
            if top.count == 1 { return (rolls, top[0], rerolled) }
            rerolled = true
        }
    }

    /// The wall is 76 stacks of two tiles, numbered clockwise around the table, each
    /// player's wall starting at its right-hand end. East rolls and counts that many
    /// stacks from the right of their own wall; dealing starts there.
    static let stacks = 76
    static let stacksPerSide = 19

    /// Where a player's wall starts. Seats: 0 you (bottom), 1 right, 2 across, 3 left.
    static func wallStart(of player: Int) -> Int {
        [0, 3 * stacksPerSide, 2 * stacksPerSide, stacksPerSide][player % 4]
    }

    static func breakPoint(dealer: Int, total: Int) -> Int {
        (wallStart(of: dealer) + total) % stacks
    }
}
