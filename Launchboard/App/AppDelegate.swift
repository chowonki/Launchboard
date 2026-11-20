//
//  AppDelegate.swift
//  Launchboard
//

import AppKit
import SwiftUI
import Carbon.HIToolbox

// MARK: - 창 / 앱

final class LauncherWindow: NSWindow {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    static weak var shared: AppDelegate?

    var store: LauncherStore!
    var window: LauncherWindow!
    private var monitors: [Any] = []
    private var hiding = false
    private var statusItem: NSStatusItem?
    private var settingsWindow: NSWindow?
    /// 로그인 시 실행된 직후에는 화면을 자동으로 띄우지 않음
    private var suppressAutoShowUntil = Date.distantPast
    /// 마지막으로 화면을 연 시각. 열자마자 들어오는 닫기 신호(Dock 재클릭, 비활성화)를 무시하는 데 사용
    private var lastShownAt = Date.distantPast
    private var justShown: Bool { Date().timeIntervalSince(lastShownAt) < 0.6 }
    /// 마지막으로 닫은 시각. 닫자마자 들어오는 '앱 활성화' 신호로 다시 열리는 것을 막음
    private var lastHiddenAt = Date.distantPast
    private var justHidden: Bool { Date().timeIntervalSince(lastHiddenAt) < 0.8 }
    /// 마지막으로 열기/닫기를 전환한 시각 (한 번의 클릭에서 오는 중복 신호 무시용)
    private var lastToggleAt = Date.distantPast
    /// Launchboard를 열기 전에 앞에 있던 앱. 닫을 때 그 앱으로 포커스를 돌려줌
    private var previousApp: NSRunningApplication?

    private var isOpen: Bool { window.isVisible && store.shown && !hiding }

    func applicationDidFinishLaunching(_ notification: Notification) {
        AppDelegate.shared = self
        store = LauncherStore()
        buildMenu()

        let w = LauncherWindow(contentRect: NSScreen.main?.frame ?? NSRect(x: 0, y: 0, width: 1440, height: 900),
                               styleMask: [.borderless],
                               backing: .buffered,
                               defer: false)
        w.isOpaque = false
        w.backgroundColor = .clear
        w.hasShadow = false
        w.level = .floating              // Dock보다 아래 → Launchpad처럼 Dock이 보임
        w.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        w.isReleasedWhenClosed = false
        let hosting = NSHostingView(rootView: RootView(store: store))
        hosting.sizingOptions = []
        w.contentView = hosting
        window = w

        // An app launch transfers focus to the selected app. Do not reactivate
        // the app that was open before Launchboard after the closing animation.
        store.onLaunch = { [weak self] in self?.hide(deactivate: false) }
        store.onDismiss = { [weak self] in self?.hide() }

        installMonitors()
        AppSettings.shared.applyHotKey()
        // 앞에 나온 앱이 바뀔 때마다 단축키를 켜거나 끔 (데스크톱에서만 동작 옵션)
        NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main
        ) { note in
            let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
            let bundleID = app?.bundleIdentifier
            MainActor.assumeIsolated {
                AppSettings.shared.updateHotKeyRegistration(frontmostBundleID: bundleID)
            }
        }
        setupStatusItem()

        if AppSettings.wasLaunchedAtLogin() {
            // 로그인 항목으로 실행되면 백그라운드에서 조용히 대기
            suppressAutoShowUntil = Date().addingTimeInterval(5)
        } else {
            // 앱이 완전히 준비된 다음 열어야 활성화가 무시되지 않음
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                self.lastToggleAt = Date()
                self.show()
            }
        }
    }

    // MARK: 메뉴 막대 아이콘

    private func setupStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        item.button?.image = NSImage(systemSymbolName: "square.grid.3x3.fill",
                                     accessibilityDescription: "Launchboard")
        let menu = NSMenu()
        menu.delegate = self
        item.menu = menu
        statusItem = item
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        let settings = AppSettings.shared
        settings.refresh()
        menu.removeAllItems()

        let open = NSMenuItem(title: "Launchboard 열기  (\(settings.hotKey.display))", action: #selector(openFromMenu), keyEquivalent: "")
        open.target = self
        menu.addItem(open)
        menu.addItem(.separator())

        let prefs = NSMenuItem(title: "설정…", action: #selector(openSettings), keyEquivalent: ",")
        prefs.target = self
        menu.addItem(prefs)
        menu.addItem(.separator())

        let login = NSMenuItem(title: "로그인 시 자동 실행", action: #selector(toggleLaunchAtLogin), keyEquivalent: "")
        login.target = self
        login.state = settings.launchAtLogin ? .on : .off
        menu.addItem(login)

        let dock = NSMenuItem(title: "Dock 실행 표시등 숨기기", action: #selector(toggleDockIcon), keyEquivalent: "")
        dock.target = self
        dock.state = settings.hideDockIndicator ? .on : .off
        menu.addItem(dock)

        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Launchboard 종료",
                                action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
    }

    @objc private func openFromMenu() { show() }

    /// ⌘W: 설정 창이 앞에 있으면 설정 창을, 아니면 Launchboard 화면을 닫음
    @objc private func closeFrontWindow() {
        if let key = NSApp.keyWindow, key !== window {
            key.performClose(nil)
            return
        }
        if isOpen {
            lastToggleAt = Date()
            hide()
        }
    }

    // MARK: 설정 창

    @objc func openSettings() {
        hide(deactivate: false)
        if settingsWindow == nil {
            let host = NSHostingController(rootView: SettingsView(settings: AppSettings.shared))
            let w = NSWindow(contentViewController: host)
            w.title = "Launchboard 설정"
            w.styleMask = [.titled, .closable]
            w.isReleasedWhenClosed = false
            w.center()
            settingsWindow = w
        }
        NSApp.activate(ignoringOtherApps: true)
        settingsWindow?.makeKeyAndOrderFront(nil)
    }

    @objc private func toggleLaunchAtLogin() {
        AppSettings.shared.setLaunchAtLogin(!AppSettings.shared.launchAtLogin)
    }

    @objc private func toggleDockIcon() {
        AppSettings.shared.setHideDockIndicator(!AppSettings.shared.hideDockIndicator)
    }

    private func installMonitors() {
        if let m = NSEvent.addLocalMonitorForEvents(matching: .keyDown, handler: { [weak self] event in
            guard let self else { return event }
            let consumed = MainActor.assumeIsolated { self.handleKeyDown(event) }
            return consumed ? nil : event
        }) { monitors.append(m) }

        if let m = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel, handler: { [weak self] event in
            guard let self else { return event }
            MainActor.assumeIsolated { self.store.handleScroll(event) }
            return nil
        }) { monitors.append(m) }
    }

    private func handleKeyDown(_ event: NSEvent) -> Bool {
        // 삭제 확인 창 같은 다른 창의 키 입력은 건드리지 않음
        guard event.window === window else { return false }
        switch Int(event.keyCode) {
        case kVK_Escape:
            if !store.handleEscape() { hide() }
            return true
        case kVK_Return, kVK_ANSI_KeypadEnter:
            if store.isSearching && store.openFolderID == nil {
                store.launchSelection()
                return true
            }
            return false
        case kVK_LeftArrow: return store.arrow(dx: -1, dy: 0)
        case kVK_RightArrow: return store.arrow(dx: 1, dy: 0)
        case kVK_UpArrow: return store.arrow(dx: 0, dy: -1)
        case kVK_DownArrow: return store.arrow(dx: 0, dy: 1)
        default: return false
        }
    }

    private func metrics(for screen: NSScreen) -> GridMetrics {
        let full = screen.frame
        let visible = screen.visibleFrame
        // Dock·메뉴 막대를 숨기면 화면 전체를, 아니면 그 둘을 피해서 배치
        let hideDock = AppSettings.shared.hideDockWhenOpen
        let menuBar = hideDock ? 0 : full.maxY - visible.maxY
        let insets = EdgeInsets(top: max(screen.safeAreaInsets.top, menuBar, 12),
                                leading: hideDock ? 0 : visible.minX - full.minX,
                                bottom: hideDock ? 0 : visible.minY - full.minY,
                                trailing: hideDock ? 0 : full.maxX - visible.maxX)
        return GridMetrics(size: full.size, insets: insets)
    }

    func show() {
        hiding = false
        let mouse = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { NSMouseInRect(mouse, $0.frame, false) } ?? NSScreen.main
        if let screen {
            window.setFrame(screen.frame, display: false)
            let m = metrics(for: screen)
            if store.metrics != m { store.metrics = m }
        }
        let alreadyShown = window.isVisible && store.shown
        if !alreadyShown {
            store.prepareForShow()
            lastShownAt = Date()
            if let front = NSWorkspace.shared.frontmostApplication,
               front.processIdentifier != NSRunningApplication.current.processIdentifier {
                previousApp = front
            }
        }
        bringToFront()
        NSApp.presentationOptions = AppSettings.shared.presentationOptions
        // 첫 실행 직후 등 활성화 요청이 무시된 경우를 대비해 잠시 뒤 다시 확인
        for delay in [0.15, 0.4, 0.8] {
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
                guard let self, self.isOpen, !NSApp.isActive || !self.window.isKeyWindow else { return }
                self.bringToFront()
                NSApp.presentationOptions = AppSettings.shared.presentationOptions
            }
        }
        if !store.shown {
            withAnimation(.easeOut(duration: 0.22)) { store.shown = true }
        }
    }

    /// 앱을 활성화하고 Launchboard 창을 키 창으로 만듦
    private func bringToFront() {
        // macOS 14+의 협조적 활성화(activate())는 첫 실행 때 무시될 수 있어 강제 활성화도 함께 사용
        NSApp.activate(ignoringOtherApps: true)
        if #available(macOS 14.0, *) { NSApp.activate() }
        window.orderFrontRegardless()
        window.makeKeyAndOrderFront(nil)
        store.focusToken += 1   // 검색창에 포커스
    }

    func hide(deactivate: Bool = true) {
        guard window.isVisible, !hiding else { return }
        hiding = true
        lastHiddenAt = Date()
        // 메뉴 막대·Dock 숨김은 앱이 아직 활성 상태일 때 바로 풀어야 다음 앱에서 메뉴 막대가 정상 표시됨
        NSApp.presentationOptions = []
        withAnimation(.easeIn(duration: 0.18)) { store.shown = false }
        Task { [weak self] in
            try? await Task.sleep(nanoseconds: 190_000_000)
            guard let self, self.hiding else { return }
            self.window.orderOut(nil)
            NSApp.presentationOptions = []
            self.hiding = false
            if deactivate && NSApp.isActive {
                // 이전 앱으로 포커스를 돌려줌 (NSApp.hide는 Dock 클릭 시 다시 열리는 원인이 됨)
                if let prev = self.previousApp, !prev.isTerminated {
                    prev.activate()
                } else {
                    NSApp.hide(nil)
                }
            }
        }
    }

    /// Dock 클릭·단축키·메뉴 공통: 열려 있으면 닫고, 닫혀 있으면 엶.
    /// 한 번의 동작에서 신호가 여러 번 와도 한 번만 전환
    func toggle() {
        guard Date().timeIntervalSince(lastToggleAt) > 0.35 else { return }
        lastToggleAt = Date()
        if isOpen { hide() } else { show() }
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        // Dock 아이콘 클릭: Launchpad처럼 열려 있으면 닫고, 닫혀 있으면 엶
        toggle()
        return false
    }

    func applicationDidBecomeActive(_ notification: Notification) {
        if Date() < suppressAutoShowUntil { return }
        if settingsWindow?.isVisible == true { return }
        // 활성화만 되고 Dock 클릭(전환) 신호가 따로 오지 않는 경우(⌘Tab 등)를 위한 보조 처리.
        // 잠깐 기다렸다가 그 사이 전환이 없었고 닫혀 있을 때만 엶
        let activatedAt = Date()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { [weak self] in
            guard let self else { return }
            if self.lastToggleAt >= activatedAt.addingTimeInterval(-0.35) { return }
            if self.justHidden || self.isOpen || !NSApp.isActive { return }
            if self.settingsWindow?.isVisible == true { return }
            self.lastToggleAt = Date()
            self.show()
        }
    }

    func applicationDidResignActive(_ notification: Notification) {
        // 열자마자 다른 앱(Finder·Dock)이 순간적으로 앞으로 오는 경우엔 닫지 않고 다시 앞으로 가져옴
        if justShown && window.isVisible && !hiding {
            DispatchQueue.main.async { [weak self] in self?.show() }
            return
        }
        NSApp.presentationOptions = []
        // 다른 앱으로 넘어갔으니 포커스를 되돌릴 필요 없이 닫기만 함
        hide(deactivate: false)
    }

    private func buildMenu() {
        let mainMenu = NSMenu()

        let appItem = NSMenuItem()
        mainMenu.addItem(appItem)
        let appMenu = NSMenu()
        let prefs = NSMenuItem(title: "설정…", action: #selector(openSettings), keyEquivalent: ",")
        prefs.target = self
        appMenu.addItem(prefs)
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "Launchboard 종료",
                        action: #selector(NSApplication.terminate(_:)),
                        keyEquivalent: "q")
        appItem.submenu = appMenu

        let fileItem = NSMenuItem()
        mainMenu.addItem(fileItem)
        let fileMenu = NSMenu(title: "파일")
        let close = NSMenuItem(title: "닫기", action: #selector(closeFrontWindow), keyEquivalent: "w")
        close.target = self
        fileMenu.addItem(close)
        fileItem.submenu = fileMenu

        let editItem = NSMenuItem()
        mainMenu.addItem(editItem)
        let editMenu = NSMenu(title: "편집")
        editMenu.addItem(withTitle: "잘라내기", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        editMenu.addItem(withTitle: "복사", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        editMenu.addItem(withTitle: "붙여넣기", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        editMenu.addItem(withTitle: "전체 선택", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        editItem.submenu = editMenu

        NSApp.mainMenu = mainMenu
    }
}
