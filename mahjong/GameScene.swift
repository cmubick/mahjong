//
//  GameScene.swift
//  mahjong
//
//  Placeholder table. The real table comes after the rules engine.
//

import SpriteKit

class GameScene: SKScene {

    override func didMove(to view: SKView) {
        backgroundColor = UIColor(red: 0.05, green: 0.30, blue: 0.20, alpha: 1)
        layout()
    }

    override func didChangeSize(_ oldSize: CGSize) {
        layout()
    }

    private func layout() {
        removeAllChildren()
        let title = SKLabelNode(text: "Mahjong")
        title.fontName = "AvenirNext-Bold"
        title.fontSize = 40
        title.position = CGPoint(x: size.width / 2, y: size.height / 2)
        addChild(title)

        let card = Card.practice
        let note = SKLabelNode(text: "\(card.title): \(card.hands.count) hands")
        note.fontName = "AvenirNext-Regular"
        note.fontSize = 18
        note.position = CGPoint(x: size.width / 2, y: size.height / 2 - 40)
        addChild(note)
    }
}
