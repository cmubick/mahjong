//
//  mahjongTests.swift
//  mahjongTests
//

import Foundation
import Testing
@testable import mahjong

private func n(_ suit: Suit, _ rank: Int) -> Tile { .number(suit, rank) }

/// The tiles that make `instance`, with no jokers.
private func tiles(of instance: HandInstance) -> [Tile] {
    instance.groups.flatMap { Array(repeating: $0.tile, count: $0.count) }.sorted()
}

private func firstInstance(of handText: String, in card: Card = .practice) -> HandInstance {
    let hand = card.hands.first { $0.text == handText }!
    return card.instances.first { $0.hand == hand.id }!
}

/// A tiny card for tests where the full practice card would get in the way.
private let testCard = try! Card(text: """
    id: test
    section: Test
    X 25 1111/A 222/A 333/A 4444/A ; a run
    C 50 NN EE WW SS RR GG 00
    """)

/// Lets the bots play every seat until the round ends, checking that no tile is
/// ever lost or made up along the way.
private func playOut(_ round: inout Round, limit: Int = 3000) throws {
    var moves = 0
    while round.outcome == nil {
        let actor = try #require(round.actors.first)
        let move = try #require(Bot.chooseMove(in: round, for: actor))
        try round.apply(move, by: actor)
        moves += 1
        #expect(round.allTiles.sorted() == Tile.fullSet)
        if moves > limit {
            Issue.record("round did not finish")
            return
        }
    }
}

struct TileTests {

    @Test func fullSetHas152Tiles() {
        let set = Tile.fullSet
        #expect(set.count == 152)
        #expect(set.filter { $0 == .joker }.count == 8)
        #expect(set.filter { $0 == .flower }.count == 8)
        #expect(set.filter { $0 == n(.dots, 5) }.count == 4)
        #expect(set.filter { if case .wind = $0 { true } else { false } }.count == 16)
        #expect(set.filter { if case .dragon = $0 { true } else { false } }.count == 12)
    }

    @Test func indexRoundTrips() {
        for index in 0..<Tile.kindCount {
            #expect(Tile(index: index).index == index)
        }
    }

    @Test func dragonsBelongToSuits() {
        #expect(Suit.bams.dragon == .green)
        #expect(Suit.craks.dragon == .red)
        #expect(Suit.dots.dragon == .white)
    }

    @Test func seededShuffleRepeats() {
        var first = SeededGenerator(seed: 42)
        var second = SeededGenerator(seed: 42)
        #expect(Tile.fullSet.seededShuffle(using: &first) == Tile.fullSet.seededShuffle(using: &second))
    }
}

struct CardTests {

    @Test func practiceCardReads() {
        let card = Card.practice
        #expect(card.id == "practice")
        #expect(card.year == 2026)
        #expect(card.hands.count == 31)
        #expect(card.sections.count == 9)
        for hand in card.hands {
            #expect(hand.tileCount == 14)
            #expect(card.instances.contains { $0.hand == hand.id }, "no way to make \(hand.text)")
        }
    }

    @Test func everyInstanceIsCompleteWithItsOwnTiles() {
        let card = Card.practice
        for instance in card.instances {
            let needed = instance.tilesNeeded(concealed: TileCounts(tiles(of: instance)), exposures: [])
            #expect(needed == 0)
        }
    }

    @Test func yearUsesSoapAsZero() {
        let instance = firstInstance(of: "NN 2026/A EEE WWW SS")
        #expect(tiles(of: instance).filter { $0 == .soap }.count == 1)
    }

    @Test func suitLettersMeanDifferentSuits() {
        let hand = Card.practice.hands.first { $0.text == "FFF 3333/A 666/B 9999/C" }!
        let instances = Card.practice.instances.filter { $0.hand == hand.id }
        #expect(instances.count == 6)
        for instance in instances {
            let suits = Set(instance.groups.compactMap { group -> Suit? in
                if case .number(let suit, _) = group.tile { return suit }
                return nil
            })
            #expect(suits.count == 3)
        }
    }

    @Test func runsTryEveryStartingNumber() {
        let hand = Card.practice.hands.first { $0.text == "aaa/A bbbb/A ccc/A dddd/A" }!
        // Three suits, starting at 1 through 6.
        #expect(Card.practice.instances.filter { $0.hand == hand.id }.count == 18)
    }

    @Test func suitDragonFollowsTheSuit() {
        let instance = firstInstance(of: "FFF 44/A 666/A DDDD/A 88/A")
        guard case .number(let suit, _) = instance.groups[1].tile else {
            Issue.record("expected a number")
            return
        }
        #expect(instance.groups[3].tile == .dragon(suit.dragon))
    }

    @Test func badCardsAreRefused() {
        #expect(throws: CardError.self) { try Card(text: "id: x\nsection: S\nX 25 111/A 222/A") }
        #expect(throws: CardError.self) { try Card(text: "id: x\nsection: S\nX 25 1111/A 2222/A 3333 44/A") }
        #expect(throws: CardError.self) { try Card(text: "id: x\nsection: S\nX 25 NNNN/A EEEE WWWW SS") }
        #expect(throws: CardError.self) { try Card(text: "id: x\nsection: S\nQ 25 NNNN EEEE WWWW SS") }
        #expect(throws: CardError.self) { try Card(text: "section: S\nX 25 NNNN EEEE WWWW SS") }
    }

    @Test func cardSavesAsItsText() throws {
        let data = try JSONEncoder().encode(testCard)
        let card = try JSONDecoder().decode(Card.self, from: data)
        #expect(card.hands.count == 2)
        #expect(card.instances.count == testCard.instances.count)
    }
}

struct MatchingTests {

    let run = firstInstance(of: "1111/A 222/A 333/A 4444/A", in: testCard)

    @Test func jokersFillPungsAndKongs() {
        var hand = tiles(of: run)
        hand.remove(at: hand.firstIndex(of: hand[0])!)
        hand.append(.joker)
        #expect(run.tilesNeeded(concealed: TileCounts(hand), exposures: []) == 0)
    }

    @Test func jokersCannotFillSinglesOrPairs() {
        let pairs = testCard.instances.first { $0.concealed }!
        var hand = tiles(of: pairs)
        hand.remove(at: hand.firstIndex(of: .wind(.north))!)
        hand.append(.joker)
        #expect(pairs.tilesNeeded(concealed: TileCounts(hand), exposures: []) == 1)
    }

    @Test func countsMissingTiles() {
        var hand = tiles(of: run)
        hand.removeLast(3)
        hand += [.flower, .flower, .flower]
        #expect(run.tilesNeeded(concealed: TileCounts(hand), exposures: []) == 3)
    }

    @Test func exposuresMustMatchAGroup() {
        let suit: Suit
        if case .number(let first, _) = run.groups[0].tile { suit = first } else { return }
        let good = Exposure(tile: n(suit, 2), count: 3, jokers: 1)
        let wrongSize = Exposure(tile: n(suit, 2), count: 4, jokers: 0)
        let concealed = tiles(of: run).filter { $0 != n(suit, 2) }
        #expect(run.tilesNeeded(concealed: TileCounts(concealed), exposures: [good]) == 0)
        #expect(run.tilesNeeded(concealed: TileCounts(concealed), exposures: [wrongSize]) == nil)
    }

    @Test func concealedHandsAllowNoExposures() {
        let pairs = testCard.instances.first { $0.concealed }!
        let exposure = Exposure(tile: .wind(.north), count: 3, jokers: 0)
        #expect(pairs.tilesNeeded(concealed: TileCounts(), exposures: [exposure]) == nil)
        #expect(!testCard.allowsExposures([Exposure(tile: .wind(.north), count: 3, jokers: 0)]))
        #expect(testCard.allowsExposures([Exposure(tile: n(.dots, 4), count: 4, jokers: 2)]))
    }
}

struct RoundTests {

    @Test func dealGivesTheDealerFourteen() {
        var generator = SeededGenerator(seed: 7)
        let round = Round.deal(card: .practice, dealer: 2, using: &generator)
        #expect(round.hands.map(\.count) == [13, 13, 14, 13])
        #expect(round.wall.count == 152 - 53)
        #expect(round.allTiles.sorted() == Tile.fullSet)
        #expect(round.phase == .charleston(.firstRight))
        #expect(round.seatWind(of: 2) == .east)
        #expect(round.seatWind(of: 3) == .south)
    }

    @Test func charlestonPassesGoRightAcrossLeft() throws {
        var generator = SeededGenerator(seed: 3)
        var round = Round.deal(card: .practice, using: &generator)
        func firstThree(_ player: Int) -> [Tile] {
            Array(round.hands[player].filter { $0 != .joker }.prefix(3))
        }

        let passed = firstThree(0)
        for player in 0..<4 {
            try round.apply(.pass(firstThree(player)), by: player)
            if player < 3 { #expect(round.phase == .charleston(.firstRight)) }
        }
        #expect(round.phase == .charleston(.firstAcross))
        // Player 0's tiles went right, to player 1.
        let received = TileCounts(round.hands[1])
        for tile in passed {
            #expect(received[tile] > 0)
        }
        #expect(round.hands.map(\.count) == [14, 13, 13, 13])

        for pass in [CharlestonPass.firstAcross, .firstLeft] {
            #expect(round.phase == .charleston(pass))
            for player in 0..<4 {
                try round.apply(.pass(firstThree(player)), by: player)
            }
        }
        #expect(round.phase == .vote)
    }

    @Test func jokersCannotBePassed() {
        var hand = Array(repeating: Tile.flower, count: 10)
        hand += [.joker, .joker, .joker]
        let round = Round(
            card: .practice, dealer: 1,
            hands: [hand, hand, hand + [.flower], hand], wall: []
        )
        #expect(!round.isLegal(.pass([.joker, .flower, .flower]), by: 0))
        #expect(round.isLegal(.pass([.flower, .flower, .flower]), by: 0))
        #expect(!round.isLegal(.pass([.flower, .flower]), by: 0))
    }

    @Test func anyNoStopsTheSecondCharleston() throws {
        var round = Round(card: .practice, dealer: 0, hands: Array(repeating: [], count: 4), wall: [], phase: .vote)
        for player in 0..<3 { try round.apply(.vote(true), by: player) }
        try round.apply(.vote(false), by: 3)
        #expect(round.phase == .courtesyOffer)
    }

    @Test func courtesyPassUsesTheSmallerOffer() throws {
        var generator = SeededGenerator(seed: 11)
        var round = Round.deal(card: .practice, using: &generator)
        round = Round(card: round.card, dealer: 0, hands: round.hands, wall: round.wall, phase: .courtesyOffer)
        try round.apply(.offer(3), by: 0)
        try round.apply(.offer(1), by: 1)
        try round.apply(.offer(2), by: 2)
        try round.apply(.offer(0), by: 3)
        #expect(round.courtesyCounts == [2, 0, 2, 0])
        #expect(round.phase == .courtesyPass)
        #expect(Set(round.actors) == [0, 2])
        try round.apply(.pass(Array(round.hands[0].filter { $0 != .joker }.prefix(2))), by: 0)
        try round.apply(.pass(Array(round.hands[2].filter { $0 != .joker }.prefix(2))), by: 2)
        #expect(round.phase == .discard(0))
        #expect(round.hands.map(\.count) == [14, 13, 13, 13])
    }

    /// Player 1 is waiting on a 4 Dot to finish a run in dots.
    private func waitingRound() -> Round {
        let waiting: [Tile] = [n(.dots, 1), n(.dots, 1), n(.dots, 1), n(.dots, 1), n(.dots, 2), n(.dots, 2), n(.dots, 2),
                               n(.dots, 3), n(.dots, 3), n(.dots, 3), n(.dots, 4), n(.dots, 4), .joker]
        let dealer: [Tile] = [n(.dots, 4)] + Array(repeating: .flower, count: 8) + [n(.bams, 1), n(.bams, 1), n(.bams, 1), .wind(.east), .wind(.east)]
        let other: [Tile] = [n(.craks, 1), n(.craks, 1), n(.craks, 1), n(.craks, 5), n(.craks, 5), n(.craks, 5),
                             .wind(.west), .wind(.west), .wind(.west), .wind(.south), .wind(.south), .wind(.south), .joker]
        let fourth: [Tile] = [n(.bams, 5), n(.bams, 5), n(.bams, 5), n(.bams, 6), n(.bams, 6), n(.bams, 6),
                              n(.bams, 7), n(.bams, 7), n(.bams, 7), .wind(.north), .wind(.north), .wind(.north), .joker]
        return Round(card: testCard, dealer: 0, hands: [dealer, waiting, other, fourth],
                     wall: [n(.craks, 9), n(.craks, 8)], phase: .discard(0))
    }

    @Test func mahjongOnADiscardBeatsOtherCalls() throws {
        var round = waitingRound()
        try round.apply(.discard(n(.dots, 4)), by: 0)
        // Only player 1 can use the tile, so the others have already let it go.
        #expect(round.actors == [1])
        #expect(round.legalMoves(for: 1).contains(.mahjong))
        try round.apply(.mahjong, by: 1)
        guard case .over(.mahjong(let win)) = round.phase else {
            Issue.record("expected a win")
            return
        }
        #expect(win.winner == 1)
        #expect(win.discarder == 0)
        #expect(!win.selfDrawn)
        #expect(!win.jokerless)
        #expect(round.payments() == [-50, 100, -25, -25])
        #expect(round.payments().reduce(0, +) == 0)
    }

    @Test func calledDiscardIsExposedAndCallerDiscards() throws {
        var round = waitingRound()
        try round.apply(.discard(.wind(.east)), by: 0)
        // Nobody can use the East, so player 1 draws.
        #expect(round.phase == .discard(1))
        #expect(round.drawn == n(.craks, 9))
        try round.apply(.discard(.joker), by: 1)
        // A discarded joker can never be called.
        #expect(round.phase == .discard(2))
        #expect(round.drawn == n(.craks, 8))
        try round.apply(.discard(.wind(.west)), by: 2)
        // The wall is empty, so nobody wins.
        #expect(round.phase == .over(.wallGame))
        #expect(round.payments() == [0, 0, 0, 0])
    }

    @Test func callingMakesAnExposure() throws {
        let caller: [Tile] = [n(.dots, 1), n(.dots, 1), n(.dots, 2), n(.dots, 2), n(.dots, 2),
                              n(.dots, 3), n(.dots, 3), n(.dots, 3), n(.dots, 4), n(.dots, 4), n(.dots, 4), .joker, .flower]
        let filler = Array(repeating: Tile.flower, count: 13)
        var round = Round(card: testCard, dealer: 0, hands: [filler + [n(.dots, 1)], caller, filler, filler],
                          wall: [n(.craks, 9)], phase: .discard(0))
        try round.apply(.discard(n(.dots, 1)), by: 0)
        #expect(round.legalMoves(for: 1) == [.call(count: 4), .decline])
        try round.apply(.call(count: 4), by: 1)
        #expect(round.phase == .discard(1))
        #expect(round.exposures[1] == [Exposure(tile: n(.dots, 1), count: 4, jokers: 1)])
        #expect(round.discards.isEmpty)
        #expect(round.hands[1].count == 10)
    }

    @Test func jokerSwapTakesTheJoker() throws {
        let exposure = Exposure(tile: n(.dots, 2), count: 3, jokers: 1)
        let filler = Array(repeating: Tile.flower, count: 13)
        var round = Round(
            card: testCard, dealer: 0,
            hands: [filler + [n(.dots, 2)], filler, Array(filler.prefix(10)), filler],
            exposures: [[], [], [exposure], []],
            wall: [], phase: .discard(0)
        )
        #expect(round.legalMoves(for: 0).contains(.swapJoker(owner: 2, exposure: 0)))
        try round.apply(.swapJoker(owner: 2, exposure: 0), by: 0)
        #expect(round.hands[0].contains(.joker))
        #expect(!round.hands[0].contains(n(.dots, 2)))
        #expect(round.exposures[2][0].jokers == 0)
    }

    @Test func selfDrawnWinIsPaidDoubleByAll() throws {
        let hand: [Tile] = [.wind(.north), .wind(.north), .wind(.east), .wind(.east), .wind(.west), .wind(.west),
                            .wind(.south), .wind(.south), .dragon(.red), .dragon(.red), .dragon(.green), .dragon(.green), .soap, .soap]
        var round = Round(card: testCard, dealer: 2, hands: [[], [], hand, []], wall: [], phase: .discard(2))
        try round.apply(.mahjong, by: 2)
        // Singles and pairs can never use jokers, so they get no jokerless bonus.
        #expect(round.payments() == [-100, -100, 300, -100])
    }

    @Test(arguments: 1...12)
    func botsPlayWholeRounds(seed: Int) throws {
        var generator = SeededGenerator(seed: UInt64(seed))
        var round = Round.deal(card: .practice, dealer: seed % 4, using: &generator)
        try playOut(&round)
        #expect(round.outcome != nil)
        #expect(round.payments().reduce(0, +) == 0)
    }
}

struct MatchTests {

    @Test func shortMatchRotatesTheDeal() throws {
        var generator = SeededGenerator(seed: 5)
        var match = Match(settings: MatchSettings(length: .short), card: .practice)
        var dealers: [Int] = []
        while !match.isOver {
            var round = match.dealRound(using: &generator)
            dealers.append(round.dealer)
            try playOut(&round)
            match.record(round)
        }
        #expect(dealers == [0, 1, 2, 3])
        #expect(match.scores.reduce(0, +) == 0)
        #expect(!match.winners.isEmpty)
    }

    /// Not a rule, but a sign the bots are any good: over many hands somebody
    /// should win most of the time instead of the wall running out.
    @Test func botsUsuallyFinishAHand() throws {
        var wins = 0
        for seed in 100..<120 {
            var generator = SeededGenerator(seed: UInt64(seed))
            var round = Round.deal(card: .practice, using: &generator)
            try playOut(&round)
            if case .over(.mahjong) = round.phase { wins += 1 }
        }
        #expect(wins >= 8, "only \(wins) of 20 hands had a winner")
    }
}
