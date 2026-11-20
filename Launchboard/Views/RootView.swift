//
//  RootView.swift
//  Launchboard
//

import AppKit
import SwiftUI

struct BlurBackground: NSViewRepresentable {
    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = .fullScreenUI
        view.blendingMode = .behindWindow
        view.state = .active
        return view
    }
    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {}
}

struct RootView: View {
    @ObservedObject var store: LauncherStore

    var body: some View {
        ZStack {
            ZStack {
                BlurBackground()
                Color.black.opacity(0.18)
            }
            .opacity(store.shown ? 1 : 0)

            ZStack {
                MainContent(store: store)
                    .blur(radius: store.openFolderID == nil ? 0 : 16)
                if let id = store.openFolderID, let folder = store.folder(id) {
                    FolderOverlay(store: store, folder: folder)
                        .transition(.opacity.combined(with: .scale(scale: 0.94)))
                }
            }
            .coordinateSpace(name: "root")
            .scaleEffect(store.shown ? 1 : 1.07)
            .opacity(store.shown ? 1 : 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .ignoresSafeArea()
        .environment(\.colorScheme, .dark)
    }
}

struct MainContent: View {
    @ObservedObject var store: LauncherStore
    @FocusState private var searchFocused: Bool

    var body: some View {
        let m = store.metrics
        ZStack(alignment: .topLeading) {
            Color.clear
                .contentShape(Rectangle())
                .onTapGesture { store.backgroundClicked() }
                .gesture(
                    // 빈 곳을 마우스로 끌어서 페이지 넘기기
                    DragGesture(minimumDistance: 8)
                        .onChanged { value in store.mouseSwipeChanged(value.translation.width) }
                        .onEnded { value in
                            store.mouseSwipeEnded(value.translation.width,
                                                  predicted: value.predictedEndTranslation.width)
                        }
                )
                .contextMenu { BackgroundMenu(store: store) }

            searchField
                .position(x: m.size.width / 2, y: m.insets.top + 46)

            if store.isSearching {
                SearchGrid(store: store)
            } else {
                AppGrid(store: store)
            }

            PageDots(store: store)
                .position(x: m.size.width / 2, y: m.size.height - m.insets.bottom - 34)
        }
        .frame(width: m.size.width, height: m.size.height)
        .onAppear { searchFocused = true }
        .onChange(of: store.focusToken) { _, _ in searchFocused = true }
    }

    private var searchField: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(Color.white.opacity(0.6))
            TextField("검색", text: $store.query)
                .textFieldStyle(.plain)
                .font(.system(size: 13))
                .foregroundStyle(.white)
                .focused($searchFocused)
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 5)
        .frame(width: 230)
        .background(Color.white.opacity(0.14), in: RoundedRectangle(cornerRadius: 7, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 7, style: .continuous).stroke(Color.white.opacity(0.18)))
    }
}

struct BackgroundMenu: View {
    @ObservedObject var store: LauncherStore

    var body: some View {
        Button("이름순으로 정렬") { store.sortByName() }
        Button("기본 배치로 초기화") { store.resetLayout() }
        if !store.hiddenAppPaths.isEmpty {
            Button("숨긴 앱 모두 다시 표시") { store.showAllHiddenApps() }
        }
        Divider()
        Button("설정…") { AppDelegate.shared?.openSettings() }
        Divider()
        Button("Launchboard 종료") { NSApp.terminate(nil) }
    }
}

struct PageDots: View {
    @ObservedObject var store: LauncherStore
    var body: some View {
        let count = store.displayPageCount
        HStack(spacing: 2) {
            ForEach(0..<count, id: \.self) { i in
                Circle()
                    .fill(Color.white.opacity(i == store.currentPage ? 0.95 : 0.35))
                    .frame(width: 8, height: 8)
                    .padding(5)
                    .contentShape(Rectangle())
                    .onTapGesture { store.goToPage(i) }
            }
        }
        .opacity(count > 1 ? 1 : 0)
    }
}
