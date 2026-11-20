//
//  Config.swift
//  Launchboard
//

import Foundation
import Carbon.HIToolbox

// MARK: - 설정

enum Config {
    /// 전역 단축키 기본값 (⌃⇧ + A). 실제 단축키는 설정 창에서 바꿔요
    static let hotKeyCode = UInt32(kVK_ANSI_A)
    /// 예: UInt32(optionKey), UInt32(cmdKey | optionKey), UInt32(controlKey | optionKey)
    static let hotKeyModifiers = UInt32(controlKey | shiftKey)
    static let columns = 7
    static let rows = 5

    // MARK: 흔들림 / 드래그 민감도 (값을 키우면 덜 민감해져요)
    /// 흔들림 모드에 들어가려면 아이콘을 누르고 있어야 하는 시간(초)
    static let longPressDuration = 1.0
    /// 이만큼(포인트) 움직여야 아이콘 드래그가 시작됨
    static let dragThreshold: CGFloat = 12
    /// 흔들림 각도(도)와 속도
    static let wiggleAngle = 1.2
    static let wiggleSpeed = 11.0
    /// true면 드래그만 해도 흔들림 모드가 유지됨(Launchpad 원래 동작). false면 드래그하는 동안만 흔들림
    static let dragKeepsEditing = false
}

func wiggleRotation(time t: Double, index: Int) -> Double {
    sin(t * Config.wiggleSpeed + Double(index) * 1.7) * Config.wiggleAngle
}

let labelOffset: CGFloat = 12   // 아이템 중심에서 아이콘 중심까지의 세로 거리

// MARK: - 앱 카테고리 → 폴더 이름

func categoryDisplayName(_ type: String) -> String? {
    let key = type.replacingOccurrences(of: "public.app-category.", with: "")
    if key.hasSuffix("games") { return "게임" }
    let names: [String: String] = [
        "business": "비즈니스", "developer-tools": "개발자 도구", "education": "교육",
        "entertainment": "엔터테인먼트", "finance": "금융", "graphics-design": "그래픽 및 디자인",
        "healthcare-fitness": "건강 및 피트니스", "lifestyle": "라이프스타일", "medical": "의료",
        "music": "음악", "news": "뉴스", "photography": "사진", "productivity": "생산성",
        "reference": "참고", "social-networking": "소셜 네트워킹", "sports": "스포츠",
        "travel": "여행", "utilities": "유틸리티", "video": "비디오", "weather": "날씨",
    ]
    return names[key]
}

func categoryName(forAppAt path: String) -> String? {
    guard let type = Bundle(path: path)?.object(forInfoDictionaryKey: "LSApplicationCategoryType") as? String
    else { return nil }
    return categoryDisplayName(type)
}

// MARK: - 한글 초성

let choseongTable: [Character] = Array("ㄱㄲㄴㄷㄸㄹㅁㅂㅃㅅㅆㅇㅈㅉㅊㅋㅌㅍㅎ")

func choseongString(_ text: String) -> String {
    var out = ""
    for scalar in text.unicodeScalars {
        let v = scalar.value
        if v >= 0xAC00 && v <= 0xD7A3 {
            out.append(choseongTable[Int((v - 0xAC00) / 588)])
        } else {
            out.unicodeScalars.append(scalar)
        }
    }
    return out
}
