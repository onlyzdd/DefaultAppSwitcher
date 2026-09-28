//
//  DropFileView.swift
//  DefaultAppSwitcher
//
//  "Drop File" tab: drop zone → app picker → Apply to All.
//

import SwiftUI

struct DropFileView: View {
    // Owned by ContentView, so the dropped file survives switching tabs.
    @ObservedObject var viewModel: FileTypeViewModel
    @State private var isDropTargeted = false

    var body: some View {
        VStack(spacing: 14) {
            DropZoneView(fileInfo: viewModel.fileInfo, isTargeted: isDropTargeted)
                // `dropDestination(for: URL.self)` (macOS 13+) accepts file URLs dragged from
                // Finder, the Dock, the Desktop, etc. `isTargeted` fires as the drag
                // enters and leaves, which drives the highlight state.
                .dropDestination(for: URL.self) { urls, _ in
                    viewModel.handleDrop(urls)
                } isTargeted: { targeted in
                    isDropTargeted = targeted
                }
                .onTapGesture { viewModel.chooseFile() }
                .overlay(alignment: .topTrailing) { clearButton }

            if viewModel.fileInfo != nil {
                controls
                    .transition(.opacity.combined(with: .move(edge: .bottom)))
            } else {
                Text("Change which app opens a file type, for every file of that type.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxHeight: .infinity)
            }
        }
        .padding(.horizontal, 20)
        .padding(.bottom, 20)
        .padding(.top, 8)
        .animation(.easeInOut(duration: 0.25), value: viewModel.fileInfo)
        .alert(
            viewModel.alert?.title ?? "",
            isPresented: Binding(
                get: { viewModel.alert != nil },
                set: { if !$0 { viewModel.alert = nil } }
            ),
            presenting: viewModel.alert
        ) { _ in
            Button("OK", role: .cancel) { }
        } message: { alert in
            Text(alert.message)
        }
    }

    // MARK: Subviews

    @ViewBuilder
    private var clearButton: some View {
        if viewModel.fileInfo != nil {
            Button {
                viewModel.reset()
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .symbolRenderingMode(.hierarchical)
                    .font(.title3)
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .help("Clear")
            .accessibilityLabel("Clear selected file")
            .padding(8)
        }
    }

    private var controls: some View {
        VStack(spacing: 12) {
            // Native NSPopUpButton-style menu. Label icons appear inside the menu items.
            Picker(selection: $viewModel.selectedHandlerID) {
                ForEach(viewModel.handlers) { app in
                    Label {
                        Text(app.id == viewModel.currentDefaultID ? "\(app.name) (default)" : app.name)
                    } icon: {
                        Image(nsImage: app.icon)
                    }
                    .tag(String?.some(app.id))
                }
            } label: {
                Label("Open with", systemImage: "app.badge.checkmark")
            }
            .pickerStyle(.menu)
            .disabled(viewModel.handlers.isEmpty)

            Button {
                viewModel.applyToAll()
            } label: {
                ZStack {
                    // Keeps the button the same size while the spinner shows.
                    Label("Apply to All", systemImage: "checkmark.circle")
                        .opacity(viewModel.isApplying ? 0 : 1)
                    if viewModel.isApplying {
                        ProgressView().controlSize(.small)
                    }
                }
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .keyboardShortcut(.defaultAction) // Return key
            .disabled(!viewModel.canApply)

            footnote
                .font(.caption)
                .multilineTextAlignment(.center)
        }
    }

    @ViewBuilder
    private var footnote: some View {
        if let info = viewModel.fileInfo {
            if info.isDynamicType {
                Label("No app formally declares this type. The change may not stick.",
                      systemImage: "exclamationmark.triangle")
                    .foregroundStyle(.orange)
            } else if let current = viewModel.currentDefaultName, !viewModel.canApply, !viewModel.isApplying {
                Label("\(current) already opens “.\(info.fileExtension)” files.",
                      systemImage: "checkmark.seal")
                    .foregroundStyle(.secondary)
            } else {
                Text("Affects every “.\(info.fileExtension)” file for your user account.")
                    .foregroundStyle(.secondary)
            }
        }
    }
}

#Preview {
    DropFileView(viewModel: FileTypeViewModel())
        .frame(width: 440, height: 440)
}
