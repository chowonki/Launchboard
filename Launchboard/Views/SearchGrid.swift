//
//  SearchGrid.swift
//  Launchboard
//

import AppKit
import SwiftUI

struct SearchGrid: View {
    @ObservedObject var store: LauncherStore

    var body: some View {
        let m = store.metrics
        let entries = store.visibleSearchEntries()
        ZStack(alignment: .topLeading) {
            if store.searchResults.isEmpty {
                Text("결과 없음")
                    .font(.system(size: 22, weight: .medium))
                    .foregroundStyle(Color.white.opacity(0.6))
                    .position(x: m.size.width / 2, y: m.size.height / 2)
            }
            ForEach(entries) { entry in
                SearchItemView(store: store, app: entry.app, iconSize: m.iconSize, width: m.cellW,
                               selected: entry.index == store.searchSelection)
                    .position(m.center(index: entry.index, currentPage: store.currentPage, offset: store.scrollOffset))
            }
        }
        .frame(width: m.size.width, height: m.size.height, alignment: .topLeading)
    }
}

struct SearchItemView: View {
    @ObservedObject var store: LauncherStore
    let app: AppInfo
    let iconSize: CGFloat
    let width: CGFloat
    let selected: Bool

    var body: some View {
        VStack(spacing: 6) {
            Image(nsImage: store.icon(for: app.path))
                .resizable()
                .interpolation(.high)
                .frame(width: iconSize, height: iconSize)
            Text(app.name)
                .font(.system(size: 12.5, weight: .medium))
                .foregroundStyle(.white)
                .lineLimit(1)
                .frame(width: width - 8)
        }
        .padding(8)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color.white.opacity(selected ? 0.2 : 0))
        )
        .frame(width: width, height: iconSize + labelOffset * 2)
        .contentShape(Rectangle())
        .onTapGesture { store.launch(app.path) }
    }
}
