//
//  AppSettings.swift
//  Launchboard
//

import AppKit
import Carbon.HIToolbox
import CoreServices
import ServiceManagement

/// 설정 창에서 바꾸는 값들. 값을 바꾸면 바로 저장·적용됩니다.
@MainActor
final class AppSettings: ObservableObject {
    static let shared = AppSettings()

    private var syncing = false

    /// 로그인 시 자동 실행 (macOS 로그인 항목)
    @Published var launchAtLogin: Bool {
        didSet {
            guard !syncing, launchAtLogin != oldValue else { return }
            applyLaunchAtLogin(launchAtLogin)
        }
    }

    /// Dock 실행 표시등(아이콘 아래 점) 숨기기.
    /// 켜면 예전 Launchpad처럼 실행 중이어도 점이 안 나와요 (Dock에 고정해 둔 아이콘은 그대로 눌러서 열 수 있음)
    @Published var hideDockIndicator: Bool {
        didSet {
            guard hideDockIndicator != oldValue else { return }
            UserDefaults.standard.set(hideDockIndicator, forKey: "hideDockIndicator")
            applyActivationPolicy()
        }
    }

    /// Launchboard를 열 때 Dock 자동 숨기기
    @Published var hideDockWhenOpen: Bool {
        didSet {
            guard hideDockWhenOpen != oldValue else { return }
            UserDefaults.standard.set(hideDockWhenOpen, forKey: "hideDockWhenOpen")
        }
    }

    /// Launchboard 열기/닫기 전역 단축키
    @Published private(set) var hotKey: Shortcut
    /// 설정 창에서 새 단축키를 입력받는 중인지
    @Published private(set) var isRecordingHotKey = false
    @Published private(set) var hotKeyMessage: String?
    private var recordMonitor: Any?

    /// 단축키를 데스크톱(Finder가 맨 앞)에서만 동작시킬지
    @Published var hotKeyDesktopOnly: Bool {
        didSet {
            guard hotKeyDesktopOnly != oldValue else { return }
            UserDefaults.standard.set(hotKeyDesktopOnly, forKey: "hotKeyDesktopOnly")
            updateHotKeyRegistration()
        }
    }

    private init() {
        hotKeyDesktopOnly = UserDefaults.standard.object(forKey: "hotKeyDesktopOnly") as? Bool ?? true
        if let data = UserDefaults.standard.data(forKey: "hotKey"),
           let saved = try? JSONDecoder().decode(Shortcut.self, from: data) {
            hotKey = saved
        } else {
            hotKey = .standard
        }
        launchAtLogin = SMAppService.mainApp.status == .enabled
        hideDockIndicator = UserDefaults.standard.object(forKey: "hideDockIndicator") as? Bool ?? false
        hideDockWhenOpen = UserDefaults.standard.object(forKey: "hideDockWhenOpen") as? Bool ?? true

        // Migrate former defaults once; preserve other custom shortcuts.
        let migrationKey = "hotKey.controlShiftAMigrated"
        if !UserDefaults.standard.bool(forKey: migrationKey) {
            let previousDefaults = [
                Shortcut(keyCode: UInt32(kVK_Space), modifiers: UInt32(optionKey)),
                Shortcut(keyCode: UInt32(kVK_Space), modifiers: UInt32(controlKey | optionKey)),
                Shortcut(keyCode: UInt32(kVK_ANSI_L), modifiers: UInt32(controlKey | optionKey)),
                Shortcut(keyCode: UInt32(kVK_ANSI_A), modifiers: UInt32(controlKey | optionKey)),
            ]
            if previousDefaults.contains(hotKey) {
                hotKey = .standard
                if let data = try? JSONEncoder().encode(hotKey) {
                    UserDefaults.standard.set(data, forKey: "hotKey")
                }
            }
            UserDefaults.standard.set(true, forKey: migrationKey)
        }
    }

    /// 시스템 설정에서 바뀌었을 수 있는 로그인 항목 상태를 다시 읽음
    func refresh() {
        syncing = true
        launchAtLogin = SMAppService.mainApp.status == .enabled
        syncing = false
    }

    // 메뉴에서 쓰는 단축 함수
    func setLaunchAtLogin(_ on: Bool) { launchAtLogin = on }
    func setHideDockIndicator(_ on: Bool) { hideDockIndicator = on }

    /// Launchboard가 떠 있는 동안 적용할 화면 옵션
    /// (메뉴 막대 자동 숨김은 macOS 규칙상 Dock 자동 숨김과 함께만 쓸 수 있어요)
    var presentationOptions: NSApplication.PresentationOptions {
        hideDockWhenOpen ? [.autoHideDock, .autoHideMenuBar] : []
    }

    // MARK: 단축키

    /// 저장된 단축키 등록 (앱 시작 시)
    func applyHotKey() {
        updateHotKeyRegistration()
    }

    /// 지금 맨 앞에 있는 앱에 맞춰 단축키를 등록하거나 해제.
    /// '데스크톱에서만'이 켜져 있으면 Finder(데스크톱)나 Launchboard가 맨 앞일 때만 등록해서,
    /// 다른 앱에서는 같은 키 조합이 그 앱으로 그대로 전달돼요.
    func updateHotKeyRegistration(frontmostBundleID: String? = NSWorkspace.shared.frontmostApplication?.bundleIdentifier) {
        guard !isRecordingHotKey else { return }
        let allowed: Bool
        if hotKeyDesktopOnly {
            allowed = frontmostBundleID == "com.apple.finder"
                || frontmostBundleID == Bundle.main.bundleIdentifier
        } else {
            allowed = true
        }
        if allowed {
            guard !HotKey.isRegistered else { return }
            if !HotKey.register(hotKey) {
                hotKeyMessage = "‘\(hotKey.display)’는 다른 앱이 쓰고 있어요. 설정에서 다른 단축키를 골라 주세요."
            }
        } else {
            HotKey.unregister()
        }
    }

    func startRecordingHotKey() {
        guard !isRecordingHotKey else { return }
        hotKeyMessage = nil
        isRecordingHotKey = true
        HotKey.unregister()   // 지금 단축키도 입력받을 수 있게 잠시 해제
        recordMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self else { return event }
            MainActor.assumeIsolated { self.handleRecorded(event) }
            return nil
        }
    }

    func stopRecordingHotKey() {
        guard isRecordingHotKey else { return }
        endRecording()
        updateHotKeyRegistration()
    }

    func resetHotKey() {
        endRecording()
        hotKeyMessage = nil
        apply(.standard)
    }

    private func endRecording() {
        if let monitor = recordMonitor {
            NSEvent.removeMonitor(monitor)
            recordMonitor = nil
        }
        isRecordingHotKey = false
    }

    private func handleRecorded(_ event: NSEvent) {
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        let code = Int(event.keyCode)
        let hasMainModifier = !flags.isDisjoint(with: [.command, .option, .control])

        // 수식키 없는 Esc → 취소
        if code == kVK_Escape && !hasMainModifier && !flags.contains(.shift) {
            stopRecordingHotKey()
            return
        }
        guard hasMainModifier || KeyNames.functionKeys.contains(code) else {
            hotKeyMessage = "⌘, ⌥, ⌃ 중 하나 이상과 함께 눌러 주세요. (F1~F20은 단독으로도 가능)"
            return
        }
        endRecording()
        hotKeyMessage = nil
        apply(Shortcut(keyCode: UInt32(code), modifiers: Shortcut.carbonModifiers(from: flags)))
    }

    private func apply(_ shortcut: Shortcut) {
        if HotKey.register(shortcut) {
            hotKey = shortcut
            if let data = try? JSONEncoder().encode(shortcut) {
                UserDefaults.standard.set(data, forKey: "hotKey")
            }
        } else {
            hotKeyMessage = "‘\(shortcut.display)’는 다른 앱이나 시스템이 쓰고 있어요. 다른 조합을 골라 주세요."
            HotKey.unregister()
        }
        updateHotKeyRegistration()   // 이전 단축키 복원 또는 범위에 맞게 재등록
    }

    // MARK: 적용

    private func applyLaunchAtLogin(_ on: Bool) {
        do {
            if on {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            let alert = NSAlert()
            alert.messageText = "로그인 항목을 변경하지 못했어요."
            alert.informativeText = error.localizedDescription
                + "\n\n앱을 /Applications 폴더에 넣은 뒤 다시 시도하거나, 시스템 설정 → 일반 → 로그인 항목에서 직접 설정할 수 있어요."
            alert.addButton(withTitle: "시스템 설정 열기")
            alert.addButton(withTitle: "닫기")
            if alert.runModal() == .alertFirstButtonReturn {
                SMAppService.openSystemSettingsLoginItems()
            }
        }
        if SMAppService.mainApp.status == .requiresApproval {
            SMAppService.openSystemSettingsLoginItems()
        }
        refresh()
    }

    func applyActivationPolicy() {
        // .accessory: Dock에 실행 표시등이 없고 ⌘Tab 목록에도 나오지 않음 (Info.plist의 LSUIElement와 같은 상태)
        NSApp.setActivationPolicy(hideDockIndicator ? .accessory : .regular)
    }

    /// 로그인 항목으로 실행됐는지 확인 (이 경우 화면을 띄우지 않고 백그라운드에서 대기)
    static func wasLaunchedAtLogin() -> Bool {
        guard let event = NSAppleEventManager.shared().currentAppleEvent else { return false }
        return event.eventID == AEEventID(kAEOpenApplication)
            && event.paramDescriptor(forKeyword: AEKeyword(keyAEPropData))?.enumCodeValue
                == OSType(keyAELaunchedAsLogInItem)
    }
}
