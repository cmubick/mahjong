//
//  GameScene.swift
//  mahjong
//
//  The table: your rack at the bottom, the other three players' exposures at the top
//  and the discards in between. The rules live in Rules/; this file only draws them
//  and turns taps into moves.
//

import SpriteKit
import StoreKit

final class GameScene: SKScene {

    // MARK: - State

    var safeInsets: UIEdgeInsets = .zero {
        didSet { if safeInsets != oldValue { relayout() } }
    }

    /// Player 0 holds the phone. Play passes to the right: You → Right → Across → Left.
    private let positions = ["You", "Right", "Across", "Left"]

    /// What to call a player: "You", or their seat wind this hand, the way people at a
    /// table say "East discarded". Winds move one seat on every hand.
    private func name(_ player: Int, in hand: Round? = nil) -> String {
        guard player != 0 else { return "You" }
        guard let hand = hand ?? round else { return positions[player] }
        return windName(hand.seatWind(of: player))
    }

    private enum Overlay {
        case menu
        case help(page: Int)
        case store
        case tipJar
        /// Choosing which card to play.
        case cards
        case history
        case newHandConfirm
        case clearConfirm
        case card(page: Int)
        /// Every hand on a card, to read through.
        case cardHands(id: String, page: Int)
        /// One hand, large.
        case handDetail(cardID: String, hand: Int)
        case summary(payments: [Int])
        case gameMenu
        /// Features on the way.
        case comingSoon
        /// Game settings: Charleston, wall and dice, call time, sound.
        case options
        /// The extras: what's next, feedback, the tip jar and the store.
        case more
    }


    /// The running tally across hands, until you clear it.
    private var scorepad = Scorepad()
    /// Every hand you have finished. Seen with the full game.
    private var history = HandHistory()
    private var round: Round?
    /// The scorepad and hand on disk.
    private var savedGame: SavedGame?
    private let store = Store(currentYear: CardLibrary.currentYear)
    private var storeMessage = ""
    private var isBuying = false
    private var storeTitleTaps = 0
    private var showsStoreDiagnostics = false
    private var generator = SystemRandomNumberGenerator()
    /// Positions in your rack that you have picked, for a pass or a discard.
    private var selection: Set<Int> = []
    /// Your rack in the order you arranged it. The engine keeps hands sorted; this is
    /// only how they are shown. New tiles go at the right end.
    private var rackOrder: [Tile] = []
    /// The rack tile being dragged to a new place, if any.
    private var draggedNode: TileNode?

    // The wall and dice (a full-game option).
    /// Where the wall was broken this hand: the first stack dealt. Nil when the wall isn't shown.
    private var wallBreak: Int?
    private let wallLayer = SKNode()
    private var wallNodes: [SKShapeNode] = []
    private static let wallKey = "wallAndDice"

    /// Show the wall, roll for East and break the wall. Off unless chosen, and only with the full game.
    private var wallAndDice: Bool {
        get { store.hasFullGame && UserDefaults.standard.bool(forKey: GameScene.wallKey) }
        set { UserDefaults.standard.set(newValue, forKey: GameScene.wallKey) }
    }
    private var eventText = ""
    private var overlay: Overlay? = .menu
    /// Bumped whenever a game starts, so timers from an old game do nothing.
    private var generation = 0
    /// Bumped on every move, so a bot never moves twice on one timer.
    private var step = 0
    private var isSetUp = false
    /// Whether the finished hand's payments are already in the scores.
    private var roundRecorded = false
    /// Debug: the bots play your seat too.
    private var autoplay = false
    /// True while the tiles fly out at the start of a hand.
    private var isDealing = false
    /// When the call window for the latest discard closes and the next player draws.
    private var claimDeadline: Date?
    /// Bumped for every call window, so a timer from an old window does nothing.
    private var windowToken = 0
    /// The window in which you tapped Pass, so it can close as soon as everyone has answered.
    private var passedWindow: Int?
    /// The shrinking bar under a discard that can still be called.
    private var claimBar: SKShapeNode?
    /// A bot move or the end of a hand waited because a panel was open or the deal
    /// was running. Closing the panel picks it up again.
    private var stalled = false
    /// Where tiles you pass go, and where tiles passed to you come from, for the next redraw.
    private var passExit: CGPoint?
    private var passSpawn: CGPoint?

    // MARK: - Nodes

    private var tileNodes: [TileNode] = []
    private let tileLayer = SKNode()
    private let hudLayer = SKNode()
    private let controlLayer = SKNode()
    private let overlayLayer = SKNode()
    private let dealLayer = SKNode()
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
        /// Room left around the discards for the wall, when it is shown.
        let wallInset: CGFloat

        init(size: CGSize, insets: UIEdgeInsets, wall: Bool = false) {
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
            wallInset = wall ? 14 * u : 0
            pileTile = min((width - 20 * u - 2 * wallInset - 13 * 2 * u) / 14, 26 * u)
        }

        /// One stack of the wall: 19 to a side, numbered clockwise from the right-hand
        /// end of your own wall at the bottom.
        func wallStack(_ index: Int) -> (center: CGPoint, size: CGSize) {
            let x0 = left + 3 * u, x1 = left + width - 3 * u
            let y0 = pileBottom - 1 * u, y1 = pileTop + 1 * u
            let t = 10 * u
            let along = CGFloat(Dice.stacksPerSide)
            let lh = (x1 - x0 - 2 * t) / along
            let lv = (y1 - y0 - 2 * t) / along
            let k = CGFloat(index % Dice.stacksPerSide) + 0.5
            switch index / Dice.stacksPerSide {
            case 0: return (CGPoint(x: x1 - t - lh * k, y: y0 + t / 2), CGSize(width: lh - 1.5 * u, height: t))
            case 1: return (CGPoint(x: x0 + t / 2, y: y0 + t + lv * k), CGSize(width: t, height: lv - 1.5 * u))
            case 2: return (CGPoint(x: x0 + t + lh * k, y: y1 - t / 2), CGSize(width: lh - 1.5 * u, height: t))
            default: return (CGPoint(x: x1 - t / 2, y: y1 - t - lv * k), CGSize(width: t, height: lv - 1.5 * u))
            }
        }

        func badge(_ player: Int) -> CGPoint {
            CGPoint(x: left + badgeSize.width / 2, y: opponentRowY[player] ?? 0)
        }

        /// Where a discard waits, large, while it can still be called: low in the
        /// middle of the discard area.
        var claimSpot: CGPoint {
            CGPoint(x: size.width / 2, y: pileBottom + wallInset + rackTile * 2 / 3 + 14 * u)
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
            let y = pileTop - 6 * u - wallInset - pileTile * 2 / 3 - CGFloat(index / pilePerRow) * (pileTile * 4 / 3 + 2 * u)
            return CGPoint(x: x, y: y)
        }
    }

    private var metrics: Metrics { Metrics(size: size, insets: safeInsets, wall: wallBreak != nil && round != nil) }

    // MARK: - Scene life cycle

    override func didMove(to view: SKView) {
        backgroundColor = Style.felt
        tileLayer.zPosition = 10
        hudLayer.zPosition = 5
        controlLayer.zPosition = 300
        dealLayer.zPosition = 500
        overlayLayer.zPosition = 1000
        wallLayer.zPosition = 8
        addChild(tileLayer)
        addChild(wallLayer)
        addChild(hudLayer)
        addChild(controlLayer)
        addChild(dealLayer)
        addChild(overlayLayer)
        isSetUp = true
        savedGame = GameSaver.load()
        scorepad = savedGame?.scorepad ?? Scorepad()
        history = HistoryStore.load()
        _ = Sounds.shared
        store.onChange = { [weak self] in self?.rebuildOverlay() }
        store.start()
        // First launch opens on the instructions.
        if !UserDefaults.standard.bool(forKey: HelpPage.seenKey) {
            overlay = .help(page: 0)
        }

        #if DEBUG
        let arguments = CommandLine.arguments
        if let index = arguments.firstIndex(of: "-unlocked"), arguments.indices.contains(index + 1) {
            store.debugOverride = arguments[index + 1] == "YES"
        }
        autoplay = arguments.contains("-autoplay")
        if let index = arguments.firstIndex(of: "-scenario"), arguments.indices.contains(index + 1) {
            switch arguments[index + 1] {
            case "tiles":
                overlay = nil
                relayout()
                showAllTiles()
                return
            case "store":
                overlay = .store
            case "shot":
                // App Store screenshots: `-scenario shot table|claim|card|detail|magnify|charleston`.
                let kind = arguments.indices.contains(index + 2) ? arguments[index + 2] : "table"
                showScreenshot(kind)
                return
            case "magnify":
                // The press-and-hold magnifier, held open over a rack tile.
                overlay = nil
                relayout()
                dealNewHand()
                after(3) { [weak self] in
                    guard let self, let node = self.tileNodes.first(where: { $0.area == .rack && $0.rackIndex == 3 }) else { return }
                    self.showMagnifier(for: node.tile, at: node.position)
                }
                return
            case "history":
                // Twelve quick bot hands, shown but never saved.
                var generator = SeededGenerator(seed: 11)
                var pad = Scorepad()
                var sample = HandHistory()
                for _ in 0..<12 {
                    var round = pad.deal(card: .practice, charleston: true, using: &generator)
                    while round.outcome == nil, let actor = round.actors.first,
                          let move = Bot.chooseMove(in: round, for: actor) {
                        try? round.apply(move, by: actor)
                    }
                    pad.record(round)
                    sample.add(HandRecord(round: round))
                }
                history = sample
                overlay = .history
            case "help":
                // `-scenario help 5` opens on the sixth page.
                let page = arguments.indices.contains(index + 2) ? Int(arguments[index + 2]) ?? 0 : 0
                overlay = .help(page: page)
            default:
                break
            }
        }
        if autoplay {
            overlay = nil
            relayout()
            // A moment's wait lets the screen settle so the deal is seen.
            after(0.6) { [weak self] in self?.dealNewHand() }
            return
        }
        #endif
        relayout()
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
        rebuildWall()

        eventLabel = Style.label("", size: 14 * m.u, color: Style.faint)
        eventLabel.position = CGPoint(x: size.width / 2, y: m.eventY)
        promptLabel = Style.label("", size: 17 * m.u, font: Style.bold)
        promptLabel.position = CGPoint(x: size.width / 2, y: m.promptY)
        infoLabel = Style.label("", size: 13 * m.u, color: Style.faint)
        infoLabel.position = CGPoint(x: size.width / 2, y: m.infoY)
        hudLayer.addChild(eventLabel)
        hudLayer.addChild(promptLabel)
        hudLayer.addChild(infoLabel)

        claimBar?.position = CGPoint(x: m.claimSpot.x, y: m.claimSpot.y - m.rackTile * 2 / 3 - 10 * m.u)
        // A new size mid-deal puts every tile straight in place.
        if isDealing {
            skipDeal()
        } else {
            sync(animated: false)
        }
        refreshHUD()
        rebuildOverlay()
    }

    // MARK: - Game flow

    /// Deals a fresh hand from the menu. A hand in progress is dropped without scoring.
    private func dealNewHand() {
        generation += 1
        overlay = nil
        rebuildOverlay()
        startRound()
    }

    private func startRound() {
        generation += 1
        clearTable()
        roundRecorded = false
        // With the wall and dice: roll for East on a fresh scorepad, then East breaks the wall.
        var east: (rolls: [(Int, Int)], winner: Int, rerolled: Bool)?
        if wallAndDice && scorepad.needsRollForEast {
            let roll = Dice.rollForEast(using: &generator)
            scorepad.rolledForEast(winner: roll.winner)
            east = roll
        }
        let next = scorepad.deal(card: chosenCard, charleston: charleston, using: &generator)
        var breakRoll: (Int, Int)?
        if wallAndDice {
            let roll = Dice.roll(using: &generator)
            breakRoll = roll
            wallBreak = Dice.breakPoint(dealer: next.dealer, total: roll.0 + roll.1)
        }
        round = next
        rebuildWall()
        pendingRolls = (east, breakRoll)
        let dealer = next.dealer == 0 ? "You are East and deal" : "\(positions[next.dealer]) is East and deals"
        eventText = "\(next.card.title). \(dealer)."
        saveProgress()
        runDeal()
    }

    /// Takes every tile off the table and forgets anything waiting to happen.
    private func clearTable() {
        stopDealAnimation()
        tileNodes.forEach { $0.removeFromParent() }
        tileNodes = []
        selection = []
        rackOrder = []
        stalled = false
        endWindow()
        wallBreak = nil
        rebuildWall()
    }

    private func isLocked(_ card: Card) -> Bool {
        CardLibrary.isPaid(card) && !store.ownsCard(card.year ?? 0)
    }

    /// Bots wait while a panel is open or the tiles are being dealt.
    private var botsWait: Bool { overlay != nil || isDealing || frozen || feedbackOpen }

    private let feedback = Feedback()
    /// True while the feedback email is open over the game.
    private var feedbackOpen = false

    /// Opens an email with a screenshot of the table, without the menu over it.
    private func sendFeedback() {
        guard let view, let controller = view.window?.rootViewController else { return }
        overlayLayer.isHidden = true
        let shot = view.texture(from: self).map { UIImage(cgImage: $0.cgImage()) }
        overlayLayer.isHidden = false
        var extra = ["Card: \(round?.card.title ?? chosenCard.title)",
                     "Scorepad: \(scorepad.handsPlayed) hands"]
        if let round { extra.append("Hand: wall \(round.wall.count), phase \(round.phase)") }
        feedbackOpen = true
        feedback.present(from: controller.presentedViewController ?? controller, screenshot: shot, extra: extra) { [weak self] in
            guard let self else { return }
            self.feedbackOpen = false
            self.resumeIfStalled()
        }
    }

    /// Debug: holds the table still for App Store screenshots.
    private var frozen = false

    /// Picks up whatever waited while a panel was open.
    private func resumeIfStalled() {
        guard stalled, overlay == nil, !isDealing else { return }
        stalled = false
        // A call window that ran out behind a panel starts again, so you still get your chance.
        endWindow()
        advance()
    }

    // MARK: - The call window

    /// How long every discard stays callable before the next player draws. Remembered
    /// between launches.
    static let callTimes: [Double] = [2, 3, 5]
    private static let callTimeKey = "callSeconds"

    private var callSeconds: Double {
        get {
            if autoplay { return 0.4 }
            // Changing it comes with the full game.
            guard store.hasFullGame else { return 3 }
            let saved = UserDefaults.standard.double(forKey: GameScene.callTimeKey)
            return GameScene.callTimes.contains(saved) ? saved : 3
        }
        set { UserDefaults.standard.set(newValue, forKey: GameScene.callTimeKey) }
    }

    private static let charlestonKey = "charleston"
    private static let cardKey = "cardID"

    /// Whether hands start with the Charleston. Remembered between launches.
    /// Turning it off comes with the full game.
    private var charleston: Bool {
        get {
            guard store.hasFullGame else { return true }
            return UserDefaults.standard.object(forKey: GameScene.charlestonKey) as? Bool ?? true
        }
        set { UserDefaults.standard.set(newValue, forKey: GameScene.charlestonKey) }
    }

    /// The card new hands are dealt with: the one you chose, if you may play it, or
    /// else the newest card you may play.
    private var chosenCard: Card {
        if let id = UserDefaults.standard.string(forKey: GameScene.cardKey),
           let card = CardLibrary.card(id: id), !isLocked(card) {
            return card
        }
        return CardLibrary.defaultCard(unlocked: CardLibrary.currentYear.map(store.ownsCard) ?? false)
    }

    private func choose(_ card: Card) {
        UserDefaults.standard.set(card.id, forKey: GameScene.cardKey)
    }

    /// Opens the window for a new discard: every discard gets the same time, whoever
    /// can use it, and a bar under it runs down.
    private func startWindowIfNeeded(m: Metrics) {
        guard claimDeadline == nil else { return }
        windowToken += 1
        claimDeadline = Date().addingTimeInterval(callSeconds)
        let token = windowToken
        after(callSeconds) { [weak self] in self?.closeWindow(token: token) }

        let width = m.rackTile * 1.4
        let bar = SKShapeNode(rectOf: CGSize(width: width, height: 4 * m.u), cornerRadius: 2 * m.u)
        bar.fillColor = Style.gold
        bar.strokeColor = .clear
        bar.position = CGPoint(x: m.claimSpot.x, y: m.claimSpot.y - m.rackTile * 2 / 3 - 10 * m.u)
        bar.zPosition = 360
        tileLayer.addChild(bar)
        bar.run(.scaleX(to: 0, duration: callSeconds))
        claimBar = bar
    }

    private func endWindow() {
        claimDeadline = nil
        claimBar?.removeFromParent()
        claimBar = nil
    }

    /// Time is up: anyone still deciding lets the discard go, and the next player draws.
    private func closeWindow(token: Int) {
        guard token == windowToken, let round, case .claim = round.phase else { return }
        if botsWait {
            stalled = true
            return
        }
        while let round = self.round, case .claim = round.phase, !round.isWaitingForDraw,
              let player = round.actors.first {
            let move = player == 0 && !autoplay ? .decline : (Bot.chooseMove(in: round, for: player) ?? .decline)
            perform(move, by: player)
        }
        drawIfWaiting()
    }

    /// Once everyone has let the discard go, the next player draws.
    private func drawIfWaiting() {
        guard let round, round.isWaitingForDraw, let next = round.actors.first else { return }
        perform(.draw, by: next)
    }

    /// Redraws, then lets a bot move if one is due.
    private func advance() {
        sync(animated: true)
        refreshHUD()
        guard let round else { return }
        if round.outcome != nil {
            after(1.4) { [weak self] in
                guard let self else { return }
                if self.botsWait { self.stalled = true } else { self.finishRound() }
            }
            return
        }
        if case .claim = round.phase {
            startWindowIfNeeded(m: metrics)
            // The draw waits for the window to close, unless you already passed.
            if round.isWaitingForDraw {
                if passedWindow == windowToken {
                    let token = windowToken
                    after(0.3) { [weak self] in
                        guard let self, self.windowToken == token, !self.botsWait else { return }
                        self.drawIfWaiting()
                    }
                }
                return
            }
        } else {
            endWindow()
        }
        guard let actor = round.actors.first(where: { $0 != 0 || autoplay }) else { return }
        let delay: TimeInterval
        switch round.phase {
        case .discard: delay = 0.85
        // Long enough to see the discard up for grabs before it settles.
        case .claim: delay = 0.6
        default: delay = 0.15
        }
        let token = step
        after(delay) { [weak self] in
            guard let self, self.step == token, let round = self.round, round.actors.contains(actor) else { return }
            if self.botsWait {
                self.stalled = true
                return
            }
            guard let move = Bot.chooseMove(in: round, for: actor) else { return }
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
        playFeedback(for: move, by: actor, before: before, after: next)
        round = next
        // Bots answer the Charleston while you choose, so keep your picks until your
        // rack or the phase changes.
        if next.phase != before.phase || next.hands[0] != before.hands[0] {
            selection = []
        }
        step += 1
        saveProgress()
        advance()
    }

    private func finishRound() {
        guard let round, let outcome = round.outcome, !roundRecorded else { return }
        roundRecorded = true
        let payments = scorepad.record(round)
        saveProgress()
        if !autoplay {
            history.add(HandRecord(round: round))
            HistoryStore.save(history)
        }
        switch outcome {
        case .mahjong(let win) where win.winner == 0:
            Sounds.shared.play(.win)
            Haptics.victory(game: false)
        case .mahjong:
            Sounds.shared.play(.warning)
            Haptics.warning()
        case .wallGame:
            Sounds.shared.play(.slide)
        }
        overlay = .summary(payments: payments)
        refreshHUD()
        rebuildOverlay()
    }

    // MARK: - Dealing

    /// Deals the way people do: four tiles at a time to each player in turn from East,
    /// three times, then one more each and one extra for East. A tap skips it.
    private func runDeal() {
        guard let round else { return }
        isDealing = true
        sync(animated: false)
        refreshHUD()
        let m = metrics
        let rack = tileNodes.filter { $0.area == .rack }.sorted { ($0.rackIndex ?? 0) < ($1.rackIndex ?? 0) }
        let step = 0.09
        var time = 0.0
        var dealtToYou = 0
        var dealt = 0

        // The dice first, when the wall is shown.
        let rolls = pendingRolls
        pendingRolls = (nil, nil)
        if wallBreak != nil {
            updateWall(taken: 0)
            if let east = rolls.east { time = showRollForEast(east, start: time) }
            if let roll = rolls.breakRoll { time = showBreakRoll(roll, start: time) }
        }

        for lap in 0..<4 {
            for seat in 0..<4 {
                let player = (round.dealer + seat) % 4
                let count = lap < 3 ? 4 : (player == round.dealer ? 2 : 1)
                // Tiles come off the wall from the break, or from the middle without one.
                let wall = wallBreak.map { m.wallStack(($0 + dealt / 2) % Dice.stacks).center } ?? m.wall
                dealt += count
                let taken = dealt
                if wallBreak != nil {
                    dealLayer.run(.sequence([.wait(forDuration: time), .run { [weak self] in self?.updateWall(taken: taken) }]))
                }
                if player == 0 {
                    for (offset, node) in rack.dropFirst(dealtToYou).prefix(count).enumerated() {
                        let target = node.position
                        let scale = node.xScale
                        node.position = wall
                        node.setScale(scale * 0.5)
                        node.alpha = 0
                        let fly = SKAction.group([
                            .fadeIn(withDuration: 0.08),
                            .move(to: target, duration: 0.3),
                            .scale(to: scale, duration: 0.3),
                        ])
                        fly.timingMode = .easeOut
                        node.run(.sequence([.wait(forDuration: time + Double(offset) * 0.02), fly]), withKey: "move")
                    }
                    dealtToYou += count
                } else {
                    let back = SKSpriteNode(texture: TileArt.back, size: TileArt.size)
                    back.setScale(m.opponentTile * 1.3 / TileArt.size.width)
                    back.position = wall
                    back.alpha = 0
                    dealLayer.addChild(back)
                    back.run(.sequence([
                        .wait(forDuration: time),
                        .fadeIn(withDuration: 0.05),
                        .move(to: m.badge(player), duration: 0.28),
                        .fadeOut(withDuration: 0.08),
                        .removeFromParent(),
                    ]))
                }
                dealLayer.run(.sequence([
                    .wait(forDuration: time),
                    .run { Sounds.shared.play(.click) },
                ]))
                time += step
            }
        }
        after(time + 0.35) { [weak self] in self?.finishDeal() }
    }

    private func finishDeal() {
        guard isDealing else { return }
        isDealing = false
        dealLayer.removeAllActions()
        dealLayer.removeAllChildren()
        advance()
    }

    /// Rolls made at the start of a hand, waiting for the deal to show them.
    private var pendingRolls: (east: (rolls: [(Int, Int)], winner: Int, rerolled: Bool)?, breakRoll: (Int, Int)?) = (nil, nil)

    // MARK: - The wall and dice

    private func rebuildWall() {
        wallLayer.removeAllChildren()
        wallNodes = []
        guard wallBreak != nil, round != nil else { return }
        let m = metrics
        for index in 0..<Dice.stacks {
            let stack = m.wallStack(index)
            let node = SKShapeNode(rectOf: stack.size, cornerRadius: 2 * m.u)
            node.fillColor = TileArt.edge
            node.strokeColor = SKColor(white: 1, alpha: 0.35)
            node.lineWidth = 0.8
            node.position = stack.center
            wallLayer.addChild(node)
            wallNodes.append(node)
        }
        if let round { updateWall(taken: isDealing ? 0 : 152 - round.wall.count) }
    }

    /// Shows which stacks are left: whole stacks of two, a single tile, or gone.
    private func updateWall(taken: Int) {
        guard let start = wallBreak, wallNodes.count == Dice.stacks else { return }
        for offset in 0..<Dice.stacks {
            let node = wallNodes[(start + offset) % Dice.stacks]
            let left = 2 - min(max(taken - 2 * offset, 0), 2)
            node.isHidden = left == 0
            node.alpha = left == 1 ? 0.5 : 1
        }
    }

    /// Where the newest tile came off the wall, or the middle of the table without one.
    private func wallPoint(_ round: Round, m: Metrics) -> CGPoint {
        guard let start = wallBreak else { return m.wall }
        let taken = 152 - round.wall.count
        return m.wallStack((start + max(taken - 1, 0) / 2) % Dice.stacks).center
    }

    /// Two dice showing `a` and `b`.
    private func diceNode(_ a: Int, _ b: Int, size: CGFloat) -> SKNode {
        let pair = SKNode()
        let spots: [Int: [(CGFloat, CGFloat)]] = [
            1: [(0, 0)], 2: [(-1, 1), (1, -1)], 3: [(-1, 1), (0, 0), (1, -1)],
            4: [(-1, 1), (1, 1), (-1, -1), (1, -1)], 5: [(-1, 1), (1, 1), (0, 0), (-1, -1), (1, -1)],
            6: [(-1, 1), (-1, 0), (-1, -1), (1, 1), (1, 0), (1, -1)],
        ]
        for (index, value) in [a, b].enumerated() {
            let die = SKShapeNode(rectOf: CGSize(width: size, height: size), cornerRadius: size * 0.2)
            die.fillColor = Style.ivory
            die.strokeColor = SKColor(white: 0, alpha: 0.35)
            die.lineWidth = 1
            die.position = CGPoint(x: (index == 0 ? -0.62 : 0.62) * size, y: 0)
            for spot in spots[value] ?? [] {
                let dot = SKShapeNode(circleOfRadius: size * 0.09)
                dot.fillColor = value == 1 ? Style.red : Style.ink
                dot.strokeColor = .clear
                dot.position = CGPoint(x: spot.0 * size * 0.26, y: spot.1 * size * 0.26)
                die.addChild(dot)
            }
            pair.addChild(die)
        }
        return pair
    }

    /// Dice that tumble for a moment, then land on `roll`, with a caption under them.
    private func rollDice(_ roll: (Int, Int), at point: CGPoint, start: Double, caption: String, size: CGFloat) {
        let u = metrics.u
        let holder = SKNode()
        holder.position = point
        holder.zPosition = 950
        holder.alpha = 0
        dealLayer.addChild(holder)
        var steps: [SKAction] = [.wait(forDuration: start), .fadeIn(withDuration: 0.05), .run { Sounds.shared.play(.click) }]
        for _ in 0..<7 {
            steps.append(.run { [weak self, weak holder] in
                guard let self, let holder else { return }
                holder.removeAllChildren()
                holder.addChild(self.diceNode(Int.random(in: 1...6), Int.random(in: 1...6), size: size))
            })
            steps.append(.wait(forDuration: 0.07))
        }
        steps.append(.run { [weak self, weak holder] in
            guard let self, let holder else { return }
            holder.removeAllChildren()
            holder.addChild(self.diceNode(roll.0, roll.1, size: size))
            let label = Style.label(caption, size: 12 * u, font: Style.bold, color: Style.gold)
            label.position = CGPoint(x: 0, y: -size * 0.95)
            holder.addChild(label)
            Sounds.shared.play(.clack)
        })
        holder.run(.sequence(steps))
    }

    /// A line of text in the middle of the table during the dice.
    private func tableMessage(_ text: String, at y: CGFloat, start: Double, duration: Double) {
        let u = metrics.u
        let label = Style.label(text, size: 15 * u, font: Style.bold, color: .white)
        label.position = CGPoint(x: size.width / 2, y: y)
        label.zPosition = 950
        label.alpha = 0
        dealLayer.addChild(label)
        label.run(.sequence([.wait(forDuration: start), .fadeIn(withDuration: 0.15),
                             .wait(forDuration: duration), .fadeOut(withDuration: 0.2), .removeFromParent()]))
    }

    /// Everyone rolls; the highest is East. Returns when the deal can start.
    private func showRollForEast(_ east: (rolls: [(Int, Int)], winner: Int, rerolled: Bool), start: Double) -> Double {
        let m = metrics
        let u = m.u
        let midX = size.width / 2
        let midY = (m.pileTop + m.pileBottom) / 2
        let reach = min(m.width / 2 - 60 * u, (m.pileTop - m.pileBottom) / 2 - 50 * u)
        let spots = [CGPoint(x: midX, y: midY - reach), CGPoint(x: midX + reach, y: midY),
                     CGPoint(x: midX, y: midY + reach), CGPoint(x: midX - reach, y: midY)]
        // Messages go between the middle pair of dice and yours, clear of all four.
        let messageY = midY - reach / 2
        tableMessage("Rolling for East", at: messageY, start: start, duration: 0.7)
        for player in 0..<4 {
            let roll = east.rolls[player]
            rollDice(roll, at: spots[player], start: start + Double(player) * 0.15,
                     caption: "\(positions[player]) · \(roll.0 + roll.1)", size: 22 * u)
        }
        let total = east.rolls[east.winner].0 + east.rolls[east.winner].1
        let who = east.winner == 0 ? "You rolled \(total) and are East" : "\(positions[east.winner]) rolled \(total) and is East"
        tableMessage(who + (east.rerolled ? " after a tie" : ""), at: messageY, start: start + 1.4, duration: 1.2)
        let end = start + 2.9
        dealLayer.run(.sequence([.wait(forDuration: end - 0.2), .run { [weak self] in
            self?.dealLayer.children.filter { $0.zPosition == 950 }.forEach { $0.run(.sequence([.fadeOut(withDuration: 0.2), .removeFromParent()])) }
        }]))
        return end
    }

    /// East rolls to break the wall; the first stack dealt flashes. Returns when dealing starts.
    private func showBreakRoll(_ roll: (Int, Int), start: Double) -> Double {
        let m = metrics
        let u = m.u
        let midY = (m.pileTop + m.pileBottom) / 2
        let total = roll.0 + roll.1
        rollDice(roll, at: CGPoint(x: size.width / 2, y: midY + 10 * u), start: start, caption: "East rolls \(total)", size: 26 * u)
        tableMessage("Breaking the wall \(total) stacks in", at: midY - 40 * u, start: start + 0.7, duration: 0.8)
        if let start = wallBreak, wallNodes.count == Dice.stacks {
            let node = wallNodes[start]
            node.run(.sequence([.wait(forDuration: 0.7), .repeat(.sequence([
                .run { node.fillColor = Style.gold }, .wait(forDuration: 0.18),
                .run { node.fillColor = TileArt.edge }, .wait(forDuration: 0.18),
            ]), count: 3)]))
        }
        let end = start + 1.9
        dealLayer.run(.sequence([.wait(forDuration: end - 0.2), .run { [weak self] in
            self?.dealLayer.children.filter { $0.zPosition == 950 }.forEach { $0.run(.sequence([.fadeOut(withDuration: 0.2), .removeFromParent()])) }
        }]))
        return end
    }

    /// Ends the deal at once with every tile in place.
    private func skipDeal() {
        guard isDealing else { return }
        wallNodes.forEach { $0.removeAllActions(); $0.fillColor = TileArt.edge }
        tileNodes.forEach { $0.removeAction(forKey: "move") }
        sync(animated: false)
        finishDeal()
    }

    /// Drops the deal without starting play, for when the table is being cleared.
    private func stopDealAnimation() {
        isDealing = false
        dealLayer.removeAllActions()
        dealLayer.removeAllChildren()
    }

    // MARK: - Saving and resuming

    /// Writes the scorepad and the hand in progress to disk. Once a finished hand is in
    /// the scores the hand itself is left out, so it can never be scored twice.
    private func saveProgress() {
        let game = SavedGame(scorepad: scorepad, round: roundRecorded ? nil : round, wallBreak: roundRecorded ? nil : wallBreak)
        savedGame = game
        GameSaver.save(game)
    }

    /// A hand you can pick up where you left off.
    private var savedHand: Round? { savedGame?.round }

    private func resumeHand() {
        guard let saved = savedHand else { return }
        generation += 1
        clearTable()
        overlay = nil
        rebuildOverlay()
        round = saved
        roundRecorded = false
        if wallAndDice {
            wallBreak = savedGame?.wallBreak ?? Dice.breakPoint(dealer: saved.dealer, total: Int.random(in: 2...12))
        }
        rebuildWall()
        eventText = "Hand resumed. \(saved.card.title)."
        sync(animated: false)
        advance()
    }

    /// A fresh sheet: scores go back to zero. The history keeps every hand.
    private func clearScorepad() {
        scorepad.clear()
        saveProgress()
        show(.menu)
    }

    /// Leaves the table for the start menu. The game stays saved.
    private func goToMainMenu() {
        generation += 1
        clearTable()
        round = nil
        sync(animated: false)
        refreshHUD()
        overlay = .menu
        rebuildOverlay()
    }

    // MARK: - Store

    /// Where the tip jar's Close button goes back to.
    private var tipReturn: Overlay = .more

    private func openTipJar(returningTo back: Overlay = .more) {
        storeMessage = ""
        tipReturn = back
        show(.tipJar)
    }

    /// Where the store's Close button goes back to.
    private var storeReturn: Overlay = .menu

    private func openStore(returningTo back: Overlay = .menu) {
        storeMessage = ""
        storeTitleTaps = 0
        storeReturn = back
        overlay = .store
        rebuildOverlay()
    }

    private func purchase(_ product: Product) {
        guard !isBuying else { return }
        isBuying = true
        storeMessage = "Contacting the App Store…"
        rebuildOverlay()
        Task { [weak self] in
            guard let self else { return }
            let outcome = await self.store.buy(product, in: self.view?.window?.windowScene)
            self.isBuying = false
            switch outcome {
            case .success:
                Haptics.victory(game: false)
                self.storeMessage = StoreOffers.tipIDs.contains(product.id)
                    ? "Thank you! Your dealer appreciates it."
                    : "Thank you! It's yours to keep."
            case .pending:
                self.storeMessage = "Waiting for approval."
            case .cancelled:
                // Signing in to the App Store ends the first attempt, so say what to do next.
                self.storeMessage = "Not purchased. Tap again to try."
            case .failed:
                self.storeMessage = "The purchase didn't go through."
            }
            self.rebuildOverlay()
        }
    }

    private func redeemCode() {
        guard !isBuying, let scene = view?.window?.windowScene else { return }
        isBuying = true
        storeMessage = "Opening the App Store…"
        rebuildOverlay()
        Task { [weak self] in
            guard let self else { return }
            let unlocked = await self.store.redeemCode(in: scene)
            self.isBuying = false
            if unlocked {
                Haptics.victory(game: false)
                self.storeMessage = "Unlocked. Enjoy the full game!"
            } else {
                // A redeemed code can arrive a moment after the sheet closes.
                self.storeMessage = ""
            }
            self.rebuildOverlay()
        }
    }

    private func restorePurchases() {
        guard !isBuying else { return }
        isBuying = true
        storeMessage = "Checking your purchases…"
        rebuildOverlay()
        Task { [weak self] in
            guard let self else { return }
            let found = await self.store.restore()
            self.isBuying = false
            self.storeMessage = found ? "Full game restored." : "No earlier purchase found."
            self.rebuildOverlay()
        }
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
        let who = name(actor)
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
        case .decline, .draw:
            break
        }

        // Claims settle when the last player answers, so report what happened then.
        if case .claim(let discard) = before.phase, after.phase != before.phase {
            if case .discard(let caller) = after.phase, after.drawn == nil,
               let count = after.exposures[caller].last?.count,
               after.exposures[caller].count > before.exposures[caller].count {
                text = "\(name(caller)) called the \(discard.tile) for a \(groupName(count))"
            } else if case .over(.mahjong(let win)) = after.phase {
                text = "\(name(win.winner)) called Mahjong on the \(discard.tile)!"
            } else if case .over(.wallGame) = after.phase {
                text = "The wall is empty."
            } else {
                text = "\(name(discard.player)) discarded \(discard.tile)"
            }
        }
        if case .discard(0) = after.phase, let drawn = after.drawn, after.phase != before.phase {
            text = (text.map { $0 + ". " } ?? "") + "You drew \(drawn)."
        }
        return text
    }

    // MARK: - Sound and touch

    /// The sound and buzz for a move. Things that happen to you get a firmer tap than
    /// things the others do.
    private func playFeedback(for move: Round.Move, by actor: Int, before: Round, after: Round) {
        let settled = after.phase != before.phase
        switch move {
        case .pass:
            if settled {
                Sounds.shared.play(.slide)
                Haptics.tick()
            }
        case .discard:
            Sounds.shared.play(.clack)
            if actor == 0 { Haptics.tap() } else { Haptics.tick() }
        case .swapJoker(let owner, _):
            Sounds.shared.play(.joker)
            if actor == 0 || owner == 0 { Haptics.thump() } else { Haptics.tick() }
        case .vote, .offer, .call, .mahjong, .decline, .draw:
            break
        }

        // A claim settles when the last player answers.
        if case .claim = before.phase, settled {
            if case .discard(let caller) = after.phase, after.drawn == nil {
                Sounds.shared.play(.knock)
                if caller == 0 { Haptics.thump() } else { Haptics.tick() }
            }
        }
        // Your draw, and being asked whether to call.
        if settled, case .discard(0) = after.phase, after.drawn != nil {
            Sounds.shared.play(.click)
            Haptics.tick()
        }
        if settled, case .claim = after.phase, after.actors.contains(0), !after.isWaitingForDraw, !autoplay {
            Haptics.thump()
        }
    }

    private func groupName(_ count: Int) -> String {
        switch count {
        case 3: "pung"
        case 4: "kong"
        case 5: "quint"
        case 6: "sextet"
        default: "group of \(count)"
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
        var isNew = false
        var rackIndex: Int?
        var group: Int?
    }

    /// Your tiles in your own order: the ones you still hold stay where you put them,
    /// and any new ones go on the end.
    private func rackTiles(_ round: Round) -> [Tile] {
        let hand = round.hands[0]
        var left = TileCounts(hand)
        var order: [Tile] = []
        for tile in rackOrder + hand where left[tile] > 0 {
            order.append(tile)
            left[tile] -= 1
        }
        return order
    }

    private func sortRack() {
        rackOrder = []
        selection = []
        Sounds.shared.play(.slide)
        sync(animated: true)
        refreshHUD()
    }

    private func placements(for round: Round, m: Metrics) -> [Placement] {
        var result: [Placement] = []

        // Discards, oldest first. The latest one waits large while it can be called.
        let claimable: Round.Discard? = {
            if case .claim(let discard) = round.phase { return discard }
            return nil
        }()
        for (index, discard) in round.discards.enumerated() {
            if claimable != nil && index == round.discards.count - 1 {
                // Still up for grabs: shown large until everyone has answered.
                var placement = Placement(tile: discard.tile, area: .pile, position: m.claimSpot,
                                          width: m.rackTile, z: 350)
                placement.highlighted = true
                result.append(placement)
                continue
            }
            result.append(Placement(
                tile: discard.tile, area: .pile, position: m.pilePosition(index),
                width: m.pileTile, z: CGFloat(index)
            ))
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

        // Your rack, in rows of seven, in the order you arranged it.
        let hand = rackTiles(round)
        let passing = isPassing(round)
        // The tile you just drew. Tiles of a kind look alike, so mark the last one.
        var newIndex: Int?
        if case .discard(0) = round.phase, let drawn = round.drawn {
            newIndex = hand.lastIndex(of: drawn)
        }
        for (index, tile) in hand.enumerated() {
            let selected = selection.contains(index)
            var position = m.rackPosition(index, count: hand.count)
            if selected { position.y += 12 * m.u }
            var placement = Placement(tile: tile, area: .rack, position: position, width: m.rackTile,
                                      z: 400 + CGFloat(index) * 2)
            placement.highlighted = selected
            placement.dimmed = passing && tile == .joker
            placement.isNew = index == newIndex
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
        rackOrder = rackTiles(round)
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
            node.isNew = false
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
            node.isNew = placement.isNew
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
        if !isDealing { updateWall(taken: 152 - round.wall.count) }
    }

    private func spawnPoint(for placement: Placement, in round: Round, m: Metrics) -> CGPoint {
        switch placement.area {
        case .rack: return passSpawn ?? wallPoint(round, m: m)
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
        let rack = rackTiles(round)
        return selection.sorted().compactMap { rack.indices.contains($0) ? rack[$0] : nil }
    }

    // MARK: - Labels, badges and buttons

    private func refreshHUD() {
        guard isSetUp else { return }
        let m = metrics
        controlLayer.removeAllChildren()
        badges.values.forEach { $0.isHidden = round == nil }
        guard let round else {
            eventLabel.text = ""
            promptLabel.text = ""
            infoLabel.text = ""
            return
        }

        for player in 1...3 {
            let active: Bool
            if case .discard(let turn) = round.phase { active = turn == player } else { active = false }
            let detail = "\(positions[player]) · \(round.hands[player].count) · \(scorepad.scores[player])"
            badges[player]?.update(name: name(player), detail: detail, active: active)
        }

        eventLabel.text = eventText
        promptLabel.fontColor = .white
        promptLabel.text = prompt(for: round)

        var info = "\(windName(round.seatWind(of: 0))) · \(scorepad.scores[0]) pts · Wall \(round.wall.count)"
        if let closest = Bot.closest(TileCounts(round.hands[0]), exposures: round.exposures[0], card: round.card).first {
            info += closest.needed == 0 ? " · Mahjong!" : " · Closest hand: \(closest.needed) away"
        }
        infoLabel.text = info

        // Card on the left, menu on the right, this moment's choices in between.
        let small = CGSize(width: 64 * m.u, height: m.buttonHeight)
        let cardButton = ButtonNode.plain(text: "Card", size: small, fontSize: 14 * m.u) { [weak self] in
            self?.skipDeal()
            self?.overlay = .card(page: 0)
            self?.rebuildOverlay()
        }
        cardButton.position = CGPoint(x: m.left + small.width / 2, y: m.buttonY)
        controlLayer.addChild(cardButton)

        let menuSize = CGSize(width: 46 * m.u, height: m.buttonHeight)
        let menuButton = ButtonNode.plain(text: "☰", size: menuSize, fontSize: 18 * m.u) { [weak self] in
            self?.skipDeal()
            self?.overlay = .gameMenu
            self?.rebuildOverlay()
        }
        menuButton.position = CGPoint(x: m.left + m.width - menuSize.width / 2, y: m.buttonY)
        controlLayer.addChild(menuButton)

        // Sort, when you have moved tiles out of order.
        var sortWidth: CGFloat = 0
        if !isDealing, rackOrder != rackOrder.sorted() {
            let sortSize = CGSize(width: 54 * m.u, height: m.buttonHeight)
            let sort = ButtonNode.plain(text: "Sort", size: sortSize, fontSize: 14 * m.u) { [weak self] in
                self?.sortRack()
            }
            sort.position = CGPoint(x: m.left + m.width - menuSize.width - 6 * m.u - sortSize.width / 2, y: m.buttonY)
            controlLayer.addChild(sort)
            sortWidth = sortSize.width + 6 * m.u
        }

        let actions = autoplay || isDealing ? [] : choices(for: round)
        guard !actions.isEmpty else { return }
        let space = m.width - small.width - menuSize.width - sortWidth - 16 * m.u
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
        if isDealing { return "Dealing…" }
        guard round.actors.contains(0), !round.isWaitingForDraw, !autoplay else {
            switch round.phase {
            case .discard(let player): return player == 0 ? "Your turn" : "\(name(player))'s turn"
            case .claim: return "Tap the waiting tile to move on"
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
            return "\(name(discard.player)) threw the \(discard.tile). Call it?"
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
        let act: (Round.Move) -> () -> Void = { [weak self] move in { self?.perform(move, by: 0) } }

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
                let tile = rackTiles(round)[index]
                result.append(Choice(title: "Discard", primary: !moves.contains(.mahjong), action: act(.discard(tile))))
            }
            return result
        case .claim:
            guard !round.isWaitingForDraw else { return [] }
            var result: [Choice] = []
            if moves.contains(.mahjong) {
                result.append(Choice(title: "Mahjong!", primary: true, action: act(.mahjong)))
            }
            for move in moves {
                if case .call(let count) = move {
                    result.append(Choice(title: groupName(count).capitalized, primary: result.isEmpty, action: act(move)))
                }
            }
            result.append(Choice(title: "Pass") { [weak self] in
                // Once you've let it go there's nothing left to wait for.
                guard let self else { return }
                self.passedWindow = self.windowToken
                self.perform(.decline, by: 0)
            })
            return result
        case .over:
            return []
        }
    }

    // MARK: - Touches

    // MARK: - Holding a tile

    /// Where the finger is now, while it is down.
    private var touchPoint: CGPoint?
    /// Bumped on every touch, so an old hold timer does nothing.
    private var holdToken = 0
    /// Whether this touch has shown the magnifier.
    private var magnified = false
    private var magnifier: SKNode?

    /// The tile under a point: inside the open panel if there is one, else on the table.
    private func tileNode(at point: CGPoint) -> TileNode? {
        let tiles = nodes(at: point).compactMap { ancestor(of: $0, as: TileNode.self) }
            .filter { overlay == nil || $0.inParentHierarchy(overlayLayer) }
        return tiles.max { $0.zPosition < $1.zPosition }
    }

    /// The name shown in the magnifier, and a short second line.
    private func spokenName(_ tile: Tile) -> (name: String, detail: String) {
        switch tile {
        case .number(let suit, let rank):
            return ("\(rank) \(suit.name)", "\(suit.name)s go with the \(suit.dragon == .white ? "Soap" : suit.dragon.name + " Dragon")")
        case .wind(let wind):
            let name = ["N": "North", "E": "East", "W": "West", "S": "South"][wind.letter] ?? wind.letter
            return ("\(name) Wind", "A wind")
        case .dragon(.white):
            return ("Soap", "The white dragon · goes with Dots · also 0 in years")
        case .dragon(let dragon):
            return ("\(dragon.name) Dragon", "Goes with \(dragon.suit.name)s")
        case .flower:
            return ("Flower", "There are eight")
        case .joker:
            return ("Joker", "Stands in for any tile in a group of 3 or more")
        }
    }

    private func showMagnifier(for tile: Tile, at point: CGPoint) {
        let u = metrics.u
        magnifier?.removeFromParent()
        let node = SKNode()
        node.zPosition = 3000
        let (name, detail) = spokenName(tile)
        let panelSize = CGSize(width: 240 * u, height: 236 * u)
        let back = SKShapeNode(rectOf: panelSize, cornerRadius: 18 * u)
        back.fillColor = Style.panel.withAlphaComponent(0.96)
        back.strokeColor = Style.gold
        back.lineWidth = 2
        node.addChild(back)
        let big = TileNode(tile: tile)
        big.setScale(96 * u / TileArt.size.width)
        big.position = CGPoint(x: 0, y: 36 * u)
        node.addChild(big)
        let title = Style.label(name, size: 24 * u, font: Style.bold, color: Style.gold)
        title.position = CGPoint(x: 0, y: -66 * u)
        node.addChild(title)
        let line = Style.label(detail, size: 12 * u, color: Style.faint)
        line.numberOfLines = 0
        line.preferredMaxLayoutWidth = panelSize.width - 24 * u
        line.position = CGPoint(x: 0, y: -94 * u)
        node.addChild(line)

        // Above the finger where there is room, else below it; always on screen.
        var y = point.y + 70 * u + panelSize.height / 2
        if y + panelSize.height / 2 > size.height - safeInsets.top {
            y = point.y - 70 * u - panelSize.height / 2
        }
        let x = min(max(point.x, panelSize.width / 2 + 8 * u), size.width - panelSize.width / 2 - 8 * u)
        node.position = CGPoint(x: x, y: y)
        addChild(node)
        magnifier = node
    }

    private func endHold() {
        holdToken += 1
        touchPoint = nil
        magnified = false
        magnifier?.removeFromParent()
        magnifier = nil
    }

    private func ancestor<T: SKNode>(of node: SKNode, as type: T.Type) -> T? {
        var current: SKNode? = node
        while let candidate = current {
            if let match = candidate as? T { return match }
            current = candidate.parent
        }
        return nil
    }

    /// Where the current touch started, to tell a swipe from a tap.
    private var touchStart: CGPoint?

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let point = touches.first?.location(in: self) else { return }
        touchStart = point
        touchPoint = point
        magnified = false
        // Holding a finger on any tile shows it large, with its name.
        holdToken += 1
        let token = holdToken
        Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(0.35))
            guard let self, self.holdToken == token, let point = self.touchPoint,
                  let tile = self.tileNode(at: point) else { return }
            self.magnified = true
            Haptics.tick()
            self.showMagnifier(for: tile.tile, at: point)
        }
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let point = touches.first?.location(in: self) else { return }
        touchPoint = point
        // Moving a rack tile before the magnifier shows picks it up to rearrange.
        if !magnified, overlay == nil, draggedNode == nil, let start = touchStart,
           hypot(point.x - start.x, point.y - start.y) > 12 * metrics.u,
           let node = tileNode(at: start), node.area == .rack, round != nil {
            holdToken += 1
            selection = []
            draggedNode = node
            node.removeAllActions()
            node.zPosition = 900
            node.setScale(node.xScale * 1.12)
            Haptics.tick()
        }
        if let node = draggedNode {
            moveDragged(node, to: point)
            return
        }
        // Slide across tiles to read each one.
        if magnified, let tile = tileNode(at: point) {
            showMagnifier(for: tile.tile, at: point)
        }
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
        endHold()
        dropDragged()
    }

    /// The dragged tile follows the finger; the rest of the rack makes room for it.
    private func moveDragged(_ node: TileNode, to point: CGPoint) {
        guard round != nil else { return }
        node.position = point
        let m = metrics
        let count = rackOrder.count
        guard let from = node.rackIndex, rackOrder.indices.contains(from) else { return }
        let to = (0..<count).min { a, b in
            let pa = m.rackPosition(a, count: count), pb = m.rackPosition(b, count: count)
            return hypot(pa.x - point.x, pa.y - point.y) < hypot(pb.x - point.x, pb.y - point.y)
        } ?? from
        guard to != from else { return }
        let tile = rackOrder.remove(at: from)
        rackOrder.insert(tile, at: to)
        // Lay out the others, then keep the dragged tile under the finger.
        sync(animated: true)
        if let dragged = tileNodes.first(where: { $0.area == .rack && $0.rackIndex == to && $0.tile == tile }) {
            if dragged !== node {
                // Tiles of a kind are interchangeable: carry on with whichever node is now in that slot.
                node.zPosition = 400 + CGFloat(node.rackIndex ?? 0) * 2
                node.setScale(m.rackTile / TileArt.size.width)
                draggedNode = dragged
                dragged.setScale(m.rackTile / TileArt.size.width * 1.12)
            }
            draggedNode?.removeAction(forKey: "move")
            draggedNode?.position = point
            draggedNode?.zPosition = 900
        }
    }

    /// Puts the dragged tile down in its new place.
    private func dropDragged() {
        guard draggedNode != nil else { return }
        draggedNode = nil
        Sounds.shared.play(.click)
        sync(animated: true)
        refreshHUD()
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let touch = touches.first else { return }
        if draggedNode != nil {
            endHold()
            dropDragged()
            return
        }
        let wasMagnified = magnified
        endHold()
        // Letting go after a hold only puts the magnifier away.
        if wasMagnified { return }
        let point = touch.location(in: self)
        let hits = nodes(at: point)

        // A sideways swipe turns the page in the card lists.
        if let paging, let start = touchStart, paging.pages > 1 {
            let dx = point.x - start.x
            let dy = point.y - start.y
            if abs(dx) > 50 * metrics.u && abs(dx) > abs(dy) * 1.5 {
                let page = dx < 0 ? (paging.page + 1) % paging.pages : (paging.page + paging.pages - 1) % paging.pages
                Sounds.shared.play(.slide)
                Haptics.tick()
                show(paging.make(page))
                return
            }
        }

        if overlay != nil {
            let button = hits.lazy
                .compactMap { self.ancestor(of: $0, as: ButtonNode.self) }
                .first { $0.inParentHierarchy(self.overlayLayer) }
            if let button { press(button) }
            return
        }
        if let button = hits.lazy.compactMap({ self.ancestor(of: $0, as: ButtonNode.self) }).first {
            press(button)
            return
        }
        if isDealing {
            skipDeal()
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

    private func press(_ button: ButtonNode) {
        Sounds.shared.play(.tap)
        Haptics.tap()
        button.action()
    }

    private func tapped(_ node: TileNode) {
        guard let round, !autoplay else { return }

        // Tapping the discard waiting in the middle lets it go and moves play on.
        if node.area == .pile, case .claim(let discard) = round.phase,
           node.tile == discard.tile, node.isHighlighted {
            passedWindow = windowToken
            Sounds.shared.play(.tap)
            Haptics.tap()
            if round.actors.contains(0) && !round.isWaitingForDraw {
                perform(.decline, by: 0)
            } else {
                drawIfWaiting()
            }
            return
        }
        guard round.actors.contains(0) else { return }

        if case .exposure(let owner) = node.area, node.tile == .joker {
            // Taking a joker: you need the real tile for that group in your rack.
            let move = Round.Move.swapJoker(owner: owner, exposure: node.group ?? -1)
            if round.isLegal(move, by: 0) {
                perform(move, by: 0)
            } else {
                eventText = "You need the real tile to take that joker"
                refuse(node)
                refreshHUD()
            }
            return
        }

        guard node.area == .rack, let index = node.rackIndex else { return }
        switch round.phase {
        case .charleston, .courtesyPass:
            if node.tile == .joker {
                eventText = "Jokers can't be passed"
                refuse(node)
            } else if selection.contains(index) {
                selection.remove(index)
                Haptics.tick()
            } else if selection.count < tilesToPass {
                selection.insert(index)
                Sounds.shared.play(.click)
                Haptics.tick()
            } else {
                refuse(node)
            }
        case .discard:
            if selection.contains(index) {
                perform(.discard(node.tile), by: 0)
                return
            }
            selection = [index]
            Sounds.shared.play(.click)
            Haptics.tick()
        default:
            return
        }
        sync(animated: true)
        refreshHUD()
    }

    /// A tap that isn't allowed: the tile shakes its head.
    private func refuse(_ node: TileNode) {
        Sounds.shared.play(.warning)
        Haptics.warning()
        shake(node)
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
        paging = nil
        guard let overlay, isSetUp else { return }
        let m = metrics

        let dimmer = SKShapeNode(rectOf: CGSize(width: size.width * 2, height: size.height * 2))
        dimmer.position = CGPoint(x: size.width / 2, y: size.height / 2)
        dimmer.fillColor = SKColor(white: 0, alpha: 0.6)
        dimmer.strokeColor = .clear
        overlayLayer.addChild(dimmer)

        let fullHeight = size.height - safeInsets.top - safeInsets.bottom - 20 * m.u
        var width = min(size.width - 32 * m.u, 360 * m.u)
        let height: CGFloat
        switch overlay {
        case .menu: height = (store.ownsEverything ? 398 : 452) * m.u
        case .options: height = (round != nil ? 510 : 484) * m.u
        case .more: height = CGFloat(ComingSoon.items.isEmpty ? 300 : 352) * m.u
        case .comingSoon:
            let lines = comingSoonLines(width: width, u: m.u).reduce(0) { $0 + $1.frame.height + 16 * m.u }
            height = min(lines + 165 * m.u, fullHeight)
        case .help: height = 540 * m.u
        case .store: height = 520 * m.u
        case .tipJar: height = 400 * m.u
        case .cards: height = min(CGFloat(220 + CardLibrary.all.count * 64) * m.u, fullHeight)
        case .cardHands, .card:
            width = min(size.width - 16 * m.u, 520 * m.u)
            height = min(820 * m.u, fullHeight)
        case .handDetail:
            width = min(size.width - 16 * m.u, 520 * m.u)
            height = min(440 * m.u, fullHeight)
        case .history: height = min(600 * m.u, fullHeight)
        case .newHandConfirm, .clearConfirm: height = 250 * m.u
        case .summary:
            width = min(size.width - 24 * m.u, 420 * m.u)
            height = 470 * m.u
        case .gameMenu: height = 432 * m.u
        }
        let panel = SKShapeNode(rectOf: CGSize(width: width, height: height), cornerRadius: 18 * m.u)
        panel.position = CGPoint(x: size.width / 2, y: size.height / 2)
        panel.fillColor = Style.panel
        panel.strokeColor = Style.gold.withAlphaComponent(0.6)
        panel.lineWidth = 1.5
        panel.zPosition = 1
        overlayLayer.addChild(panel)

        switch overlay {
        case .menu:
            buildMenu(in: panel, width: width, m: m)
        case .help(let page):
            buildHelp(in: panel, width: width, page: page, m: m)
        case .store:
            buildStore(in: panel, width: width, m: m)
        case .tipJar:
            buildTipJar(in: panel, width: width, m: m)
        case .cards:
            buildCards(in: panel, width: width, height: height, m: m)
        case .cardHands(let id, let page):
            buildCardHands(in: panel, width: width, height: height, cardID: id, page: page, m: m)
        case .handDetail(let cardID, let hand):
            buildHandDetail(in: panel, width: width, height: height, cardID: cardID, handIndex: hand, m: m)
        case .history:
            buildHistory(in: panel, width: width, height: height, m: m)
        case .newHandConfirm:
            buildConfirm(in: panel, width: width, m: m,
                         title: "Start a new hand?",
                         body: "The hand in progress won't be scored.",
                         action: "New hand") { [weak self] in self?.dealNewHand() }
        case .clearConfirm:
            buildConfirm(in: panel, width: width, m: m,
                         title: "Clear the scorepad?",
                         body: "Everyone goes back to zero. Your history keeps every hand.",
                         action: "Clear") { [weak self] in self?.clearScorepad() }
        case .card(let page):
            buildCard(in: panel, width: width, height: height, page: page, m: m)
        case .summary(let payments):
            buildSummary(in: panel, width: width, payments: payments, m: m)
        case .gameMenu:
            buildGameMenu(in: panel, width: width, m: m)
        case .comingSoon:
            buildComingSoon(in: panel, width: width, height: height, m: m)
        case .options:
            buildOptions(in: panel, width: width, height: height, m: m)
        case .more:
            buildMore(in: panel, width: width, height: height, m: m)
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
        resumeIfStalled()
    }

    private func show(_ next: Overlay) {
        overlay = next
        rebuildOverlay()
    }

    /// A block of centred text that wraps to `width`.
    private func paragraph(_ text: String, size: CGFloat, width: CGFloat, color: SKColor = .white) -> SKLabelNode {
        let style = NSMutableParagraphStyle()
        style.alignment = .center
        style.lineSpacing = size * 0.2
        let label = SKLabelNode()
        label.attributedText = NSAttributedString(string: text, attributes: [
            .font: UIFont(name: Style.regular, size: size) ?? .systemFont(ofSize: size),
            .foregroundColor: color,
            .paragraphStyle: style,
        ])
        label.numberOfLines = 0
        label.preferredMaxLayoutWidth = width
        label.verticalAlignmentMode = .center
        return label
    }

    /// A quieter full-width button for the menus.
    private func secondary(_ text: String, size: CGSize, fontSize: CGFloat, color: SKColor = .white, action: @escaping () -> Void) -> ButtonNode {
        ButtonNode(text: text, size: size, fontSize: fontSize, fill: SKColor(white: 1, alpha: 0.12), textColor: color, action: action)
    }

    private func signed(_ value: Int) -> String {
        value > 0 ? "+\(value)" : "\(value)"
    }

    private func buildMenu(in panel: SKNode, width: CGFloat, m: Metrics) {
        let u = m.u
        let lock = " \u{1F512}"
        let unlocked = store.hasFullGame
        let top = (store.ownsEverything ? 398 : 452) * u / 2
        add(Style.label("Mahjong", size: 44 * u, font: Style.bold, color: Style.gold), to: panel, y: top - 50 * u)
        add(Style.label("American style · You and three bots", size: 14 * u, color: SKColor(white: 1, alpha: 0.8)),
            to: panel, y: top - 84 * u)

        let wide = CGSize(width: width - 40 * u, height: 40 * u)
        let half = CGSize(width: (width - 52 * u) / 2, height: 40 * u)
        add(Style.label("Card", size: 14 * u, font: Style.bold), to: panel, y: top - 120 * u)
        let cardButton = ButtonNode.plain(text: chosenCard.title + "  ›", size: wide, fontSize: 15 * u) { [weak self] in
            self?.show(.cards)
        }
        add(cardButton, to: panel, y: top - 154 * u)

        // The scorepad: your running total, and a way to start a fresh sheet.
        let tally = scorepad.handsPlayed == 0
            ? "Scorepad: no hands yet"
            : "Scorepad: you \(signed(scorepad.scores[0])) after \(scorepad.handsPlayed) hand\(scorepad.handsPlayed == 1 ? "" : "s")"
        let tallyLabel = Style.label(tally, size: 13 * u, color: Style.faint)
        if scorepad.handsPlayed > 0 {
            tallyLabel.horizontalAlignmentMode = .left
            add(tallyLabel, to: panel, x: -width / 2 + 22 * u, y: top - 198 * u)
            let clear = secondary("Clear", size: CGSize(width: 64 * u, height: 26 * u), fontSize: 12 * u) { [weak self] in
                self?.show(.clearConfirm)
            }
            add(clear, to: panel, x: width / 2 - 54 * u, y: top - 198 * u)
        } else {
            add(tallyLabel, to: panel, y: top - 198 * u)
        }

        let primary = CGSize(width: half.width, height: 50 * u)
        let left = -(half.width / 2 + 6 * u), right = half.width / 2 + 6 * u
        if savedHand != nil {
            let resume = ButtonNode(text: "Resume hand", size: primary, fontSize: 17 * u) { [weak self] in
                self?.resumeHand()
            }
            add(resume, to: panel, x: left, y: top - 246 * u)
            let fresh = secondary("New hand", size: primary, fontSize: 17 * u) { [weak self] in
                self?.show(.newHandConfirm)
            }
            add(fresh, to: panel, x: right, y: top - 246 * u)
        } else {
            let deal = ButtonNode(text: "Deal", size: CGSize(width: width - 40 * u, height: 50 * u), fontSize: 20 * u) {
                [weak self] in self?.dealNewHand()
            }
            add(deal, to: panel, y: top - 246 * u)
        }

        let small = CGSize(width: half.width, height: 44 * u)
        let help = secondary("How to play", size: small, fontSize: 16 * u) { [weak self] in
            self?.show(.help(page: 0))
        }
        add(help, to: panel, x: left, y: top - 304 * u)
        let historyButton = secondary("History" + (unlocked ? "" : lock), size: small, fontSize: 16 * u) { [weak self] in
            if unlocked { self?.show(.history) } else { self?.openStore() }
        }
        add(historyButton, to: panel, x: right, y: top - 304 * u)
        let optionsButton = secondary("Options", size: small, fontSize: 16 * u) { [weak self] in
            self?.openOptions(returningTo: .menu)
        }
        add(optionsButton, to: panel, x: left, y: top - 356 * u)
        let moreButton = secondary("More", size: small, fontSize: 16 * u) { [weak self] in
            self?.show(.more)
        }
        add(moreButton, to: panel, x: right, y: top - 356 * u)

        // Until everything is bought, the way to buy it stays on the front page.
        if !store.ownsEverything {
            let storeButton = secondary(storeTitle, size: CGSize(width: width - 40 * u, height: 44 * u),
                                        fontSize: 16 * u, color: Style.gold) { [weak self] in
                self?.openStore()
            }
            add(storeButton, to: panel, y: top - 410 * u)
        }
    }

    /// What the store button says: what's left to buy, or that you have it all.
    private var storeTitle: String {
        store.ownsEverything ? "Full game ✓" : (store.hasFullGame ? "This year's card" : "Unlock full game")
    }

    /// Where the options panel's Done button goes back to.
    private var optionsReturn: Overlay = .menu

    private func openOptions(returningTo back: Overlay) {
        optionsReturn = back
        show(.options)
    }

    /// Every setting in one place, from the start menu or the game menu.
    private func buildOptions(in panel: SKNode, width: CGFloat, height: CGFloat, m: Metrics) {
        let u = m.u
        let lock = " \u{1F512}"
        let unlocked = store.hasFullGame
        let top = height / 2
        add(Style.label("Options", size: 24 * u, font: Style.bold, color: Style.gold), to: panel, y: top - 40 * u)

        let half = CGSize(width: (width - 52 * u) / 2, height: 40 * u)
        let left = -(half.width / 2 + 6 * u), right = half.width / 2 + 6 * u
        var y = top - 84 * u

        /// A heading and an On / Off pair. `free` is the choice that needs no purchase.
        func toggle(_ title: String, isOn: Bool, free: Bool?, set: @escaping (Bool) -> Void) {
            add(Style.label(title, size: 14 * u, font: Style.bold), to: panel, y: y)
            for (on, x) in [(true, left), (false, right)] {
                let locked = free != nil && on != free && !unlocked
                let button = ButtonNode.plain(text: (on ? "On" : "Off") + (locked ? lock : ""), size: half,
                                              fontSize: 15 * u, selected: isOn == on) { [weak self] in
                    guard let self else { return }
                    if locked { self.openStore(returningTo: .options); return }
                    set(on)
                    self.rebuildOverlay()
                }
                add(button, to: panel, x: x, y: y - 34 * u)
            }
            y -= 84 * u
        }

        toggle("Charleston", isOn: charleston, free: true) { [weak self] in self?.charleston = $0 }
        toggle("Wall & dice", isOn: wallAndDice, free: false) { [weak self] in self?.wallAndDice = $0 }

        add(Style.label("Time to call each discard", size: 14 * u, font: Style.bold), to: panel, y: y)
        let third = CGSize(width: (width - 56 * u) / 3, height: 40 * u)
        for (index, seconds) in GameScene.callTimes.enumerated() {
            let locked = seconds != 3 && !unlocked
            let button = ButtonNode.plain(text: "\(Int(seconds)) sec" + (locked ? lock : ""), size: third, fontSize: 15 * u,
                                          selected: callSeconds == seconds) { [weak self] in
                if locked { self?.openStore(returningTo: .options); return }
                self?.callSeconds = seconds
                self?.rebuildOverlay()
            }
            add(button, to: panel, x: CGFloat(index - 1) * (third.width + 8 * u), y: y - 34 * u)
        }
        y -= 84 * u

        toggle("Sound", isOn: !Sounds.shared.isMuted, free: nil) { Sounds.shared.isMuted = !$0 }

        if round != nil {
            add(Style.label("Charleston and Wall & dice start with the next hand.", size: 12 * u, color: Style.faint),
                to: panel, y: y + 4 * u)
        }
        let done = secondary("Done", size: CGSize(width: width - 40 * u, height: 44 * u), fontSize: 17 * u) {
            [weak self] in guard let self else { return }; self.show(self.optionsReturn)
        }
        add(done, to: panel, y: -top + 36 * u)
    }

    /// The extras that don't need to be on the front page.
    private func buildMore(in panel: SKNode, width: CGFloat, height: CGFloat, m: Metrics) {
        let u = m.u
        let top = height / 2
        add(Style.label("More", size: 24 * u, font: Style.bold, color: Style.gold), to: panel, y: top - 40 * u)
        let wide = CGSize(width: width - 40 * u, height: 44 * u)
        var y = top - 92 * u
        func row(_ text: String, color: SKColor = .white, action: @escaping () -> Void) {
            add(secondary(text, size: wide, fontSize: 17 * u, color: color, action: action), to: panel, y: y)
            y -= 52 * u
        }
        if !ComingSoon.items.isEmpty {
            row("What's next") { [weak self] in self?.show(.comingSoon) }
        }
        row("Send feedback") { [weak self] in self?.sendFeedback() }
        row("Tip jar", color: Style.gold) { [weak self] in self?.openTipJar(returningTo: .more) }
        row(storeTitle, color: Style.gold) { [weak self] in self?.openStore(returningTo: .more) }
        let close = secondary("Close", size: wide, fontSize: 17 * u) { [weak self] in self?.show(.menu) }
        add(close, to: panel, y: -top + 36 * u)
    }

    private func buildConfirm(in panel: SKNode, width: CGFloat, m: Metrics,
                              title: String, body: String, action: String, perform: @escaping () -> Void) {
        let u = m.u
        add(Style.label(title, size: 22 * u, font: Style.bold, color: Style.gold), to: panel, y: 88 * u)
        add(paragraph(body, size: 15 * u, width: width - 48 * u), to: panel, y: 26 * u)

        let size = CGSize(width: (width - 52 * u) / 2, height: 46 * u)
        let cancel = ButtonNode(text: "Cancel", size: size, fontSize: 16 * u) { [weak self] in
            self?.show(.menu)
        }
        add(cancel, to: panel, x: -(size.width / 2 + 6 * u), y: -70 * u)
        let go = secondary(action, size: size, fontSize: 16 * u, action: perform)
        add(go, to: panel, x: size.width / 2 + 6 * u, y: -70 * u)
    }

    /// Every card in the app. The newest League card needs the full game.
    private func buildCards(in panel: SKNode, width: CGFloat, height: CGFloat, m: Metrics) {
        let u = m.u
        let top = height / 2
        add(Style.label("Choose a card", size: 24 * u, font: Style.bold, color: Style.gold), to: panel, y: top - 40 * u)
        add(Style.label("New hands are dealt with this card.", size: 13 * u, color: Style.faint), to: panel, y: top - 66 * u)
        if CardLibrary.all.contains(where: { !$0.isPractice }) {
            add(paragraph("A League card needs two things: your own printed card from the League, and the card bought in this app. Buying one doesn't include the other.",
                          size: 11.5 * u, width: width - 40 * u, color: Style.faint),
                to: panel, y: -height / 2 + 92 * u)
        }

        let chosen = chosenCard.id
        let handsWidth = 74 * u
        var y = top - 108 * u
        for card in CardLibrary.all {
            let locked = isLocked(card)
            let size = CGSize(width: width - 40 * u - (locked ? 0 : handsWidth + 8 * u), height: 42 * u)
            let title = card.title + (locked ? " \u{1F512}" : "") + (card.id == chosen ? "  ✓" : "")
            if !locked {
                let hands = secondary("Hands", size: CGSize(width: handsWidth, height: 42 * u), fontSize: 14 * u) {
                    [weak self] in
                    self?.handsReturn = .cards
                    self?.show(.cardHands(id: card.id, page: 0))
                }
                add(hands, to: panel, x: width / 2 - 20 * u - handsWidth / 2, y: y)
            }
            let button = ButtonNode.plain(text: title, size: size, fontSize: 15 * u, selected: card.id == chosen) {
                [weak self] in
                guard let self else { return }
                if locked {
                    self.openStore()
                } else {
                    self.choose(card)
                    self.show(.menu)
                }
            }
            add(button, to: panel, x: -width / 2 + 20 * u + size.width / 2, y: y)
            let note: String
            if card.isPractice {
                note = "Written for this game · always free"
            } else if CardLibrary.isPaid(card) {
                note = "This year's card · needs your own official card"
            } else {
                note = "Past year · free · needs your own official card"
            }
            add(Style.label(note, size: 11.5 * u, color: Style.faint), to: panel, y: y - 30 * u)
            y -= 64 * u
        }

        let close = secondary("Close", size: CGSize(width: width - 40 * u, height: 44 * u), fontSize: 17 * u) {
            [weak self] in self?.show(.menu)
        }
        add(close, to: panel, y: -height / 2 + 36 * u)
    }

    /// Where the League sells the official card.
    static let leagueURL = URL(string: "https://www.nationalmahjonggleague.org")!

    /// Where the hands viewer's Close button goes back to.
    private var handsReturn: Overlay = .cards

    /// Every hand on a card, page by page, each shown one way it can be made.
    private func buildCardHands(in panel: SKNode, width: CGFloat, height: CGFloat, cardID: String, page: Int, m: Metrics) {
        let card = (round?.card.id == cardID ? round?.card : nil) ?? CardLibrary.card(id: cardID) ?? .practice
        let rows = card.hands.map { hand -> ListRow in
            let instance = card.instances.first { $0.hand == hand.id }
            let tiles = instance.map { $0.groups.map { group in (0..<group.count).map { _ in (tile: group.tile, have: true) } } } ?? []
            return ListRow(hand: hand, status: .none, tiles: tiles)
        }
        buildHandList(in: panel, width: width, height: height, card: card, rows: rows, page: page,
                      subtitle: "Each hand is shown one way it can be made",
                      pageOverlay: { .cardHands(id: cardID, page: $0) }, m: m) { [weak self] in
            guard let self else { return }
            self.show(self.handsReturn)
        }
    }

    // MARK: - Hands, large

    /// A hand in one of the card lists.
    private struct ListRow {
        enum Status {
            /// No progress shown: reading the card away from a game.
            case none
            /// Tiles still needed, or nil when your exposures rule the hand out.
            case needed(Int?)
        }
        let hand: Hand
        let status: Status
        let tiles: [[(tile: Tile, have: Bool)]]
    }

    /// The list on screen and how to turn its pages, for the sideways swipe.
    private var paging: (page: Int, pages: Int, make: (Int) -> Overlay)?
    /// Where a single hand's Back button goes.
    private var detailReturn: Overlay = .menu

    private let largestListTile: CGFloat = 34

    /// Splits a hand's groups into lines of at most `limit` tiles, breaking between
    /// groups, and never inside a run of singles like 2026.
    private func tileLines(_ groups: [[(tile: Tile, have: Bool)]], limit: Int) -> [[[(tile: Tile, have: Bool)]]] {
        let total = groups.reduce(0) { $0 + $1.count }
        guard total > limit else { return [groups] }
        var best: (index: Int, score: Int)?
        var count = 0
        for index in 1..<groups.count {
            count += groups[index - 1].count
            let natural = groups[index].count > 1 || groups[index - 1].count > 1
            let longest = max(count, total - count)
            guard longest <= limit + 2 else { continue }
            let score = longest * 10 + (natural ? 0 : 5)
            if best == nil || score < best!.score { best = (index, score) }
        }
        let split = best?.index ?? groups.count / 2
        return [Array(groups[..<split]), Array(groups[split...])]
    }

    /// Draws a hand's tiles as large as they fit, in one or two lines. Returns the height used.
    @discardableResult
    private func addHandTiles(_ groups: [[(tile: Tile, have: Bool)]], to panel: SKNode, left: CGFloat, top: CGFloat,
                              width: CGFloat, largest: CGFloat, m: Metrics) -> CGFloat {
        let gap = 4 * m.u
        let oneLine = (width - gap * CGFloat(gapCount(groups))) / 14
        let lines = oneLine >= largest * m.u ? [groups] : tileLines(groups, limit: 8)
        let tileWidth = lines.map { line -> CGFloat in
            let count = CGFloat(line.reduce(0) { $0 + $1.count })
            return (width - gap * CGFloat(gapCount(line))) / max(count, 8)
        }.min().map { min($0, largest * m.u) } ?? largest * m.u
        let tileHeight = tileWidth * 4 / 3
        var y = top - tileHeight / 2
        for line in lines {
            addTiles(line, to: panel, left: left, y: y, tileWidth: tileWidth, gap: gap)
            y -= tileHeight + 6 * m.u
        }
        return CGFloat(lines.count) * (tileHeight + 6 * m.u)
    }

    private func neededText(_ needed: Int?) -> (String, SKColor) {
        switch needed {
        case .some(0): ("Mahjong!", Style.gold)
        case .some(let count): ("\(count) away", count <= 3 ? Style.gold : .white)
        case .none: ("ruled out", SKColor(white: 1, alpha: 0.4))
        }
    }

    /// A few hands to a page, with tiles big enough to read. Tap a hand to see it on
    /// its own; swipe sideways or use the arrows to turn the page.
    private func buildHandList(in panel: SKNode, width: CGFloat, height: CGFloat, card: Card, rows: [ListRow], page: Int,
                               subtitle: String, pageOverlay: @escaping (Int) -> Overlay, m: Metrics,
                               close: @escaping () -> Void) {
        let u = m.u
        let top = height / 2
        add(Style.label(card.title, size: 22 * u, font: Style.bold, color: Style.gold), to: panel, y: top - 28 * u)
        var y = top - 52 * u
        add(Style.label(subtitle + " · tap a hand to enlarge", size: 11.5 * u, color: Style.faint), to: panel, y: y)
        if !card.isPractice {
            y -= 26 * u
            let link = secondary("Own an official card? Buy one from the League ›", size: CGSize(width: width - 60 * u, height: 26 * u),
                                 fontSize: 12 * u, color: Style.gold) {
                UIApplication.shared.open(GameScene.leagueURL)
            }
            add(link, to: panel, y: y)
        }

        let inner = width - 32 * u
        let left = -width / 2 + 16 * u
        let probeWidth = min((inner - 12 * u) / 8, largestListTile * u)
        // Caption, two lines of tiles, and the note under them.
        let rowHeight = 16 * u + 2 * (probeWidth * 4 / 3 + 6 * u) + 22 * u
        let listTop = y - 18 * u
        let listBottom = -height / 2 + 60 * u
        let perPage = max(2, Int((listTop - listBottom) / rowHeight))
        let pages = max(1, (rows.count + perPage - 1) / perPage)
        let page = min(max(page, 0), pages - 1)
        paging = (page, pages, pageOverlay)

        y = listTop
        for row in rows.dropFirst(page * perPage).prefix(perPage) {
            let hand = row.hand
            // The whole row is a button that opens the hand on its own.
            let target = ButtonNode(text: "", size: CGSize(width: width - 16 * u, height: rowHeight - 6 * u), fontSize: 1,
                                    fill: SKColor(white: 1, alpha: 0.05), outlined: false) { [weak self] in
                guard let self else { return }
                self.detailReturn = pageOverlay(page)
                self.show(.handDetail(cardID: card.id, hand: hand.id))
            }
            add(target, to: panel, y: y - rowHeight / 2 + 3 * u)
            target.zPosition = 0.5

            let caption = "\(hand.section) · \(hand.value)\(hand.concealed ? " · concealed" : "")"
            let label = Style.label(caption, size: 12.5 * u, font: Style.bold, color: Style.faint)
            label.horizontalAlignmentMode = .left
            add(label, to: panel, x: left, y: y - 10 * u)
            if case .needed(let needed) = row.status {
                let (text, color) = neededText(needed)
                let badge = Style.label(text, size: 14 * u, font: Style.bold, color: color)
                badge.horizontalAlignmentMode = .right
                add(badge, to: panel, x: -left, y: y - 10 * u)
            }
            let used = addHandTiles(row.tiles, to: panel, left: left, top: y - 22 * u, width: inner, largest: largestListTile, m: m)
            let note = Style.label(hand.note, size: 11.5 * u, color: SKColor(white: 1, alpha: 0.65))
            note.horizontalAlignmentMode = .left
            add(note, to: panel, x: left, y: y - 22 * u - used - 6 * u)
            y -= rowHeight
        }

        let buttonY = -height / 2 + 32 * u
        if pages > 1 {
            let previous = ButtonNode.plain(text: "‹", size: CGSize(width: 50 * u, height: 40 * u), fontSize: 22 * u) { [weak self] in
                self?.show(pageOverlay((page + pages - 1) % pages))
            }
            add(previous, to: panel, x: -width / 2 + 44 * u, y: buttonY)
            add(Style.label("\(page + 1) of \(pages)", size: 13 * u, color: Style.faint), to: panel, x: -width / 2 + 110 * u, y: buttonY)
            let next = ButtonNode.plain(text: "›", size: CGSize(width: 50 * u, height: 40 * u), fontSize: 22 * u) { [weak self] in
                self?.show(pageOverlay((page + 1) % pages))
            }
            add(next, to: panel, x: -width / 2 + 176 * u, y: buttonY)
        }
        let closeButton = ButtonNode(text: "Close", size: CGSize(width: 110 * u, height: 40 * u), fontSize: 16 * u, action: close)
        add(closeButton, to: panel, x: width / 2 - 70 * u, y: buttonY)
    }

    /// One hand, as large as it fits: during a hand, the way you are closest to with
    /// the tiles you still need dimmed; otherwise one way to make it.
    private func buildHandDetail(in panel: SKNode, width: CGFloat, height: CGFloat, cardID: String, handIndex: Int, m: Metrics) {
        let u = m.u
        let inGame = round?.card.id == cardID
        let card = (inGame ? round?.card : nil) ?? CardLibrary.card(id: cardID) ?? .practice
        guard card.hands.indices.contains(handIndex) else { return }
        let hand = card.hands[handIndex]
        let top = height / 2

        add(Style.label(hand.section, size: 24 * u, font: Style.bold, color: Style.gold), to: panel, y: top - 36 * u)
        add(Style.label("\(hand.concealed ? "Concealed" : "Exposed") · worth \(hand.value)", size: 14 * u, color: Style.faint),
            to: panel, y: top - 62 * u)

        var tiles: [[(tile: Tile, have: Bool)]] = []
        var y = top - 96 * u
        if inGame, let round, let row = cardRows(for: round).first(where: { $0.hand == handIndex }) {
            tiles = row.tiles
            let color = neededText(row.needed).1
            let status: String
            switch row.needed {
            case .some(0): status = "You have this hand. Mahjong!"
            case .some(let count): status = "You need \(count) more tile\(count == 1 ? "" : "s"): " + (count <= 3 ? "close!" : "the dim ones")
            case .none: status = "Your exposed groups rule this hand out"
            }
            add(Style.label(status, size: 15 * u, font: Style.bold, color: color), to: panel, y: y)
            y -= 24 * u
        } else if let instance = card.instances.first(where: { $0.hand == handIndex }) {
            tiles = instance.groups.map { group in (0..<group.count).map { _ in (tile: group.tile, have: true) } }
        }

        let inner = width - 32 * u
        let used = addHandTiles(tiles, to: panel, left: -width / 2 + 16 * u, top: y - 8 * u, width: inner, largest: 56, m: m)
        y -= used + 26 * u
        add(paragraph(hand.note, size: 15 * u, width: inner), to: panel, y: y)

        let back = ButtonNode(text: "Back", size: CGSize(width: width - 40 * u, height: 46 * u), fontSize: 17 * u) { [weak self] in
            guard let self else { return }
            self.show(self.detailReturn)
        }
        add(back, to: panel, y: -height / 2 + 36 * u)
    }

    /// Your record over every hand you have played, with the most recent hands.
    private func buildHistory(in panel: SKNode, width: CGFloat, height: CGFloat, m: Metrics) {
        let u = m.u
        let top = height / 2
        add(Style.label("Your history", size: 24 * u, font: Style.bold, color: Style.gold), to: panel, y: top - 40 * u)

        let close = ButtonNode(text: "Close", size: CGSize(width: width - 40 * u, height: 44 * u), fontSize: 17 * u) {
            [weak self] in self?.show(.menu)
        }
        add(close, to: panel, y: -height / 2 + 36 * u)

        let summary = history.summary
        guard summary.played > 0 else {
            add(paragraph("No hands yet.\nEvery hand you finish shows up here.", size: 15 * u,
                          width: width - 48 * u, color: Style.faint), to: panel, y: 20 * u)
            return
        }

        let left = -width / 2 + 24 * u
        let right = width / 2 - 24 * u
        var y = top - 84 * u
        func row(_ title: String, _ value: String, highlight: Bool = false) {
            let name = Style.label(title, size: 14 * u, color: Style.faint)
            name.horizontalAlignmentMode = .left
            add(name, to: panel, x: left, y: y)
            let number = Style.label(value, size: 15 * u, font: Style.bold, color: highlight ? Style.gold : .white)
            number.horizontalAlignmentMode = .right
            add(number, to: panel, x: right, y: y)
            y -= 25 * u
        }
        row("Hands played", "\(summary.played)")
        row("You won", "\(summary.won) · \(Int((summary.winRate * 100).rounded()))%", highlight: true)
        row("Won on a tile you drew", "\(summary.selfDrawn)")
        row("Others won on your discard", "\(summary.fedWins)")
        row("Wall games", "\(summary.wallGames)")
        row("Points overall", signed(summary.net), highlight: summary.net > 0)
        row("Biggest win", summary.biggestWin > 0 ? "+\(summary.biggestWin)" : "–")
        row("Favourite section", summary.favouriteSection ?? "–")

        y -= 12 * u
        add(Style.label("Recent hands", size: 14 * u, font: Style.bold), to: panel, y: y)
        y -= 26 * u
        let formatter = DateFormatter()
        formatter.dateStyle = .short
        formatter.timeStyle = .none
        let roomForRows = Int((y - (-height / 2 + 70 * u)) / (24 * u))
        for hand in history.hands.suffix(max(roomForRows, 0)).reversed() {
            let what: String
            switch hand.winner {
            case nil: what = "Wall game"
            case 0?: what = "You won" + (hand.section.map { " · \($0)" } ?? "")
            case let winner?:
                let wind = hand.dealer.map { windName([Wind.east, .south, .west, .north][(winner - $0 + 4) % 4]) }
                what = "\(wind ?? positions[winner]) won" + (hand.discarder == 0 && !hand.selfDrawn ? " on your discard" : "")
            }
            let label = Style.label("\(formatter.string(from: hand.date))  \(what)", size: 13 * u)
            label.horizontalAlignmentMode = .left
            add(label, to: panel, x: left, y: y)
            let result = Style.label(signed(hand.yourResult), size: 13 * u, font: Style.bold,
                                     color: hand.yourResult > 0 ? Style.gold : .white)
            result.horizontalAlignmentMode = .right
            add(result, to: panel, x: right, y: y)
            y -= 24 * u
        }
    }

    private func buildHelp(in panel: SKNode, width: CGFloat, page index: Int, m: Metrics) {
        let u = m.u
        let pages = HelpPage.all
        let index = min(max(index, 0), pages.count - 1)
        let page = pages[index]
        let isLast = index == pages.count - 1

        add(Style.label(page.title, size: 24 * u, font: Style.bold, color: Style.gold), to: panel, y: 232 * u)

        var bodyY = 0 * u
        if page.rows.isEmpty {
            let groups = page.examples.map { group in group.map { (tile: $0, have: true) } }
            let count = CGFloat(page.examples.reduce(0) { $0 + $1.count })
            let gaps = 8 * u * CGFloat(gapCount(groups))
            let tileWidth = min((width - 40 * u - gaps) / count, 34 * u)
            let total = tileWidth * count + gaps
            addTiles(groups, to: panel, left: -total / 2, y: 166 * u, tileWidth: tileWidth, gap: 8 * u)
        } else {
            // The whole set: a label, then the tiles, every row lined up.
            let labelWidth = 50 * u
            let gap = 6 * u
            let widest = page.rows.map { row in row.groups.reduce(0) { $0 + $1.count } }.max() ?? 1
            let tileWidth = min((width - 32 * u - labelWidth - gap) / CGFloat(widest), 30 * u)
            let left = -width / 2 + 16 * u
            for (index, row) in page.rows.enumerated() {
                let y = (178 - CGFloat(index) * 48) * u
                let label = Style.label(row.label, size: 12 * u, font: Style.bold, color: Style.faint)
                label.horizontalAlignmentMode = .left
                add(label, to: panel, x: left, y: y)
                var x = left + labelWidth + tileWidth / 2
                for (groupIndex, group) in row.groups.enumerated() {
                    if groupIndex > 0 { x += gap }
                    for tile in group {
                        let node = TileNode(tile: tile)
                        node.area = .picture
                        node.setScale(tileWidth / TileArt.size.width)
                        add(node, to: panel, x: x, y: y)
                        x += tileWidth
                    }
                }
            }
            bodyY = -76 * u
        }

        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = .center
        paragraph.lineSpacing = 3 * u
        let body = SKLabelNode()
        body.attributedText = NSAttributedString(string: page.text, attributes: [
            .font: UIFont(name: Style.regular, size: 15 * u) ?? .systemFont(ofSize: 15 * u),
            .foregroundColor: SKColor.white,
            .paragraphStyle: paragraph,
        ])
        body.numberOfLines = 0
        body.preferredMaxLayoutWidth = width - 40 * u
        body.verticalAlignmentMode = .center
        add(body, to: panel, y: bodyY)

        for dot in pages.indices {
            let circle = SKShapeNode(circleOfRadius: 3.5 * u)
            circle.fillColor = dot == index ? Style.gold : SKColor(white: 1, alpha: 0.3)
            circle.strokeColor = .clear
            add(circle, to: panel, x: (CGFloat(dot) - CGFloat(pages.count - 1) / 2) * 14 * u, y: -176 * u)
        }

        let size = CGSize(width: (width - 52 * u) / 2, height: 46 * u)
        let close: () -> Void = { [weak self] in
            UserDefaults.standard.set(true, forKey: HelpPage.seenKey)
            // Opened mid-game, the instructions go back to the game menu.
            self?.show(self?.round != nil ? .gameMenu : .menu)
        }
        let back = secondary(index == 0 ? "Skip" : "Back", size: size, fontSize: 17 * u) { [weak self] in
            if index == 0 { close() } else { self?.show(.help(page: index - 1)) }
        }
        add(back, to: panel, x: -(size.width / 2 + 6 * u), y: -224 * u)
        let next = ButtonNode(text: isLast ? "Done" : "Next", size: size, fontSize: 17 * u) { [weak self] in
            if isLast { close() } else { self?.show(.help(page: index + 1)) }
        }
        add(next, to: panel, x: size.width / 2 + 6 * u, y: -224 * u)
    }

    /// The card that is for sale, by name, for the store's wording.
    private var currentCardName: String {
        CardLibrary.currentYear.map { "the \($0) card" } ?? "this year's card"
    }

    /// The title, description and button style for each thing on sale.
    private func describeOffer(_ id: String) -> (title: String, detail: String) {
        let year = CardLibrary.currentYear.map(String.init) ?? "This year's"
        switch id {
        case StoreOffers.upgradeID:
            return store.currentYear != nil && store.ownsCard(store.currentYear!)
                ? ("Upgrade to the full game", "You have \(currentCardName). Add history and game options.")
                : ("Full game", "History, stats and game options")
        case let id where id.hasPrefix("mahjong.fullgame."):
            return ("Full game", "\(year) card, plus history and game options")
        default:
            return ("\(year) card", "Play \(currentCardName). Next year's card is sold separately.")
        }
    }

    private func buildStore(in panel: SKNode, width: CGFloat, m: Metrics) {
        let u = m.u
        let faint = SKColor(white: 1, alpha: 0.7)
        add(Style.label("Mahjong: Full Game", size: 24 * u, font: Style.bold, color: Style.gold), to: panel, y: 210 * u)

        // What you have.
        var owned: [String] = []
        if let year = store.currentYear, store.ownsCard(year) { owned.append("✓ The \(year) card") }
        if store.hasFullGame { owned.append("✓ Full game: history and game options") }
        var y: CGFloat = 172 * u
        for line in owned {
            add(Style.label(line, size: 15 * u, font: Style.bold, color: Style.gold), to: panel, y: y)
            y -= 24 * u
        }
        if store.ownsEverything {
            add(paragraph("You have everything. Thank you for supporting Mahjong!", size: 15 * u,
                          width: width - 48 * u), to: panel, y: y - 20 * u)
            y -= 70 * u
        } else {
            y -= 8 * u
            // What you can buy, best first.
            let wide = CGSize(width: width - 40 * u, height: 48 * u)
            for (index, offer) in store.offers.enumerated() {
                let info = describeOffer(offer.id)
                let price = offer.product?.displayPrice
                let text = info.title + (price.map { " · \($0)" } ?? "")
                let button: ButtonNode
                if let product = offer.product {
                    button = index == 0
                        ? ButtonNode(text: text, size: wide, fontSize: 18 * u) { [weak self] in self?.purchase(product) }
                        : secondary(text, size: wide, fontSize: 17 * u) { [weak self] in self?.purchase(product) }
                } else {
                    button = secondary(info.title + (store.hasLoaded ? " · unavailable" : " · loading…"),
                                       size: wide, fontSize: 16 * u, color: faint) {}
                }
                add(button, to: panel, y: y - 24 * u)
                add(Style.label(info.detail, size: 12 * u, color: faint), to: panel, y: y - 60 * u)
                y -= 84 * u
            }
        }

        if !store.hasFullGame {
            add(Style.label("Game options: Charleston off, the wall and dice, call time.", size: 12 * u, color: faint),
                to: panel, y: y + 6 * u)
            y -= 14 * u
        }
        if let year = store.currentYear, !store.ownsCard(year) {
            add(Style.label("You also need your own official \(year) card from the League.", size: 12 * u, color: faint),
                to: panel, y: y + 6 * u)
            y -= 14 * u
            add(Style.label("The League's printed card doesn't unlock it here.", size: 12 * u, color: faint),
                to: panel, y: y + 6 * u)
            y -= 14 * u
        }
        add(Style.label("Past years' cards are always free.", size: 12.5 * u, color: faint), to: panel, y: y - 6 * u)
        let small = CGSize(width: (width - 50 * u) / 2, height: 30 * u)
        let restore = secondary("Restore purchases", size: small, fontSize: 13 * u) { [weak self] in
            self?.restorePurchases()
        }
        add(restore, to: panel, x: -(small.width / 2 + 5 * u), y: y - 40 * u)
        let redeem = secondary("Redeem code", size: small, fontSize: 13 * u) { [weak self] in
            self?.redeemCode()
        }
        add(redeem, to: panel, x: small.width / 2 + 5 * u, y: y - 40 * u)
        add(Style.label(storeMessage, size: 14 * u, font: Style.bold, color: Style.gold), to: panel, y: y - 74 * u)
        if store.currentYear != nil {
            let link = secondary("Buy an official card from the League ›", size: CGSize(width: width - 40 * u, height: 30 * u),
                                 fontSize: 13 * u, color: Style.gold) {
                UIApplication.shared.open(GameScene.leagueURL)
            }
            add(link, to: panel, y: -112 * u)
        }

        // Hidden support tool: five taps on the title show what the App Store told the app.
        let secret = ButtonNode(text: "", size: CGSize(width: 240 * u, height: 36 * u), fontSize: 1,
                                fill: .clear, outlined: false) { [weak self] in
            guard let self else { return }
            self.storeTitleTaps += 1
            if self.storeTitleTaps >= 5 {
                self.storeTitleTaps = 0
                self.showsStoreDiagnostics.toggle()
                self.rebuildOverlay()
            }
        }
        add(secret, to: panel, y: 210 * u)
        if showsStoreDiagnostics {
            let detail = Style.label(store.diagnostics, size: 9.5 * u, color: SKColor(white: 1, alpha: 0.55))
            detail.numberOfLines = 0
            detail.preferredMaxLayoutWidth = width - 32 * u
            add(detail, to: panel, y: y - 104 * u)
        }

        let wide = CGSize(width: width - 40 * u, height: 46 * u)
        let tips = secondary("Tip jar", size: wide, fontSize: 17 * u, color: Style.gold) { [weak self] in
            self?.openTipJar(returningTo: .store)
        }
        add(tips, to: panel, y: -160 * u)
        let close = secondary("Close", size: wide, fontSize: 18 * u) { [weak self] in
            guard let self else { return }
            self.show(self.storeReturn)
        }
        add(close, to: panel, y: -214 * u)
    }

    /// Optional tips. They never unlock anything.
    private func buildTipJar(in panel: SKNode, width: CGFloat, m: Metrics) {
        let u = m.u
        let faint = SKColor(white: 1, alpha: 0.7)
        add(Style.label("Tip jar", size: 26 * u, font: Style.bold, color: Style.gold), to: panel, y: 160 * u)
        add(paragraph("Enjoying the game? A tip helps a small studio keep making it. Tips are optional and don't unlock anything.",
                      size: 14.5 * u, width: width - 48 * u), to: panel, y: 96 * u)

        let tipY: CGFloat = 20 * u
        if store.tips.isEmpty {
            add(Style.label(store.hasLoaded ? "Tips are unavailable right now." : "Loading…",
                            size: 14 * u, color: faint), to: panel, y: tipY)
        } else {
            let count = CGFloat(store.tips.count)
            let size = CGSize(width: (width - 40 * u - (count - 1) * 10 * u) / count, height: 46 * u)
            for (index, tip) in store.tips.enumerated() {
                let x = (CGFloat(index) - (count - 1) / 2) * (size.width + 10 * u)
                let button = ButtonNode(text: tip.displayPrice, size: size, fontSize: 17 * u) { [weak self] in
                    self?.purchase(tip)
                }
                add(button, to: panel, x: x, y: tipY)
                add(Style.label(tip.displayName, size: 12 * u, color: faint), to: panel, x: x, y: tipY - 36 * u)
            }
        }
        add(Style.label(storeMessage, size: 14 * u, font: Style.bold, color: Style.gold), to: panel, y: -70 * u)

        let close = secondary("Close", size: CGSize(width: width - 40 * u, height: 46 * u), fontSize: 18 * u) {
            [weak self] in guard let self else { return }; self.show(self.tipReturn)
        }
        add(close, to: panel, y: -150 * u)
    }

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
        guard let round else { return }
        let card = round.card
        let rows = cardRows(for: round).map { row in
            ListRow(hand: card.hands[row.hand], status: .needed(row.needed), tiles: row.tiles)
        }
        buildHandList(in: panel, width: width, height: height, card: card, rows: rows, page: page,
                      subtitle: "Closest first · dim tiles are ones you still need",
                      pageOverlay: { .card(page: $0) }, m: m) { [weak self] in
            self?.closeOverlay()
        }
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
            let title = win.winner == 0 ? "Mahjong! You win" : "\(name(win.winner)) wins"
            add(Style.label(title, size: 26 * u, font: Style.bold, color: Style.gold), to: panel, y: y)
            y -= 30 * u
            let hand = round.card.hands[win.hand]
            var how = "Drawn from the wall"
            if let discarder = win.discarder, !win.selfDrawn {
                how = discarder == 0 ? "On your discard" : "On \(name(discarder))'s discard"
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
            cell(name(player), column: 0, y: y, bold: player == 0)
            cell(paymentText, column: 1, y: y, color: payment > 0 ? Style.gold : .white)
            cell("\(scorepad.scores[player])", column: 2, y: y, bold: true)
            y -= 28 * u
        }

        y -= 14 * u
        add(Style.label("Hand \(scorepad.handsPlayed) on this scorepad", size: 13 * u, color: Style.faint), to: panel, y: y)
        let size = CGSize(width: (width - 52 * u) / 2, height: 46 * u)
        let next = ButtonNode(text: "Next hand", size: size, fontSize: 17 * u) { [weak self] in
            self?.overlay = nil
            self?.rebuildOverlay()
            self?.startRound()
        }
        add(next, to: panel, x: -(size.width / 2 + 6 * u), y: -190 * u)
        let menu = secondary("Main menu", size: size, fontSize: 17 * u) { [weak self] in
            self?.goToMainMenu()
        }
        add(menu, to: panel, x: size.width / 2 + 6 * u, y: -190 * u)
    }

    private func buildGameMenu(in panel: SKNode, width: CGFloat, m: Metrics) {
        let u = m.u
        add(Style.label("Game menu", size: 24 * u, font: Style.bold, color: Style.gold), to: panel, y: 178 * u)

        let wide = CGSize(width: width - 40 * u, height: 44 * u)
        let back = ButtonNode(text: "Back to game", size: wide, fontSize: 18 * u) { [weak self] in
            self?.closeOverlay()
        }
        add(back, to: panel, y: 124 * u)
        let options = secondary("Options", size: wide, fontSize: 17 * u) { [weak self] in
            self?.openOptions(returningTo: .gameMenu)
        }
        add(options, to: panel, y: 72 * u)
        // Only the card in play: that's the one that matters mid-hand.
        let cardID = round?.card.id ?? chosenCard.id
        let seeCard = secondary("See the card", size: wide, fontSize: 17 * u) { [weak self] in
            self?.handsReturn = .gameMenu
            self?.show(.cardHands(id: cardID, page: 0))
        }
        add(seeCard, to: panel, y: 20 * u)
        let help = secondary("How to play", size: wide, fontSize: 17 * u) { [weak self] in
            self?.show(.help(page: 0))
        }
        add(help, to: panel, y: -32 * u)
        let feedbackButton = secondary("Send feedback", size: wide, fontSize: 17 * u) { [weak self] in
            self?.sendFeedback()
        }
        add(feedbackButton, to: panel, y: -84 * u)
        let menu = secondary("Main menu", size: wide, fontSize: 17 * u) { [weak self] in
            self?.goToMainMenu()
        }
        add(menu, to: panel, y: -136 * u)
        add(Style.label("The game waits while this menu is open.", size: 12 * u, color: Style.faint), to: panel, y: -178 * u)
    }

    /// Features on the way, from ComingSoon.swift.
    private func comingSoonLines(width: CGFloat, u: CGFloat) -> [SKLabelNode] {
        ComingSoon.items.map { item in
            let line = paragraph("•  " + item, size: 15 * u, width: width - 48 * u)
            line.horizontalAlignmentMode = .center
            return line
        }
    }

    private func buildComingSoon(in panel: SKNode, width: CGFloat, height: CGFloat, m: Metrics) {
        let u = m.u
        let top = height / 2
        add(Style.label("What's next", size: 24 * u, font: Style.bold, color: Style.gold), to: panel, y: top - 40 * u)
        add(Style.label("Coming to Mahjong. Plans can change.", size: 12.5 * u, color: Style.faint), to: panel, y: top - 66 * u)
        // Each item sits under the last by its own height, one line or two.
        var y = top - 96 * u
        for line in comingSoonLines(width: width, u: u) {
            let h = line.frame.height
            add(line, to: panel, y: y - h / 2)
            y -= h + 16 * u
        }
        let close = secondary("Close", size: CGSize(width: width - 40 * u, height: 44 * u), fontSize: 17 * u) {
            [weak self] in self?.show(.more)
        }
        add(close, to: panel, y: -height / 2 + 36 * u)
    }

    // MARK: - Debug

    #if DEBUG
    /// Plays seeded bot hands until `stop` says the position is a good picture.
    private func screenshotRound(_ stop: (Round) -> Bool) -> Round? {
        for seed in UInt64(1)...200 {
            var generator = SeededGenerator(seed: seed)
            var round = Round.deal(card: .practice, dealer: 0, charleston: true, using: &generator)
            var moves = 0
            while round.outcome == nil && moves < 600 {
                if stop(round) { return round }
                guard let actor = round.actors.first, let move = Bot.chooseMove(in: round, for: actor) else { break }
                try? round.apply(move, by: actor)
                moves += 1
            }
        }
        return nil
    }

    /// A still position for an App Store screenshot, on the practice card.
    private func showScreenshot(_ kind: String) {
        frozen = true
        overlay = nil
        // A scorepad with a few hands on it where you are ahead, so the scores look lived in.
        for seed in UInt64(3)...40 {
            var generator = SeededGenerator(seed: seed)
            var pad = Scorepad()
            for _ in 0..<5 {
                var hand = pad.deal(card: .practice, charleston: false, using: &generator)
                while hand.outcome == nil, let actor = hand.actors.first, let move = Bot.chooseMove(in: hand, for: actor) {
                    try? hand.apply(move, by: actor)
                }
                pad.record(hand)
            }
            scorepad = pad
            if pad.scores[0] > 0 { break }
        }
        relayout()

        let found: Round?
        switch kind {
        case "charleston":
            found = screenshotRound { if case .charleston(.firstRight) = $0.phase { return true }; return false }
        case "claim":
            found = screenshotRound { round in
                guard case .claim = round.phase, !round.isWaitingForDraw, round.actors.contains(0),
                      round.discards.count >= 12 else { return false }
                return round.legalMoves(for: 0).contains { if case .call = $0 { return true }; return false }
            }
        default:
            found = screenshotRound { round in
                guard case .discard(0) = round.phase, round.drawn != nil, round.discards.count >= 16 else { return false }
                return round.exposures.reduce(0) { $0 + $1.count } >= 3 && !round.exposures[0].isEmpty
            }
        }
        guard let found else { return }
        round = found
        roundRecorded = false
        switch kind {
        case "charleston":
            eventText = "Hand 6. You are East and deal."
            selection = [3, 7, 11]
        case "claim":
            let discard = found.discards.last!
            eventText = "\(name(discard.player)) discarded \(discard.tile)"
        default:
            eventText = "Left discarded \(found.discards.last!.tile). You drew \(found.drawn!)."
        }
        sync(animated: false)
        refreshHUD()
        if kind == "claim" {
            advance()
            // Hold the call window's bar partway down.
            claimBar?.removeAllActions()
            claimBar?.xScale = 0.6
        }
        switch kind {
        case "card": show(.card(page: 0))
        case "detail":
            if let best = cardRows(for: found).first {
                detailReturn = .card(page: 0)
                show(.handDetail(cardID: found.card.id, hand: best.hand))
            }
        case "magnify":
            if let node = tileNodes.first(where: { $0.area == .rack && $0.rackIndex == 4 }) {
                showMagnifier(for: node.tile, at: node.position)
            }
        default: break
        }
    }

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
