//
//  FolderOverlay.swift
//  Launchboard
//

import AppKit
import SwiftUI

struct FolderOverlay: View {
    @ObservedObject var store: LauncherStore
    let folder: Folder
    @State private var name = ""

    var body: some View {
        let m = store.metrics
        let g = FolderGeometry(count: folder.apps.count, metrics: m)
        ZStack(alignment: .topLeading) {
            Color.black.opacity(0.28)
                .contentShape(Rectangle())
                .onTapGesture { close() }

            RoundedRectangle(cornerRadius: 30, style: .continuous)
                .fill(.ultraThinMaterial)
                .overlay(RoundedRectangle(cornerRadius: 30, style: .continuous)
                    .stroke(Color.white.opacity(0.12)))
                .frame(width: g.rect.width, height: g.rect.height)
                .contentShape(Rectangle())
                .onTapGesture { }
                .position(x: g.rect.midX, y: g.rect.midY)
                .opacity(store.folderDragOutside ? 0.35 : 1)

            TextField("폴더 이름", text: $name)
                .textFieldStyle(.plain)
                .multilineTextAlignment(.center)
                .font(.system(size: 26, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 420)
                .onSubmit { store.renameFolder(folder.id, to: name) }
                .position(x: g.rect.midX, y: g.rect.minY + 40)
                .opacity(store.folderDragOutside ? 0.35 : 1)

            TimelineView(.animation(minimumInterval: nil, paused: !store.wiggling)) { timeline in
                let t = timeline.date.timeIntervalSinceReferenceDate
                ZStack(alignment: .topLeading) {
                    ForEach(Array(folder.apps.enumerated()), id: \.element) { index, path in
                        let isDragged = store.folderDragPath == path
                        let angle = (store.wiggling && !isDragged) ? wiggleRotation(time: t, index: index) : 0
                        FolderAppView(store: store, folderID: folder.id, path: path,
                                      iconSize: g.iconSize, width: g.cellW)
                            .rotationEffect(.degrees(angle))
                            .scaleEffect(isDragged ? 1.12 : 1)
                            .position(isDragged ? store.dragLocation : g.center(index))
                            .zIndex(isDragged ? 10 : 0)
                    }
                }
                .frame(width: m.size.width, height: m.size.height, alignment: .topLeading)
            }
        }
        .frame(width: m.size.width, height: m.size.height)
        .onAppear { name = folder.name }
        .onDisappear { store.renameFolder(folder.id, to: name) }
    }

    private func close() {
        store.renameFolder(folder.id, to: name)
        store.closeFolder()
    }
}

struct FolderAppView: View {
    @ObservedObject var store: LauncherStore
    let folderID: UUID
    let path: String
    let iconSize: CGFloat
    let width: CGFloat

    var body: some View {
        let isDragged = store.folderDragPath == path
        VStack(spacing: 6) {
            Image(nsImage: store.icon(for: path))
                .resizable()
                .interpolation(.high)
                .frame(width: iconSize, height: iconSize)
                .overlay(alignment: .topLeading) {
                    if store.wiggling && !isDragged && store.isDeletable(path) {
                        DeleteBadge(size: max(18, iconSize * 0.24)) { store.requestDelete(path) }
                            .offset(x: -iconSize * 0.06, y: -iconSize * 0.06)
                    }
                }
            Text(store.apps[path]?.name ?? "")
                .font(.system(size: 12.5, weight: .medium))
                .foregroundStyle(.white)
                .lineLimit(1)
                .frame(width: width - 8)
                .opacity(isDragged ? 0 : 1)
        }
        .frame(width: width, height: iconSize + labelOffset * 2)
        .contentShape(Rectangle())
        .onTapGesture { store.activateInFolder(path) }
        .simultaneousGesture(
            LongPressGesture(minimumDuration: Config.longPressDuration, maximumDistance: 3)
                .onEnded { _ in store.enterEditing() }
        )
        .gesture(
            DragGesture(minimumDistance: Config.dragThreshold, coordinateSpace: .named("root"))
                .onChanged { value in
                    store.folderDragChanged(folderID: folderID, path: path,
                                            location: value.location, start: value.startLocation)
                }
                .onEnded { _ in store.folderDragEnded(folderID: folderID) }
        )
        .contextMenu {
            Button("열기") { store.launch(path) }
            Button("Finder에서 보기") {
                NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: path)])
            }
            Button("Launchboard에서 숨기기") { store.hideFromList(path) }
            Divider()
            if store.isDeletable(path) {
                Button("휴지통으로 이동") { store.requestDelete(path) }
            }
            Button("폴더에서 빼기") {
                store.removeFromFolder(path, folderID: folderID)
            }
        }
    }
}
