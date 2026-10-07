import AppKit
import LpxCore
import SwiftUI

/// Library-wide plug-in usage: what you depend on, what's missing, grouped by category.
struct PluginRailView: View {
    @Environment(LibraryModel.self) private var model

    var body: some View {
        @Bindable var model = model
        let all = model.pluginRows
        let facets = PluginRail.facets(all)
        let shown = PluginRail.filter(all, query: model.pluginQuery, status: model.pluginStatus, category: model.pluginCategory)
        let categorised = all.filter { $0.fineCategory != .uncategorised }.count

        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 8) {
                Picker("Show", selection: $model.pluginStatus) {
                    Text("All").tag(PluginStatusFilter.all)
                    Text("Installed").tag(PluginStatusFilter.installed)
                    Text("Missing").tag(PluginStatusFilter.missing)
                    Text("2+ projects").tag(PluginStatusFilter.multipleProjects)
                }
                .pickerStyle(.segmented).labelsHidden()

                if !facets.isEmpty {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 6) {
                            facetChip("All", count: all.count, selected: model.pluginCategory == nil) { model.pluginCategory = nil }
                            ForEach(facets, id: \.category) { f in
                                facetChip(f.category.rawValue, count: f.count, selected: model.pluginCategory == f.category) {
                                    model.pluginCategory = (model.pluginCategory == f.category) ? nil : f.category
                                }
                            }
                        }
                    }
                }
                Text(countLine(shown: shown.count, total: all.count, categorised: categorised))
                    .font(.caption).foregroundStyle(.secondary)
            }
            .padding(10)
            Divider()
            List(shown, id: \.fingerprint, selection: $model.selectedPlugin) { row in
                PluginRowView(row: row).tag(row.fingerprint)
            }
            .overlay {
                if all.isEmpty {
                    ContentUnavailableView("No plug-ins yet", systemImage: "puzzlepiece.extension",
                                           description: Text(model.isScanning ? "Projects are still being read." : "Add a folder of Logic projects first."))
                } else if shown.isEmpty {
                    ContentUnavailableView("No plug-ins match", systemImage: "line.3.horizontal.decrease.circle")
                }
            }
        }
        .navigationTitle("Plug-ins")
        .navigationSplitViewColumnWidth(min: 300, ideal: 750)
    }

    private func countLine(shown: Int, total: Int, categorised: Int) -> String {
        var line = shown == total ? "\(total) plug-ins" : "\(shown) of \(total) plug-ins"
        if total > 0 { line += " · \(categorised) of \(total) categorised" }
        if !model.pluginRowsKnowInstallStatus { line += " · install status unknown until AU scan finishes" }
        return line
    }

    private func facetChip(_ title: String, count: Int, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text("\(title) \(count)").font(.caption)
                .padding(.horizontal, 8).padding(.vertical, 3)
                .background(selected ? Color.accentColor.opacity(0.25) : Color.secondary.opacity(0.12), in: Capsule())
        }
        .buttonStyle(.plain)
    }
}

struct PluginRowView: View {
    let row: PluginRow

    var body: some View {
        HStack(spacing: 8) {
            statusIcon
            VStack(alignment: .leading, spacing: 1) {
                Text(row.name).lineLimit(1)
                Text(row.fineCategory.rawValue).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 1) {
                Text("\(row.projectCount) project\(row.projectCount == 1 ? "" : "s")").font(.caption)
                if row.instanceCount > row.projectCount {
                    Text("×\(row.instanceCount)").font(.caption2).foregroundStyle(.secondary)
                }
            }
            .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder private var statusIcon: some View {
        switch row.status {
        case .installed: Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
        case .missing: Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
        case .unknown: Image(systemName: "circle.dotted").foregroundStyle(.tertiary)
        }
    }
}

struct PluginDetailView: View {
    @Environment(LibraryModel.self) private var model
    let row: PluginRow

    private var statusText: String {
        switch row.status {
        case .installed: "Installed on this Mac"
        case .missing: "Not installed on this Mac"
        case .unknown: "Install status unknown (AU scan not read yet)"
        }
    }

    var body: some View {
        Form {
            Section {
                LabeledContent("Category", value: row.fineCategory.rawValue)
                LabeledContent("Status", value: statusText)
                LabeledContent("Fingerprint") {
                    // Quotes make significant spaces in 4CCs visible ("kHs ").
                    Text(row.fingerprint.split(separator: "/", omittingEmptySubsequences: false).map { "\"\($0)\"" }.joined(separator: " / "))
                        .font(.body.monospaced()).textSelection(.enabled)
                }
                LabeledContent("Used in", value: "\(row.projectCount) project\(row.projectCount == 1 ? "" : "s"), \(row.instanceCount) instance\(row.instanceCount == 1 ? "" : "s")")
                HStack {
                    Button("Copy Name") {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(row.name, forType: .string)
                    }
                }
            }
            Section("Projects (\(row.projectCount))") {
                ForEach(row.projectPaths, id: \.self) { path in
                    Button { model.showProject(path) } label: {
                        VStack(alignment: .leading, spacing: 1) {
                            Text(LibraryModel.projectName(path))
                            Text(URL(fileURLWithPath: path).deletingLastPathComponent().path)
                                .font(.caption).foregroundStyle(.secondary).lineLimit(1).truncationMode(.head)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .formStyle(.grouped)
        .navigationTitle(row.name)
        .navigationSubtitle("Plug-in")
    }
}
