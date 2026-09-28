//
//  Models.swift
//  DefaultAppSwitcher
//
//  Plain value types shared by the manager, view models and views.
//

import AppKit
import UniformTypeIdentifiers

/// A file type identified by its extension and the Uniform Type Identifier
/// LaunchServices associates with it.
struct FileTypeInfo: Equatable {
    /// The file the type came from (drag & drop), or nil when built from an extension alone.
    let url: URL?
    /// Lower-cased extension without the dot, e.g. "txt".
    let fileExtension: String
    /// e.g. `public.plain-text` for .txt, `public.png` for .png.
    let contentType: UTType

    /// A *dynamic* UTI (identifier starts with `dyn.`) means no installed app formally
    /// declares this extension. LaunchServices synthesises one on the fly. You can still
    /// set a handler for it, but it's less robust than a declared type.
    var isDynamicType: Bool { contentType.isDynamic }

    /// Finder-style description, e.g. "Plain Text Document".
    var typeDescription: String {
        contentType.localizedDescription ?? (isDynamicType ? "Unregistered Type" : contentType.identifier)
    }
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

// MARK: - Common file types catalog

struct FileTypeCategory: Identifiable {
    let name: String
    let systemImage: String
    let extensions: [String]
    var id: String { name }
}

/// The extensions shown in the "Common Types" tab, grouped the way people think about them.
/// Several extensions can share one UTI (jpg/jpeg → public.jpeg, htm/html → public.html),
/// so changing one also changes the other. The list refreshes after every change to show that.
enum CommonFileTypes {
    static let categories: [FileTypeCategory] = [
        FileTypeCategory(name: "Text & Code", systemImage: "doc.plaintext",
                         extensions: ["txt", "md", "log", "csv", "json", "xml", "yaml",
                                      "py", "js", "ts", "swift", "sh", "c", "cpp", "java", "go", "rs"]),
        FileTypeCategory(name: "Documents", systemImage: "doc.richtext",
                         extensions: ["pdf", "rtf", "doc", "docx", "xls", "xlsx", "ppt", "pptx",
                                      "pages", "numbers", "key", "epub"]),
        FileTypeCategory(name: "Images", systemImage: "photo",
                         extensions: ["png", "jpg", "jpeg", "gif", "heic", "webp", "tiff", "bmp", "svg", "psd"]),
        FileTypeCategory(name: "Audio", systemImage: "waveform",
                         extensions: ["mp3", "m4a", "wav", "aac", "flac", "aiff"]),
        FileTypeCategory(name: "Video", systemImage: "film",
                         extensions: ["mp4", "mov", "m4v", "mkv", "avi", "webm"]),
        FileTypeCategory(name: "Archives & Disk Images", systemImage: "archivebox",
                         extensions: ["zip", "tar", "gz", "7z", "rar", "dmg"]),
        FileTypeCategory(name: "Web", systemImage: "globe",
                         extensions: ["html", "htm", "webloc"]),
    ]

    static let allExtensions: Set<String> = Set(categories.flatMap(\.extensions))
}
