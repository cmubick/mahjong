//
//  Round.swift
//  mahjong
//
//  One hand of American mahjong, from the deal until someone calls Mahjong or the
//  wall runs out. Players are numbered in turn order: play passes from 0 to 1 to 2
//  to 3, so a player's "right" is the next player and their "left" the one before.
//

import Foundation

nonisolated enum RuleError: Error, Equatable {
    case illegalMove
}

/// The passes of the Charleston, in order. The first three always happen; the next
/// three only if everyone agrees.
nonisolated enum CharlestonPass: Int, CaseIterable, Sendable, Codable {
    case firstRight, firstAcross, firstLeft, secondLeft, secondAcross, secondRight

    /// How many seats on in turn order the tiles go: 1 is right, 2 across, 3 left.
    var offset: Int {
        switch self {
        case .firstRight, .secondRight: 1
        case .firstAcross, .secondAcross: 2
        case .firstLeft, .secondLeft: 3
        }
    }

    var direction: String {
        switch offset {
        case 1: "right"
        case 2: "across"
        default: "left"
        }
    }
}

nonisolated struct Round: Sendable, Codable {

    static let passSize = 3
    static let maxCourtesy = 3

    struct Discard: Hashable, Sendable, Codable {
        let tile: Tile
        let player: Int
    }

    struct Win: Hashable, Sendable, Codable {
        let winner: Int
        /// The hand on the card, by `Hand.id`.
        let hand: Int
        /// True when the winning tile came from the wall (or the dealer's opening hand).
        let selfDrawn: Bool
        /// Who threw the winning tile, when it was a discard.
        let discarder: Int?
        let jokerless: Bool
    }

    enum Outcome: Hashable, Sendable, Codable {
        case mahjong(Win)
        /// The wall ran out with no winner.
        case wallGame
    }

    enum Phase: Hashable, Sendable, Codable {
        /// Everyone passes three tiles at once.
        case charleston(CharlestonPass)
        /// Everyone says whether to do the second Charleston. Any "no" stops it.
        case vote
        /// Everyone says how many tiles (0 to 3) they would swap with the player across.
        case courtesyOffer
        /// Players swap the agreed number of tiles across.
        case courtesyPass
        /// The player must discard, or call Mahjong, or swap tiles for jokers first.
        case discard(Int)
        /// The other players may call the latest discard. The window stays open until
        /// someone calls it or the next player draws.
        case claim(Discard)
        case over(Outcome)
    }

    enum Move: Hashable, Sendable, Codable {
        /// Charleston or courtesy pass.
        case pass([Tile])
        /// For or against the second Charleston.
        case vote(Bool)
        /// How many tiles to swap in the courtesy pass.
        case offer(Int)
        case discard(Tile)
        /// Give the real tile for a joker in `owner`'s exposure number `exposure`.
        case swapJoker(owner: Int, exposure: Int)
        /// Take the discard and expose a group of `count` of it.
        case call(count: Int)
        /// Win with the tiles in hand, or with the discard during a claim.
        case mahjong
        /// Let the discard go.
        case decline
        /// The next player draws from the wall, which closes the call window. Only
        /// once everyone else has let the discard go.
        case draw
    }

    let card: Card
    let dealer: Int
    /// Each player's concealed tiles.
    private(set) var hands: [[Tile]]
    /// Each player's exposed groups, in the order they were called.
    private(set) var exposures: [[Exposure]]
    /// Discards lying in the middle of the table. Called discards are taken back out.
    private(set) var discards: [Discard] = []
    /// The tiles still to be drawn, next one first.
    private(set) var wall: [Tile]
    private(set) var phase: Phase
    /// Moves made so far in a phase where several players act at once.
    private(set) var answers: [Int: Move] = [:]
    /// Tiles each player swaps in the courtesy pass.
    private(set) var courtesyCounts = [0, 0, 0, 0]
    /// The tile the player in the discard phase just drew, or nil if they called a discard.
    private(set) var drawn: Tile?
    /// Whose discard the player in the discard phase called, if they called one.
    private(set) var calledFrom: Int?

    var playerCount: Int { hands.count }

    init(
        card: Card,
        dealer: Int,
        hands: [[Tile]],
        exposures: [[Exposure]]? = nil,
        wall: [Tile],
        phase: Phase? = nil
    ) {
        self.card = card
        self.dealer = dealer
        self.hands = hands
        self.exposures = exposures ?? Array(repeating: [], count: hands.count)
        self.wall = wall
        self.phase = phase ?? .charleston(.firstRight)
    }

    /// Shuffles the set and deals 13 tiles each, 14 to the dealer (East).
    static func deal(
        card: Card,
        dealer: Int = 0,
        charleston: Bool = true,
        using generator: inout some RandomNumberGenerator
    ) -> Round {
        var wall = Tile.fullSet.seededShuffle(using: &generator)
        var hands = Array(repeating: [Tile](), count: 4)
        for offset in 0..<4 {
            let player = (dealer + offset) % 4
            let size = player == dealer ? 14 : 13
            hands[player] = Array(wall.prefix(size)).sorted()
            wall.removeFirst(size)
        }
        return Round(
            card: card, dealer: dealer, hands: hands, wall: wall,
            phase: charleston ? .charleston(.firstRight) : .discard(dealer)
        )
    }

    // MARK: - Seats

    func nextPlayer(after player: Int) -> Int { (player + 1) % playerCount }

    func across(from player: Int) -> Int { (player + 2) % playerCount }

    /// The wind each player sits at this hand. The dealer is East and play goes East,
    /// South, West, North.
    func seatWind(of player: Int) -> Wind {
        [.east, .south, .west, .north][(player - dealer + playerCount) % playerCount]
    }

    // MARK: - Whose move

    /// The players who still have to act. Several can act at once in the Charleston
    /// and when a discard can be called.
    var actors: [Int] {
        let everyone = Array(0..<playerCount)
        switch phase {
        case .charleston, .vote, .courtesyOffer:
            return everyone.filter { answers[$0] == nil }
        case .courtesyPass:
            return everyone.filter { courtesyCounts[$0] > 0 && answers[$0] == nil }
        case .discard(let player):
            return [player]
        case .claim(let discard):
            let undecided = everyone.filter { $0 != discard.player && answers[$0] == nil }
            if undecided.isEmpty && isWaitingForDraw {
                return [nextPlayer(after: discard.player)]
            }
            return undecided
        case .over:
            return []
        }
    }

    /// Everyone has let the discard go, so it stays callable only until the next
    /// player draws.
    var isWaitingForDraw: Bool {
        guard case .claim(let discard) = phase else { return false }
        let others = (0..<playerCount).filter { $0 != discard.player }
        return others.allSatisfy { answers[$0] == .decline }
    }

    var outcome: Outcome? {
        if case .over(let outcome) = phase { return outcome }
        return nil
    }

    // MARK: - Legal moves

    /// The moves `player` may make. Passes are not listed, since any tiles will do:
    /// check one with `isLegal`.
    func legalMoves(for player: Int) -> [Move] {
        guard actors.contains(player) else { return [] }
        switch phase {
        case .charleston, .courtesyPass, .over:
            return []
        case .vote:
            return [.vote(true), .vote(false)]
        case .courtesyOffer:
            return (0...Round.maxCourtesy).map(Move.offer)
        case .discard:
            var moves: [Move] = []
            if !card.completedHands(concealed: hands[player], exposures: exposures[player]).isEmpty {
                moves.append(.mahjong)
            }
            moves += jokerSwaps(for: player)
            moves += Set(hands[player]).sorted().map(Move.discard)
            return moves
        case .claim(let discard):
            if isWaitingForDraw { return [.draw] }
            var moves: [Move] = []
            if canWin(player, with: discard.tile) {
                moves.append(.mahjong)
            }
            moves += callCounts(for: player, tile: discard.tile).map { Move.call(count: $0) }
            moves.append(.decline)
            return moves
        }
    }

    func isLegal(_ move: Move, by player: Int) -> Bool {
        guard actors.contains(player) else { return false }
        switch (phase, move) {
        case (.charleston, .pass(let tiles)):
            return tiles.count == Round.passSize && canPass(tiles, from: player)
        case (.courtesyPass, .pass(let tiles)):
            return tiles.count == courtesyCounts[player] && canPass(tiles, from: player)
        default:
            return legalMoves(for: player).contains(move)
        }
    }

    /// Jokers may never be passed.
    private func canPass(_ tiles: [Tile], from player: Int) -> Bool {
        guard !tiles.contains(.joker) else { return false }
        var hand = TileCounts(hands[player])
        for tile in tiles {
            guard hand[tile] > 0 else { return false }
            hand[tile] -= 1
        }
        return true
    }

    private func jokerSwaps(for player: Int) -> [Move] {
        let held = Set(hands[player])
        var moves: [Move] = []
        for owner in 0..<playerCount {
            for (index, exposure) in exposures[owner].enumerated()
            where exposure.jokers > 0 && held.contains(exposure.tile) {
                moves.append(.swapJoker(owner: owner, exposure: index))
            }
        }
        return moves
    }

    /// Whether `tile` completes the player's hand.
    func canWin(_ player: Int, with tile: Tile) -> Bool {
        guard tile != .joker else { return false }
        return !card.completedHands(concealed: hands[player] + [tile], exposures: exposures[player]).isEmpty
    }

    /// The sizes of group the player could expose by calling `tile`. A discard can only
    /// be called for a group of three or more that still fits a hand on the card; the
    /// card decides which sizes exist.
    func callCounts(for player: Int, tile: Tile) -> [Int] {
        guard tile != .joker else { return [] }
        let hand = TileCounts(hands[player])
        return (3...Card.handSize).filter { count in
            guard hand[tile] + hand.jokers >= count - 1 else { return false }
            let exposure = Round.exposure(of: tile, count: count, from: hand)
            return card.allowsExposures(exposures[player] + [exposure])
        }
    }

    /// The group made by calling `tile` for `count`, using real tiles before jokers.
    static func exposure(of tile: Tile, count: Int, from hand: TileCounts) -> Exposure {
        let real = min(hand[tile], count - 1)
        return Exposure(tile: tile, count: count, jokers: count - 1 - real)
    }

    // MARK: - Playing

    mutating func apply(_ move: Move, by player: Int) throws {
        guard isLegal(move, by: player) else { throw RuleError.illegalMove }

        switch (phase, move) {
        case (.charleston(let pass), .pass):
            answers[player] = move
            if answers.count == playerCount {
                exchangePasses(offset: pass.offset)
                switch pass {
                case .firstLeft: phase = .vote
                case .secondRight: phase = .courtesyOffer
                default: phase = .charleston(CharlestonPass(rawValue: pass.rawValue + 1)!)
                }
            }

        case (.vote, .vote):
            answers[player] = move
            if answers.count == playerCount {
                let everyoneAgrees = answers.values.allSatisfy { $0 == .vote(true) }
                answers = [:]
                phase = everyoneAgrees ? .charleston(.secondLeft) : .courtesyOffer
            }

        case (.courtesyOffer, .offer):
            answers[player] = move
            if answers.count == playerCount {
                let offers = (0..<playerCount).map { seat -> Int in
                    if case .offer(let count) = answers[seat] { return count }
                    return 0
                }
                courtesyCounts = (0..<playerCount).map { min(offers[$0], offers[across(from: $0)]) }
                answers = [:]
                if courtesyCounts.allSatisfy({ $0 == 0 }) {
                    startPlay()
                } else {
                    phase = .courtesyPass
                }
            }

        case (.courtesyPass, .pass):
            answers[player] = move
            if actors.isEmpty {
                exchangePasses(offset: 2)
                startPlay()
            }

        case (.discard, .discard(let tile)):
            remove(tile, from: player)
            let discard = Discard(tile: tile, player: player)
            discards.append(discard)
            drawn = nil
            calledFrom = nil
            phase = .claim(discard)
            answers = [:]
            declineForPlayersWithNoChoice()

        case (.discard, .swapJoker(let owner, let index)):
            let tile = exposures[owner][index].tile
            remove(tile, from: player)
            hands[player].append(.joker)
            hands[player].sort()
            exposures[owner][index].jokers -= 1

        case (.discard, .mahjong):
            declareWin(
                for: player,
                selfDrawn: calledFrom == nil,
                discarder: calledFrom
            )

        case (.claim, .mahjong), (.claim, .call), (.claim, .decline):
            answers[player] = move
            declineForPlayersWithNoChoice()

        case (.claim(let discard), .draw):
            resolveClaims(for: discard)

        default:
            throw RuleError.illegalMove
        }
    }

    private mutating func remove(_ tile: Tile, from player: Int) {
        guard let index = hands[player].firstIndex(of: tile) else { return }
        hands[player].remove(at: index)
    }

    /// Everyone's chosen tiles move `offset` seats on, all at once.
    private mutating func exchangePasses(offset: Int) {
        var incoming = Array(repeating: [Tile](), count: playerCount)
        for (player, move) in answers {
            guard case .pass(let tiles) = move else { continue }
            for tile in tiles {
                remove(tile, from: player)
            }
            incoming[(player + offset) % playerCount] = tiles
        }
        for player in 0..<playerCount {
            hands[player] = (hands[player] + incoming[player]).sorted()
        }
        answers = [:]
    }

    private mutating func startPlay() {
        answers = [:]
        drawn = nil
        calledFrom = nil
        phase = .discard(dealer)
    }

    /// Players who can do nothing with a discard let it go straight away, so nobody
    /// waits on them. Once everyone has answered, a call or Mahjong takes the tile at
    /// once; if everyone let it go, it waits for the next player's draw.
    private mutating func declineForPlayersWithNoChoice() {
        guard case .claim(let discard) = phase, !isWaitingForDraw else { return }
        for player in actors where legalMoves(for: player) == [.decline] {
            answers[player] = .decline
        }
        if actors.isEmpty {
            resolveClaims(for: discard)
        }
    }

    /// Once everyone has answered: Mahjong beats any other call, and between equal
    /// calls the player next in turn after the discarder gets the tile.
    private mutating func resolveClaims(for discard: Discard) {
        let order = (1..<playerCount).map { (discard.player + $0) % playerCount }
        let claims = answers
        answers = [:]

        if let winner = order.first(where: { claims[$0] == .mahjong }) {
            discards.removeLast()
            hands[winner].append(discard.tile)
            hands[winner].sort()
            declareWin(for: winner, selfDrawn: false, discarder: discard.player)
            return
        }

        for caller in order {
            guard case .call(let count) = claims[caller] else { continue }
            discards.removeLast()
            let exposure = Round.exposure(of: discard.tile, count: count, from: TileCounts(hands[caller]))
            for _ in 0..<(count - 1 - exposure.jokers) {
                remove(discard.tile, from: caller)
            }
            for _ in 0..<exposure.jokers {
                remove(.joker, from: caller)
            }
            exposures[caller].append(exposure)
            drawn = nil
            calledFrom = discard.player
            phase = .discard(caller)
            return
        }

        let next = nextPlayer(after: discard.player)
        guard !wall.isEmpty else {
            phase = .over(.wallGame)
            return
        }
        let tile = wall.removeFirst()
        hands[next].append(tile)
        hands[next].sort()
        drawn = tile
        calledFrom = nil
        phase = .discard(next)
    }

    private mutating func declareWin(for player: Int, selfDrawn: Bool, discarder: Int?) {
        let ways = card.completedHands(concealed: hands[player], exposures: exposures[player])
        guard let best = ways.first else { return }
        let usedJokers = hands[player].contains(.joker) || exposures[player].contains { $0.jokers > 0 }
        let jokerless = !usedJokers && card.hands[best.hand].jokersAllowed
        let win = Win(
            winner: player, hand: best.hand, selfDrawn: selfDrawn,
            discarder: discarder, jokerless: jokerless
        )
        phase = .over(.mahjong(win))
    }

    // MARK: - Scoring

    /// What each player wins (positive) or pays (negative) for this hand.
    ///
    /// The winner is paid the hand's value by everyone, doubled for a jokerless hand.
    /// Whoever threw the winning discard pays double; if the winner drew the tile from
    /// the wall, everyone pays double.
    func payments() -> [Int] {
        var result = Array(repeating: 0, count: playerCount)
        guard case .over(.mahjong(let win)) = phase else { return result }
        let value = card.hands[win.hand].value * (win.jokerless ? 2 : 1)
        for player in 0..<playerCount where player != win.winner {
            let pays = win.selfDrawn || player == win.discarder ? value * 2 : value
            result[player] -= pays
            result[win.winner] += pays
        }
        return result
    }

    // MARK: - Counting

    /// Every tile in the round, wherever it is. Always the full set of 152.
    var allTiles: [Tile] {
        hands.flatMap { $0 }
            + exposures.flatMap { $0.flatMap(\.tiles) }
            + discards.map(\.tile)
            + wall
    }
}
