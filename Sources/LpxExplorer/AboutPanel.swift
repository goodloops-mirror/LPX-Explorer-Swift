import AppKit
import LpxCore

/// The standard About panel with Good Loops branding, acknowledgements and (when configured) the repository / coffee links.
/// Links are handed to the system as clickable text and open in the user's browser; the app makes no request itself.
enum AboutPanel {
    static func show() {
        let center = NSMutableParagraphStyle()
        center.alignment = .center
        center.paragraphSpacing = 6
        let body: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: 11), .foregroundColor: NSColor.labelColor, .paragraphStyle: center]

        let credits = NSMutableAttributedString()
        if let url = Bundle.main.url(forResource: "GoodLoopsLogo", withExtension: "png"), let image = NSImage(contentsOf: url) {
            let attachment = NSTextAttachment()
            attachment.image = image
            attachment.bounds = CGRect(x: 0, y: 0, width: 72, height: 72)
            let logo = NSMutableAttributedString(attachment: attachment)
            if let link = URL(string: AboutInfo.companyURL) { logo.addAttribute(.link, value: link, range: NSRange(location: 0, length: logo.length)) }
            logo.addAttribute(.paragraphStyle, value: center, range: NSRange(location: 0, length: logo.length))
            credits.append(logo)
            credits.append(NSAttributedString(string: "\n", attributes: body))
        }
        for line in AboutInfo.credits() {
            for segment in line.segments {
                var attributes = body
                if let target = segment.link, let url = URL(string: target) { attributes[.link] = url }
                credits.append(NSAttributedString(string: segment.text, attributes: attributes))
            }
            credits.append(NSAttributedString(string: "\n", attributes: body))
        }

        var options: [NSApplication.AboutPanelOptionKey: Any] = [
            .applicationName: "LPX Explorer",
            .credits: credits,
            NSApplication.AboutPanelOptionKey(rawValue: "Copyright"): AboutInfo.copyright,
        ]
        if Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") == nil { options[.applicationVersion] = "development build" }
        NSApplication.shared.orderFrontStandardAboutPanel(options: options)
        NSApplication.shared.activate(ignoringOtherApps: true)
    }
}
