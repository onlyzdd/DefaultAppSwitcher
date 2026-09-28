//
//  DefaultAppSwitcherApp.swift
//  DefaultAppSwitcher
//
//  App entry point. A single, fixed-size utility window.
//

import SwiftUI
import AppKit

@main
struct DefaultAppSwitcherApp: App {
    // Utility apps on macOS usually quit when their only window closes.
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        // `Window` (macOS 13+) is a single-instance scene, unlike `WindowGroup`,
        // so ⌘N can't spawn duplicate windows.
        Window("Default App Switcher", id: "main") {
            ContentView()
        }
        // Content draws under the title bar so the translucent material fills the whole window.
        .windowStyle(.hiddenTitleBar)
        // The window takes its size from ContentView's fixed frame and can't be resized.
        .windowResizability(.contentSize)
        .commands {
            // Remove "New Window" — there's only ever one window.
            CommandGroup(replacing: .newItem) { }
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }
}
