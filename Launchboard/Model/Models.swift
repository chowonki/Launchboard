//
//  Models.swift
//  Launchboard
//

import Foundation

// MARK: - 모델

enum AppSource { case system, utility, user }

struct AppInfo: Identifiable, Hashable {
    let path: String
    let name: String
    let fileName: String
    let source: AppSource
    /// /Applications, ~/Applications 에 있고 시스템 볼륨 앱이 아니면 삭제 가능
    let deletable: Bool
    var id: String { path }
}

struct Folder: Codable, Hashable, Identifiable {
    var id = UUID()
    var name: String
    var apps: [String]
}

enum LaunchItem: Codable, Hashable, Identifiable {
    case app(String)
    case folder(Folder)

    var id: String {
        switch self {
        case .app(let path): return "app:" + path
        case .folder(let folder): return "folder:" + folder.id.uuidString
        }
    }
}

struct GridEntry: Identifiable {
    let index: Int
    let item: LaunchItem
    var id: String { item.id }
}

struct SearchEntry: Identifiable {
    let index: Int
    let app: AppInfo
    var id: String { app.id }
}
