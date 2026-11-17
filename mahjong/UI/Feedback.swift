//
//  Feedback.swift
//  mahjong
//
//  "Send feedback": an email to the studio with a screenshot of the table and the
//  details that help with a bug report. The player can add photos or videos in Mail.
//

import MessageUI
import UIKit

final class Feedback: NSObject, MFMailComposeViewControllerDelegate {
    static let address = "info@tuesdaygames.com"

    /// Called when the email (or share sheet) is closed, so the game can carry on.
    private var onClose: (() -> Void)?

    /// What the app and the device are, for the body of the email.
    static func details(extra: [String]) -> String {
        let info = Bundle.main.infoDictionary
        let version = info?["CFBundleShortVersionString"] as? String ?? "?"
        let build = info?["CFBundleVersion"] as? String ?? "?"
        var model = utsname()
        uname(&model)
        let machine = withUnsafeBytes(of: &model.machine) { raw in
            String(decoding: raw.prefix { $0 != 0 }, as: UTF8.self)
        }
        let lines = [
            "App: Mahjong \(version) (\(build))",
            "Device: \(machine), \(UIDevice.current.systemName) \(UIDevice.current.systemVersion)",
        ] + extra
        return lines.joined(separator: "\n")
    }

    /// Opens an email with the screenshot attached, or the share sheet if Mail isn't set up.
    func present(from controller: UIViewController, screenshot: UIImage?, extra: [String], onClose: @escaping () -> Void) {
        self.onClose = onClose
        let body = "What happened, or what would you like to see?\n\n\n\n—\n" + Feedback.details(extra: extra)

        if MFMailComposeViewController.canSendMail() {
            let mail = MFMailComposeViewController()
            mail.mailComposeDelegate = self
            mail.setToRecipients([Feedback.address])
            mail.setSubject("Mahjong feedback")
            mail.setMessageBody(body, isHTML: false)
            if let data = screenshot?.pngData() {
                mail.addAttachmentData(data, mimeType: "image/png", fileName: "mahjong.png")
            }
            controller.present(mail, animated: true)
        } else {
            var items: [Any] = ["Send to \(Feedback.address)\n\n" + body]
            if let screenshot { items.append(screenshot) }
            let share = UIActivityViewController(activityItems: items, applicationActivities: nil)
            share.popoverPresentationController?.sourceView = controller.view
            share.popoverPresentationController?.sourceRect = CGRect(
                x: controller.view.bounds.midX, y: controller.view.bounds.midY, width: 1, height: 1)
            share.completionWithItemsHandler = { [weak self] _, _, _, _ in self?.finish() }
            controller.present(share, animated: true)
        }
    }

    func mailComposeController(_ controller: MFMailComposeViewController, didFinishWith result: MFMailComposeResult, error: Error?) {
        controller.dismiss(animated: true) { [weak self] in self?.finish() }
    }

    private func finish() {
        let close = onClose
        onClose = nil
        close?()
    }
}
