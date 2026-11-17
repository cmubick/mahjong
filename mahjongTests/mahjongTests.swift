//
//  mahjongTests.swift
//  mahjongTests
//

import Foundation
import StoreKit
import StoreKitTest
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

    @Test func the2026CardReads() throws {
        let card = try #require(CardLibrary.card(id: "nmjl2026"))
        #expect(card.year == 2026)
        #expect(!card.isPractice)
        #expect(card.hands.count == 72)
        #expect(card.sections == ["2026", "2468", "Any Like Numbers", "Quints", "Consecutive Run",
                                  "13579", "Winds and Dragons", "369", "Singles and Pairs"])
        for hand in card.hands {
            #expect(hand.variants.allSatisfy { $0.reduce(0) { $0 + $1.count } == 14 })
            #expect(card.instances.contains { $0.hand == hand.id }, "no way to make \(hand.text)")
        }
        for instance in card.instances {
            let needed = instance.tilesNeeded(concealed: TileCounts(tiles(of: instance)), exposures: [])
            #expect(needed == 0)
        }
        // The newest League card is the one for sale.
        #expect(CardLibrary.currentYear == 2026)
        #expect(CardLibrary.isPaid(card))
    }

    @Test func alternativesAreAllPlayable() throws {
        let card = try #require(CardLibrary.card(id: "nmjl2026"))
        // "Kong 2 or 6": both kongs make the hand.
        let hand = try #require(card.hands.first { $0.text.hasPrefix("2026/A DDD/A 2222/B") })
        #expect(hand.variants.count == 2)
        let kongs = Set(card.instances.filter { $0.hand == hand.id }.flatMap { instance in
            instance.groups.filter { $0.count == 4 }.compactMap { group -> Int? in
                if case .number(_, let rank) = group.tile { return rank }
                return nil
            }
        })
        #expect(kongs == [2, 6])
    }

    @Test func runWithThreeDragonsKongMatchesTheRun() throws {
        let card = try #require(CardLibrary.card(id: "nmjl2026"))
        let hand = try #require(card.hands.first { $0.text == "abcd/A DDD/B DDD/C DDDD/A" })
        let ways = card.instances.filter { $0.hand == hand.id }
        // Three suits for the run, times six runs (1234 to 6789).
        #expect(ways.count == 3 * 6)
        for way in ways {
            let numbers = way.groups.compactMap { group -> Suit? in
                if case .number(let suit, _) = group.tile { return suit }
                return nil
            }
            let suit = try #require(numbers.first)
            #expect(numbers.allSatisfy { $0 == suit })
            // The kong is the run's own dragon; the other two dragons are pungs.
            #expect(way.groups.contains { $0.tile == .dragon(suit.dragon) && $0.count == 4 })
            for other in Suit.allCases where other != suit {
                #expect(way.groups.contains { $0.tile == .dragon(other.dragon) && $0.count == 3 })
            }
        }
    }

    @Test func twoQuintsInOneSuitWithAnotherSuitsDragon() throws {
        let card = try #require(CardLibrary.card(id: "nmjl2026"))
        let hand = try #require(card.hands.first { $0.text.hasPrefix("aaaaa/A bbbbb/A DDDD/B") })
        let ways = card.instances.filter { $0.hand == hand.id }
        var pairs = Set<[Int]>()
        for way in ways {
            let quints = way.groups.filter { $0.count == 5 }
            let suits = Set(quints.compactMap { group -> Suit? in
                if case .number(let suit, _) = group.tile { return suit }
                return nil
            })
            #expect(suits.count == 1)
            let suit = try #require(suits.first)
            let ranks = quints.compactMap { group -> Int? in
                if case .number(_, let rank) = group.tile { return rank }
                return nil
            }.sorted()
            #expect(ranks.count == 2 && ranks[0] != ranks[1])
            pairs.insert(ranks)
            let dragon = try #require(way.groups.first { $0.count == 4 })
            #expect(dragon.tile != .dragon(suit.dragon))
            #expect(Suit.allCases.contains { $0 != suit && dragon.tile == .dragon($0.dragon) })
        }
        // Any two different numbers: every pair from 1 to 9.
        #expect(pairs.count == 36)
    }

    @Test func sixFlowersAreOneGroupAndCanBeCalled() throws {
        let card = try #require(CardLibrary.card(id: "nmjl2026"))
        let hand = try #require(card.hands.first { $0.text == "aaaa/A FFFFFF aaaa/B" })
        #expect(hand.groups.contains { $0.face == .flower && $0.count == 6 })
        #expect(card.allowsExposures([Exposure(tile: .flower, count: 6, jokers: 2)]))
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
        // Nobody can use the East, but it stays callable until player 1 draws.
        #expect(round.phase == .claim(Round.Discard(tile: .wind(.east), player: 0)))
        #expect(round.isWaitingForDraw)
        #expect(round.actors == [1])
        #expect(round.legalMoves(for: 1) == [.draw])
        #expect(!round.isLegal(.draw, by: 2))
        try round.apply(.draw, by: 1)
        #expect(round.phase == .discard(1))
        #expect(round.drawn == n(.craks, 9))
        try round.apply(.discard(.joker), by: 1)
        // A discarded joker can never be called.
        #expect(round.legalMoves(for: 2) == [.draw])
        try round.apply(.draw, by: 2)
        #expect(round.phase == .discard(2))
        #expect(round.drawn == n(.craks, 8))
        try round.apply(.discard(.wind(.west)), by: 2)
        try round.apply(.draw, by: 3)
        // The wall is empty, so nobody wins.
        #expect(round.phase == .over(.wallGame))
        #expect(round.payments() == [0, 0, 0, 0])
    }

    @Test func theDrawWaitsForEveryoneWhoCanCall() throws {
        var round = waitingRound()
        try round.apply(.discard(n(.dots, 4)), by: 0)
        // Player 1 could win on it, so nobody may draw until they answer.
        #expect(round.actors == [1])
        #expect(!round.isWaitingForDraw)
        try round.apply(.decline, by: 1)
        #expect(round.isWaitingForDraw)
        #expect(round.legalMoves(for: 1) == [.draw])
        try round.apply(.draw, by: 1)
        #expect(round.phase == .discard(1))
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

struct ScorepadTests {

    @Test func theDealMovesOnAndScoresAddUp() throws {
        var generator = SeededGenerator(seed: 5)
        var pad = Scorepad()
        var dealers: [Int] = []
        for _ in 0..<5 {
            var round = pad.deal(card: .practice, charleston: true, using: &generator)
            dealers.append(round.dealer)
            try playOut(&round)
            pad.record(round)
        }
        #expect(dealers == [0, 1, 2, 3, 0])
        #expect(pad.handsPlayed == 5)
        #expect(pad.scores.reduce(0, +) == 0)
    }

    @Test func clearingStartsAFreshSheetButKeepsTheDeal() throws {
        var generator = SeededGenerator(seed: 6)
        var pad = Scorepad()
        for _ in 0..<3 {
            var round = pad.deal(card: .practice, charleston: false, using: &generator)
            try playOut(&round)
            pad.record(round)
        }
        let later = Date().addingTimeInterval(60)
        pad.clear(at: later)
        #expect(pad.scores == [0, 0, 0, 0])
        #expect(pad.wins == [0, 0, 0, 0])
        #expect(pad.handsPlayed == 0)
        #expect(pad.started == later)
        #expect(pad.dealer == 3)
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

struct SavedGameTests {

    /// Plays a seeded bot game for a while so there is a realistic position to save.
    private func midGame(moves: Int = 60) throws -> (Scorepad, Round) {
        var generator = SeededGenerator(seed: 42)
        let match = Scorepad()
        var round = match.deal(card: .practice, charleston: true, using: &generator)
        for _ in 0..<moves {
            guard round.outcome == nil else { break }
            let actor = try #require(round.actors.first)
            try round.apply(try #require(Bot.chooseMove(in: round, for: actor)), by: actor)
        }
        return (match, round)
    }

    @Test func aHandInProgressSurvivesSavingAndLoading() throws {
        let (match, round) = try midGame()
        let data = try JSONEncoder().encode(SavedGame(scorepad: match, round: round))
        let loaded = try JSONDecoder().decode(SavedGame.self, from: data)
        let restored = try #require(loaded.round)

        #expect(restored.hands == round.hands)
        #expect(restored.exposures == round.exposures)
        #expect(restored.discards == round.discards)
        #expect(restored.wall == round.wall)
        #expect(restored.phase == round.phase)
        #expect(restored.drawn == round.drawn)
        #expect(restored.card.hands.map(\.text) == round.card.hands.map(\.text))
        for player in 0..<4 {
            #expect(Set(restored.legalMoves(for: player)) == Set(round.legalMoves(for: player)))
        }
        #expect(loaded.scorepad.scores == match.scores)
        #expect(loaded.scorepad.dealer == match.dealer)
    }

    @Test func aRestoredHandCanBePlayedToTheEnd() throws {
        let (_, round) = try midGame()
        var restored = try JSONDecoder().decode(Round.self, from: JSONEncoder().encode(round))
        try playOut(&restored)
        #expect(restored.outcome != nil)
    }

    @Test func savingBetweenHandsKeepsNoHand() throws {
        let (match, _) = try midGame()
        let data = try JSONEncoder().encode(SavedGame(scorepad: match, round: nil))
        #expect(try JSONDecoder().decode(SavedGame.self, from: data).round == nil)
    }

    @Test func saverWritesLoadsAndClearsAFile() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("mahjong-tests-\(UUID().uuidString)")
            .appendingPathComponent("savedGame.json")
        #expect(GameSaver.load(from: url) == nil)
        let (match, round) = try midGame()
        GameSaver.save(SavedGame(scorepad: match, round: round), to: url)
        #expect(GameSaver.load(from: url)?.round?.hands == round.hands)
        GameSaver.clear(at: url)
        #expect(GameSaver.load(from: url) == nil)
    }
}

struct SoundTests {

    @Test(arguments: Sound.allCases)
    func everySoundIsAValidShortWavFile(sound: Sound) {
        let data = SoundSynth.wav(for: sound)
        #expect(String(decoding: data.prefix(4), as: UTF8.self) == "RIFF")
        #expect(String(decoding: data[8..<12], as: UTF8.self) == "WAVE")
        let samples = SoundSynth.samples(for: sound)
        #expect(data.count == 44 + samples.count * 2)
        // Audible, never clipping, and short enough to stay out of the way.
        #expect(samples.contains { abs($0) > 0.05 })
        #expect(samples.allSatisfy { abs($0) <= 1 })
        #expect(Double(samples.count) / SoundSynth.sampleRate < 1.5)
    }
}

struct StoreOfferTests {

    private let year = 2026

    @Test func withNothingOwnedTheFullGameComesFirstThenTheCardAlone() {
        #expect(StoreOffers.offers(owned: [], currentYear: year) == ["mahjong.fullgame.2026", "mahjong.card.2026"])
    }

    @Test func owningThisYearsCardOffersTheUpgrade() {
        let owned: Set<String> = ["mahjong.card.2026"]
        #expect(StoreOffers.ownsCard(year, owned: owned))
        #expect(!StoreOffers.hasFullGame(owned: owned))
        #expect(StoreOffers.offers(owned: owned, currentYear: year) == ["mahjong.upgrade"])
    }

    @Test func theFullGameGivesThisYearsCardAndHistory() {
        let owned: Set<String> = ["mahjong.fullgame.2026"]
        #expect(StoreOffers.ownsCard(year, owned: owned))
        #expect(StoreOffers.hasFullGame(owned: owned))
        #expect(StoreOffers.offers(owned: owned, currentYear: year).isEmpty)
    }

    @Test func nextYearsCardIsStillForSale() {
        // Bought the full game in 2026; the 2027 card arrives.
        let owned: Set<String> = ["mahjong.fullgame.2026"]
        #expect(!StoreOffers.ownsCard(2027, owned: owned))
        #expect(StoreOffers.hasFullGame(owned: owned))
        #expect(StoreOffers.offers(owned: owned, currentYear: 2027) == ["mahjong.card.2027"])
        // Bought the card alone in 2026 and the upgrade: only the new card is left to buy.
        #expect(StoreOffers.offers(owned: ["mahjong.card.2026", "mahjong.upgrade"], currentYear: 2027) == ["mahjong.card.2027"])
        // Bought only the 2026 card: next year it's the full game again, or the card alone.
        #expect(StoreOffers.offers(owned: ["mahjong.card.2026"], currentYear: 2027)
                == ["mahjong.fullgame.2027", "mahjong.card.2027"])
    }

    @Test func withNoCardForSaleTheFullGameIsJustTheExtras() {
        #expect(StoreOffers.offers(owned: [], currentYear: nil) == ["mahjong.upgrade"])
        #expect(StoreOffers.offers(owned: ["mahjong.upgrade"], currentYear: nil).isEmpty)
        #expect(!StoreOffers.productIDs(currentYear: nil).contains { $0.hasPrefix("mahjong.card.") })
    }
}

/// Runs the store against the local test configuration in Mahjong.storekit.
@MainActor
@Suite(.serialized)
struct StoreTests {

    private func makeSession() throws -> SKTestSession {
        let session = try SKTestSession(configurationFileNamed: "Mahjong")
        session.disableDialogs = true
        session.clearTransactions()
        return session
    }

    private func makeStore(defaults: UserDefaults? = nil) -> Store {
        Store(currentYear: 2026, defaults: defaults ?? UserDefaults(suiteName: "store-tests-\(UUID().uuidString)")!)
    }

    @Test func loadsTheProductsAndThreeTips() async throws {
        _ = try makeSession()
        let store = makeStore()
        await store.refresh()
        #expect(store.hasLoaded)
        #expect(store.offers.map(\.id) == ["mahjong.fullgame.2026", "mahjong.card.2026"])
        #expect(store.offers.allSatisfy { $0.product != nil })
        #expect(store.tips.map(\.id) == StoreOffers.tipIDs)
        #expect(!store.hasFullGame)
    }

    @Test func buyingTheCardThenTheUpgradeGivesEverything() async throws {
        _ = try makeSession()
        let defaults = UserDefaults(suiteName: "store-tests-\(UUID().uuidString)")!
        let store = makeStore(defaults: defaults)
        await store.refresh()
        #expect(await store.buy(try #require(store.products["mahjong.card.2026"])) == .success)
        #expect(store.ownsCard(2026))
        #expect(store.offers.map(\.id) == ["mahjong.upgrade"])
        #expect(await store.buy(try #require(store.products["mahjong.upgrade"])) == .success)
        #expect(store.ownsEverything)

        // A fresh launch reads the cached answer, then the store confirms it.
        let relaunched = makeStore(defaults: defaults)
        #expect(relaunched.ownsEverything)
        await relaunched.refresh()
        #expect(relaunched.ownsEverything)
    }

    @Test func tippingDoesNotUnlockAnything() async throws {
        _ = try makeSession()
        let store = makeStore()
        await store.refresh()
        let tip = try #require(store.tips.first)
        #expect(await store.buy(tip) == .success)
        #expect(!store.hasFullGame)
        #expect(await store.buy(tip) == .success)
    }

    @Test func restoreFindsAnEarlierPurchase() async throws {
        _ = try makeSession()
        let first = makeStore()
        await first.refresh()
        #expect(await first.buy(try #require(first.products["mahjong.fullgame.2026"])) == .success)
        let store = makeStore()
        #expect(!store.hasFullGame)
        #expect(await store.restore())
        #expect(store.ownsEverything)
    }
}

struct CardLibraryTests {

    private func card(_ id: String, year: Int, practice: Bool = false) throws -> Card {
        try Card(text: """
            id: \(id)
            title: \(id)
            year: \(year)
            \(practice ? "kind: practice" : "")
            section: Test
            X 25 1111/A 222/A 333/A 4444/A
            """)
    }

    @Test func theNewestLeagueCardIsPaidAndTheRestAreFree() throws {
        let cards = CardLibrary.sorted([
            try card("practice", year: 2026, practice: true),
            try card("league2024", year: 2024),
            try card("league2026", year: 2026),
            try card("league2025", year: 2025),
        ])
        #expect(cards.map(\.id) == ["league2026", "league2025", "league2024", "practice"])
        #expect(CardLibrary.paidCardID(in: cards) == "league2026")
        #expect(!CardLibrary.isPaid(cards[1], in: cards))
        #expect(!CardLibrary.isPaid(cards[3], in: cards))
        #expect(CardLibrary.defaultCard(unlocked: true, in: cards).id == "league2026")
        #expect(CardLibrary.defaultCard(unlocked: false, in: cards).id == "league2025")
    }

    @Test func thePracticeCardIsNeverPaid() throws {
        let cards = [try card("practice", year: 2026, practice: true)]
        #expect(CardLibrary.paidCardID(in: cards) == nil)
        #expect(CardLibrary.defaultCard(unlocked: false, in: cards).id == "practice")
        #expect(Card.practice.isPractice)
    }

    @Test func theAppShipsThePracticeCard() {
        #expect(CardLibrary.all.contains { $0.id == "practice" })
    }
}

struct HistoryTests {

    private func finishedRounds(_ count: Int, seed: UInt64 = 9) throws -> [Round] {
        var generator = SeededGenerator(seed: seed)
        var pad = Scorepad()
        var rounds: [Round] = []
        for _ in 0..<count {
            var round = pad.deal(card: .practice, charleston: true, using: &generator)
            try playOut(&round)
            pad.record(round)
            rounds.append(round)
        }
        return rounds
    }

    @Test func aRecordRemembersWhoWonAndWhatYouPaid() throws {
        for round in try finishedRounds(6) {
            let record = HandRecord(round: round)
            #expect(record.payments == round.payments())
            #expect(record.cardTitle == "Practice Card")
            if case .over(.mahjong(let win)) = round.phase {
                #expect(record.winner == win.winner)
                #expect(record.value == round.card.hands[win.hand].value)
            } else {
                #expect(record.winner == nil)
            }
        }
    }

    @Test func theSummaryAddsUpYourHands() throws {
        let rounds = try finishedRounds(12)
        var history = HandHistory()
        for round in rounds { history.add(HandRecord(round: round)) }
        let summary = history.summary
        #expect(summary.played == 12)
        #expect(summary.net == rounds.map { $0.payments()[0] }.reduce(0, +))
        let youWon = rounds.filter { if case .over(.mahjong(let win)) = $0.phase { return win.winner == 0 }; return false }
        #expect(summary.won == youWon.count)
        let walls = rounds.filter { $0.phase == .over(.wallGame) }
        #expect(summary.wallGames == walls.count)
    }

    @Test func historySurvivesSavingAndIsCapped() throws {
        let round = try #require(try finishedRounds(1).first)
        var history = HandHistory()
        for _ in 0..<(HandHistory.cap + 5) { history.add(HandRecord(round: round)) }
        #expect(history.hands.count == HandHistory.cap)

        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("mahjong-tests-\(UUID().uuidString)")
            .appendingPathComponent("history.json")
        HistoryStore.save(history, to: url)
        #expect(HistoryStore.load(from: url).hands.count == HandHistory.cap)
        try? FileManager.default.removeItem(at: url.deletingLastPathComponent())
    }
}
