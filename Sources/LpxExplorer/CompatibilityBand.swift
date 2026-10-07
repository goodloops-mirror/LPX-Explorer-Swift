import LpxCore
import SwiftUI

/// "Will this open on this Mac?" band at the top of the inspector.
struct CompatibilityBand: View {
    @Environment(AuRegistry.self) private var registry
    let summary: ProjectSummary

    private var verdict: CompatibilityVerdict {
        CompatibilityVerdict.evaluate(plugins: summary.fingerprints, installed: registry.installed)
    }

    private func style(_ status: CompatibilityVerdict.Status) -> (symbol: String, color: Color) {
        switch status {
        case .clean: ("checkmark.seal.fill", .green)
        case .warnings: ("exclamationmark.triangle.fill", .orange)
        case .willNotOpen: ("xmark.octagon.fill", .red)
        case .unknown: ("questionmark.circle.fill", .secondary)
        }
    }

    /// Visible tracks that use a given plug-in, so "missing" says where it matters.
    private func tracks(using au: AURef) -> [String] {
        summary.tracks.filter { t in
            ([t.instrument].compactMap { $0 } + t.midiFx + t.audioFx).contains { $0.fingerprint == au.fingerprint }
        }.map(\.displayName)
    }

    var body: some View {
        let v = verdict
        let look = style(v.status)
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                Image(systemName: look.symbol).font(.title2).foregroundStyle(look.color)
                VStack(alignment: .leading, spacing: 1) {
                    Text(v.headline).font(.headline)
                    if let summaryText = v.summary { Text(summaryText).font(.callout).foregroundStyle(.secondary) }
                    if v.status == .unknown { unknownDetail }
                }
                Spacer()
            }
            if !v.missing.isEmpty {
                DisclosureGroup("Show what's missing") {
                    VStack(alignment: .leading, spacing: 6) {
                        ForEach(v.missing, id: \.fingerprint) { au in
                            let used = tracks(using: au)
                            VStack(alignment: .leading, spacing: 1) {
                                Text(registry.name(for: au))
                                Text(used.isEmpty ? "Not on a visible track" : "Used on: " + used.prefix(3).joined(separator: ", ") + (used.count > 3 ? " +\(used.count - 3) more" : ""))
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading).padding(.top, 4)
                }
            }
        }
        .padding(.vertical, 4)
    }

    @ViewBuilder private var unknownDetail: some View {
        if registry.isScanning {
            Text("Reading your AU library…").font(.callout).foregroundStyle(.secondary)
        } else {
            Button("Run AU scan") { registry.refresh() }.buttonStyle(.link)
        }
    }
}
