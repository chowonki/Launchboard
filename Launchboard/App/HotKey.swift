//
//  HotKey.swift
//  Launchboard
//

import AppKit
import Carbon.HIToolbox

// MARK: - 전역 단축키 (Carbon)

private func hotKeyHandler(_ next: EventHandlerCallRef?, _ event: EventRef?,
                           _ userData: UnsafeMutableRawPointer?) -> OSStatus {
    DispatchQueue.main.async {
        MainActor.assumeIsolated {
            AppDelegate.shared?.toggle()
        }
    }
    return noErr
}

enum HotKey {
    static var ref: EventHotKeyRef?
    static var handlerInstalled = false
    static var isRegistered: Bool { ref != nil }

    /// 단축키 등록. 다른 앱이 이미 쓰고 있으면 false
    @discardableResult
    static func register(_ shortcut: Shortcut) -> Bool {
        unregister()
        if !handlerInstalled {
            var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard),
                                     eventKind: UInt32(kEventHotKeyPressed))
            InstallEventHandler(GetApplicationEventTarget(), hotKeyHandler, 1, &spec, nil, nil)
            handlerInstalled = true
        }
        let hotKeyID = EventHotKeyID(signature: OSType(0x4C42_5244), id: 1) // 'LBRD'
        let status = RegisterEventHotKey(shortcut.keyCode, shortcut.modifiers, hotKeyID,
                                         GetApplicationEventTarget(), 0, &ref)
        return status == noErr
    }

    static func unregister() {
        if let existing = ref {
            UnregisterEventHotKey(existing)
            ref = nil
        }
    }
}
