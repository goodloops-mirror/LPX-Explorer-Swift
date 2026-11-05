import LpxCore
import SwiftUI

/// How the middle pane shows the selected library folder: the flat project list, Finder's list view (collapsible
/// folders) or its column view.
enum BrowseMode: String, CaseIterable, Identifiable {
    case list, tree, columns
    var id: String { rawValue }
    var title: String {
        switch self { case .list: "All Projects"; case .tree: "Folders as List"; case .columns: "Folders as Columns" }
    }
    var icon: String {
        switch self { case .list: "list.bullet"; case .tree: "list.bullet.indent"; case .columns: "rectangle.split.3x1" }
    }
}

/// State of the folder views: what each folder contains (listed lazily, in the background, once), which folders are
/// expanded and what is selected. The file system is only ever read.
@MainActor @Observable
final class FolderBrowser {
    private static let modeKey = "browseMode", expandedKey = "browseExpanded"

    var mode: BrowseMode = BrowseMode(rawValue: UserDefaults.standard.string(forKey: FolderBrowser.modeKey) ?? "") ?? .list {
        didSet { UserDefaults.standard.set(mode.rawValue, forKey: Self.modeKey) }
    }
    private(set) var contents: [String: [FolderItem]] = [:]
    private(set) var known: [String: FolderItem] = [:]
    private(set) var expanded = Set(UserDefaults.standard.stringArray(forKey: FolderBrowser.expandedKey) ?? [])
    /// The selected row (a folder or a project) of the list view, or of the last column.
    var selected: String?
    /// Column view: the selected item of every column, left to right.
    var chain: [String] = []
    @ObservationIgnored private var loading: Set<String> = []

    func load(_ dir: String, force: Bool = false) {
        if !force, contents[dir] != nil { return }
        guard loading.insert(dir).inserted else { return }
        Task {
            let items = await Task.detached(priority: .userInitiated) { FolderListing.items(in: URL(fileURLWithPath: dir)) }.value
            contents[dir] = items
            for item in items { known[item.path] = item }
            loading.remove(dir)
        }
    }

    /// Lists every folder shown so far again (after a scan, or when the file system changed).
    func reload() { for dir in Array(contents.keys) { load(dir, force: true) } }

    func isExpanded(_ path: String) -> Bool { expanded.contains(path) }

    func setExpanded(_ path: String, _ on: Bool) {
        if on { expanded.insert(path); load(path) } else { expanded.remove(path) }
        UserDefaults.standard.set(Array(expanded), forKey: Self.expandedKey)
    }

    func resetSelection() { selected = nil; chain = [] }

    /// Make `path` visible and selected: expand the folders above it (list view), fill the columns (column view).
    func reveal(_ path: String, under root: String) {
        guard let steps = FolderListing.chain(to: path, under: root) else { return }
        load(root)
        for dir in steps.dropLast() { load(dir) }
        if !steps.dropLast().allSatisfy(expanded.contains) {
            expanded.formUnion(steps.dropLast())
            UserDefaults.standard.set(Array(expanded), forKey: Self.expandedKey)
        }
        selected = path
        chain = steps
    }

    /// A folder's items in the order of the project list: sub-folders by name, then the projects in the chosen sort order.
    func ordered(_ dir: String, by order: ProjectOrder, value: (String) -> Int64?) -> [FolderItem] {
        let items = contents[dir] ?? []
        let folders = items.filter(\.isFolder)
        let projects = ProjectSorting.sorted(items.filter { !$0.isFolder }, by: order, path: \.path, value: value)
        return (order.field == .name && !order.ascending ? folders.reversed() : folders) + projects
    }
}

/// Folder icon or project icon plus the name, the way both folder views draw an item.
struct FolderItemLabel: View {
    @Environment(LibraryModel.self) private var model
    let item: FolderItem

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: item.isFolder ? "folder.fill" : "music.note.house")
                .foregroundStyle(item.isFolder ? Color.accentColor : .secondary)
                .frame(width: 18)
            Text(item.isFolder ? item.name : LibraryModel.projectName(item.path)).fixedSize(horizontal: false, vertical: true)
            if !item.isFolder {
                if let v = model.verdict(for: item.path), !v.missing.isEmpty {
                    Image(systemName: v.status == .willNotOpen ? "xmark.octagon.fill" : "exclamationmark.triangle.fill")
                        .foregroundStyle(v.status == .willNotOpen ? .red : .orange).help(v.headline)
                }
                if model.hasBounce(item.path) { Image(systemName: "waveform").foregroundStyle(.secondary).help("Has a bounce") }
            }
        }
    }
}

private extension View {
    func folderItemMenu(_ path: String) -> some View {
        contextMenu {
            Button("Reveal in Finder") { NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: path)]) }
            Button("Copy Path") {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(path, forType: .string)
            }
        }
    }
}

/// Selecting a project shows it in the inspector; selecting a folder clears the inspector.
@MainActor private func select(_ path: String?, model: LibraryModel) {
    guard let path else { return }
    model.selectedProject = model.browser.known[path]?.isFolder == true ? nil : path
}

// MARK: list view

/// Finder's list view: folders open and close in place, projects show the optional columns.
struct FolderTreeView: View {
    @Environment(LibraryModel.self) private var model
    let root: String

    private struct Row: Identifiable { let item: FolderItem; let depth: Int; var id: String { item.path } }

    private func rows(in dir: String, depth: Int, into out: inout [Row]) {
        for item in model.browser.ordered(dir, by: model.sortOrder, value: model.sortValue) {
            out.append(Row(item: item, depth: depth))
            if item.isFolder, model.browser.isExpanded(item.path), depth < 40 { rows(in: item.path, depth: depth + 1, into: &out) }
        }
    }

    var body: some View {
        @Bindable var browser = model.browser
        var rows: [Row] = []
        self.rows(in: root, depth: 0, into: &rows)
        return List(selection: $browser.selected) {
            ForEach(rows) { row in
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Color.clear.frame(width: CGFloat(row.depth) * 16, height: 1)
                    if row.item.isFolder {
                        Button { browser.setExpanded(row.item.path, !browser.isExpanded(row.item.path)) } label: {
                            Image(systemName: browser.isExpanded(row.item.path) ? "chevron.down" : "chevron.right")
                                .font(.system(size: 9, weight: .semibold)).foregroundStyle(.secondary).frame(width: 12)
                        }
                        .buttonStyle(.plain)
                    } else {
                        Color.clear.frame(width: 12, height: 1)
                    }
                    FolderItemLabel(item: row.item)
                    Spacer(minLength: 4)
                    if !row.item.isFolder { ProjectColumnCells(path: row.item.path) }
                }
                .listRowInsets(ProjectColumnLayout.rowInsets)
                .tag(row.item.path)
                .folderItemMenu(row.item.path)
            }
        }
        .onKeyPress(.rightArrow) { arrow(open: true) }
        .onKeyPress(.leftArrow) { arrow(open: false) }
        .task(id: root) { model.browser.load(root); for dir in model.browser.expanded { model.browser.load(dir) } }
        .onChange(of: browser.selected) { _, path in select(path, model: model) }
        .onChange(of: model.selectedProject) { _, path in
            if let path, path != model.browser.selected { model.browser.reveal(path, under: root) }
        }
        .onAppear { if let path = model.selectedProject, path != model.browser.selected { model.browser.reveal(path, under: root) } }
        .navigationTitle(URL(fileURLWithPath: root).lastPathComponent)
        .navigationSplitViewColumnWidth(min: 260, ideal: 450)
    }

    private func arrow(open: Bool) -> KeyPress.Result {
        guard let path = model.browser.selected, model.browser.known[path]?.isFolder == true,
              model.browser.isExpanded(path) != open else { return .ignored }
        model.browser.setExpanded(path, open)
        return .handled
    }
}

// MARK: column view

/// Finder's column view: choosing a folder opens its contents in a new column to the right. A project ends the columns;
/// the inspector takes the place of Finder's preview.
struct FolderColumnsView: View {
    @Environment(LibraryModel.self) private var model
    let root: String
    static let columnWidth: CGFloat = 250

    private var columnDirs: [String] {
        var dirs = [root]
        for path in model.browser.chain {
            guard model.browser.known[path]?.isFolder == true else { break }
            dirs.append(path)
        }
        return dirs
    }

    private func binding(_ index: Int) -> Binding<String?> {
        Binding(
            get: { model.browser.chain.count > index ? model.browser.chain[index] : nil },
            set: { new in
                guard let new else { return }
                model.browser.chain = Array(model.browser.chain.prefix(index)) + [new]
                model.browser.selected = new
                model.browser.load(new)
                select(new, model: model)
            })
    }

    var body: some View {
        let dirs = columnDirs
        ScrollViewReader { proxy in
            ScrollView(.horizontal) {
                HStack(spacing: 0) {
                    ForEach(Array(dirs.enumerated()), id: \.element) { index, dir in
                        List(selection: binding(index)) {
                            ForEach(model.browser.ordered(dir, by: model.sortOrder, value: model.sortValue)) { item in
                                HStack(spacing: 4) {
                                    FolderItemLabel(item: item)
                                    Spacer(minLength: 4)
                                    if item.isFolder { Image(systemName: "chevron.right").font(.system(size: 9, weight: .semibold)).foregroundStyle(.secondary) }
                                }
                                .tag(item.path)
                                .folderItemMenu(item.path)
                            }
                        }
                        .frame(width: Self.columnWidth)
                        .id(dir)
                        Divider()
                    }
                }
                .frame(maxHeight: .infinity)
            }
            .onChange(of: dirs.last) { _, last in if let last { withAnimation { proxy.scrollTo(last, anchor: .trailing) } } }
        }
        .task(id: root) {
            model.browser.load(root)
            if let path = model.selectedProject { model.browser.reveal(path, under: root) }
        }
        .onChange(of: model.selectedProject) { _, path in
            if let path, path != model.browser.selected { model.browser.reveal(path, under: root) }
        }
        .navigationTitle(URL(fileURLWithPath: root).lastPathComponent)
        .navigationSplitViewColumnWidth(min: 260, ideal: 450)
    }
}
