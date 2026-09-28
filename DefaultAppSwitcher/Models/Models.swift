//
//  Models.swift
//  DefaultAppSwitcher
//
//  Plain value types shared by the manager, view model and views.
//

import AppKit
import UniformTypeIdentifiers

/// Describes the file the user dropped: its extension and the Uniform Type Identifier
/// LaunchServices associates with it.
struct DroppedFileInfo: Equatable {
    let url: URL
    /// Lower-cased extension without the dot, e.g. "txt".
    let fileExtension: String
    /// e.g. `public.plain-text` for .txt, `public.png` for .png.
    let contentType: UTType

    /// A *dynamic* UTI (identifier starts with `dyn.`) means no installed app formally
    /// declares this extension. LaunchServices synthesises one on the fly. You can still
    /// set a handler for it, but it's less robust than a declared type.
    var isDynamicType: Bool { contentType.isDynamic }
}

/// One application that LaunchServices says can open a given content type.
struct AppHandler: Identifiable, Hashable {
    let bundleIdentifier: String
    let name: String
    let url: URL
    let icon: NSImage

    var id: String { bundleIdentifier }

    // Identity is the bundle ID; the icon and URL don't take part in equality.
    static func == (lhs: AppHandler, rhs: AppHandler) -> Bool {
        lhs.bundleIdentifier == rhs.bundleIdentifier
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(bundleIdentifier)
    }
}
