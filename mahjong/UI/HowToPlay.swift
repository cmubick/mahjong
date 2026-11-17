//
//  HowToPlay.swift
//  mahjong
//
//  The text and example tiles for the How to play pages.
//

import Foundation

struct HelpPage {
    /// A labelled line of tiles, for the page that shows the whole set.
    struct Row {
        let label: String
        let groups: [[Tile]]
    }

    let title: String
    /// Example tiles drawn at the top of the page, in groups with a little space between.
    var examples: [[Tile]] = []
    /// Labelled lines of tiles, drawn instead of `examples`.
    var rows: [Row] = []
    let text: String

    static let seenKey = "hasSeenHowToPlay"

    private static func n(_ suit: Suit, _ ranks: Int...) -> [Tile] {
        ranks.map { .number(suit, $0) }
    }

    private static func same(_ tile: Tile, _ count: Int) -> [Tile] {
        Array(repeating: tile, count: count)
    }

    static let all: [HelpPage] = [
        HelpPage(
            title: "The goal",
            examples: [same(.number(.dots, 2), 3), same(.number(.dots, 4), 4), same(.number(.dots, 6), 4), same(.number(.dots, 8), 3)],
            text: "Be the first to make one of the hands on the card: 14 tiles that match a line exactly.\n\nEvery hand is a game of its own. The winner is paid the hand's value, and the scorepad keeps a running total until you clear it."
        ),
        HelpPage(
            title: "The tiles",
            examples: [n(.bams, 1), n(.craks, 5), n(.dots, 9), [.wind(.east)], [.dragon(.red)], [.flower], [.joker]],
            text: "Three suits numbered 1 to 9: Bams, Craks and Dots. Four winds, three dragons, eight flowers and eight jokers.\n\nEach suit has its own dragon: Green with Bams, Red with Craks, and Soap (the white dragon) with Dots. Soap also stands for 0 in year hands like 2026."
        ),
        HelpPage(
            title: "Every tile",
            rows: [
                Row(label: "Bams", groups: [(1...9).map { .number(.bams, $0) }, [.dragon(.green)]]),
                Row(label: "Craks", groups: [(1...9).map { .number(.craks, $0) }, [.dragon(.red)]]),
                Row(label: "Dots", groups: [(1...9).map { .number(.dots, $0) }, [.dragon(.white)]]),
                Row(label: "Others", groups: [Wind.allCases.map { .wind($0) }, [.flower], [.joker]]),
            ],
            text: "Each suit's dragon ends its row: Green with Bams, Red with Craks, Soap with Dots.\n\nFour of every tile, plus eight flowers and eight jokers: 152 in all."
        ),
        HelpPage(
            title: "The card",
            examples: [n(.bams, 2) + [.dragon(.white)] + n(.bams, 2, 6), same(.number(.craks, 3), 3)],
            text: "Each line of the card is a hand. Some are fixed; others say \"any suit\" or \"any run\", so they can be made several ways.\n\nTap Card at any time to see every hand, closest first. To play a League card, you need your own official card from the National Mah Jongg League."
        ),
        HelpPage(
            title: "The Charleston",
            examples: [n(.craks, 1), [.wind(.north)], n(.dots, 7)],
            text: "Before play, everyone passes 3 tiles: right, then across, then left. If everyone agrees, a second Charleston goes left, across, right.\n\nLast, you may swap up to 3 tiles with the player across. Jokers can never be passed."
        ),
        HelpPage(
            title: "Your turn",
            examples: [n(.bams, 4), [.wind(.west)], n(.dots, 1)],
            text: "East starts by discarding. After that, each turn you draw a tile from the wall (it glows gold in your rack) and discard one.\n\nTap a tile to pick it, and tap it again to discard it."
        ),
        HelpPage(
            title: "Calling a discard",
            examples: [same(.number(.craks, 7), 2) + [.joker], same(.wind(.south), 4)],
            text: "Each discard waits in the middle until the bar under it runs out. If you need it for a pung (3), kong (4) or quint (5), call it: the group goes face up in front of you, and you discard.\n\nYou can only call a tile for a single or a pair if it gives you Mahjong."
        ),
        HelpPage(
            title: "Jokers",
            examples: [same(.number(.dots, 5), 2) + [.joker], [.joker, .joker]],
            text: "A joker stands in for any tile in a pung, kong or quint, but never in a single or a pair.\n\nOn your turn, if anyone's face-up group has a joker and you hold the real tile, tap the joker to swap your tile for it."
        ),
        HelpPage(
            title: "Mahjong",
            examples: [same(.number(.bams, 1), 2), same(.number(.bams, 2), 3), same(.number(.bams, 3), 4)],
            text: "When your hand is complete, tap Mahjong! Everyone pays you the hand's value from the card.\n\nIf you win on a discard, the discarder pays double. Drawing the winning tile yourself makes everyone pay double, and a hand with no jokers counts double."
        ),
    ]
}
