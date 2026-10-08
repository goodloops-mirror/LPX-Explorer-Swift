import AppKit
import LpxCore
import SwiftUI

/// The About window: resizable, follows light/dark, with Good Loops branding, the acknowledgement of the original author,
/// the licence and (once configured) the source / coffee links. Links open in the user's browser; the app requests nothing.
struct AboutView: View {
    private var versionText: String {
        let info = Bundle.main.infoDictionary
        return AboutInfo.versionText(short: info?["CFBundleShortVersionString"] as? String,
                                     build: info?["CFBundleVersion"] as? String,
                                     describe: info?["LpxBuildDescription"] as? String)
    }

    private func attributed(_ line: AboutInfo.Line) -> AttributedString {
        var out = AttributedString()
        for segment in line.segments {
            var piece = AttributedString(segment.text)
            if let target = segment.link, let url = URL(string: target) { piece.link = url }
            out += piece
        }
        return out
    }

    private var logo: NSImage? {
        Bundle.main.url(forResource: "GoodLoopsLogo", withExtension: "png").flatMap { NSImage(contentsOf: $0) }
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 14) {
                Image(nsImage: NSApplication.shared.applicationIconImage).resizable().frame(width: 128, height: 128)
                Text("LPX Explorer").font(.largeTitle.bold())
                Text(versionText).font(.callout).foregroundStyle(.secondary).textSelection(.enabled)
                Text(AboutInfo.copyright).font(.caption).foregroundStyle(.secondary)

                Divider().padding(.vertical, 6)

                if let logo, let link = URL(string: AboutInfo.companyURL) {
                    Link(destination: link) { Image(nsImage: logo).resizable().scaledToFit().frame(width: 120, height: 120) }
                        .buttonStyle(.plain).focusEffectDisabled().help(AboutInfo.companyURL) // no blue keyboard-focus ring
                }
                ForEach(Array(AboutInfo.credits().enumerated()), id: \.offset) { _, line in
                    Text(attributed(line)).font(.body).multilineTextAlignment(.center).fixedSize(horizontal: false, vertical: true)
                }
            }
            .frame(maxWidth: .infinity)
            .padding(28)
        }
        .frame(minWidth: 380, minHeight: 420)
    }
}
