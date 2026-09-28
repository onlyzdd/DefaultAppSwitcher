//
//  DropZoneView.swift
//  DefaultAppSwitcher
//
//  The drop target. It shows a prompt when empty and the file type once a file is dropped.
//  The border, fill, symbol and scale all react while a drag hovers over it.
//

import SwiftUI
import AppKit

struct DropZoneView: View {
    let fileInfo: FileTypeInfo?
    let isTargeted: Bool

    private let shape = RoundedRectangle(cornerRadius: 12, style: .continuous)

    var body: some View {
        ZStack {
            shape
                .fill(isTargeted ? Color.accentColor.opacity(0.12) : Color.primary.opacity(0.04))

            // Dashed border at rest; a solid accent border while a drag is over the zone.
            shape
                .strokeBorder(
                    isTargeted ? Color.accentColor : Color.secondary.opacity(0.45),
                    style: StrokeStyle(lineWidth: isTargeted ? 2 : 1.25,
                                       dash: isTargeted ? [] : [6, 4])
                )

            content
                .padding(12)
        }
        .frame(height: 160)
        .contentShape(shape) // The whole rectangle is clickable, not just the text.
        .scaleEffect(isTargeted ? 1.02 : 1)
        .animation(.easeOut(duration: 0.15), value: isTargeted)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
        .accessibilityHint("Drop a file here, or activate to choose one.")
    }

    @ViewBuilder
    private var content: some View {
        if let info = fileInfo {
            VStack(spacing: 4) {
                // The system's generic document icon for this UTType.
                Image(nsImage: NSWorkspace.shared.icon(for: info.contentType))
                    .resizable()
                    .interpolation(.high)
                    .frame(width: 48, height: 48)

                Text(".\(info.fileExtension)")
                    .font(.title2.weight(.semibold))

                Text(info.contentType.localizedDescription ?? "Unknown Type")
                    .font(.callout)
                    .foregroundStyle(.secondary)

                Text(info.contentType.identifier)
                    .font(.caption.monospaced())
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .textSelection(.enabled)
            }
        } else {
            VStack(spacing: 8) {
                Image(systemName: isTargeted ? "arrow.down.doc.fill" : "arrow.down.doc")
                    .symbolRenderingMode(.hierarchical)
                    .font(.system(size: 38, weight: .light))
                    .foregroundStyle(isTargeted ? Color.accentColor : Color.secondary)

                Text("Drop a File Here")
                    .font(.headline)

                Text("or click to choose")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
}
