import AppKit
import LpxCore
import SwiftUI

/// Detail for a single-file Logic 4–9 project (`.lso`): what can be known without reading it — name, folder, size, dates —
/// plus its bounces, and an honest note that its contents (tracks, tempo, plug-ins) are not read.
struct LegacyProjectView: View {
    let summary: ProjectSummary
    private var url: URL { URL(fileURLWithPath: summary.path) }

    var body: some View {
        Form {
            Section {
                Label {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Legacy Logic project").font(.headline)
                        Text("This is a single-file project from Logic 4–9 (.lso). LPX Explorer lists it by name, so it can be found, revealed and matched with its bounces, but its tracks, tempo and plug-ins can't be read. Open and save it in a current Logic version to see them here.")
                            .foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                    }
                } icon: { Image(systemName: "clock.arrow.circlepath").foregroundStyle(.secondary) }
            }
            Section {
                LabeledContent("Folder") { Text(url.deletingLastPathComponent().path).textSelection(.enabled) }
                LabeledContent("File size", value: ByteCountFormatter.string(fromByteCount: Int64(summary.stats.sizeBytes), countStyle: .file))
                LabeledContent("Created", value: MetadataFormat.dateWithRelative(unix: summary.stats.createdAt))
                LabeledContent("Modified", value: MetadataFormat.dateWithRelative(unix: summary.stats.modifiedAt))
            }
            BouncesSection(projectPath: summary.path)
        }
        .formStyle(.grouped)
        .navigationTitle(LibraryModel.projectName(summary.path))
        .navigationSubtitle(url.deletingLastPathComponent().path)
        .toolbar {
            ToolbarItem {
                Button { NSWorkspace.shared.activateFileViewerSelecting([url]) } label: { Label("Reveal in Finder", systemImage: "folder") }
                    .help("Reveal this project in Finder")
            }
        }
    }
}
