//
//  History.swift
//  mahjong
//
//  A record of every hand you finish. Unlike the scorepad it is never cleared, so
//  it can show how you play over time.
//

import Foundation

nonisolated struct HandRecord: Codable, Sendable, Equatable {
    var date: Date
    var cardTitle: String
    /// The winner's seat (0 is you), or nil for a wall game.
    var winner: Int?
    var section: String?
    var value: Int?
    var selfDrawn = false
    var discarder: Int?
    var jokerless = false
    /// What each seat won or paid.
    var payments: [Int]

    init(round: Round, date: Date = Date()) {
        self.date = date
        cardTitle = round.card.title
        payments = round.payments()
        if case .over(.mahjong(let win)) = round.phase {
            let hand = round.card.hands[win.hand]
            winner = win.winner
            section = hand.section
            value = hand.value
            selfDrawn = win.selfDrawn
            discarder = win.discarder
            jokerless = win.jokerless
        }
    }

    /// What you won or paid on this hand.
    var yourResult: Int { payments.first ?? 0 }
}

nonisolated struct HandHistory: Codable, Sendable {
    /// The most hands kept. The oldest are dropped first.
    static let cap = 2000

    private(set) var hands: [HandRecord] = []

    mutating func add(_ record: HandRecord) {
        hands.append(record)
        if hands.count > HandHistory.cap {
            hands.removeFirst(hands.count - HandHistory.cap)
        }
    }

    struct Summary: Equatable {
        var played = 0
        var won = 0
        var wallGames = 0
        /// Wins on a tile you drew yourself.
        var selfDrawn = 0
        /// Times someone won on your discard.
        var fedWins = 0
        /// Everything you have won, less everything you have paid.
        var net = 0
        var biggestWin = 0
        /// The section of the card you have won with most, if you have won.
        var favouriteSection: String?

        var winRate: Double { played == 0 ? 0 : Double(won) / Double(played) }
    }

    var summary: Summary {
        var summary = Summary()
        var sectionWins: [String: Int] = [:]
        for hand in hands {
            summary.played += 1
            summary.net += hand.yourResult
            switch hand.winner {
            case nil:
                summary.wallGames += 1
            case 0?:
                summary.won += 1
                if hand.selfDrawn { summary.selfDrawn += 1 }
                summary.biggestWin = max(summary.biggestWin, hand.yourResult)
                if let section = hand.section { sectionWins[section, default: 0] += 1 }
            default:
                if hand.discarder == 0 && !hand.selfDrawn { summary.fedWins += 1 }
            }
        }
        summary.favouriteSection = sectionWins.max { ($0.value, $1.key) < ($1.value, $0.key) }?.key
        return summary
    }
}

/// Keeps the history as a JSON file in Application Support.
nonisolated enum HistoryStore {
    static var url: URL {
        let folder = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return folder.appendingPathComponent("history.json")
    }

    static func load(from url: URL = HistoryStore.url) -> HandHistory {
        guard let data = try? Data(contentsOf: url),
              let history = try? JSONDecoder().decode(HandHistory.self, from: data) else { return HandHistory() }
        return history
    }

    static func save(_ history: HandHistory, to url: URL = HistoryStore.url) {
        do {
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try JSONEncoder().encode(history).write(to: url, options: .atomic)
        } catch {
            // A failed save only loses the newest hands from the history.
        }
    }
}
