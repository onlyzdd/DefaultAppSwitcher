//
//  FileTypeViewModel.swift
//  DefaultAppSwitcher
//
//  Holds UI state and turns user actions into LaunchServicesManager calls.
//

import AppKit
import SwiftUI
import UniformTypeIdentifiers

@MainActor
final class FileTypeViewModel: ObservableObject {

    struct AlertContent: Identifiable {
        let id = UUID()
        let title: String
        let message: String
    }

    // MARK: Published state

    @Published private(set) var fileInfo: DroppedFileInfo?
    @Published private(set) var handlers: [AppHandler] = []
    @Published private(set) var currentDefaultID: String?
    @Published private(set) var isApplying = false
    @Published var selectedHandlerID: String?
    @Published var alert: AlertContent?

    private let manager: LaunchServicesManager

    // Assigned in init, which runs on the main actor, so Swift 6 strict concurrency
    // accepts the main-actor-isolated singleton.
    init(manager: LaunchServicesManager? = nil) {
        self.manager = manager ?? .shared
    }

    // MARK: Derived state

    var selectedHandler: AppHandler? {
        handlers.first { $0.id == selectedHandlerID }
    }

    /// Enabled only when the choice differs from the current default.
    var canApply: Bool {
        guard fileInfo != nil, let selected = selectedHandler, !isApplying else { return false }
        return selected.id != currentDefaultID
    }

    var currentDefaultName: String? {
        handlers.first { $0.id == currentDefaultID }?.name
    }

    // MARK: Intents

    /// Called by the drop zone. Returning `false` tells the system the drop was rejected,
    /// and Finder animates the icon back to where it came from.
    @discardableResult
    func handleDrop(_ urls: [URL]) -> Bool {
        guard let url = urls.first(where: \.isFileURL) else { return false }
        do {
            let info = try manager.resolveFileInfo(for: url)
            load(info)
            return true
        } catch {
            alert = AlertContent(title: "Can’t Use This Item", message: error.localizedDescription)
            return false
        }
    }

    /// Keyboard and click alternative to dragging, as the HIG recommends.
    func chooseFile() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.prompt = "Choose"
        panel.message = "Choose a file whose type you want to change."
        if panel.runModal() == .OK, let url = panel.url {
            handleDrop([url])
        }
    }

    func applyToAll() {
        guard let info = fileInfo, let app = selectedHandler else { return }
        isApplying = true

        Task {
            defer { isApplying = false }
            do {
                try await manager.setDefaultApplication(app, for: info.contentType)
                refreshCurrentDefault()
                alert = AlertContent(
                    title: "Default App Changed",
                    message: "All “.\(info.fileExtension)” files will now open with \(app.name)."
                )
            } catch {
                alert = AlertContent(
                    title: "Couldn’t Change Default App",
                    message: error.localizedDescription
                )
            }
        }
    }

    func reset() {
        fileInfo = nil
        handlers = []
        currentDefaultID = nil
        selectedHandlerID = nil
    }

    // MARK: Private

    private func load(_ info: DroppedFileInfo) {
        fileInfo = info
        handlers = manager.applications(for: info.contentType)
        refreshCurrentDefault()

        // Pre-select the current default so the picker reflects reality.
        selectedHandlerID = currentDefaultID ?? handlers.first?.id

        if handlers.isEmpty {
            alert = AlertContent(
                title: "No Apps Found",
                message: "No installed app declares that it can open “.\(info.fileExtension)” files."
            )
        }
    }

    private func refreshCurrentDefault() {
        guard let info = fileInfo else {
            currentDefaultID = nil
            return
        }
        let id = manager.currentDefaultBundleID(for: info.contentType)
        // Bundle IDs are case-insensitive to LaunchServices, so map to the exact
        // spelling used in `handlers`.
        currentDefaultID = handlers.first { $0.id.caseInsensitiveCompare(id ?? "") == .orderedSame }?.id ?? id
    }
}
