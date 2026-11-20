//
//  SettingsView.swift
//  Launchboard
//

import SwiftUI

struct SettingsView: View {
    @ObservedObject var settings: AppSettings

    var body: some View {
        Form {
            Section("시작") {
                Toggle("로그인 시 자동 실행", isOn: $settings.launchAtLogin)
                Text("로그인할 때 화면을 띄우지 않고 백그라운드에서 대기해요. 앱을 /Applications에 넣은 뒤 켜는 걸 권장해요.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Dock") {
                Toggle("Launchboard를 열 때 Dock 자동 숨기기", isOn: $settings.hideDockWhenOpen)
                Text("열려 있는 동안 Dock과 메뉴 막대가 숨겨져 Launchboard가 화면 전체를 써요. 마우스를 화면 끝으로 가져가면 다시 보여요.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Toggle("Dock 실행 표시등 숨기기", isOn: $settings.hideDockIndicator)
                Text("켜면 Dock 아이콘 아래에 실행 중 점이 나오지 않고 ⌘Tab 목록에도 보이지 않아요. Dock 아이콘은 응용 프로그램 폴더에서 Dock으로 끌어다 놓아 고정해 두세요.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("단축키") {
                LabeledContent("Launchboard 열기/닫기") {
                    HStack(spacing: 8) {
                        Button {
                            if settings.isRecordingHotKey {
                                settings.stopRecordingHotKey()
                            } else {
                                settings.startRecordingHotKey()
                            }
                        } label: {
                            Text(settings.isRecordingHotKey ? "단축키를 누르세요…" : settings.hotKey.display)
                                .font(.system(size: 13, weight: .medium))
                                .frame(minWidth: 130)
                        }
                        .buttonStyle(.bordered)
                        .tint(settings.isRecordingHotKey ? .accentColor : nil)

                        Button("기본값") { settings.resetHotKey() }
                            .disabled(settings.hotKey == .standard && !settings.isRecordingHotKey)
                    }
                }
                if let message = settings.hotKeyMessage {
                    Text(message)
                        .font(.caption)
                        .foregroundStyle(.red)
                }
                Text("단축키 버튼을 누른 뒤 원하는 조합을 누르세요. Esc를 누르면 취소돼요.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Toggle("데스크톱 화면에서만 단축키 사용", isOn: $settings.hotKeyDesktopOnly)
                Text("켜면 Finder(데스크톱)가 맨 앞일 때만 단축키로 열려요. 다른 앱을 쓰는 중에는 같은 키 조합이 그 앱으로 그대로 전달돼요.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                LabeledContent("설정 열기", value: "⌘ ,")
            }
        }
        .formStyle(.grouped)
        .frame(width: 460)
        .fixedSize(horizontal: false, vertical: true)
        .onAppear { settings.refresh() }
        .onDisappear { settings.stopRecordingHotKey() }
    }
}
