//
//  AppGrid.swift
//  Launchboard
//

import AppKit
import SwiftUI

struct AppGrid: View {
    @ObservedObject var store: LauncherStore

    var body: some View {
        let m = store.metrics
        let entries = store.visibleGridEntries()
        TimelineView(.animation(minimumInterval: nil, paused: !store.wiggling)) { timeline in
            let t = timeline.date.timeIntervalSinceReferenceDate
            ZStack(alignment: .topLeading) {
                ForEach(entries) { entry in
                    let isDragged = store.draggingID == entry.item.id
                    GridItemView(store: store, item: entry.item, iconSize: m.iconSize, width: m.cellW)
                        .rotationEffect(.degrees(wiggleAngle(t: t, index: entry.index, active: store.wiggling && !isDragged)))
                        .scaleEffect(isDragged ? 1.12 : 1)
                        .position(store.position(for: entry))
                        .zIndex(isDragged ? 10 : 0)
                }
            }
            .frame(width: m.size.width, height: m.size.height, alignment: .topLeading)
        }
    }

    private func wiggleAngle(t: Double, index: Int, active: Bool) -> Double {
        guard active else { return 0 }
        return wiggleRotation(time: t, index: index)
    }
}

struct GridItemView: View {
    @ObservedObject var store: LauncherStore
    let item: LaunchItem
    let iconSize: CGFloat
    let width: CGFloat

    var body: some View {
        let isDragged = store.draggingID == item.id
        let isMergeTarget = store.mergeTargetID == item.id
        VStack(spacing: 6) {
            icon(isMergeTarget: isMergeTarget)
                .frame(width: iconSize, height: iconSize)
                .overlay(alignment: .topLeading) { deleteBadge(isDragged: isDragged) }
            Text(store.displayName(item))
                .font(.system(size: 12.5, weight: .medium))
                .foregroundStyle(.white)
                .lineLimit(1)
                .truncationMode(.tail)
                .frame(width: width - 8)
                .shadow(color: Color.black.opacity(0.45), radius: 2, y: 1)
                .opacity(isDragged ? 0 : 1)
        }
        .frame(width: width, height: iconSize + labelOffset * 2)
        .contentShape(Rectangle())
        .onTapGesture { store.activate(item) }
        .simultaneousGesture(
            // 길게 누르면 흔들림 모드 (움직이면 취소되고 드래그로 넘어감)
            LongPressGesture(minimumDuration: Config.longPressDuration, maximumDistance: 3)
                .onEnded { _ in store.enterEditing() }
        )
        .gesture(
            DragGesture(minimumDistance: Config.dragThreshold, coordinateSpace: .named("root"))
                .onChanged { value in
                    store.dragChanged(id: item.id, location: value.location, start: value.startLocation)
                }
                .onEnded { _ in store.dragEnded() }
        )
        .contextMenu { menu }
    }

    @ViewBuilder
    private func deleteBadge(isDragged: Bool) -> some View {
        if case .app(let path) = item, store.wiggling, !isDragged,
           store.draggingID == nil, store.isDeletable(path) {
            DeleteBadge(size: max(18, iconSize * 0.24)) { store.requestDelete(path) }
                .offset(x: -iconSize * 0.06, y: -iconSize * 0.06)
                .transition(.scale.combined(with: .opacity))
        }
    }

    @ViewBuilder
    private func icon(isMergeTarget: Bool) -> some View {
        switch item {
        case .app(let path):
            ZStack {
                if isMergeTarget {
                    RoundedRectangle(cornerRadius: iconSize * 0.24, style: .continuous)
                        .fill(Color.white.opacity(0.3))
                        .frame(width: iconSize * 1.2, height: iconSize * 1.2)
                }
                Image(nsImage: store.icon(for: path))
                    .resizable()
                    .interpolation(.high)
                    .scaleEffect(isMergeTarget ? 0.85 : 1)
            }
        case .folder(let folder):
            FolderIcon(store: store, folder: folder, size: iconSize, highlighted: isMergeTarget)
                .scaleEffect(isMergeTarget ? 1.15 : 1)
        }
    }

    @ViewBuilder private var menu: some View {
        switch item {
        case .app(let path):
            Button("열기") { store.launch(path) }
            Button("Finder에서 보기") {
                NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: path)])
            }
            Button("Launchboard에서 숨기기") { store.hideFromList(path) }
            Divider()
            Button("새 폴더 만들기") { store.createFolder(with: path) }
            if !store.folders.isEmpty {
                Menu("폴더로 이동") {
                    ForEach(store.folders) { folder in
                        Button(folder.name) { store.addToFolder(path, folderID: folder.id) }
                    }
                }
            }
            if store.isDeletable(path) {
                Divider()
                Button("휴지통으로 이동") { store.requestDelete(path) }
            }
        case .folder(let folder):
            Button("열기") { store.openFolder(folder.id) }
            Button("폴더 해제") { store.ungroup(folder.id) }
        }
    }
}

struct FolderIcon: View {
    @ObservedObject var store: LauncherStore
    let folder: Folder
    let size: CGFloat
    let highlighted: Bool

    var body: some View {
        let mini = size * 0.22
        let gap = size * 0.06
        RoundedRectangle(cornerRadius: size * 0.24, style: .continuous)
            .fill(Color.white.opacity(highlighted ? 0.4 : 0.22))
            .frame(width: size, height: size)
            .overlay(alignment: .topLeading) {
                VStack(alignment: .leading, spacing: gap) {
                    ForEach(0..<3, id: \.self) { row in
                        HStack(spacing: gap) {
                            ForEach(0..<3, id: \.self) { col in
                                miniIcon(at: row * 3 + col, size: mini)
                            }
                        }
                    }
                }
                .padding(size * 0.11)
            }
    }

    @ViewBuilder
    private func miniIcon(at index: Int, size: CGFloat) -> some View {
        if index < folder.apps.count {
            Image(nsImage: store.icon(for: folder.apps[index]))
                .resizable()
                .interpolation(.high)
                .frame(width: size, height: size)
        } else {
            Color.clear.frame(width: size, height: size)
        }
    }
}

/// Launchpad 흔들림 모드의 ⓧ 삭제 버튼
struct DeleteBadge: View {
    let size: CGFloat
    let action: () -> Void

    var body: some View {
        ZStack {
            Circle()
                .fill(Color(white: 0.82))
                .shadow(color: Color.black.opacity(0.35), radius: 2, y: 1)
            Image(systemName: "xmark")
                .font(.system(size: size * 0.45, weight: .bold))
                .foregroundStyle(Color(white: 0.25))
        }
        .frame(width: size, height: size)
        .contentShape(Circle())
        .onTapGesture { action() }
    }
}
