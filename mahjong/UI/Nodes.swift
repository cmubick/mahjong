//
//  Nodes.swift
//  mahjong
//
//  The SpriteKit building blocks: tiles, buttons and the opponents' badges.
//

import SpriteKit

enum Style {
    static let felt = SKColor(red: 0.05, green: 0.30, blue: 0.20, alpha: 1)
    static let panel = SKColor(red: 0.04, green: 0.22, blue: 0.15, alpha: 1)
    static let gold = SKColor(red: 1.00, green: 0.82, blue: 0.30, alpha: 1)
    static let red = SKColor(red: 0.80, green: 0.13, blue: 0.15, alpha: 1)
    static let ink = SKColor(red: 0.10, green: 0.10, blue: 0.12, alpha: 1)
    static let ivory = SKColor(red: 0.99, green: 0.98, blue: 0.95, alpha: 1)
    static let faint = SKColor(white: 1, alpha: 0.75)

    static let regular = "AvenirNext-Medium"
    static let bold = "AvenirNext-Bold"

    static func label(_ text: String, size: CGFloat, font: String = Style.regular, color: SKColor = .white) -> SKLabelNode {
        let label = SKLabelNode(fontNamed: font)
        label.text = text
        label.fontSize = size
        label.fontColor = color
        label.verticalAlignmentMode = .center
        label.horizontalAlignmentMode = .center
        return label
    }
}

/// Where a tile node is on the table, so it knows where to go when it leaves.
enum TileArea: Equatable {
    case rack
    case exposure(Int)
    case pile
    /// Pictures of tiles inside a panel.
    case picture
}

final class TileNode: SKNode {
    let tile: Tile
    var area: TileArea = .rack
    /// Position in the player's rack, for tiles there.
    var rackIndex: Int?
    /// Which of its owner's exposures the tile is in, for tiles in an exposure.
    var group: Int?

    private let sprite: SKSpriteNode
    private let outline: SKShapeNode

    var isDimmed = false {
        didSet { updateTint() }
    }

    /// The tile you just drew: a warm gold face until you discard.
    var isNew = false {
        didSet { updateTint() }
    }

    private func updateTint() {
        if isDimmed {
            sprite.color = .black
            sprite.colorBlendFactor = 0.42
        } else if isNew {
            sprite.color = Style.gold
            sprite.colorBlendFactor = 0.38
        } else {
            sprite.colorBlendFactor = 0
        }
    }

    /// A gold border: selected in the rack, or the latest discard.
    var isHighlighted = false {
        didSet { outline.isHidden = !isHighlighted }
    }

    init(tile: Tile) {
        self.tile = tile
        sprite = SKSpriteNode(texture: TileArt.texture(for: tile), size: TileArt.size)
        outline = SKShapeNode(rectOf: CGSize(width: TileArt.size.width + 4, height: TileArt.size.height + 4), cornerRadius: 10)
        super.init()
        addChild(sprite)
        outline.strokeColor = Style.gold
        outline.lineWidth = 4
        outline.fillColor = .clear
        outline.zPosition = 1
        outline.isHidden = true
        addChild(outline)
    }

    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}

final class ButtonNode: SKNode {
    let action: () -> Void

    init(
        text: String,
        size: CGSize,
        fontSize: CGFloat,
        fill: SKColor = Style.gold,
        textColor: SKColor = Style.ink,
        outlined: Bool = true,
        action: @escaping () -> Void
    ) {
        self.action = action
        super.init()

        let shape = SKShapeNode(rectOf: size, cornerRadius: min(size.height / 2, 12))
        shape.fillColor = fill
        shape.strokeColor = outlined ? SKColor(white: 1, alpha: 0.35) : .clear
        shape.lineWidth = 1
        addChild(shape)

        let label = Style.label(text, size: fontSize, font: Style.bold, color: textColor)
        label.zPosition = 1
        addChild(label)
    }

    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    /// A quieter button for secondary choices.
    static func plain(text: String, size: CGSize, fontSize: CGFloat, selected: Bool = false, action: @escaping () -> Void) -> ButtonNode {
        ButtonNode(
            text: text, size: size, fontSize: fontSize,
            fill: selected ? Style.ivory : SKColor(white: 1, alpha: 0.12),
            textColor: selected ? Style.ink : .white,
            action: action
        )
    }
}

/// An opponent's name, seat wind, tile count and score.
final class BadgeNode: SKNode {
    private let shape: SKShapeNode
    private let nameLabel: SKLabelNode
    private let detailLabel: SKLabelNode

    init(size: CGSize, unit u: CGFloat) {
        shape = SKShapeNode(rectOf: size, cornerRadius: 10 * u)
        nameLabel = Style.label("", size: 15 * u, font: Style.bold)
        detailLabel = Style.label("", size: 11.5 * u, color: Style.faint)
        super.init()

        shape.fillColor = SKColor(white: 0, alpha: 0.25)
        addChild(shape)
        nameLabel.position = CGPoint(x: 0, y: 8 * u)
        detailLabel.position = CGPoint(x: 0, y: -10 * u)
        addChild(nameLabel)
        addChild(detailLabel)
    }

    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func update(name: String, detail: String, active: Bool) {
        nameLabel.text = name
        nameLabel.fontColor = active ? Style.gold : .white
        detailLabel.text = detail
        shape.strokeColor = active ? Style.gold : SKColor(white: 1, alpha: 0.2)
        shape.lineWidth = active ? 2.5 : 1
    }
}
