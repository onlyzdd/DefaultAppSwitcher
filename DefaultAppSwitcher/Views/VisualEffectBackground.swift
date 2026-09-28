//
//  VisualEffectBackground.swift
//  DefaultAppSwitcher
//
//  Why not just `.background(.thinMaterial)`?
//  On macOS, SwiftUI materials blur only what's inside the window (within-window
//  blending). Placed on an ordinary opaque window, `.thinMaterial` looks flat gray.
//  To get the frosted look that shows the desktop behind the window, like Finder's
//  sidebar or Control Center, you need an NSVisualEffectView with `.behindWindow`
//  blending. The window server then composites the blur, so the window can stay opaque.
//
//  `.thinMaterial` still works well on views layered on top of this background.
//

import SwiftUI
import AppKit

struct VisualEffectBackground: NSViewRepresentable {
    var material: NSVisualEffectView.Material = .sidebar
    var blendingMode: NSVisualEffectView.BlendingMode = .behindWindow

    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = material
        view.blendingMode = blendingMode
        // Standard Mac behavior: vibrant when the window is key, dimmed when it's inactive.
        view.state = .followsWindowActiveState
        return view
    }

    func updateNSView(_ view: NSVisualEffectView, context: Context) {
        view.material = material
        view.blendingMode = blendingMode
    }
}
