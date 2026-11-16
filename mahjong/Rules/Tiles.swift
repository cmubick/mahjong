//
//  Tiles.swift
//  mahjong
//
//  The 152 tiles of an American mahjong set. Pure Swift: no SpriteKit or UIKit.
//

import Foundation

nonisolated enum Suit: Int, CaseIterable, Hashable, Sendable, Codable {
    case bams, craks, dots

    /// Each suit has a dragon of its own: green with bams, red with craks, white with dots.
    var dragon: Dragon {
        switch self {
        case .bams: .green
        case .craks: .red
        case .dots: .white
        }
    }

    var name: String {
        switch self {
        case .bams: "Bam"
        case .craks: "Crak"
        case .dots: "Dot"
        }
    }
}

nonisolated enum Wind: Int, CaseIterable, Hashable, Sendable, Codable {
    case north, east, west, south

    var letter: String {
        switch self {
        case .north: "N"
        case .east: "E"
        case .west: "W"
        case .south: "S"
        }
    }
}

nonisolated enum Dragon: Int, CaseIterable, Hashable, Sendable, Codable {
    case green, red, white

    var suit: Suit {
        switch self {
        case .green: .bams
        case .red: .craks
        case .white: .dots
        }
    }

    var name: String {
        switch self {
        case .green: "Green"
        case .red: "Red"
        case .white: "Soap"
        }
    }
}

/// What is printed on a tile. Identical tiles are equal: a set has four of most tiles
/// and eight flowers and eight jokers.
nonisolated enum Tile: Hashable, Sendable, Codable, Comparable, CustomStringConvertible {
    case number(Suit, Int)
    case wind(Wind)
    case dragon(Dragon)
    case flower
    case joker

    /// How many different tiles there are: 27 numbers, 4 winds, 3 dragons, flower, joker.
    static let kindCount = 36

    static let soap = Tile.dragon(.white)

    /// A dense index from 0 to 35, used for counting tiles.
    var index: Int {
        switch self {
        case .number(let suit, let rank): suit.rawValue * 9 + rank - 1
        case .wind(let wind): 27 + wind.rawValue
        case .dragon(let dragon): 31 + dragon.rawValue
        case .flower: 34
        case .joker: 35
        }
    }

    init(index: Int) {
        switch index {
        case 0..<27: self = .number(Suit(rawValue: index / 9)!, index % 9 + 1)
        case 27..<31: self = .wind(Wind(rawValue: index - 27)!)
        case 31..<34: self = .dragon(Dragon(rawValue: index - 31)!)
        case 34: self = .flower
        default: self = .joker
        }
    }

    static func < (lhs: Tile, rhs: Tile) -> Bool { lhs.index < rhs.index }

    var isJoker: Bool { self == .joker }

    /// How many of this tile a set contains.
    var copiesInSet: Int {
        switch self {
        case .flower, .joker: 8
        default: 4
        }
    }

    var description: String {
        switch self {
        case .number(let suit, let rank): "\(rank) \(suit.name)"
        case .wind(let wind): wind.letter
        case .dragon(let dragon): dragon.name
        case .flower: "Flower"
        case .joker: "Joker"
        }
    }

    /// The complete set of 152 tiles, in order.
    static let fullSet: [Tile] = (0..<kindCount).flatMap { index in
        let tile = Tile(index: index)
        return Array(repeating: tile, count: tile.copiesInSet)
    }
}

/// How many of each tile a group of tiles holds, indexed by `Tile.index`.
nonisolated struct TileCounts: Hashable, Sendable {
    private(set) var counts = [Int](repeating: 0, count: Tile.kindCount)

    init() {}

    init(_ tiles: some Sequence<Tile>) {
        for tile in tiles {
            counts[tile.index] += 1
        }
    }

    subscript(tile: Tile) -> Int {
        get { counts[tile.index] }
        set { counts[tile.index] = newValue }
    }

    subscript(index: Int) -> Int {
        counts[index]
    }

    var jokers: Int { counts[Tile.joker.index] }
}

/// Small seedable generator so deals and bot games can be reproduced.
nonisolated struct SeededGenerator: RandomNumberGenerator, Sendable, Codable {
    private var state: UInt64

    init(seed: UInt64) {
        state = seed
    }

    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
}

extension Array {
    /// Fisher–Yates shuffle written out by hand, so the Android port can repeat it
    /// exactly from the same seed.
    nonisolated func seededShuffle(using generator: inout some RandomNumberGenerator) -> [Element] {
        var result = self
        var index = result.count - 1
        while index > 0 {
            let other = Int(generator.next() % UInt64(index + 1))
            result.swapAt(index, other)
            index -= 1
        }
        return result
    }
}
