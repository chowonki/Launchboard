//
//  LaunchboardApp.swift
//  Launchboard
//

import AppKit

// MARK: - 진입점

@main
struct LaunchboardMain {
    static func main() {
        // 이미 다른 Launchboard가 실행 중이면 그쪽을 열고 이 실행은 바로 종료 (중복 실행 방지)
        let me = NSRunningApplication.current
        if let bundleID = Bundle.main.bundleIdentifier {
            let others = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID)
                .filter { $0.processIdentifier != me.processIdentifier && !$0.isTerminated }
            if let other = others.first {
                // 실행 중인 쪽에 '다시 열기'를 보내면 화면이 열림
                if let url = other.bundleURL {
                    NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration())
                }
                exit(0)
            }
        }

        MainActor.assumeIsolated {
            let app = NSApplication.shared
            let delegate = AppDelegate()
            app.delegate = delegate
            AppSettings.shared.applyActivationPolicy()
            app.run()
        }
    }
}
