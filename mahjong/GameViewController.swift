//
//  GameViewController.swift
//  mahjong
//

import UIKit
import SpriteKit

class GameViewController: UIViewController {

    private var gameScene: GameScene?

    override func viewDidLoad() {
        super.viewDidLoad()

        guard let view = self.view as? SKView else { return }
        let scene = GameScene(size: view.bounds.size)
        scene.scaleMode = .resizeFill
        view.presentScene(scene)
        gameScene = scene
    }

    override var supportedInterfaceOrientations: UIInterfaceOrientationMask {
        UIDevice.current.userInterfaceIdiom == .phone ? .portrait : .all
    }

    override var prefersStatusBarHidden: Bool { true }
}
