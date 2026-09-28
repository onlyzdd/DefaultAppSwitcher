//
//  CommonTypesView.swift
//  DefaultAppSwitcher
//
//  "Common Types" tab: every everyday extension, its current default app, and a
//  picker to change it on the spot. Type any extension in the filter field to add it.
//

import SwiftUI

struct CommonTypesView: View {
    // Owned by ContentView, so rows stay loaded across tab switches; onAppear only refreshes.
    @ObservedObject var viewModel: CommonTypesViewModel

    var body: some View {
        VStack(spacing: 8) {
            header

            List {
                ForEach(viewModel.visibleSections) { section in
                    Section {
                        ForEach(section.extensions, id: \.self) { ext in
                            if let row = viewModel.rows[ext] {
                                FileTypeRowView(row: row) { appID in
                                    viewModel.setDefault(appID: appID, for: ext)
                                }
                                // Load candidate apps only when the row actually appears.
                                .task(id: ext) { viewModel.loadHandlers(for: ext) }
                            }
                        }
                    } header: {
                        Label(section.title, systemImage: section.systemImage)
                    }
                }
            }
            .listStyle(.inset)
            // Let the window's translucent material show through the list.
            .scrollContentBackground(.hidden)
            .overlay {
                if viewModel.visibleSections.isEmpty {
                    Text("No matching file types")
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(.top, 4)
        .onAppear { viewModel.loadIfNeeded() }
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

    private var header: some View {
        HStack(spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                TextField("Filter, or type any extension", text: $viewModel.searchText)
                    .textFieldStyle(.plain)
                if !viewModel.searchText.isEmpty {
                    Button {
                        viewModel.searchText = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Clear filter")
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(.quaternary.opacity(0.6), in: RoundedRectangle(cornerRadius: 7, style: .continuous))

            Button {
                viewModel.refreshDefaults(reloadApps: true)
            } label: {
                Image(systemName: "arrow.clockwise")
            }
            .help("Reload default apps")
            .accessibilityLabel("Reload default apps")
        }
        .padding(.horizontal, 16)
    }
}

// MARK: - Row

private struct FileTypeRowView: View {
    let row: CommonTypesViewModel.Row
    let onSelect: (String) -> Void

    var body: some View {
        HStack(spacing: 10) {
            Image(nsImage: row.typeIcon)
                .resizable()
                .interpolation(.high)
                .frame(width: 26, height: 26)

            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 4) {
                    Text(".\(row.info.fileExtension)")
                        .font(.body.weight(.medium))
                    if row.info.isDynamicType {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.caption2)
                            .foregroundStyle(.orange)
                            .help("No installed app formally declares this type. Changes may not stick.")
                    }
                }
                Text(row.info.typeDescription)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }

            Spacer(minLength: 6)

            statusIndicator
                .frame(width: 16)

            appPicker
                .frame(width: 170, alignment: .trailing)
        }
        .padding(.vertical, 2)
        .accessibilityElement(children: .contain)
    }

    @ViewBuilder
    private var statusIndicator: some View {
        switch row.status {
        case .applying:
            ProgressView().controlSize(.small)
        case .applied:
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(.green)
                .transition(.opacity)
                .accessibilityLabel("Changed")
        case .idle:
            Color.clear
        }
    }

    @ViewBuilder
    private var appPicker: some View {
        let apps = row.handlers ?? (row.defaultApp.map { [$0] } ?? [])

        if apps.isEmpty {
            Text(row.handlers == nil ? "…" : "No apps")
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .trailing)
        } else {
            Picker("Default app for .\(row.info.fileExtension)", selection: selection) {
                if row.defaultApp == nil {
                    Text("No Default").tag(String?.none)
                }
                ForEach(apps) { app in
                    Label {
                        Text(app.name)
                    } icon: {
                        Image(nsImage: app.icon)
                    }
                    .tag(String?.some(app.id))
                }
            }
            .labelsHidden()
            .pickerStyle(.menu)
            .disabled(row.status == .applying)
        }
    }

    /// Shows the pending choice while applying. Otherwise shows the real default,
    /// which is re-read from LaunchServices after every change.
    private var selection: Binding<String?> {
        Binding(
            get: { row.pendingAppID ?? row.defaultApp?.id },
            set: { newValue in
                if let newValue { onSelect(newValue) }
            }
        )
    }
}
