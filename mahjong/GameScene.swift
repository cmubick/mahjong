//
//  GameScene.swift
//  mahjong
//
//  The table: your rack at the bottom, the other three players' exposures at the top
//  and the discards in between. The rules live in Rules/; this file only draws them
//  and turns taps into moves.
//

import SpriteKit

final class GameScene: SKScene {

    // MARK: - State

    var safeInsets: UIEdgeInsets = .zero {
        didSet { if safeInsets != oldValue { relayout() } }
    }

    /// Player 0 holds the phone. Play passes to the right: You → Right → Across → Left.
    private let names = ["You", "Right", "Across", "Left"]

    private enum Overlay {
        case card(page: Int)
        case summary(payments: [Int])
        case gameMenu
    }

    private var match = Match(card: .practice)
    private var round: Round?
    private var generator = SystemRandomNumberGenerator()
    /// Positions in your rack that you have picked, for a pass or a discard.
    private var selection: Set<Int> = []
    private var eventText = ""
    private var overlay: Overlay?
    /// Bumped whenever a game starts, so timers from an old game do nothing.
    private var generation = 0
    /// Bumped on every move, so a bot never moves twice on one timer.
    private var step = 0
    private var isSetUp = false
    /// Whether the finished hand's payments are already in the scores.
    private var roundRecorded = false
    /// Debug: the bots play your seat too.
    private var autoplay = false
    /// Where tiles you pass go, and where tiles passed to you come from, for the next redraw.
    private var passExit: CGPoint?
    private var passSpawn: CGPoint?

    // MARK: - Nodes

    private var tileNodes: [TileNode] = []
    private let tileLayer = SKNode()
    private let hudLayer = SKNode()
    private let controlLayer = SKNode()
    private let overlayLayer = SKNode()
    private var badges: [Int: BadgeNode] = [:]
    private var eventLabel = SKLabelNode()
    private var promptLabel = SKLabelNode()
    private var infoLabel = SKLabelNode()

    // MARK: - Layout

    private struct Metrics {
        let size: CGSize
        let u: CGFloat
        /// The width everything is laid out in, centered on the screen.
        let width: CGFloat
        let left: CGFloat

        let rackTile: CGFloat
        let rackGap: CGFloat
        let rackBottomRowY: CGFloat
        let rackRowStep: CGFloat
        let exposureTile: CGFloat
        let exposureY: CGFloat
        let buttonY: CGFloat
        let buttonHeight: CGFloat
        let infoY: CGFloat
        let promptY: CGFloat
        let eventY: CGFloat

        /// The other players sit in rows at the top: Right, then Across, then Left.
        let opponentRowY: [Int: CGFloat]
        let badgeSize: CGSize
        let opponentTile: CGFloat

        let pileTop: CGFloat
        let pileBottom: CGFloat
        let pileTile: CGFloat
        let pilePerRow = 14

        init(size: CGSize, insets: UIEdgeInsets) {
            self.size = size
            let u = min(size.width / 390, size.height / 844)
            self.u = u
            width = min(size.width - 24 * u, 560 * u)
            left = (size.width - width) / 2

            rackGap = 4 * u
            rackTile = min((width - 6 * rackGap) / 7, 54 * u)
            let rackHeight = rackTile * 4 / 3
            rackBottomRowY = insets.bottom + 8 * u + rackHeight / 2
            rackRowStep = rackHeight + 5 * u
            let rackTop = rackBottomRowY + rackRowStep + rackHeight / 2

            exposureTile = min((width - 24 * u) / 14, 30 * u)
            exposureY = rackTop + 14 * u + exposureTile * 2 / 3
            buttonHeight = 40 * u
            buttonY = exposureY + exposureTile * 2 / 3 + 10 * u + buttonHeight / 2
            infoY = buttonY + buttonHeight / 2 + 14 * u
            promptY = infoY + 24 * u
            eventY = promptY + 24 * u

            badgeSize = CGSize(width: 92 * u, height: 40 * u)
            let firstRow = size.height - insets.top - 8 * u - badgeSize.height / 2
            let rowStep = badgeSize.height + 6 * u
            opponentRowY = [1: firstRow, 2: firstRow - rowStep, 3: firstRow - rowStep * 2]
            opponentTile = min((width - badgeSize.width - 8 * u - 12 * u) / 14, 22 * u)

            pileTop = firstRow - rowStep * 2 - badgeSize.height / 2 - 10 * u
            pileBottom = eventY + 14 * u
            pileTile = min((width - 20 * u - 13 * 2 * u) / 14, 26 * u)
        }

        func badge(_ player: Int) -> CGPoint {
            CGPoint(x: left + badgeSize.width / 2, y: opponentRowY[player] ?? 0)
        }

        /// Where tiles come from when drawn from the wall.
        var wall: CGPoint {
            CGPoint(x: size.width / 2, y: (pileTop + pileBottom) / 2)
        }

        func rackPosition(_ index: Int, count: Int) -> CGPoint {
            let row = index / 7
            let rows = (count + 6) / 7
            let inRow = row == rows - 1 ? count - row * 7 : 7
            let column = index % 7
            let rowWidth = CGFloat(inRow) * rackTile + CGFloat(inRow - 1) * rackGap
            let x = size.width / 2 - rowWidth / 2 + rackTile / 2 + CGFloat(column) * (rackTile + rackGap)
            let y = rackBottomRowY + CGFloat(rows - 1 - row) * rackRowStep
            return CGPoint(x: x, y: y)
        }

        func pilePosition(_ index: Int) -> CGPoint {
            let step = pileTile + 2 * u
            let rowWidth = CGFloat(pilePerRow) * step - 2 * u
            let x = size.width / 2 - rowWidth / 2 + pileTile / 2 + CGFloat(index % pilePerRow) * step
            let y = pileTop - 6 * u - pileTile * 2 / 3 - CGFloat(index / pilePerRow) * (pileTile * 4 / 3 + 2 * u)
            return CGPoint(x: x, y: y)
        }
    }

    private var metrics: Metrics { Metrics(size: size, insets: safeInsets) }

    // MARK: - Scene life cycle

    override func didMove(to view: SKView) {
        backgroundColor = Style.felt
        tileLayer.zPosition = 10
        hudLayer.zPosition = 5
        controlLayer.zPosition = 300
        overlayLayer.zPosition = 1000
        addChild(tileLayer)
        addChild(hudLayer)
        addChild(controlLayer)
        addChild(overlayLayer)
        isSetUp = true

        let arguments = CommandLine.arguments
        #if DEBUG
        autoplay = arguments.contains("-autoplay")
        if let index = arguments.firstIndex(of: "-scenario"), arguments.indices.contains(index + 1),
           arguments[index + 1] == "tiles" {
            relayout()
            showAllTiles()
            return
        }
        #endif
        startMatch()
    }

    override func didChangeSize(_ oldSize: CGSize) {
        relayout()
    }

    private func relayout() {
        guard isSetUp else { return }
        let m = metrics

        hudLayer.removeAllChildren()
        badges = [:]
        for player in 1...3 {
            let badge = BadgeNode(size: m.badgeSize, unit: m.u)
            badge.position = m.badge(player)
            hudLayer.addChild(badge)
            badges[player] = badge
        }

        // A faint frame around the discards.
        let pile = SKShapeNode(rectOf: CGSize(width: m.width, height: m.pileTop - m.pileBottom + 8 * m.u), cornerRadius: 12 * m.u)
        pile.position = CGPoint(x: size.width / 2, y: (m.pileTop + m.pileBottom) / 2)
        pile.fillColor = SKColor(white: 0, alpha: 0.12)
        pile.strokeColor = SKColor(white: 1, alpha: 0.08)
        hudLayer.addChild(pile)

        eventLabel = Style.label("", size: 14 * m.u, color: Style.faint)
        eventLabel.position = CGPoint(x: size.width / 2, y: m.eventY)
        promptLabel = Style.label("", size: 17 * m.u, font: Style.bold)
        promptLabel.position = CGPoint(x: size.width / 2, y: m.promptY)
        infoLabel = Style.label("", size: 13 * m.u, color: Style.faint)
        infoLabel.position = CGPoint(x: size.width / 2, y: m.infoY)
        hudLayer.addChild(eventLabel)
        hudLayer.addChild(promptLabel)
        hudLayer.addChild(infoLabel)

        sync(animated: false)
        refreshHUD()
        rebuildOverlay()
    }

    // MARK: - Game flow

    private func startMatch() {
        generation += 1
        match = Match(settings: MatchSettings(length: .standard), card: .practice)
        overlay = nil
        startRound()
    }

    private func startRound() {
        generation += 1
        tileNodes.forEach { $0.removeFromParent() }
        tileNodes = []
        selection = []
        roundRecorded = false
        let next = match.dealRound(using: &generator)
        round = next
        let dealer = next.dealer == 0 ? "You are East and deal" : "\(names[next.dealer]) is East and deals"
        eventText = "Hand \(match.handsPlayed + 1) of \(match.settings.length.hands). \(dealer)."
        advance()
    }

    /// Redraws, then lets a bot move if one is due.
    private func advance() {
        sync(animated: true)
        refreshHUD()
        guard let round else { return }
        if round.outcome != nil {
            after(1.4) { [weak self] in self?.finishRound() }
            return
        }
        guard let actor = round.actors.first(where: { $0 != 0 || autoplay }) else { return }
        let delay: TimeInterval
        switch round.phase {
        case .discard: delay = 0.85
        case .claim: delay = 0.3
        default: delay = 0.15
        }
        let token = step
        after(delay) { [weak self] in
            guard let self, self.step == token, let round = self.round, round.actors.contains(actor),
                  let move = Bot.chooseMove(in: round, for: actor) else { return }
            self.perform(move, by: actor)
        }
    }

    private func perform(_ move: Round.Move, by actor: Int) {
        guard var next = round else { return }
        let before = next
        do {
            try next.apply(move, by: actor)
        } catch {
            return
        }
        if let text = describe(move, by: actor, before: before, after: next) {
            eventText = text
        }
        setPassHints(before: before, after: next)
        round = next
        // Bots answer the Charleston while you choose, so keep your picks until your
        // rack or the phase changes.
        if next.phase != before.phase || next.hands[0] != before.hands[0] {
            selection = []
        }
        step += 1
        advance()
    }

    private func finishRound() {
        guard let round, round.outcome != nil, !roundRecorded else { return }
        roundRecorded = true
        let payments = match.record(round)
        overlay = .summary(payments: payments)
        refreshHUD()
        rebuildOverlay()
    }

    private func after(_ seconds: TimeInterval, _ body: @escaping () -> Void) {
        let token = generation
        Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(seconds))
            guard let self, self.generation == token else { return }
            body()
        }
    }

    // MARK: - Describing moves

    private func describe(_ move: Round.Move, by actor: Int, before: Round, after: Round) -> String? {
        let who = names[actor]
        var text: String?
        switch move {
        case .pass(let tiles):
            if case .charleston(let pass) = before.phase, after.phase != before.phase {
                text = "Passed \(pass.direction). You got \(received(before: before, after: after, passed: passedByYou(before, move: move, actor: actor, fallback: tiles)))."
            } else if case .courtesyPass = before.phase, after.phase != before.phase {
                if before.courtesyCounts[0] > 0 {
                    text = "Courtesy pass done. You got \(received(before: before, after: after, passed: passedByYou(before, move: move, actor: actor, fallback: tiles)))."
                } else {
                    text = "The others swapped tiles across."
                }
            }
        case .vote:
            if after.phase != before.phase {
                text = after.phase == .charleston(.secondLeft) ? "Everyone wants a second Charleston." : "No second Charleston."
            }
        case .offer:
            if after.phase != before.phase {
                let count = after.courtesyCounts[0]
                text = count == 0 ? "No courtesy pass for you." : "You and Across swap \(count) tile\(count == 1 ? "" : "s")."
            }
        case .discard(let tile):
            text = "\(who) discarded \(tile)"
        case .call:
            // Reported below, once every player has answered.
            break
        case .swapJoker(let owner, let index):
            let tile = before.exposures[owner][index].tile
            text = "\(who) traded a \(tile) for a joker"
        case .mahjong:
            if case .discard = before.phase { text = "\(who) called Mahjong!" }
        case .decline:
            break
        }

        // Claims settle when the last player answers, so report what happened then.
        if case .claim(let discard) = before.phase, after.phase != before.phase {
            if case .discard(let caller) = after.phase, after.drawn == nil,
               let count = after.exposures[caller].last?.count,
               after.exposures[caller].count > before.exposures[caller].count {
                text = "\(names[caller]) called the \(discard.tile) for a \(groupName(count))"
            } else if case .over(.mahjong(let win)) = after.phase {
                text = "\(names[win.winner]) called Mahjong on the \(discard.tile)!"
            } else if case .over(.wallGame) = after.phase {
                text = "The wall is empty."
            } else {
                text = "\(names[discard.player]) discarded \(discard.tile)"
            }
        }
        if case .discard(0) = after.phase, let drawn = after.drawn, after.phase != before.phase {
            text = (text.map { $0 + ". " } ?? "") + "You drew \(drawn)."
        }
        return text
    }

    private func groupName(_ count: Int) -> String {
        switch count {
        case 3: "pung"
        case 4: "kong"
        default: "quint"
        }
    }

    private func passedByYou(_ before: Round, move: Round.Move, actor: Int, fallback: [Tile]) -> [Tile] {
        if actor == 0 { return fallback }
        if case .pass(let tiles)? = before.answers[0] { return tiles }
        return []
    }

    private func received(before: Round, after: Round, passed: [Tile]) -> String {
        var remaining = TileCounts(before.hands[0])
        for tile in passed { remaining[tile] -= 1 }
        let now = TileCounts(after.hands[0])
        var got: [Tile] = []
        for index in 0..<Tile.kindCount {
            let extra = now[index] - remaining[index]
            if extra > 0 {
                got += Array(repeating: Tile(index: index), count: extra)
            }
        }
        return got.map(\.description).joined(separator: ", ")
    }

    /// When you pass tiles, they fly to whoever gets them and the new ones come from
    /// whoever sent them.
    private func setPassHints(before: Round, after: Round) {
        guard after.phase != before.phase else { return }
        let offset: Int
        switch before.phase {
        case .charleston(let pass): offset = pass.offset
        case .courtesyPass where before.courtesyCounts[0] > 0: offset = 2
        default: return
        }
        let m = metrics
        passExit = m.badge(offset % 4)
        passSpawn = m.badge((4 - offset) % 4)
    }

    // MARK: - Drawing the tiles

    private struct Placement {
        let tile: Tile
        let area: TileArea
        let position: CGPoint
        let width: CGFloat
        let z: CGFloat
        var highlighted = false
        var dimmed = false
        var rackIndex: Int?
        var group: Int?
    }

    private func placements(for round: Round, m: Metrics) -> [Placement] {
        var result: [Placement] = []

        // Discards, oldest first. The latest one glows while it can be called.
        let claimable: Round.Discard? = {
            if case .claim(let discard) = round.phase { return discard }
            return nil
        }()
        for (index, discard) in round.discards.enumerated() {
            var placement = Placement(
                tile: discard.tile, area: .pile, position: m.pilePosition(index),
                width: m.pileTile, z: CGFloat(index)
            )
            placement.highlighted = claimable != nil && index == round.discards.count - 1
            result.append(placement)
        }

        // The other players' exposures, beside their badges.
        let swappable = swappableJokers(in: round)
        for player in 1...3 {
            let tiles = round.exposures[player].map(\.tiles)
            let available = m.width - m.badgeSize.width - 8 * m.u
            let count = tiles.reduce(0) { $0 + $1.count }
            let gap = 4 * m.u
            let width = count == 0 ? m.opponentTile
                : min(m.opponentTile * 1.25, (available - gap * CGFloat(max(tiles.count - 1, 0))) / CGFloat(count))
            var x = m.left + m.badgeSize.width + 8 * m.u + width / 2
            let y = m.opponentRowY[player] ?? 0
            for (groupIndex, group) in tiles.enumerated() {
                for tile in group {
                    var placement = Placement(tile: tile, area: .exposure(player), position: CGPoint(x: x, y: y),
                                              width: width, z: 200 + x / 10)
                    placement.highlighted = tile == .joker && swappable.contains(where: { $0.owner == player && $0.index == groupIndex })
                    placement.group = groupIndex
                    result.append(placement)
                    x += width
                }
                x += gap
            }
        }

        // Your own exposures, in a row above your rack.
        let mine = round.exposures[0].map(\.tiles)
        let myCount = mine.reduce(0) { $0 + $1.count }
        if myCount > 0 {
            let gap = 6 * m.u
            let rowWidth = CGFloat(myCount) * m.exposureTile + gap * CGFloat(mine.count - 1)
            var x = size.width / 2 - rowWidth / 2 + m.exposureTile / 2
            for (groupIndex, group) in mine.enumerated() {
                for tile in group {
                    var placement = Placement(tile: tile, area: .exposure(0), position: CGPoint(x: x, y: m.exposureY),
                                              width: m.exposureTile, z: 200 + x / 10)
                    placement.highlighted = tile == .joker && swappable.contains(where: { $0.owner == 0 && $0.index == groupIndex })
                    placement.group = groupIndex
                    result.append(placement)
                    x += m.exposureTile
                }
                x += gap
            }
        }

        // Your rack, in rows of seven.
        let hand = round.hands[0]
        let passing = isPassing(round)
        for (index, tile) in hand.enumerated() {
            let selected = selection.contains(index)
            var position = m.rackPosition(index, count: hand.count)
            if selected { position.y += 12 * m.u }
            var placement = Placement(tile: tile, area: .rack, position: position, width: m.rackTile,
                                      z: 400 + CGFloat(index) * 2)
            placement.highlighted = selected
            placement.dimmed = passing && tile == .joker
            placement.rackIndex = index
            result.append(placement)
        }
        return result
    }

    /// Lays the tiles out where they belong. Tiles are not unique, so each node goes to
    /// the nearest spot for its kind of tile; that way a discard slides from the rack to
    /// the pile instead of every tile jumping.
    private func sync(animated: Bool) {
        guard let round else {
            tileNodes.forEach { $0.removeFromParent() }
            tileNodes = []
            return
        }
        let m = metrics
        let targets = placements(for: round, m: m)

        var unused: [Int: [TileNode]] = Dictionary(grouping: tileNodes, by: { $0.tile.index })
        var assigned: [(TileNode, Placement, Bool)] = []

        for (kind, kindTargets) in Dictionary(grouping: targets, by: { $0.tile.index }) {
            let nodes = unused[kind] ?? []
            let open = kindTargets
            var pairs: [(node: Int, target: Int, distance: CGFloat)] = []
            for (n, node) in nodes.enumerated() {
                for (t, target) in open.enumerated() {
                    let dx = node.position.x - target.position.x
                    let dy = node.position.y - target.position.y
                    pairs.append((n, t, dx * dx + dy * dy))
                }
            }
            pairs.sort { $0.distance < $1.distance }
            var usedNodes = Set<Int>()
            var usedTargets = Set<Int>()
            for pair in pairs where !usedNodes.contains(pair.node) && !usedTargets.contains(pair.target) {
                usedNodes.insert(pair.node)
                usedTargets.insert(pair.target)
                assigned.append((nodes[pair.node], open[pair.target], false))
            }
            for (t, target) in open.enumerated() where !usedTargets.contains(t) {
                let node = TileNode(tile: target.tile)
                node.position = spawnPoint(for: target, in: round, m: m)
                node.setScale(target.width / TileArt.size.width)
                node.alpha = animated ? 0 : 1
                tileLayer.addChild(node)
                assigned.append((node, target, true))
            }
            unused[kind] = nodes.enumerated().filter { !usedNodes.contains($0.offset) }.map(\.element)
        }

        // Tiles that left the table: passed away, or a joker someone took.
        for node in unused.values.flatMap({ $0 }) {
            let exit = exitPoint(for: node, m: m)
            node.isHighlighted = false
            if animated {
                node.run(.sequence([
                    .group([.move(to: exit, duration: 0.35), .fadeOut(withDuration: 0.35)]),
                    .removeFromParent(),
                ]))
            } else {
                node.removeFromParent()
            }
        }

        tileNodes = assigned.map(\.0)
        for (node, placement, isNew) in assigned {
            node.area = placement.area
            node.rackIndex = placement.rackIndex
            node.group = placement.group
            node.zPosition = placement.z
            node.isHighlighted = placement.highlighted
            node.isDimmed = placement.dimmed
            let scale = placement.width / TileArt.size.width
            node.removeAction(forKey: "move")
            if animated {
                let move = SKAction.group([
                    .move(to: placement.position, duration: 0.3),
                    .scale(to: scale, duration: 0.3),
                    .fadeIn(withDuration: isNew ? 0.25 : 0),
                ])
                move.timingMode = .easeOut
                node.run(move, withKey: "move")
            } else {
                node.position = placement.position
                node.setScale(scale)
                node.alpha = 1
            }
        }
        passExit = nil
        passSpawn = nil
    }

    private func spawnPoint(for placement: Placement, in round: Round, m: Metrics) -> CGPoint {
        switch placement.area {
        case .rack: return passSpawn ?? m.wall
        case .exposure(let player): return player == 0 ? m.wall : m.badge(player)
        case .pile:
            let discarder = round.discards.last?.player ?? 0
            return discarder == 0 ? m.wall : m.badge(discarder)
        case .picture: return placement.position
        }
    }

    private func exitPoint(for node: TileNode, m: Metrics) -> CGPoint {
        switch node.area {
        case .rack: return passExit ?? m.wall
        case .exposure(let player): return player == 0 ? m.wall : m.badge(player)
        case .pile, .picture: return m.wall
        }
    }

    // MARK: - What you may do

    private func isPassing(_ round: Round) -> Bool {
        guard round.actors.contains(0) else { return false }
        switch round.phase {
        case .charleston, .courtesyPass: return true
        default: return false
        }
    }

    private var tilesToPass: Int {
        guard let round else { return 0 }
        switch round.phase {
        case .charleston: return Round.passSize
        case .courtesyPass: return round.courtesyCounts[0]
        default: return 0
        }
    }

    private func swappableJokers(in round: Round) -> [(owner: Int, index: Int)] {
        guard case .discard(0) = round.phase, !autoplay else { return [] }
        return round.legalMoves(for: 0).compactMap { move in
            if case .swapJoker(let owner, let index) = move { return (owner, index) }
            return nil
        }
    }

    private var selectedTiles: [Tile] {
        guard let round else { return [] }
        return selection.sorted().map { round.hands[0][$0] }
    }

    // MARK: - Labels, badges and buttons

    private func refreshHUD() {
        guard isSetUp else { return }
        let m = metrics
        controlLayer.removeAllChildren()
        guard let round else {
            eventLabel.text = ""
            promptLabel.text = ""
            infoLabel.text = ""
            return
        }

        for player in 1...3 {
            let active: Bool
            if case .discard(let turn) = round.phase { active = turn == player } else { active = false }
            let wind = windName(round.seatWind(of: player))
            let detail = "\(wind) · \(round.hands[player].count) · \(match.scores[player])"
            badges[player]?.update(name: names[player], detail: detail, active: active)
        }

        eventLabel.text = eventText
        promptLabel.fontColor = .white
        promptLabel.text = prompt(for: round)

        var info = "\(windName(round.seatWind(of: 0))) · \(match.scores[0]) pts · Wall \(round.wall.count)"
        if let closest = Bot.closest(TileCounts(round.hands[0]), exposures: round.exposures[0], card: round.card).first {
            info += closest.needed == 0 ? " · Mahjong!" : " · Closest hand: \(closest.needed) away"
        }
        infoLabel.text = info

        // Card on the left, menu on the right, this moment's choices in between.
        let small = CGSize(width: 64 * m.u, height: m.buttonHeight)
        let cardButton = ButtonNode.plain(text: "Card", size: small, fontSize: 14 * m.u) { [weak self] in
            self?.overlay = .card(page: 0)
            self?.rebuildOverlay()
        }
        cardButton.position = CGPoint(x: m.left + small.width / 2, y: m.buttonY)
        controlLayer.addChild(cardButton)

        let menuSize = CGSize(width: 46 * m.u, height: m.buttonHeight)
        let menuButton = ButtonNode.plain(text: "☰", size: menuSize, fontSize: 18 * m.u) { [weak self] in
            self?.overlay = .gameMenu
            self?.rebuildOverlay()
        }
        menuButton.position = CGPoint(x: m.left + m.width - menuSize.width / 2, y: m.buttonY)
        controlLayer.addChild(menuButton)

        let actions = autoplay ? [] : choices(for: round)
        guard !actions.isEmpty else { return }
        let space = m.width - small.width - menuSize.width - 16 * m.u
        let gap = 6 * m.u
        let buttonWidth = min((space - gap * CGFloat(actions.count - 1)) / CGFloat(actions.count), 130 * m.u)
        let total = buttonWidth * CGFloat(actions.count) + gap * CGFloat(actions.count - 1)
        var x = m.left + small.width + 8 * m.u + (space - total) / 2 + buttonWidth / 2
        for choice in actions {
            let buttonSize = CGSize(width: buttonWidth, height: m.buttonHeight)
            let button: ButtonNode
            if choice.primary {
                button = ButtonNode(text: choice.title, size: buttonSize, fontSize: 14 * m.u, action: choice.action)
            } else {
                button = ButtonNode.plain(text: choice.title, size: buttonSize, fontSize: 14 * m.u, action: choice.action)
            }
            button.position = CGPoint(x: x, y: m.buttonY)
            if !choice.enabled { button.alpha = 0.4 }
            controlLayer.addChild(button)
            x += buttonWidth + gap
        }
    }

    private func windName(_ wind: Wind) -> String {
        switch wind {
        case .north: "North"
        case .east: "East"
        case .west: "West"
        case .south: "South"
        }
    }

    private func prompt(for round: Round) -> String {
        guard round.actors.contains(0), !autoplay else {
            switch round.phase {
            case .discard(let player): return player == 0 ? "Your turn" : "\(names[player])'s turn"
            case .claim: return ""
            case .over: return ""
            default: return "Waiting for the others…"
            }
        }
        switch round.phase {
        case .charleston(let pass):
            return "Choose 3 tiles to pass \(pass.direction) (\(selection.count)/3)"
        case .vote:
            return "Do a second Charleston?"
        case .courtesyOffer:
            return "Courtesy pass with Across: how many?"
        case .courtesyPass:
            let count = round.courtesyCounts[0]
            return "Choose \(count) tile\(count == 1 ? "" : "s") to pass across (\(selection.count)/\(count))"
        case .discard:
            if round.legalMoves(for: 0).contains(.mahjong) { return "You have Mahjong!" }
            if !selection.isEmpty { return "Tap it again to discard" }
            return swappableJokers(in: round).isEmpty
                ? "Your turn: pick a tile to discard"
                : "Discard, or tap a glowing joker to take it"
        case .claim(let discard):
            return "\(names[discard.player]) threw the \(discard.tile). Call it?"
        case .over:
            return ""
        }
    }

    private struct Choice {
        let title: String
        var primary = false
        var enabled = true
        let action: () -> Void
    }

    private func choices(for round: Round) -> [Choice] {
        guard round.actors.contains(0) else { return [] }
        let moves = round.legalMoves(for: 0)
        let act: (Round.Move) -> () -> Void = { move in { [weak self] in self?.perform(move, by: 0) } }

        switch round.phase {
        case .charleston, .courtesyPass:
            let ready = selection.count == tilesToPass
            return [Choice(title: "Pass", primary: true, enabled: ready) { [weak self] in
                guard let self, ready else { return }
                self.perform(.pass(self.selectedTiles), by: 0)
            }]
        case .vote:
            return [Choice(title: "Yes", primary: true, action: act(.vote(true))),
                    Choice(title: "No", action: act(.vote(false)))]
        case .courtesyOffer:
            return (0...Round.maxCourtesy).map { Choice(title: "\($0)", primary: $0 == 0, action: act(.offer($0))) }
        case .discard:
            var result: [Choice] = []
            if moves.contains(.mahjong) {
                result.append(Choice(title: "Mahjong!", primary: true, action: act(.mahjong)))
            }
            if let index = selection.first {
                let tile = round.hands[0][index]
                result.append(Choice(title: "Discard", primary: !moves.contains(.mahjong), action: act(.discard(tile))))
            }
            return result
        case .claim:
            var result: [Choice] = []
            if moves.contains(.mahjong) {
                result.append(Choice(title: "Mahjong!", primary: true, action: act(.mahjong)))
            }
            for move in moves {
                if case .call(let count) = move {
                    result.append(Choice(title: groupName(count).capitalized, primary: result.isEmpty, action: act(move)))
                }
            }
            result.append(Choice(title: "Pass", action: act(.decline)))
            return result
        case .over:
            return []
        }
    }

    // MARK: - Touches

    private func ancestor<T: SKNode>(of node: SKNode, as type: T.Type) -> T? {
        var current: SKNode? = node
        while let candidate = current {
            if let match = candidate as? T { return match }
            current = candidate.parent
        }
        return nil
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let touch = touches.first else { return }
        let hits = nodes(at: touch.location(in: self))

        if overlay != nil {
            let button = hits.lazy
                .compactMap { self.ancestor(of: $0, as: ButtonNode.self) }
                .first { $0.inParentHierarchy(self.overlayLayer) }
            button?.action()
            return
        }
        if let button = hits.lazy.compactMap({ self.ancestor(of: $0, as: ButtonNode.self) }).first {
            button.action()
            return
        }
        let tiles = hits.compactMap { ancestor(of: $0, as: TileNode.self) }
        guard let top = tiles.max(by: { $0.zPosition < $1.zPosition }) else {
            if !selection.isEmpty {
                selection = []
                sync(animated: true)
                refreshHUD()
            }
            return
        }
        tapped(top)
    }

    private func tapped(_ node: TileNode) {
        guard let round, round.actors.contains(0), !autoplay else { return }

        if case .exposure(let owner) = node.area, node.tile == .joker {
            // Taking a joker: you need the real tile for that group in your rack.
            let move = Round.Move.swapJoker(owner: owner, exposure: node.group ?? -1)
            if round.isLegal(move, by: 0) {
                perform(move, by: 0)
            } else {
                eventText = "You need the real tile to take that joker"
                shake(node)
                refreshHUD()
            }
            return
        }

        guard node.area == .rack, let index = node.rackIndex else { return }
        switch round.phase {
        case .charleston, .courtesyPass:
            if node.tile == .joker {
                eventText = "Jokers can't be passed"
                shake(node)
            } else if selection.contains(index) {
                selection.remove(index)
            } else if selection.count < tilesToPass {
                selection.insert(index)
            } else {
                shake(node)
            }
        case .discard:
            if selection.contains(index) {
                perform(.discard(node.tile), by: 0)
                return
            }
            selection = [index]
        default:
            return
        }
        sync(animated: true)
        refreshHUD()
    }

    private func shake(_ node: TileNode) {
        let nudge = 6 * metrics.u
        node.run(.sequence([
            .moveBy(x: nudge, y: 0, duration: 0.05),
            .moveBy(x: -nudge * 2, y: 0, duration: 0.08),
            .moveBy(x: nudge, y: 0, duration: 0.05),
        ]))
    }

    // MARK: - Overlays

    private func rebuildOverlay() {
        overlayLayer.removeAllChildren()
        guard let overlay, isSetUp else { return }
        let m = metrics

        let dimmer = SKShapeNode(rectOf: CGSize(width: size.width * 2, height: size.height * 2))
        dimmer.position = CGPoint(x: size.width / 2, y: size.height / 2)
        dimmer.fillColor = SKColor(white: 0, alpha: 0.6)
        dimmer.strokeColor = .clear
        overlayLayer.addChild(dimmer)

        let width = min(size.width - 24 * m.u, 420 * m.u)
        let height: CGFloat
        switch overlay {
        case .card: height = min(560 * m.u, size.height - safeInsets.top - safeInsets.bottom - 20 * m.u)
        case .summary: height = 470 * m.u
        case .gameMenu: height = 240 * m.u
        }
        let panel = SKShapeNode(rectOf: CGSize(width: width, height: height), cornerRadius: 18 * m.u)
        panel.position = CGPoint(x: size.width / 2, y: size.height / 2)
        panel.fillColor = Style.panel
        panel.strokeColor = Style.gold.withAlphaComponent(0.6)
        panel.lineWidth = 1.5
        panel.zPosition = 1
        overlayLayer.addChild(panel)

        switch overlay {
        case .card(let page):
            buildCard(in: panel, width: width, height: height, page: page, m: m)
        case .summary(let payments):
            buildSummary(in: panel, width: width, payments: payments, m: m)
        case .gameMenu:
            buildGameMenu(in: panel, width: width, m: m)
        }
    }

    private func add(_ node: SKNode, to panel: SKNode, x: CGFloat = 0, y: CGFloat) {
        node.position = CGPoint(x: x, y: y)
        node.zPosition = 1
        panel.addChild(node)
    }

    private func closeOverlay() {
        overlay = nil
        rebuildOverlay()
    }

    /// A row of small tiles in a panel, with a little space between groups. Tiles
    /// marked missing are dimmed.
    private func addTiles(_ groups: [[(tile: Tile, have: Bool)]], to panel: SKNode, left: CGFloat, y: CGFloat, tileWidth: CGFloat, gap: CGFloat) {
        var x = left + tileWidth / 2
        for (index, group) in groups.enumerated() {
            // Singles in a row, like 2026 or 13579, read as one word: no gap between them.
            if index > 0 && (group.count > 1 || groups[index - 1].count > 1) {
                x += gap
            }
            for item in group {
                let node = TileNode(tile: item.tile)
                node.area = .picture
                node.setScale(tileWidth / TileArt.size.width)
                node.isDimmed = !item.have
                node.alpha = item.have ? 1 : 0.55
                add(node, to: panel, x: x, y: y)
                x += tileWidth
            }
        }
    }

    /// How many gaps `addTiles` leaves between these groups.
    private func gapCount(_ groups: [[(tile: Tile, have: Bool)]]) -> Int {
        (1..<max(groups.count, 1)).filter { groups[$0].count > 1 || groups[$0 - 1].count > 1 }.count
    }

    /// The card, closest hands first, showing which tiles of each you already have.
    private func buildCard(in panel: SKNode, width: CGFloat, height: CGFloat, page: Int, m: Metrics) {
        let u = m.u
        guard let round else { return }
        let card = round.card
        let rows = cardRows(for: round)
        let perPage = max(4, Int((height - 120 * u) / (46 * u)))
        let pages = max(1, (rows.count + perPage - 1) / perPage)
        let page = min(page, pages - 1)

        add(Style.label(card.title, size: 22 * u, font: Style.bold, color: Style.gold), to: panel, y: height / 2 - 28 * u)
        add(Style.label("Closest hands first · dim tiles are ones you still need", size: 11.5 * u, color: Style.faint),
            to: panel, y: height / 2 - 50 * u)

        let left = -width / 2 + 14 * u
        let tileLeft = left + 54 * u
        let tileSpace = width - 54 * u - 28 * u
        var y = height / 2 - 84 * u
        for row in rows.dropFirst(page * perPage).prefix(perPage) {
            let hand = card.hands[row.hand]
            let neededText: String
            let color: SKColor
            switch row.needed {
            case .some(0): neededText = "✓"; color = Style.gold
            case .some(let needed): neededText = "\(needed)"; color = needed <= 3 ? Style.gold : .white
            case .none: neededText = "–"; color = SKColor(white: 1, alpha: 0.35)
            }
            add(Style.label(neededText, size: 20 * u, font: Style.bold, color: color), to: panel, x: left + 16 * u, y: y - 6 * u)
            let caption = "\(hand.section) · \(hand.value)\(hand.concealed ? " · concealed" : "")"
            let label = Style.label(caption, size: 11 * u, color: row.needed == nil ? SKColor(white: 1, alpha: 0.4) : Style.faint)
            label.horizontalAlignmentMode = .left
            add(label, to: panel, x: tileLeft, y: y + 8 * u)
            let tileWidth = min((tileSpace - 3 * u * CGFloat(gapCount(row.tiles))) / 14, 19 * u)
            addTiles(row.tiles, to: panel, left: tileLeft, y: y - 12 * u, tileWidth: tileWidth, gap: 3 * u)
            y -= 46 * u
        }

        let buttonY = -height / 2 + 32 * u
        if pages > 1 {
            let previous = ButtonNode.plain(text: "‹", size: CGSize(width: 50 * u, height: 40 * u), fontSize: 22 * u) { [weak self] in
                self?.overlay = .card(page: (page + pages - 1) % pages)
                self?.rebuildOverlay()
            }
            add(previous, to: panel, x: -width / 2 + 44 * u, y: buttonY)
            add(Style.label("\(page + 1) of \(pages)", size: 13 * u, color: Style.faint), to: panel, x: -width / 2 + 110 * u, y: buttonY)
            let next = ButtonNode.plain(text: "›", size: CGSize(width: 50 * u, height: 40 * u), fontSize: 22 * u) { [weak self] in
                self?.overlay = .card(page: (page + 1) % pages)
                self?.rebuildOverlay()
            }
            add(next, to: panel, x: -width / 2 + 176 * u, y: buttonY)
        }
        let close = ButtonNode(text: "Close", size: CGSize(width: 110 * u, height: 40 * u), fontSize: 16 * u) { [weak self] in
            self?.closeOverlay()
        }
        add(close, to: panel, x: width / 2 - 70 * u, y: buttonY)
    }

    private struct CardRow {
        let hand: Int
        /// Tiles still needed, or nil when your exposures rule the hand out.
        let needed: Int?
        let tiles: [[(tile: Tile, have: Bool)]]
    }

    /// For every hand, the way of making it that you are closest to.
    private func cardRows(for round: Round) -> [CardRow] {
        let card = round.card
        let concealed = TileCounts(round.hands[0])
        let exposures = round.exposures[0]
        var best: [Int: (instance: HandInstance, needed: Int?)] = [:]
        for instance in card.instances {
            let needed = instance.tilesNeeded(concealed: concealed, exposures: exposures)
            if let current = best[instance.hand] {
                if let needed, needed < (current.needed ?? 99) {
                    best[instance.hand] = (instance, needed)
                }
            } else {
                best[instance.hand] = (instance, needed)
            }
        }
        let rows = best.map { hand, entry in
            CardRow(hand: hand, needed: entry.needed, tiles: haveMarks(for: entry.instance, round: round))
        }
        return rows.sorted { ($0.needed ?? 99, $0.hand) < ($1.needed ?? 99, $1.hand) }
    }

    /// Which tiles of `instance` you hold: real tiles go to singles and pairs first,
    /// then to bigger groups, and jokers fill what is left of the bigger groups.
    private func haveMarks(for instance: HandInstance, round: Round) -> [[(tile: Tile, have: Bool)]] {
        var real = TileCounts(round.hands[0].filter { $0 != .joker })
        var jokers = round.hands[0].filter { $0 == .joker }.count
        for exposure in round.exposures[0] {
            real[exposure.tile] += exposure.count - exposure.jokers
            jokers += exposure.jokers
        }
        var marks = instance.groups.map { group in Array(repeating: false, count: group.count) }
        for pass in [false, true] {
            for (index, group) in instance.groups.enumerated() where (group.count >= 3) == pass {
                for slot in 0..<group.count where real[group.tile] > 0 {
                    marks[index][slot] = true
                    real[group.tile] -= 1
                }
            }
        }
        for (index, group) in instance.groups.enumerated() where group.count >= 3 {
            for slot in 0..<group.count where !marks[index][slot] && jokers > 0 {
                marks[index][slot] = true
                jokers -= 1
            }
        }
        return instance.groups.enumerated().map { index, group in
            (0..<group.count).map { (group.tile, marks[index][$0]) }
        }
    }

    private func buildSummary(in panel: SKNode, width: CGFloat, payments: [Int], m: Metrics) {
        let u = m.u
        guard let round, let outcome = round.outcome else { return }
        var y: CGFloat = 200 * u

        switch outcome {
        case .wallGame:
            add(Style.label("Wall game", size: 28 * u, font: Style.bold, color: Style.gold), to: panel, y: y)
            y -= 34 * u
            add(Style.label("The tiles ran out and nobody won.", size: 14 * u, color: Style.faint), to: panel, y: y)
            y -= 40 * u
        case .mahjong(let win):
            let title = win.winner == 0 ? "Mahjong! You win" : "\(names[win.winner]) wins"
            add(Style.label(title, size: 26 * u, font: Style.bold, color: Style.gold), to: panel, y: y)
            y -= 30 * u
            let hand = round.card.hands[win.hand]
            var how = "Drawn from the wall"
            if let discarder = win.discarder, !win.selfDrawn {
                how = discarder == 0 ? "On your discard" : "On \(names[discarder])'s discard"
            }
            if win.jokerless { how += " · jokerless, doubled" }
            add(Style.label("\(hand.section) · \(hand.value) · \(how)", size: 12.5 * u, color: Style.faint), to: panel, y: y)
            y -= 34 * u
            if let instance = round.card.completedHands(concealed: round.hands[win.winner], exposures: round.exposures[win.winner]).first {
                let groups = instance.groups.map { group in (0..<group.count).map { _ in (group.tile, true) } }
                let gaps = 3 * u * CGFloat(gapCount(groups))
                let tileWidth = min((width - 40 * u - gaps) / 14, 24 * u)
                let total = tileWidth * 14 + gaps
                addTiles(groups, to: panel, left: -total / 2, y: y, tileWidth: tileWidth, gap: 3 * u)
            }
            y -= 44 * u
        }

        let columns: [CGFloat] = [-width / 2 + 30 * u, width / 2 - 140 * u, width / 2 - 40 * u]
        func cell(_ text: String, column: Int, y: CGFloat, bold: Bool = false, color: SKColor = .white) {
            let label = Style.label(text, size: 15 * u, font: bold ? Style.bold : Style.regular, color: color)
            label.horizontalAlignmentMode = column == 0 ? .left : .right
            add(label, to: panel, x: columns[column], y: y)
        }
        cell("This hand", column: 1, y: y, color: Style.faint)
        cell("Total", column: 2, y: y, color: Style.faint)
        y -= 30 * u
        for player in 0..<4 {
            let payment = payments[player]
            let paymentText = payment > 0 ? "+\(payment)" : "\(payment)"
            cell(names[player], column: 0, y: y, bold: player == 0)
            cell(paymentText, column: 1, y: y, color: payment > 0 ? Style.gold : .white)
            cell("\(match.scores[player])", column: 2, y: y, bold: true)
            y -= 28 * u
        }

        y -= 14 * u
        if match.isOver {
            let winners = match.winners
            let text = winners.contains(0)
                ? (winners.count > 1 ? "You tied for the win!" : "You won the game!")
                : "\(winners.map { names[$0] }.joined(separator: " and ")) won the game"
            add(Style.label(text, size: 17 * u, font: Style.bold, color: Style.gold), to: panel, y: y)
            let button = ButtonNode(text: "New game", size: CGSize(width: 180 * u, height: 46 * u), fontSize: 17 * u) { [weak self] in
                self?.startMatch()
            }
            add(button, to: panel, y: -190 * u)
        } else {
            add(Style.label("Hand \(match.handsPlayed) of \(match.settings.length.hands)", size: 13 * u, color: Style.faint), to: panel, y: y)
            let button = ButtonNode(text: "Next hand", size: CGSize(width: 180 * u, height: 46 * u), fontSize: 17 * u) { [weak self] in
                self?.overlay = nil
                self?.rebuildOverlay()
                self?.startRound()
            }
            add(button, to: panel, y: -190 * u)
        }
    }

    private func buildGameMenu(in panel: SKNode, width: CGFloat, m: Metrics) {
        let u = m.u
        add(Style.label("Mahjong", size: 26 * u, font: Style.bold, color: Style.gold), to: panel, y: 80 * u)
        let keep = ButtonNode(text: "Keep playing", size: CGSize(width: 200 * u, height: 46 * u), fontSize: 17 * u) { [weak self] in
            self?.closeOverlay()
        }
        add(keep, to: panel, y: 20 * u)
        let restart = ButtonNode.plain(text: "New game", size: CGSize(width: 200 * u, height: 46 * u), fontSize: 17 * u) { [weak self] in
            self?.startMatch()
        }
        add(restart, to: panel, y: -40 * u)
    }

    // MARK: - Debug

    #if DEBUG
    /// Every tile, large, for checking the artwork. Launch with `-scenario tiles`.
    private func showAllTiles() {
        let m = metrics
        let columns = 6
        let tileWidth = min((m.width - 5 * 8 * m.u) / CGFloat(columns), 60 * m.u)
        let tileHeight = tileWidth * 4 / 3
        let top = size.height - safeInsets.top - 20 * m.u - tileHeight / 2
        for index in 0..<Tile.kindCount {
            let node = TileNode(tile: Tile(index: index))
            node.setScale(tileWidth / TileArt.size.width)
            let column = CGFloat(index % columns)
            let row = CGFloat(index / columns)
            node.position = CGPoint(
                x: size.width / 2 + (column - CGFloat(columns - 1) / 2) * (tileWidth + 8 * m.u),
                y: top - row * (tileHeight + 10 * m.u)
            )
            tileLayer.addChild(node)
        }
    }
    #endif
}
