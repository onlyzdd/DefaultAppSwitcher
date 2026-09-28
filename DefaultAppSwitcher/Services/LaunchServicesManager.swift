//
//  LaunchServicesManager.swift
//  DefaultAppSwitcher
//
//  The bridge to LaunchServices, the macOS subsystem (run by the `lsd` daemon)
//  that tracks which apps can open which content types, and which app is each
//  type's default handler.
//
//  How it works:
//  • Each app declares in its Info.plist which content types it handles
//    (CFBundleDocumentTypes / LSItemContentTypes). When an app is installed or
//    launched, LaunchServices records those claims in its database.
//  • The user's own choices ("Open with X by default") are stored per user in
//    ~/Library/Preferences/com.apple.LaunchServices/com.apple.launchservices.secure.plist
//    under the `LSHandlers` key. Apps never write that file directly: they call
//    LaunchServices, which asks `lsd` to update it and refresh its cache.
//  • The change applies to the current user account and takes effect at once in
//    Finder, `open`, and any other app that opens documents.
//

import AppKit
import CoreServices          // LaunchServices C APIs (LSSetDefaultRoleHandlerForContentType, LSRolesMask)
import UniformTypeIdentifiers

// MARK: - Errors

enum LaunchServicesError: LocalizedError {
    case isFolder
    case isApplication
    case noExtension
    case unknownType(String)
    case launchServicesStatus(OSStatus)

    var errorDescription: String? {
        switch self {
        case .isFolder:
            return "Folders can't have a default app. Drop a file instead."
        case .isApplication:
            return "That's an application. Drop a document of the type you want to change."
        case .noExtension:
            return "This file has no extension, so there's no file type to change."
        case .unknownType(let ext):
            return "macOS couldn't identify a file type for “.\(ext)”."
        case .launchServicesStatus(let status):
            // -54 (permErr) usually means the process is sandboxed.
            if status == -54 {
                return "Permission denied (error -54). Make sure App Sandbox is turned off for this app."
            }
            return "LaunchServices returned error \(status)."
        }
    }
}

// MARK: - Manager

@MainActor
final class LaunchServicesManager {
    static let shared = LaunchServicesManager()

    private let workspace = NSWorkspace.shared
    private let fileManager = FileManager.default

    // Loading an app's icon means reading its bundle from disk. The Common Types list shows
    // the same few apps across dozens of rows, so each icon is cached by bundle path.
    private var appIconCache: [String: NSImage] = [:]
    private var typeIconCache: [String: NSImage] = [:]

    private init() {}

    // MARK: Identify the dropped file

    /// Works out the extension and UTType for a file URL.
    func resolveFileInfo(for url: URL) throws -> FileTypeInfo {
        // Resource values come from the file system and LaunchServices; the file's
        // contents are never read.
        let values = try url.resourceValues(forKeys: [.isDirectoryKey, .isPackageKey, .contentTypeKey])

        // A package (e.g. .rtfd, .pages) is a folder that Finder shows as one document,
        // so it's allowed. A plain folder isn't.
        if values.isDirectory == true && values.isPackage != true {
            throw LaunchServicesError.isFolder
        }

        let ext = url.pathExtension.lowercased()
        guard !ext.isEmpty else { throw LaunchServicesError.noExtension }

        // Prefer the type LaunchServices has already assigned to this file; if that's
        // missing, look it up from the extension. UTType(filenameExtension:) always returns
        // a declared type when some app or the system declares one, and otherwise a
        // dynamic `dyn.…` type.
        guard let type = values.contentType ?? UTType(filenameExtension: ext) else {
            throw LaunchServicesError.unknownType(ext)
        }

        if type.conforms(to: .application) {
            throw LaunchServicesError.isApplication
        }

        return FileTypeInfo(url: url, fileExtension: ext, contentType: type)
    }

    /// Builds a FileTypeInfo from a typed or catalog extension ("txt", ".TXT", " md ").
    /// Returns nil for an empty or invalid extension.
    func fileTypeInfo(forExtension raw: String) -> FileTypeInfo? {
        var ext = raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        while ext.hasPrefix(".") { ext.removeFirst() }
        guard !ext.isEmpty,
              ext.allSatisfy({ $0.isLetter || $0.isNumber || $0 == "-" || $0 == "_" || $0 == "." }),
              let type = UTType(filenameExtension: ext),
              !type.conforms(to: .application)
        else { return nil }
        return FileTypeInfo(url: nil, fileExtension: ext, contentType: type)
    }

    // MARK: Look up candidate apps

    /// Every app LaunchServices knows can open `type`, de-duplicated and sorted by name.
    ///
    /// `NSWorkspace.urlsForApplications(toOpen:)` (macOS 12+) is the modern wrapper around
    /// LaunchServices' handler query (formerly `LSCopyAllRoleHandlersForContentType`).
    /// It returns app bundle URLs, including apps that claim a parent type. For example,
    /// a text editor that declares `public.text` also appears for `public.plain-text`.
    func applications(for type: UTType) -> [AppHandler] {
        let urls = workspace.urlsForApplications(toOpen: type)

        var seen = Set<String>()
        var handlers: [AppHandler] = []

        for url in urls {
            guard let handler = makeHandler(for: url) else { continue }

            // The same app can be installed in more than one place (/Applications,
            // ~/Applications, a mounted DMG…). LaunchServices lists its preferred copy
            // first, so keep only the first one.
            guard seen.insert(handler.bundleIdentifier.lowercased()).inserted else { continue }
            handlers.append(handler)
        }

        return handlers.sorted {
            $0.name.localizedStandardCompare($1.name) == .orderedAscending
        }
    }

    /// Bundle ID of the app that currently opens `type` by default, if there is one.
    func currentDefaultBundleID(for type: UTType) -> String? {
        defaultApplication(for: type)?.bundleIdentifier
    }

    /// The app that currently opens `type` by default, with its name and icon.
    func defaultApplication(for type: UTType) -> AppHandler? {
        // NSWorkspace.urlForApplication(toOpen:) wraps LSCopyDefaultRoleHandlerForContentType.
        guard let url = workspace.urlForApplication(toOpen: type) else { return nil }
        return makeHandler(for: url)
    }

    /// The system's generic document icon for a type, cached. Used by the Common Types list.
    func documentIcon(for type: UTType) -> NSImage {
        if let cached = typeIconCache[type.identifier] { return cached }
        let icon = workspace.icon(for: type)
        typeIconCache[type.identifier] = icon
        return icon
    }

    // MARK: Change the default

    /// Makes `app` the default handler for every file of `type`, for the current user.
    ///
    /// Strategy:
    /// 1. `NSWorkspace.setDefaultApplication(at:toOpen:completionHandler:)`, macOS 12+.
    ///    This is Apple's current supported API. Internally it asks `lsd` to write the
    ///    LSHandlers entry for all roles (viewer, editor, shell).
    /// 2. If that fails for a reason other than the user cancelling, fall back to the
    ///    older C function `LSSetDefaultRoleHandlerForContentType`. It's deprecated since
    ///    macOS 12, so Xcode shows a warning, but it's still present and works.
    func setDefaultApplication(_ app: AppHandler, for type: UTType) async throws {
        do {
            try await setWithWorkspace(appURL: app.url, type: type)
        } catch let error as NSError
            where error.domain == NSCocoaErrorDomain && error.code == NSUserCancelledError {
            // Some protected types may trigger a system confirmation. If the user said no,
            // respect that and don't retry through the older API.
            throw error
        } catch {
            try setWithLegacyLaunchServices(bundleID: app.bundleIdentifier, type: type)
        }
    }

    /// Wraps NSWorkspace's completion-handler API in async/await. A checked
    /// continuation is used instead of the SDK's async overload so the call stays
    /// Swift 6 strict-concurrency clean.
    private func setWithWorkspace(appURL: URL, type: UTType) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            workspace.setDefaultApplication(at: appURL, toOpen: type) { error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume()
                }
            }
        }
    }

    /// The classic LaunchServices call.
    /// - `inContentType`: the UTI string, e.g. "public.plain-text".
    /// - `inRole`: `.all` covers viewer, editor and shell roles. That matches what
    ///   Finder's "Change All…" does.
    /// - `inHandlerBundleID`: the app's bundle identifier, e.g. "com.apple.TextEdit".
    /// Returns an OSStatus; 0 (`noErr`) means success.
    private func setWithLegacyLaunchServices(bundleID: String, type: UTType) throws {
        let status = LSSetDefaultRoleHandlerForContentType(
            type.identifier as CFString,
            LSRolesMask.all,
            bundleID as CFString
        )
        guard status == OSStatus(noErr) else {
            throw LaunchServicesError.launchServicesStatus(status)
        }
    }

    // MARK: Helpers

    private func makeHandler(for appURL: URL) -> AppHandler? {
        // The bundle ID is the stable key LaunchServices stores in LSHandlers.
        guard let bundleID = Bundle(url: appURL)?.bundleIdentifier else { return nil }
        return AppHandler(
            bundleIdentifier: bundleID,
            name: displayName(for: appURL),
            url: appURL,
            icon: appIcon(for: appURL)
        )
    }

    private func appIcon(for appURL: URL) -> NSImage {
        if let cached = appIconCache[appURL.path] { return cached }
        // icon(forFile:) returns a new NSImage each time, so resizing it is safe.
        // 16×16 matches the standard size for menu item images.
        let icon = workspace.icon(forFile: appURL.path)
        icon.size = NSSize(width: 16, height: 16)
        appIconCache[appURL.path] = icon
        return icon
    }

    /// The app's localized, Finder-style name, without ".app".
    private func displayName(for appURL: URL) -> String {
        let name = fileManager.displayName(atPath: appURL.path)
        return name.hasSuffix(".app") ? String(name.dropLast(4)) : name
    }
}
