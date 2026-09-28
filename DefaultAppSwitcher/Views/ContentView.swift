//
//  ContentView.swift
//  DefaultAppSwitcher
//
//  Root view: a segmented control switching between the two tools.
//

import SwiftUI

struct ContentView: View {
    enum Tab: String, CaseIterable, Identifiable {
        case dropFile = "Drop File"
        case commonTypes = "Common Types"
        var id: String { rawValue }
    }

    // Both view models live here, so each tab keeps its state when you switch away.
    @StateObject private var dropModel = FileTypeViewModel()
    @StateObject private var commonModel = CommonTypesViewModel()
    @State private var tab: Tab = .dropFile

    var body: some View {
        VStack(spacing: 8) {
            Picker("Mode", selection: $tab) {
                ForEach(Tab.allCases) { tab in
                    Text(tab.rawValue).tag(tab)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .fixedSize()

            switch tab {
            case .dropFile:
                DropFileView(viewModel: dropModel)
            case .commonTypes:
                CommonTypesView(viewModel: commonModel)
            }
        }
        .frame(width: 440, height: 480)
        // True window translucency; see VisualEffectBackground.swift for why this is used
        // instead of `.background(.thinMaterial)` alone.
        .background(VisualEffectBackground().ignoresSafeArea())
    }
}

#Preview {
    ContentView()
}
