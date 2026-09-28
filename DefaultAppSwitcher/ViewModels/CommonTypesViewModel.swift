//
//  CommonTypesViewModel.swift
//  DefaultAppSwitcher
//
//  State for the "Common Types" tab: a catalog of everyday extensions, each with its
//  current default app, a lazily loaded list of alternatives, and per-row apply status.
//

import AppKit
import SwiftUI
import UniformTypeIdentifiers

@MainActor
final class CommonTypesViewModel: ObservableObject {

    enum RowStatus: Equatable {
        case idle, applying, applied
    }

    struct Row: Identifiable {
        let info: FileTypeInfo
        let typeIcon: NSImage
        var defaultApp: AppHandler?
        /// nil until the row first scrolls into view. Querying every type up front would
        /// stall the window on open.
        var handlers: [AppHandler]?
        /// Shown in the picker while a change is being applied, so it doesn't snap back.
        var pendingAppID: String?
        var status: RowStatus = .idle

        var id: String { info.fileExtension }
    }

    struct VisibleSection: Identifiable {
        let title: String
        let systemImage: String
        let extensions: [String]
        var id: String { title }
    }

    @Published private(set) var rows: [String: Row] = [:]
    @Published var alert: FileTypeViewModel.AlertContent?
    @Published var searchText = "" {
        didSet { addCustomRowIfNeeded() }
    }

    private let manager: LaunchServicesManager
    /// Extension typed in the search field that isn't in the catalog.
    private var typedCustom: String?
    /// Custom extensions the user changed. They stay listed for the rest of the session.
    private var pinnedCustom: [String] = []

    init(manager: LaunchServicesManager? = nil) {
        self.manager = manager ?? .shared
    }

    // MARK: Loading

    /// Builds every catalog row with its current default. That takes one LaunchServices
    /// query per type, which is fast. Candidate apps load later, per row.
    func loadIfNeeded() {
        guard rows.isEmpty else {
            refreshDefaults()
            return
        }
        var newRows: [String: Row] = [:]
        for ext in CommonFileTypes.categories.flatMap(\.extensions) {
            if let row = makeRow(for: ext) { newRows[ext] = row }
        }
        rows = newRows
    }

    /// Called when a row appears on screen.
    func loadHandlers(for ext: String) {
        guard var row = rows[ext], row.handlers == nil else { return }
        row.handlers = candidates(for: row)
        rows[ext] = row
    }

    /// Re-reads every row's default app, e.g. after a change in Finder's Get Info or in the
    /// Drop File tab. With `reloadApps`, rows that already loaded their candidate apps
    /// re-query them too, so newly installed apps show up.
    func refreshDefaults(reloadApps: Bool = false) {
        for ext in rows.keys {
            guard var row = rows[ext] else { continue }
            row.defaultApp = manager.defaultApplication(for: row.info.contentType)
            if row.handlers != nil {
                row.handlers = reloadApps ? candidates(for: row) : withDefault(row.handlers ?? [], row.defaultApp)
            }
            rows[ext] = row
        }
    }

    private func candidates(for row: Row) -> [AppHandler] {
        withDefault(manager.applications(for: row.info.contentType), row.defaultApp)
    }

    /// Rarely the default app isn't in the candidate list (e.g. one set by another tool).
    /// Include it so the picker can still show the current selection.
    private func withDefault(_ handlers: [AppHandler], _ current: AppHandler?) -> [AppHandler] {
        guard let current, !handlers.contains(current) else { return handlers }
        return [current] + handlers
    }

    // MARK: Changing a default

    func setDefault(appID: String, for ext: String) {
        guard var row = rows[ext],
              appID != row.defaultApp?.id,
              let app = row.handlers?.first(where: { $0.id == appID })
        else { return }

        row.pendingAppID = appID
        row.status = .applying
        rows[ext] = row
        let contentType = row.info.contentType

        Task {
            do {
                try await manager.setDefaultApplication(app, for: contentType)
                finish(ext, status: .applied)
                if !CommonFileTypes.allExtensions.contains(ext), !pinnedCustom.contains(ext) {
                    pinnedCustom.insert(ext, at: 0)
                }
                // Sibling extensions that share this UTI (jpg ↔ jpeg) change too.
                refreshDefaults()
                try? await Task.sleep(nanoseconds: 1_800_000_000)
                if rows[ext]?.status == .applied { finish(ext, status: .idle) }
            } catch {
                finish(ext, status: .idle)
                refreshDefaults()
                alert = FileTypeViewModel.AlertContent(title: "Couldn’t Change Default App",
                              message: "“.\(ext)” → \(app.name): \(error.localizedDescription)")
            }
        }
    }

    private func finish(_ ext: String, status: RowStatus) {
        guard var row = rows[ext] else { return }
        row.status = status
        row.pendingAppID = nil
        rows[ext] = row
    }

    // MARK: Filtering

    /// Catalog sections filtered by the search text. A typed extension that isn't in the
    /// catalog gets its own "Custom" section, so any type can be changed from here.
    var visibleSections: [VisibleSection] {
        let query = normalizedQuery
        var sections: [VisibleSection] = []

        var custom = pinnedCustom.filter { query.isEmpty || $0.contains(query) }
        // Offer the typed extension only once no catalog extension starts with it, so
        // typing "pn" on the way to "png" doesn't flash a custom ".pn" row.
        if let typed = typedCustom, typed == query, !custom.contains(typed),
           !CommonFileTypes.allExtensions.contains(where: { $0.hasPrefix(query) }) {
            custom.insert(typed, at: 0)
        }
        if !custom.isEmpty {
            sections.append(.init(title: "Custom", systemImage: "plus.circle", extensions: custom))
        }

        for category in CommonFileTypes.categories {
            let matches = category.extensions.filter { ext in
                guard rows[ext] != nil else { return false }
                if query.isEmpty { return true }
                if ext.contains(query) { return true }
                let row = rows[ext]
                return row?.info.typeDescription.localizedCaseInsensitiveContains(query) == true
                    || row?.defaultApp?.name.localizedCaseInsensitiveContains(query) == true
            }
            if !matches.isEmpty {
                sections.append(.init(title: category.name, systemImage: category.systemImage, extensions: matches))
            }
        }
        return sections
    }

    private var normalizedQuery: String {
        var q = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        while q.hasPrefix(".") { q.removeFirst() }
        return q
    }

    private func addCustomRowIfNeeded() {
        let ext = normalizedQuery

        // Drop the previous typed row unless the user changed it, so typing
        // "m", "ma", "mar"… doesn't pile up rows.
        if let old = typedCustom, old != ext, !pinnedCustom.contains(old) {
            rows[old] = nil
        }
        typedCustom = nil

        guard !ext.isEmpty, !CommonFileTypes.allExtensions.contains(ext) else { return }
        if rows[ext] == nil {
            guard let row = makeRow(for: ext) else { return }
            rows[ext] = row
        }
        typedCustom = ext
    }

    private func makeRow(for ext: String) -> Row? {
        guard let info = manager.fileTypeInfo(forExtension: ext) else { return nil }
        return Row(
            info: info,
            typeIcon: manager.documentIcon(for: info.contentType),
            defaultApp: manager.defaultApplication(for: info.contentType)
        )
    }
}
