//
//  Bot.swift
//  mahjong
//
//  A computer player. It only looks at its own tiles, its own exposures and the card:
//  it keeps the tiles that bring it closest to some hand and lets the rest go.
//

import Foundation

nonisolated enum Bot {

    /// How many of the closest ways to make a hand the bot keeps in mind.
    private static let focus = 40

    /// Picks a move for `player`, or nil if they have nothing to do right now.
    static func chooseMove(in round: Round, for player: Int) -> Round.Move? {
        guard round.actors.contains(player) else { return nil }
        let hand = round.hands[player]
        let exposures = round.exposures[player]
        let card = round.card

        switch round.phase {
        case .over:
            return nil

        case .charleston:
            return .pass(worstTiles(Round.passSize, of: hand, exposures: exposures, card: card))

        case .vote:
            // Keep passing while the hand is still a long way off.
            let needed = closest(TileCounts(hand), exposures: exposures, card: card).first?.needed ?? 99
            return .vote(needed >= 5)

        case .courtesyOffer:
            let ways = closest(TileCounts(hand), exposures: exposures, card: card)
            guard let best = ways.first, best.needed > 3 else { return .offer(0) }
            let wanted = Set(ways.prefix(10).flatMap { $0.instance.groups.map(\.tile) })
            let spare = hand.filter { $0 != .joker && !wanted.contains($0) }.count
            return .offer(min(spare, Round.maxCourtesy))

        case .courtesyPass:
            let count = round.courtesyCounts[player]
            return .pass(worstTiles(count, of: hand, exposures: exposures, card: card))

        case .discard:
            let moves = round.legalMoves(for: player)
            if moves.contains(.mahjong) { return .mahjong }

            // Trade a real tile for an exposed joker whenever that is no worse.
            let current = score(TileCounts(hand), exposures: exposures, card: card)
            for move in moves {
                guard case .swapJoker(let owner, let index) = move else { continue }
                var swapped = TileCounts(hand)
                swapped[round.exposures[owner][index].tile] -= 1
                swapped[.joker] += 1
                if score(swapped, exposures: exposures, card: card) >= current {
                    return move
                }
            }
            let tile = worstTiles(1, of: hand, exposures: exposures, card: card, allowJokers: true).first
            return tile.map(Round.Move.discard) ?? moves.last

        case .claim(let discard):
            let moves = round.legalMoves(for: player)
            if moves == [.draw] { return .draw }
            if moves.contains(.mahjong) { return .mahjong }

            let neededNow = closest(TileCounts(hand), exposures: exposures, card: card).first?.needed ?? 99
            var bestCall: (move: Round.Move, needed: Int)?
            for move in moves {
                guard case .call(let count) = move else { continue }
                var counts = TileCounts(hand)
                let exposure = Round.exposure(of: discard.tile, count: count, from: counts)
                counts[discard.tile] -= count - 1 - exposure.jokers
                counts[.joker] -= exposure.jokers
                let needed = closest(counts, exposures: exposures + [exposure], card: card).first?.needed ?? 99
                if needed < neededNow && needed < (bestCall?.needed ?? 99) {
                    bestCall = (move, needed)
                }
            }
            return bestCall?.move ?? .decline
        }
    }

    // MARK: - Judging a set of tiles

    struct Way {
        let instance: HandInstance
        let needed: Int
        let value: Int
    }

    /// The ways to make a hand that need the fewest more tiles, closest first.
    static func closest(_ tiles: TileCounts, exposures: [Exposure], card: Card) -> [Way] {
        card.instances
            .compactMap { instance -> Way? in
                guard let needed = instance.tilesNeeded(concealed: tiles, exposures: exposures) else {
                    return nil
                }
                return Way(instance: instance, needed: needed, value: card.hands[instance.hand].value)
            }
            .sorted { ($0.needed, -$0.value) < ($1.needed, -$1.value) }
            .prefix(focus)
            .map { $0 }
    }

    /// Higher is better. Mostly how close the nearest hand is; then how many other
    /// hands are nearly as close, so the bot keeps its options open; then value.
    static func score(_ tiles: TileCounts, exposures: [Exposure], card: Card, among ways: [Way]? = nil) -> Double {
        let ways = (ways ?? closest(tiles, exposures: exposures, card: card)).compactMap { way -> Way? in
            guard let needed = way.instance.tilesNeeded(concealed: tiles, exposures: exposures) else { return nil }
            return Way(instance: way.instance, needed: needed, value: way.value)
        }
        guard let best = ways.map(\.needed).min() else { return -1000 }
        let nearlyAsGood = ways.filter { $0.needed <= best + 1 }
        let value = nearlyAsGood.filter { $0.needed == best }.map(\.value).max() ?? 0
        return Double(-best) * 10 + log2(Double(1 + nearlyAsGood.count)) + Double(value) / 100
    }

    /// The `count` tiles the hand can best spare, chosen one at a time.
    static func worstTiles(
        _ count: Int,
        of hand: [Tile],
        exposures: [Exposure],
        card: Card,
        allowJokers: Bool = false
    ) -> [Tile] {
        var tiles = TileCounts(hand)
        let ways = closest(tiles, exposures: exposures, card: card)
        var chosen: [Tile] = []
        for _ in 0..<count {
            var best: (tile: Tile, score: Double)?
            for tile in Set(hand).sorted() where tiles[tile] > 0 {
                if tile == .joker && !allowJokers { continue }
                var without = tiles
                without[tile] -= 1
                // A joker is never wasted lightly.
                let penalty = tile == .joker ? 5.0 : 0
                let result = score(without, exposures: exposures, card: card, among: ways) - penalty
                if best == nil || result > best!.score {
                    best = (tile, result)
                }
            }
            guard let pick = best?.tile else { break }
            chosen.append(pick)
            tiles[pick] -= 1
        }
        return chosen
    }
}
