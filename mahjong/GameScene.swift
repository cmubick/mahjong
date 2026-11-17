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
    private let names = ["You", "Right", "Across", "Left"]

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
        case summary(payments: [Int])
        case gameMenu
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

        /// Where a discard waits, large, while it can still be called: low in the
        /// middle of the discard area.
        var claimSpot: CGPoint {
            CGPoint(x: size.width / 2, y: pileBottom + rackTile * 2 / 3 + 14 * u)
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
        dealLayer.zPosition = 500
        overlayLayer.zPosition = 1000
        addChild(tileLayer)
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
        let next = scorepad.deal(card: chosenCard, charleston: charleston, using: &generator)
        round = next
        let dealer = next.dealer == 0 ? "You are East and deal" : "\(names[next.dealer]) is East and deals"
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
        stalled = false
        endWindow()
    }

    private func isLocked(_ card: Card) -> Bool {
        CardLibrary.isPaid(card) && !store.ownsCard(card.year ?? 0)
    }

    /// Bots wait while a panel is open or the tiles are being dealt.
    private var botsWait: Bool { overlay != nil || isDealing }

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
        let wall = m.wall
        let rack = tileNodes.filter { $0.area == .rack }.sorted { ($0.rackIndex ?? 0) < ($1.rackIndex ?? 0) }
        let step = 0.09
        var time = 0.0
        var dealtToYou = 0

        for lap in 0..<4 {
            for seat in 0..<4 {
                let player = (round.dealer + seat) % 4
                let count = lap < 3 ? 4 : (player == round.dealer ? 2 : 1)
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

    /// Ends the deal at once with every tile in place.
    private func skipDeal() {
        guard isDealing else { return }
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
        let game = SavedGame(scorepad: scorepad, round: roundRecorded ? nil : round)
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

    private func openTipJar() {
        storeMessage = ""
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
        case .decline, .draw:
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

        // Your rack, in rows of seven.
        let hand = round.hands[0]
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
            let wind = windName(round.seatWind(of: player))
            let detail = "\(wind) · \(round.hands[player].count) · \(scorepad.scores[player])"
            badges[player]?.update(name: names[player], detail: detail, active: active)
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

        let actions = autoplay || isDealing ? [] : choices(for: round)
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
        if isDealing { return "Dealing…" }
        guard round.actors.contains(0), !round.isWaitingForDraw, !autoplay else {
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
                let tile = round.hands[0][index]
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
        guard let round, round.actors.contains(0), !autoplay else { return }

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
        case .menu: height = 540 * m.u
        case .help: height = 540 * m.u
        case .store: height = 520 * m.u
        case .tipJar: height = 400 * m.u
        case .cards: height = min(CGFloat(170 + CardLibrary.all.count * 64) * m.u, fullHeight)
        case .cardHands:
            width = min(size.width - 24 * m.u, 420 * m.u)
            height = min(640 * m.u, fullHeight)
        case .history: height = min(600 * m.u, fullHeight)
        case .newHandConfirm, .clearConfirm: height = 250 * m.u
        case .card:
            width = min(size.width - 24 * m.u, 420 * m.u)
            height = min(560 * m.u, fullHeight)
        case .summary:
            width = min(size.width - 24 * m.u, 420 * m.u)
            height = 470 * m.u
        case .gameMenu: height = 436 * m.u
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
        add(Style.label("Mahjong", size: 44 * u, font: Style.bold, color: Style.gold), to: panel, y: 222 * u)
        add(Style.label("American style · You and three bots", size: 14 * u, color: SKColor(white: 1, alpha: 0.8)),
            to: panel, y: 188 * u)

        let sound = secondary(Sounds.shared.isMuted ? "Sound off" : "Sound on",
                              size: CGSize(width: 76 * u, height: 22 * u), fontSize: 11 * u) { [weak self] in
            Sounds.shared.isMuted.toggle()
            self?.rebuildOverlay()
        }
        add(sound, to: panel, x: width / 2 - 50 * u, y: 249 * u)

        let wide = CGSize(width: width - 40 * u, height: 40 * u)
        add(Style.label("Card", size: 14 * u, font: Style.bold), to: panel, y: 150 * u)
        let cardButton = ButtonNode.plain(text: chosenCard.title + "  ›", size: wide, fontSize: 15 * u) { [weak self] in
            self?.show(.cards)
        }
        add(cardButton, to: panel, y: 116 * u)

        add(Style.label("Charleston", size: 14 * u, font: Style.bold), to: panel, y: 78 * u)
        let half = CGSize(width: (width - 52 * u) / 2, height: 40 * u)
        for (index, on) in [true, false].enumerated() {
            let locked = !on && !unlocked
            let button = ButtonNode.plain(text: (on ? "On" : "Off") + (locked ? lock : ""), size: half, fontSize: 15 * u,
                                          selected: charleston == on) { [weak self] in
                if locked { self?.openStore(); return }
                self?.charleston = on
                self?.rebuildOverlay()
            }
            add(button, to: panel, x: (index == 0 ? -1 : 1) * (half.width / 2 + 6 * u), y: 44 * u)
        }

        add(Style.label("Time to call each discard", size: 14 * u, font: Style.bold), to: panel, y: 6 * u)
        let third = CGSize(width: (width - 56 * u) / 3, height: 40 * u)
        for (index, seconds) in GameScene.callTimes.enumerated() {
            let locked = seconds != 3 && !unlocked
            let button = ButtonNode.plain(text: "\(Int(seconds)) sec" + (locked ? lock : ""), size: third, fontSize: 15 * u,
                                          selected: callSeconds == seconds) { [weak self] in
                if locked { self?.openStore(); return }
                self?.callSeconds = seconds
                self?.rebuildOverlay()
            }
            add(button, to: panel, x: CGFloat(index - 1) * (third.width + 8 * u), y: -28 * u)
        }

        // The scorepad: your running total, and a way to start a fresh sheet.
        let tally = scorepad.handsPlayed == 0
            ? "Scorepad: no hands yet"
            : "Scorepad: you \(signed(scorepad.scores[0])) after \(scorepad.handsPlayed) hand\(scorepad.handsPlayed == 1 ? "" : "s")"
        let tallyLabel = Style.label(tally, size: 13 * u, color: Style.faint)
        if scorepad.handsPlayed > 0 {
            tallyLabel.horizontalAlignmentMode = .left
            add(tallyLabel, to: panel, x: -width / 2 + 22 * u, y: -66 * u)
            let clear = secondary("Clear", size: CGSize(width: 64 * u, height: 26 * u), fontSize: 12 * u) { [weak self] in
                self?.show(.clearConfirm)
            }
            add(clear, to: panel, x: width / 2 - 54 * u, y: -66 * u)
        } else {
            add(tallyLabel, to: panel, y: -66 * u)
        }

        let primary = CGSize(width: half.width, height: 50 * u)
        if savedHand != nil {
            let resume = ButtonNode(text: "Resume hand", size: primary, fontSize: 17 * u) { [weak self] in
                self?.resumeHand()
            }
            add(resume, to: panel, x: -(half.width / 2 + 6 * u), y: -112 * u)
            let fresh = secondary("New hand", size: primary, fontSize: 17 * u) { [weak self] in
                self?.show(.newHandConfirm)
            }
            add(fresh, to: panel, x: half.width / 2 + 6 * u, y: -112 * u)
        } else {
            let deal = ButtonNode(text: "Deal", size: CGSize(width: width - 40 * u, height: 50 * u), fontSize: 20 * u) {
                [weak self] in self?.dealNewHand()
            }
            add(deal, to: panel, y: -112 * u)
        }

        let small = CGSize(width: half.width, height: 44 * u)
        let help = secondary("How to play", size: small, fontSize: 16 * u) { [weak self] in
            self?.show(.help(page: 0))
        }
        add(help, to: panel, x: -(half.width / 2 + 6 * u), y: -172 * u)
        let historyButton = secondary("History" + (unlocked ? "" : lock), size: small, fontSize: 16 * u) { [weak self] in
            if unlocked { self?.show(.history) } else { self?.openStore() }
        }
        add(historyButton, to: panel, x: half.width / 2 + 6 * u, y: -172 * u)
        let storeButton = secondary(store.ownsEverything ? "Full game ✓" : (unlocked ? "This year's card" : "Unlock full game"),
                                    size: small, fontSize: 15 * u, color: Style.gold) { [weak self] in
            self?.openStore()
        }
        add(storeButton, to: panel, x: -(half.width / 2 + 6 * u), y: -224 * u)
        let tipButton = secondary("Tip jar", size: small, fontSize: 16 * u, color: Style.gold) { [weak self] in
            self?.openTipJar()
        }
        add(tipButton, to: panel, x: half.width / 2 + 6 * u, y: -224 * u)
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
        let u = m.u
        let card = (round?.card.id == cardID ? round?.card : nil) ?? CardLibrary.card(id: cardID) ?? .practice
        let top = height / 2
        add(Style.label(card.title, size: 22 * u, font: Style.bold, color: Style.gold), to: panel, y: top - 30 * u)

        var y = top - 56 * u
        if !card.isPractice {
            add(Style.label("Play with your own official card from the League.", size: 11.5 * u, color: Style.faint),
                to: panel, y: y)
            let link = secondary("Buy an official card ›", size: CGSize(width: 190 * u, height: 26 * u),
                                 fontSize: 12 * u, color: Style.gold) {
                UIApplication.shared.open(GameScene.leagueURL)
            }
            add(link, to: panel, y: y - 24 * u)
            y -= 52 * u
        } else {
            add(Style.label("Each hand is shown one way it can be made.", size: 11.5 * u, color: Style.faint),
                to: panel, y: y)
            y -= 22 * u
        }

        let rowHeight = 62 * u
        let firstRow = y - 22 * u
        // Each row reaches about 40 points below its caption; keep clear of the buttons.
        let perPage = max(3, Int((firstRow - (-height / 2 + 100 * u)) / rowHeight) + 1)
        let pages = max(1, (card.hands.count + perPage - 1) / perPage)
        let page = min(max(page, 0), pages - 1)
        let left = -width / 2 + 16 * u
        let space = width - 32 * u
        y = firstRow
        for hand in card.hands.dropFirst(page * perPage).prefix(perPage) {
            let caption = "\(hand.section) · \(hand.value)\(hand.concealed ? " · concealed" : "")"
            let label = Style.label(caption, size: 11.5 * u, font: Style.bold, color: Style.faint)
            label.horizontalAlignmentMode = .left
            add(label, to: panel, x: left, y: y + 14 * u)
            if let instance = card.instances.first(where: { $0.hand == hand.id }) {
                let groups = instance.groups.map { group in (0..<group.count).map { _ in (group.tile, true) } }
                let gaps = 3 * u * CGFloat(gapCount(groups))
                let tileWidth = min((space - gaps) / 14, 22 * u)
                addTiles(groups, to: panel, left: left, y: y - 8 * u, tileWidth: tileWidth, gap: 3 * u)
            }
            let note = Style.label(hand.note, size: 11 * u, color: SKColor(white: 1, alpha: 0.6))
            note.horizontalAlignmentMode = .left
            add(note, to: panel, x: left, y: y - 30 * u)
            y -= rowHeight
        }

        let buttonY = -height / 2 + 32 * u
        if pages > 1 {
            let previous = ButtonNode.plain(text: "‹", size: CGSize(width: 50 * u, height: 40 * u), fontSize: 22 * u) {
                [weak self] in self?.show(.cardHands(id: cardID, page: (page + pages - 1) % pages))
            }
            add(previous, to: panel, x: -width / 2 + 44 * u, y: buttonY)
            add(Style.label("\(page + 1) of \(pages)", size: 13 * u, color: Style.faint), to: panel, x: -width / 2 + 110 * u, y: buttonY)
            let next = ButtonNode.plain(text: "›", size: CGSize(width: 50 * u, height: 40 * u), fontSize: 22 * u) {
                [weak self] in self?.show(.cardHands(id: cardID, page: (page + 1) % pages))
            }
            add(next, to: panel, x: -width / 2 + 176 * u, y: buttonY)
        }
        let close = ButtonNode(text: "Close", size: CGSize(width: 110 * u, height: 40 * u), fontSize: 16 * u) { [weak self] in
            guard let self else { return }
            self.show(self.handsReturn)
        }
        add(close, to: panel, x: width / 2 - 70 * u, y: buttonY)
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
                what = "\(names[winner]) won" + (hand.discarder == 0 && !hand.selfDrawn ? " on your discard" : "")
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
            add(Style.label("Game options: no Charleston, and 2 or 5 seconds to call.", size: 12 * u, color: faint),
                to: panel, y: y + 6 * u)
            y -= 14 * u
        }
        if let year = store.currentYear, !store.ownsCard(year) {
            add(Style.label("You also need your own official \(year) card from the League.", size: 12 * u, color: faint),
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
            self?.openTipJar()
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
            [weak self] in self?.show(.menu)
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

        let wide = CGSize(width: width - 40 * u, height: 46 * u)
        let back = ButtonNode(text: "Back to game", size: wide, fontSize: 18 * u) { [weak self] in
            self?.closeOverlay()
        }
        add(back, to: panel, y: 120 * u)
        let sound = secondary(Sounds.shared.isMuted ? "Sound: off" : "Sound: on", size: wide, fontSize: 17 * u) {
            [weak self] in
            Sounds.shared.isMuted.toggle()
            self?.rebuildOverlay()
        }
        add(sound, to: panel, y: 64 * u)
        let timeLocked = !store.hasFullGame
        let time = secondary("Time to call: \(Int(callSeconds)) sec" + (timeLocked ? " \u{1F512}" : ""),
                             size: wide, fontSize: 17 * u) { [weak self] in
            guard let self else { return }
            if timeLocked {
                self.openStore(returningTo: .gameMenu)
                return
            }
            let times = GameScene.callTimes
            let index = times.firstIndex(of: self.callSeconds) ?? 0
            self.callSeconds = times[(index + 1) % times.count]
            self.rebuildOverlay()
        }
        add(time, to: panel, y: 8 * u)
        // Only the card in play: that's the one that matters mid-hand.
        let cardID = round?.card.id ?? chosenCard.id
        let seeCard = secondary("See the card", size: wide, fontSize: 17 * u) { [weak self] in
            self?.handsReturn = .gameMenu
            self?.show(.cardHands(id: cardID, page: 0))
        }
        add(seeCard, to: panel, y: -48 * u)
        let help = secondary("How to play", size: wide, fontSize: 17 * u) { [weak self] in
            self?.show(.help(page: 0))
        }
        add(help, to: panel, y: -104 * u)
        let menu = secondary("Main menu", size: wide, fontSize: 17 * u) { [weak self] in
            self?.goToMainMenu()
        }
        add(menu, to: panel, y: -160 * u)
        add(Style.label("The game waits while this menu is open.", size: 12 * u, color: Style.faint), to: panel, y: -198 * u)
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
