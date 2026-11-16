//
//  TileArt.swift
//  mahjong
//
//  Paints each tile once with Core Graphics and keeps it as a texture. The set ships
//  no images: every face is drawn here.
//

import SpriteKit
import UIKit

enum TileArt {
    /// The size a tile is painted at, in points. Nodes scale it to fit.
    static let size = CGSize(width: 60, height: 80)
    /// The darker edge along the bottom that makes a tile look thick.
    static let depth: CGFloat = 5

    static let ivory = UIColor(red: 0.99, green: 0.97, blue: 0.91, alpha: 1)
    static let edge = UIColor(red: 0.13, green: 0.47, blue: 0.40, alpha: 1)
    static let bamGreen = UIColor(red: 0.08, green: 0.50, blue: 0.26, alpha: 1)
    static let crakRed = UIColor(red: 0.78, green: 0.11, blue: 0.13, alpha: 1)
    static let dotBlue = UIColor(red: 0.11, green: 0.30, blue: 0.66, alpha: 1)
    static let ink = UIColor(red: 0.12, green: 0.12, blue: 0.16, alpha: 1)
    static let jokerPurple = UIColor(red: 0.47, green: 0.20, blue: 0.70, alpha: 1)

    private static var cache: [Int: SKTexture] = [:]
    private static var backTexture: SKTexture?

    static func texture(for tile: Tile) -> SKTexture {
        if let cached = cache[tile.index] { return cached }
        let texture = SKTexture(image: image(for: tile))
        cache[tile.index] = texture
        return texture
    }

    /// The back of a tile, for tiles nobody may see.
    static var back: SKTexture {
        if let backTexture { return backTexture }
        let renderer = UIGraphicsImageRenderer(size: size)
        let image = renderer.image { _ in
            drawBody(face: edge)
            let inner = UIBezierPath(roundedRect: faceRect.insetBy(dx: 6, dy: 6), cornerRadius: 5)
            ivory.withAlphaComponent(0.35).setStroke()
            inner.lineWidth = 1.5
            inner.stroke()
        }
        let texture = SKTexture(image: image)
        backTexture = texture
        return texture
    }

    static func suitColor(_ suit: Suit) -> UIColor {
        switch suit {
        case .bams: bamGreen
        case .craks: crakRed
        case .dots: dotBlue
        }
    }

    // MARK: - Painting

    private static var faceRect: CGRect {
        CGRect(x: 0, y: 0, width: size.width, height: size.height - depth)
    }

    /// Where the picture goes: below the corner number, inside a small margin.
    private static var artRect: CGRect {
        CGRect(x: 6, y: 13, width: size.width - 12, height: size.height - depth - 18)
    }

    private static func image(for tile: Tile) -> UIImage {
        UIGraphicsImageRenderer(size: size).image { context in
            drawBody(face: ivory)
            let cg = context.cgContext
            switch tile {
            case .number(let suit, let rank):
                corner(String(rank), color: suitColor(suit))
                switch suit {
                case .dots: drawDots(rank, in: cg)
                case .bams: drawBams(rank, in: cg)
                case .craks: drawCrak(rank)
                }
            case .wind(let wind):
                drawWind(wind)
            case .dragon(let dragon):
                drawDragon(dragon)
            case .flower:
                drawFlower(in: cg)
            case .joker:
                drawJoker()
            }
        }
    }

    private static func drawBody(face: UIColor) {
        let base = UIBezierPath(roundedRect: CGRect(x: 0, y: depth, width: size.width, height: size.height - depth), cornerRadius: 8)
        edge.setFill()
        base.fill()
        let top = UIBezierPath(roundedRect: faceRect.insetBy(dx: 0.5, dy: 0.5), cornerRadius: 8)
        face.setFill()
        top.fill()
        UIColor(white: 0, alpha: 0.18).setStroke()
        top.lineWidth = 1
        top.stroke()
    }

    private static func corner(_ text: String, color: UIColor) {
        draw(text, font: .systemFont(ofSize: 12, weight: .heavy), color: color,
             center: CGPoint(x: 9, y: 9))
    }

    private static func draw(_ text: String, font: UIFont, color: UIColor, center: CGPoint) {
        let attributes: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: color]
        let string = NSAttributedString(string: text, attributes: attributes)
        let bounds = string.size()
        string.draw(at: CGPoint(x: center.x - bounds.width / 2, y: center.y - bounds.height / 2))
    }

    private static func chinese(_ size: CGFloat) -> UIFont {
        UIFont(name: "PingFangTC-Semibold", size: size) ?? .systemFont(ofSize: size, weight: .semibold)
    }

    /// Positions in the picture area, as fractions of its width and height.
    private static func point(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
        CGPoint(x: artRect.minX + artRect.width * x, y: artRect.minY + artRect.height * y)
    }

    // MARK: Dots

    private static let dotLayouts: [[(CGFloat, CGFloat)]] = [
        [(0.5, 0.5)],
        [(0.5, 0.25), (0.5, 0.75)],
        [(0.22, 0.18), (0.5, 0.5), (0.78, 0.82)],
        [(0.28, 0.25), (0.72, 0.25), (0.28, 0.75), (0.72, 0.75)],
        [(0.25, 0.2), (0.75, 0.2), (0.5, 0.5), (0.25, 0.8), (0.75, 0.8)],
        [(0.28, 0.17), (0.72, 0.17), (0.28, 0.5), (0.72, 0.5), (0.28, 0.83), (0.72, 0.83)],
        [(0.2, 0.1), (0.5, 0.22), (0.8, 0.34), (0.28, 0.62), (0.72, 0.62), (0.28, 0.88), (0.72, 0.88)],
        [(0.28, 0.12), (0.72, 0.12), (0.28, 0.37), (0.72, 0.37), (0.28, 0.63), (0.72, 0.63), (0.28, 0.88), (0.72, 0.88)],
        [(0.2, 0.17), (0.5, 0.17), (0.8, 0.17), (0.2, 0.5), (0.5, 0.5), (0.8, 0.5), (0.2, 0.83), (0.5, 0.83), (0.8, 0.83)],
    ]

    private static func drawDots(_ rank: Int, in cg: CGContext) {
        let radii: [CGFloat] = [17, 11, 9.5, 10, 9, 8.5, 7, 6.6, 7.2]
        let radius = radii[rank - 1]
        for (index, spot) in dotLayouts[rank - 1].enumerated() {
            let center = point(spot.0, spot.1)
            // Traditional sets mix colors: the middle of a 5 and the low row of a 7 are red.
            let red = (rank == 5 && index == 2) || (rank == 7 && index >= 3) || (rank == 1)
            let outer = red ? crakRed : dotBlue
            fillCircle(center, radius, outer, in: cg)
            fillCircle(center, radius * 0.66, ivory, in: cg)
            fillCircle(center, radius * 0.4, rank == 1 ? bamGreen : outer, in: cg)
            if rank == 1 {
                fillCircle(center, radius * 0.18, ivory, in: cg)
            }
        }
    }

    private static func fillCircle(_ center: CGPoint, _ radius: CGFloat, _ color: UIColor, in cg: CGContext) {
        cg.setFillColor(color.cgColor)
        cg.fillEllipse(in: CGRect(x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2))
    }

    // MARK: Bams

    /// Rows of sticks for each rank, top row first.
    private static let bamRows: [[Int]] = [[1], [1, 1], [1, 2], [2, 2], [2, 1, 2], [3, 3], [1, 3, 3], [4, 4], [3, 3, 3]]

    private static func drawBams(_ rank: Int, in cg: CGContext) {
        let rows = bamRows[rank - 1]
        let rowHeight = artRect.height / CGFloat(rows.count)
        for (rowIndex, sticks) in rows.enumerated() {
            let y = artRect.minY + rowHeight * (CGFloat(rowIndex) + 0.5)
            let columnWidth = artRect.width / CGFloat(max(sticks, 3))
            let rowWidth = columnWidth * CGFloat(sticks)
            for stick in 0..<sticks {
                let x = artRect.midX - rowWidth / 2 + columnWidth * (CGFloat(stick) + 0.5)
                let height = rank == 1 ? artRect.height * 0.9 : rowHeight * 0.86
                let width = rank == 1 ? 16 : min(columnWidth * 0.5, 8.5)
                // Mix in a red stick where traditional sets have one.
                let red = (rank == 5 && rowIndex == 1) || (rank == 7 && rowIndex == 0) || (rank == 9 && stick == 1)
                drawStick(center: CGPoint(x: x, y: y), size: CGSize(width: width, height: height),
                          color: red ? crakRed : bamGreen, in: cg)
            }
        }
    }

    private static func drawStick(center: CGPoint, size: CGSize, color: UIColor, in cg: CGContext) {
        let rect = CGRect(x: center.x - size.width / 2, y: center.y - size.height / 2, width: size.width, height: size.height)
        let path = UIBezierPath(roundedRect: rect, cornerRadius: size.width / 2)
        color.setFill()
        path.fill()
        // The joints of the bamboo.
        cg.setStrokeColor(ivory.withAlphaComponent(0.85).cgColor)
        cg.setLineWidth(1.2)
        for fraction in [0.5] as [CGFloat] {
            let y = rect.minY + rect.height * fraction
            cg.move(to: CGPoint(x: rect.minX + 1, y: y))
            cg.addLine(to: CGPoint(x: rect.maxX - 1, y: y))
        }
        cg.strokePath()
        cg.setStrokeColor(ivory.withAlphaComponent(0.6).cgColor)
        cg.setLineWidth(1)
        cg.move(to: CGPoint(x: rect.midX, y: rect.minY + 3))
        cg.addLine(to: CGPoint(x: rect.midX, y: rect.maxY - 3))
        cg.strokePath()
    }

    // MARK: Craks, winds, dragons

    private static let numerals = ["一", "二", "三", "四", "五", "六", "七", "八", "九"]

    private static func drawCrak(_ rank: Int) {
        draw(numerals[rank - 1], font: chinese(24), color: ink, center: point(0.5, 0.24))
        draw("萬", font: chinese(27), color: crakRed, center: point(0.5, 0.72))
    }

    private static func drawWind(_ wind: Wind) {
        let character: String
        switch wind {
        case .north: character = "北"
        case .east: character = "東"
        case .west: character = "西"
        case .south: character = "南"
        }
        draw(wind.letter, font: .systemFont(ofSize: 30, weight: .heavy), color: ink, center: point(0.5, 0.3))
        draw(character, font: chinese(20), color: dotBlue, center: point(0.5, 0.8))
    }

    private static func drawDragon(_ dragon: Dragon) {
        switch dragon {
        case .red:
            draw("中", font: chinese(40), color: crakRed, center: point(0.5, 0.45))
        case .green:
            draw("發", font: chinese(36), color: bamGreen, center: point(0.5, 0.45))
        case .white:
            // Soap: an empty blue frame.
            let frame = faceRect.insetBy(dx: 9, dy: 10)
            let outer = UIBezierPath(roundedRect: frame, cornerRadius: 4)
            dotBlue.setStroke()
            outer.lineWidth = 4
            outer.stroke()
            let inner = UIBezierPath(roundedRect: frame.insetBy(dx: 6, dy: 6), cornerRadius: 2)
            inner.lineWidth = 1.5
            inner.stroke()
        }
    }

    // MARK: Flower and joker

    private static func drawFlower(in cg: CGContext) {
        let center = point(0.5, 0.4)
        // The stem and a leaf.
        cg.setStrokeColor(bamGreen.cgColor)
        cg.setLineWidth(2.5)
        cg.move(to: center)
        cg.addQuadCurve(to: point(0.45, 1.0), control: point(0.58, 0.75))
        cg.strokePath()
        cg.setFillColor(bamGreen.cgColor)
        cg.fillEllipse(in: CGRect(x: point(0.5, 0.75).x, y: point(0.5, 0.75).y - 4, width: 13, height: 7))

        let petal = UIColor(red: 0.93, green: 0.42, blue: 0.58, alpha: 1)
        for index in 0..<5 {
            cg.saveGState()
            cg.translateBy(x: center.x, y: center.y)
            cg.rotate(by: CGFloat(index) * .pi * 2 / 5)
            cg.setFillColor(petal.cgColor)
            cg.fillEllipse(in: CGRect(x: -5.5, y: -19, width: 11, height: 16))
            cg.restoreGState()
        }
        fillCircle(center, 5.5, UIColor(red: 0.98, green: 0.78, blue: 0.20, alpha: 1), in: cg)
    }

    private static func drawJoker() {
        draw("★", font: .systemFont(ofSize: 30, weight: .bold), color: UIColor(red: 0.95, green: 0.70, blue: 0.15, alpha: 1),
             center: point(0.5, 0.32))
        draw("JOKER", font: .systemFont(ofSize: 12.5, weight: .black), color: jokerPurple, center: point(0.5, 0.82))
    }
}
