//
//  Card.swift
//  mahjong
//
//  The card: the list of hands a player may win with. A card is read from a small
//  text file (see Cards/practice.txt for the format), so a new year's card is a new
//  file, not new code.
//

import Foundation

nonisolated enum CardError: Error, Equatable, CustomStringConvertible {
    case badLine(Int, String)

    var description: String {
        switch self {
        case .badLine(let line, let message): "line \(line): \(message)"
        }
    }
}

/// One group of a hand as printed on the card, before suits and numbers are chosen.
nonisolated struct PatternGroup: Hashable, Sendable {
    enum Face: Hashable, Sendable {
        /// A fixed number, 1 to 9.
        case number(Int)
        /// A number chosen by the player: 0 is the lowest number of the hand's run, 1 the next.
        case relative(Int)
        case wind(Wind)
        case dragon(Dragon)
        /// The dragon that belongs to the group's suit.
        case suitDragon
        case flower
    }

    let face: Face
    let count: Int
    /// 0, 1 or 2 for the card's /A, /B or /C, or nil for tiles that have no suit.
    let suit: Int?
}

/// One hand on the card.
nonisolated struct Hand: Sendable, Identifiable {
    /// Position on the card, counting from 0.
    let id: Int
    let section: String
    let concealed: Bool
    let value: Int
    let groups: [PatternGroup]
    let note: String
    /// The line as written in the card file, without the X/C and value.
    let text: String

    var tileCount: Int { groups.reduce(0) { $0 + $1.count } }

    /// Singles-and-pairs hands have no group of three or more, so jokers can never be used.
    var jokersAllowed: Bool { groups.contains { $0.count >= 3 } }
}

/// One group with its tile settled.
nonisolated struct ConcreteGroup: Hashable, Sendable {
    let tile: Tile
    let count: Int
}

/// One concrete way to make a hand: every suit and number chosen.
nonisolated struct HandInstance: Sendable {
    let hand: Int
    let concealed: Bool
    let groups: [ConcreteGroup]
    /// Tiles needed in singles and pairs. Only real tiles will do.
    let loose: TileCounts
    /// Tiles needed in groups of three or more, where jokers may stand in.
    let jokerable: TileCounts
    /// How many groups of each kind of three or more, for matching exposures.
    let multiGroups: [ConcreteGroup: Int]

    init(hand: Hand, groups: [ConcreteGroup]) {
        self.hand = hand.id
        concealed = hand.concealed
        self.groups = groups
        var loose = TileCounts()
        var jokerable = TileCounts()
        var multi: [ConcreteGroup: Int] = [:]
        for group in groups {
            if group.count >= 3 {
                jokerable[group.tile] += group.count
                multi[group, default: 0] += 1
            } else {
                loose[group.tile] += group.count
            }
        }
        self.loose = loose
        self.jokerable = jokerable
        multiGroups = multi
    }

    /// How many more tiles this player needs to finish the hand this way, or nil when
    /// their exposures rule it out. 0 means the hand is complete.
    ///
    /// `concealed` is the tiles in the player's rack; `exposures` the groups they have
    /// laid out. Real tiles go to singles and pairs first, because jokers cannot.
    func tilesNeeded(concealed tiles: TileCounts, exposures: [Exposure]) -> Int? {
        if concealed && !exposures.isEmpty { return nil }

        var jokerable = self.jokerable
        var matched = 0
        if !exposures.isEmpty {
            var available = multiGroups
            for exposure in exposures {
                let group = ConcreteGroup(tile: exposure.tile, count: exposure.count)
                guard let left = available[group], left > 0 else { return nil }
                available[group] = left - 1
                jokerable[exposure.tile] -= exposure.count
                matched += exposure.count
            }
        }

        var short = 0
        for index in 0..<(Tile.kindCount - 1) {
            let real = tiles[index]
            let forLoose = min(real, loose[index])
            let forGroups = min(real - forLoose, jokerable[index])
            matched += forLoose + forGroups
            short += jokerable[index] - forGroups
        }
        matched += min(tiles.jokers, short)
        return Card.handSize - matched
    }

    /// Whether a group of `count` of `tile` could be exposed for this instance.
    func hasGroup(_ tile: Tile, count: Int) -> Bool {
        multiGroups[ConcreteGroup(tile: tile, count: count)] != nil
    }
}

nonisolated struct Card: Sendable {
    static let handSize = 14

    let id: String
    let title: String
    let year: Int?
    let sections: [String]
    let hands: [Hand]
    /// Every concrete way to make every hand.
    let instances: [HandInstance]
    /// The text the card was read from.
    let source: String

    /// The practice card that ships with the game.
    static let practice: Card = {
        guard let url = Bundle.main.url(forResource: "practice", withExtension: "txt"),
              let text = try? String(contentsOf: url, encoding: .utf8) else {
            fatalError("practice.txt is missing from the app")
        }
        do {
            return try Card(text: text)
        } catch {
            fatalError("practice.txt: \(error)")
        }
    }()

    init(text: String) throws {
        var id = ""
        var title = ""
        var year: Int?
        var sections: [String] = []
        var hands: [Hand] = []

        for (offset, rawLine) in text.components(separatedBy: .newlines).enumerated() {
            let lineNumber = offset + 1
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            if line.isEmpty || line.hasPrefix("#") { continue }

            if let colon = line.firstIndex(of: ":"),
               let key = Optional(line[..<colon].lowercased()),
               ["id", "title", "year", "section"].contains(key) {
                let value = line[line.index(after: colon)...].trimmingCharacters(in: .whitespaces)
                switch key {
                case "id": id = value
                case "title": title = value
                case "year": year = Int(value)
                default: sections.append(value)
                }
                continue
            }

            guard let section = sections.last else {
                throw CardError.badLine(lineNumber, "hand before any section")
            }
            let hand = try Card.parseHand(line, id: hands.count, section: section, lineNumber: lineNumber)
            hands.append(hand)
        }

        guard !id.isEmpty else { throw CardError.badLine(0, "the card has no id") }
        self.id = id
        self.title = title.isEmpty ? id : title
        self.year = year
        self.sections = sections
        self.hands = hands
        instances = hands.flatMap(Card.instances(of:))
        source = text
    }

    // MARK: - Reading hands

    private static func parseHand(_ line: String, id: Int, section: String, lineNumber: Int) throws -> Hand {
        let parts = line.split(separator: ";", maxSplits: 1)
        let note = parts.count > 1 ? parts[1].trimmingCharacters(in: .whitespaces) : ""
        let words = parts[0].split(separator: " ").map(String.init)
        guard words.count >= 3 else { throw CardError.badLine(lineNumber, "too short") }

        let concealed: Bool
        switch words[0] {
        case "X": concealed = false
        case "C": concealed = true
        default: throw CardError.badLine(lineNumber, "must start with X or C")
        }
        guard let value = Int(words[1]), value > 0 else {
            throw CardError.badLine(lineNumber, "bad value \(words[1])")
        }

        var groups: [PatternGroup] = []
        for word in words.dropFirst(2) {
            groups += try parseToken(word, lineNumber: lineNumber)
        }
        let hand = Hand(
            id: id, section: section, concealed: concealed, value: value,
            groups: groups, note: note, text: words.dropFirst(2).joined(separator: " ")
        )
        guard hand.tileCount == handSize else {
            throw CardError.badLine(lineNumber, "\(hand.tileCount) tiles instead of \(handSize)")
        }
        guard hand.groups.allSatisfy({ $0.count <= 5 }) else {
            throw CardError.badLine(lineNumber, "a group has more than 5 tiles")
        }
        return hand
    }

    /// Splits a word like `2026/A` or `NNN` into groups of identical characters.
    private static func parseToken(_ word: String, lineNumber: Int) throws -> [PatternGroup] {
        let pieces = word.split(separator: "/", omittingEmptySubsequences: false)
        guard pieces.count <= 2, let body = pieces.first, !body.isEmpty else {
            throw CardError.badLine(lineNumber, "cannot read \(word)")
        }
        var suit: Int?
        if pieces.count == 2 {
            switch pieces[1] {
            case "A": suit = 0
            case "B": suit = 1
            case "C": suit = 2
            default: throw CardError.badLine(lineNumber, "suit must be A, B or C in \(word)")
            }
        }

        var runs: [(Character, Int)] = []
        for character in body {
            if let last = runs.last, last.0 == character {
                runs[runs.count - 1].1 += 1
            } else {
                runs.append((character, 1))
            }
        }

        var needsSuit = false
        var groups: [PatternGroup] = []
        for (character, count) in runs {
            let face: PatternGroup.Face
            switch character {
            case "1"..."9":
                face = .number(character.wholeNumberValue!)
                needsSuit = true
            case "a"..."i":
                face = .relative(Int(character.asciiValue! - Character("a").asciiValue!))
                needsSuit = true
            case "D":
                face = .suitDragon
                needsSuit = true
            case "0": face = .dragon(.white)
            case "R": face = .dragon(.red)
            case "G": face = .dragon(.green)
            case "F": face = .flower
            case "N": face = .wind(.north)
            case "E": face = .wind(.east)
            case "W": face = .wind(.west)
            case "S": face = .wind(.south)
            default: throw CardError.badLine(lineNumber, "unknown tile \(character) in \(word)")
            }
            let groupSuit: Int?
            switch face {
            case .number, .relative, .suitDragon: groupSuit = suit
            default: groupSuit = nil
            }
            groups.append(PatternGroup(face: face, count: count, suit: groupSuit))
        }
        if needsSuit && suit == nil {
            throw CardError.badLine(lineNumber, "\(word) needs a suit such as /A")
        }
        if !needsSuit && suit != nil {
            throw CardError.badLine(lineNumber, "\(word) has no tiles with a suit")
        }
        return groups
    }

    // MARK: - Every way to make a hand

    /// Tries every choice of suits and starting number, dropping duplicates and any
    /// that would need more of a tile in singles and pairs than the set has.
    static func instances(of hand: Hand) -> [HandInstance] {
        let suitVariables = Set(hand.groups.compactMap(\.suit)).sorted()
        let highestOffset = hand.groups.compactMap { group -> Int? in
            if case .relative(let offset) = group.face { return offset }
            return nil
        }.max()
        let bases = highestOffset.map { Array(1...(9 - $0)) } ?? [1]

        var seen = Set<[ConcreteGroup]>()
        var result: [HandInstance] = []
        for suits in assignments(of: suitVariables.count) {
            for base in bases {
                let groups = hand.groups.map { group -> ConcreteGroup in
                    let suit = group.suit.map { suits[suitVariables.firstIndex(of: $0)!] }
                    let tile: Tile
                    switch group.face {
                    case .number(let rank): tile = .number(suit!, rank)
                    case .relative(let offset): tile = .number(suit!, base + offset)
                    case .wind(let wind): tile = .wind(wind)
                    case .dragon(let dragon): tile = .dragon(dragon)
                    case .suitDragon: tile = .dragon(suit!.dragon)
                    case .flower: tile = .flower
                    }
                    return ConcreteGroup(tile: tile, count: group.count)
                }
                let key = groups.sorted { ($0.tile, $0.count) < ($1.tile, $1.count) }
                guard seen.insert(key).inserted else { continue }
                let instance = HandInstance(hand: hand, groups: groups)
                let possible = (0..<(Tile.kindCount - 1)).allSatisfy { index in
                    instance.loose[index] <= Tile(index: index).copiesInSet
                }
                if possible { result.append(instance) }
            }
        }
        return result
    }

    /// Every way to give `count` suit letters different suits.
    private static func assignments(of count: Int) -> [[Suit]] {
        if count == 0 { return [[]] }
        var result: [[Suit]] = []
        for rest in assignments(of: count - 1) {
            for suit in Suit.allCases where !rest.contains(suit) {
                result.append(rest + [suit])
            }
        }
        return result
    }

    // MARK: - Checking a player's tiles

    /// The ways the player's tiles already make a hand on this card, best paying first.
    func completedHands(concealed: [Tile], exposures: [Exposure]) -> [HandInstance] {
        let counts = TileCounts(concealed)
        return instances
            .filter { $0.tilesNeeded(concealed: counts, exposures: exposures) == 0 }
            .sorted { hands[$0.hand].value > hands[$1.hand].value }
    }

    /// Whether the exposures still fit at least one hand. A player whose exposures fit
    /// nothing could never win.
    func allowsExposures(_ exposures: [Exposure]) -> Bool {
        instances.contains { instance in
            guard !instance.concealed else { return false }
            var available = instance.multiGroups
            for exposure in exposures {
                let group = ConcreteGroup(tile: exposure.tile, count: exposure.count)
                guard let left = available[group], left > 0 else { return false }
                available[group] = left - 1
            }
            return true
        }
    }
}

/// A card is saved as the text it was read from.
extension Card: Codable {
    nonisolated init(from decoder: Decoder) throws {
        let text = try decoder.singleValueContainer().decode(String.self)
        try self.init(text: text)
    }

    nonisolated func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(source)
    }
}

/// A group a player has laid out on the table after calling a discard.
nonisolated struct Exposure: Hashable, Sendable, Codable {
    let tile: Tile
    let count: Int
    /// How many of the group are jokers standing in for `tile`.
    var jokers: Int

    var tiles: [Tile] {
        Array(repeating: tile, count: count - jokers) + Array(repeating: .joker, count: jokers)
    }
}
