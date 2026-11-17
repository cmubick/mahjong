//
//  Haptics.swift
//  mahjong
//
//  Short taps for things that happen at the table, and a buzz for a win.
//

import UIKit
import AudioToolbox

enum Haptics {
    private static let selection = UISelectionFeedbackGenerator()
    private static let light = UIImpactFeedbackGenerator(style: .light)
    private static let medium = UIImpactFeedbackGenerator(style: .medium)
    private static let heavy = UIImpactFeedbackGenerator(style: .heavy)
    private static let notification = UINotificationFeedbackGenerator()

    /// The faintest tick: another player did something.
    static func tick() {
        selection.selectionChanged()
    }

    /// A light tap: you pressed a button or discarded a tile.
    static func tap() {
        light.impactOccurred()
    }

    /// A firmer tap: something that matters to you, like a call or a joker.
    static func thump() {
        medium.impactOccurred()
    }

    /// A move that is not allowed, or bad news.
    static func warning() {
        notification.notificationOccurred(.warning)
    }

    /// A buzz for Mahjong. Winning the whole game buzzes longer.
    static func victory(game: Bool) {
        notification.notificationOccurred(.success)
        let pulses = game ? 6 : 3
        Task { @MainActor in
            for _ in 0..<pulses {
                try? await Task.sleep(for: .milliseconds(110))
                heavy.impactOccurred(intensity: 1)
            }
            if game {
                // The long system vibration, on devices that have one.
                AudioServicesPlaySystemSound(kSystemSoundID_Vibrate)
            }
        }
    }
}
