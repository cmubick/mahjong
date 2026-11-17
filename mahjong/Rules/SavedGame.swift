//
//  SavedGame.swift
//  mahjong
//
//  The scorepad and the hand in progress, saved so they survive the app being closed.
//

import Foundation

nonisolated struct SavedGame: Codable, Sendable {
    var scorepad: Scorepad
    /// The hand being played, or nil between hands: the next hand has not been dealt yet.
    var round: Round?
    /// Where the wall was broken for this hand, when the wall is shown.
    var wallBreak: Int?
}

/// Keeps the saved game as a small JSON file in Application Support.
nonisolated enum GameSaver {
    static var url: URL {
        let folder = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return folder.appendingPathComponent("savedGame.json")
    }

    static func load(from url: URL = GameSaver.url) -> SavedGame? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(SavedGame.self, from: data)
    }

    static func save(_ game: SavedGame, to url: URL = GameSaver.url) {
        do {
            try FileManager.default.createDirectory(
                at: url.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try JSONEncoder().encode(game).write(to: url, options: .atomic)
        } catch {
            // A failed save only means the game can't be resumed later.
        }
    }

    static func clear(at url: URL = GameSaver.url) {
        try? FileManager.default.removeItem(at: url)
    }
}
