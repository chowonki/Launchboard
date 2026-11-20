//
//  LauncherStore.swift
//  Launchboard
//

import AppKit
import SwiftUI

// MARK: - 상태 저장소

@MainActor
final class LauncherStore: ObservableObject {
    @Published private(set) var apps: [String: AppInfo] = [:]
    @Published var layout: [LaunchItem] = []
    @Published private(set) var searchResults: [AppInfo] = []
    @Published var query = "" {
        didSet {
            guard query != oldValue else { return }
            let wasEmpty = oldValue.trimmingCharacters(in: .whitespaces).isEmpty
            updateSearchResults()
            searchSelection = 0
            scrollOffset = 0
            if isSearching {
                if wasEmpty { pageBeforeSearch = currentPage }
                currentPage = 0
            } else {
                currentPage = min(pageBeforeSearch, pageCount - 1)
            }
        }
    }
    @Published var searchSelection = 0
    @Published var currentPage = 0
    @Published var scrollOffset: CGFloat = 0
    @Published var metrics = GridMetrics()
    @Published var openFolderID: UUID?
    @Published var editing = false
    @Published var shown = false
    @Published var focusToken = 0

    // 메인 격자 드래그
    @Published var draggingID: String?
    @Published var dragLocation: CGPoint = .zero
    @Published var mergeTargetID: String?
    // 폴더 안 드래그
    @Published var folderDragPath: String?
    @Published var folderDragOutside = false

    var onLaunch: (() -> Void)?
    var onDismiss: (() -> Void)?

    private var pageBeforeSearch = 0
    private var iconCache: [String: NSImage] = [:]
    private var grabOffset: CGSize = .zero
    private var lastCursor: CGPoint = .zero
    private var mergeCandidateID: String?
    private var mergeTask: Task<Void, Never>?
    private var edgeTask: Task<Void, Never>?
    private var edgeDirection = 0
    private var lastWheelFlip = Date.distantPast
    private let layoutKey = "layout.v2"

    init() {
        loadLayout()
        reload()
    }

    var isSearching: Bool { !query.trimmingCharacters(in: .whitespaces).isEmpty }
    var wiggling: Bool { editing }
    /// 드래그 때문에 임시로 켜진 흔들림인지 (길게 눌러서 켠 경우 false)
    private var editingFromDrag = false

    var pageCount: Int {
        let n = isSearching ? searchResults.count : layout.count
        return max(1, (n + metrics.perPage - 1) / metrics.perPage)
    }

    var displayPageCount: Int { max(pageCount, currentPage + 1) }

    // MARK: 앱 목록

    func reload() {
        let discovered = Self.scanApplications()
        let modernSiri = Self.modernSiriPath(in: discovered)
        // An existing saved layout refers to the old bundle path. Preserve its page
        // position (and folder membership) instead of appending the new icon at the end.
        if let modernSiri {
            migrateLegacySiri(to: modernSiri)
        }
        let userHidden = hiddenAppPaths
        apps = discovered.filter { !userHidden.contains($0.key) }
        iconCache.removeAll()
        reconcile()
        updateSearchResults()
        if currentPage > pageCount - 1 { currentPage = pageCount - 1 }
    }

    private func migrateLegacySiri(to modern: String) {
        let old = ((modern as NSString).deletingLastPathComponent as NSString)
            .appendingPathComponent("Siri.app")
        guard old != modern else { return }

        var changed = false
        var seen = Set<String>()
        layout = layout.map { item in
            switch item {
            case .app(let path):
                let target = path == old ? modern : path
                if path != target { changed = true }
                if seen.insert(target).inserted { return .app(target) }
                changed = true
                return .app("")
            case .folder(var folder):
                let oldApps = folder.apps
                folder.apps = folder.apps.map { $0 == old ? modern : $0 }
                    .filter { seen.insert($0).inserted }
                if folder.apps != oldApps { changed = true }
                return .folder(folder)
            }
        }.filter {
            if case .app(let path) = $0 { return !path.isEmpty }
            return true
        }
        if changed { saveLayout() }

        // Retain the user's explicit decision to hide Siri after its bundle moved.
        var hidden = hiddenAppPaths
        if hidden.remove(old) != nil {
            hidden.insert(modern)
            UserDefaults.standard.set(Array(hidden), forKey: hiddenKey)
        }
    }

    static func scanApplications() -> [String: AppInfo] {
        let fm = FileManager.default
        let selfPath = Bundle.main.bundleURL.resolvingSymlinksInPath().path
        let home = fm.homeDirectoryForCurrentUser.path
        var result: [String: AppInfo] = [:]

        func scan(_ dir: String, depth: Int) {
            guard let names = try? fm.contentsOfDirectory(atPath: dir) else { return }
            for name in names where !name.hasPrefix(".") && name != "__MACOSX" {
                let full = (dir as NSString).appendingPathComponent(name)
                // Finder에서 숨김 처리된 항목(숨김 속성)은 Launchpad처럼 표시하지 않음
                if isHidden(full) { continue }
                if name.hasSuffix(".app") {
                    let resolved = URL(fileURLWithPath: full).resolvingSymlinksInPath().path
                    if resolved == selfPath || result[resolved] != nil || isHidden(resolved) { continue }
                    // Archive metadata can contain empty .app directories. Only list
                    // application bundles with an executable, not just an .app suffix.
                    guard let bundle = Bundle(path: resolved),
                          bundle.object(forInfoDictionaryKey: "CFBundlePackageType") as? String == "APPL",
                          let executable = bundle.executableURL,
                          fm.isExecutableFile(atPath: executable.path) else { continue }
                    var display = fm.displayName(atPath: full)
                    if display.hasSuffix(".app") { display = String(display.dropLast(4)) }
                    let source: AppSource
                    if full.hasPrefix("/System/Applications/Utilities") {
                        source = .utility
                    } else if full.hasPrefix("/System/Applications") {
                        source = .system
                    } else {
                        source = .user
                    }
                    let deletable = source == .user && !resolved.hasPrefix("/System")
                    result[resolved] = AppInfo(path: resolved, name: display,
                                               fileName: String(name.dropLast(4)), source: source,
                                               deletable: deletable)
                } else if depth < 2 {
                    var isDir: ObjCBool = false
                    if fm.fileExists(atPath: full, isDirectory: &isDir), isDir.boolValue {
                        scan(full, depth: depth + 1)
                    }
                }
            }
        }

        for root in ["/System/Applications", "/Applications", home + "/Applications"] {
            scan(root, depth: 0)
        }
        return removingSameNameTwins(removingDuplicates(result))
    }

    /// Tahoe can ship Siri.app and Siri AI.app side by side, both displayed as "Siri".
    /// The legacy path must not steal the icon/launch action from the modern Siri app.
    /// Only prefer the new bundle if the actual app was discovered on this Mac.
    private static func modernSiriPath(in apps: [String: AppInfo]) -> String? {
        apps.values.first { app in
            guard app.source == .system,
                  app.path == "/System/Applications/Siri AI.app",
                  let bundle = Bundle(path: app.path),
                  bundle.bundleIdentifier == "com.apple.campo",
                  let executable = bundle.executableURL else { return false }
            return FileManager.default.isExecutableFile(atPath: executable.path)
        }?.path
    }

    private static func isLegacySiri(_ app: AppInfo, replacingWith modern: String) -> Bool {
        guard app.source == .system,
              app.fileName.caseInsensitiveCompare("Siri") == .orderedSame else { return false }
        // Do not override similarly named third-party apps in /Applications.
        return (app.path as NSString).deletingLastPathComponent
            == (modern as NSString).deletingLastPathComponent
    }

    /// 같은 폴더에 같은 표시 이름을 갖는 앱이 둘 이상이면 실제 실행 대상에 맞는
    /// 번들을 우선합니다. 일반 앱은 이전처럼 파일 이름이 표시 이름과 일치하는 쪽을 유지합니다.
    private static func removingSameNameTwins(_ apps: [String: AppInfo]) -> [String: AppInfo] {
        let modernSiri = modernSiriPath(in: apps)
        var groups: [String: [AppInfo]] = [:]
        for app in apps.values {
            let dir = (app.path as NSString).deletingLastPathComponent
            groups[dir + "|" + app.name.lowercased(), default: []].append(app)
        }
        var result: [String: AppInfo] = [:]
        for group in groups.values {
            let candidates = group.filter { app in
                guard let modernSiri else { return true }
                return !isLegacySiri(app, replacingWith: modernSiri)
            }
            guard !candidates.isEmpty else { continue }
            let keep = candidates.first { $0.path == modernSiri }
                ?? candidates.first { $0.fileName.caseInsensitiveCompare($0.name) == .orderedSame }
                ?? candidates.min { ($0.fileName.count, $0.path) < ($1.fileName.count, $1.path) }!
            result[keep.path] = keep
        }
        return result
    }

    /// Finder에서 보이지 않는 항목인지. macOS가 항목을 숨기는 방법을 모두 확인해요.
    ///  1) 이름이 '.'으로 시작   2) chflags hidden (UF_HIDDEN)
    ///  3) Finder 정보의 '보이지 않음' 비트 (SetFile -a V)   4) 시스템이 보고하는 숨김 값
    private static func isHidden(_ path: String) -> Bool {
        // A visible symlink can point into a hidden directory. Check ancestors too.
        var url = URL(fileURLWithPath: path).standardizedFileURL
        while url.path != "/" {
            if isHiddenItem(url.path) { return true }
            url.deleteLastPathComponent()
        }
        return false
    }

    private static func isHiddenItem(_ path: String) -> Bool {
        if (path as NSString).lastPathComponent.hasPrefix(".") { return true }

        // 2) UF_HIDDEN 플래그 (심볼릭 링크는 링크 자체와 대상 모두 확인)
        var st = stat()
        if lstat(path, &st) == 0, st.st_flags & UInt32(UF_HIDDEN) != 0 { return true }
        if stat(path, &st) == 0, st.st_flags & UInt32(UF_HIDDEN) != 0 { return true }

        // 3) com.apple.FinderInfo 의 kIsInvisible(0x4000) 비트: 9번째 바이트의 0x40
        var info = [UInt8](repeating: 0, count: 32)
        let n = getxattr(path, "com.apple.FinderInfo", &info, 32, 0, 0)
        if n >= 9, info[8] & 0x40 != 0 { return true }

        // 4) 시스템 판단
        let url = URL(fileURLWithPath: path)
        if let values = try? url.resourceValues(forKeys: [.isHiddenKey]), values.isHidden == true {
            return true
        }
        return false
    }

    /// 같은 앱(번들 ID가 같은 앱)이 여러 위치에 있으면 하나만 남깁니다.
    /// 시스템 앱 > 유틸리티 > 그 외 순으로, 같으면 경로가 짧은 쪽을 남겨요.
    private static func removingDuplicates(_ apps: [String: AppInfo]) -> [String: AppInfo] {
        func priority(_ app: AppInfo) -> Int {
            switch app.source {
            case .system: return 0
            case .utility: return 1
            case .user: return 2
            }
        }
        let modernSiri = modernSiriPath(in: apps)
        var result: [String: AppInfo] = [:]
        var chosen: [String: AppInfo] = [:]   // 번들 ID → 남길 앱
        for app in apps.values {
            guard let bundleID = Bundle(path: app.path)?.bundleIdentifier else {
                result[app.path] = app
                continue
            }
            if let current = chosen[bundleID] {
                // When both Siri bundles share an identifier, the usual shortest-path
                // tie-breaker would discard Siri AI before the visible-name check.
                let isModernSiri = app.path == modernSiri
                let wasModernSiri = current.path == modernSiri
                let better = isModernSiri != wasModernSiri
                    ? isModernSiri
                    : (priority(app), app.path.count, app.path) < (priority(current), current.path.count, current.path)
                if better { chosen[bundleID] = app }
            } else {
                chosen[bundleID] = app
            }
        }
        for app in chosen.values { result[app.path] = app }
        return result
    }

    private static let systemOrder = [
        "App Store", "Safari", "Mail", "Messages", "FaceTime", "Phone", "Maps", "Photos",
        "Contacts", "Calendar", "Reminders", "Notes", "Freeform", "Music", "Podcasts", "TV",
        "News", "Books", "Stocks", "Weather", "Clock", "Home", "Find My", "Photo Booth",
        "Preview", "Journal", "Passwords", "Games", "iPhone Mirroring", "System Settings",
    ]

    private func byName(_ a: AppInfo, _ b: AppInfo) -> Bool {
        a.name.localizedStandardCompare(b.name) == .orderedAscending
    }

    /// 처음 실행 시 Launchpad 기본 배치와 비슷하게: Apple 앱 → '기타' 폴더(유틸리티) → 나머지 앱
    private func defaultLayout() -> [LaunchItem] {
        let all = Array(apps.values)
        func rank(_ a: AppInfo) -> Int { Self.systemOrder.firstIndex(of: a.fileName) ?? Int.max }
        let primary = all
            .filter { $0.source == .system || rank($0) != Int.max }
            .sorted { a, b in
                let ra = rank(a), rb = rank(b)
                if ra != rb { return ra < rb }
                return byName(a, b)
            }
        let utilities = all.filter { $0.source == .utility }.sorted(by: byName)
        let others = all.filter { $0.source == .user && rank($0) == Int.max }.sorted(by: byName)

        var items = primary.map { LaunchItem.app($0.path) }
        if !utilities.isEmpty {
            items.append(.folder(Folder(name: "기타", apps: utilities.map { $0.path })))
        }
        items.append(contentsOf: others.map { LaunchItem.app($0.path) })
        return items
    }

    private func reconcile() {
        if layout.isEmpty {
            layout = defaultLayout()
            saveLayout()
            return
        }
        var seen = Set<String>()
        var newLayout: [LaunchItem] = []
        for item in layout {
            switch item {
            case .app(let path):
                if apps[path] != nil && seen.insert(path).inserted { newLayout.append(item) }
            case .folder(var folder):
                folder.apps = folder.apps.filter { apps[$0] != nil && seen.insert($0).inserted }
                if folder.apps.count >= 2 {
                    newLayout.append(.folder(folder))
                } else if let only = folder.apps.first {
                    newLayout.append(.app(only))
                }
            }
        }
        let newcomers = apps.values.filter { !seen.contains($0.path) }.sorted(by: byName)
        newLayout.append(contentsOf: newcomers.map { LaunchItem.app($0.path) })
        if newLayout != layout {
            layout = newLayout
            saveLayout()
        }
    }

    private func loadLayout() {
        guard let data = UserDefaults.standard.data(forKey: layoutKey),
              let items = try? JSONDecoder().decode([LaunchItem].self, from: data) else { return }
        layout = items
    }

    func saveLayout() {
        if let data = try? JSONEncoder().encode(layout) {
            UserDefaults.standard.set(data, forKey: layoutKey)
        }
    }

    // MARK: 조회

    func icon(for path: String) -> NSImage {
        if let cached = iconCache[path] { return cached }
        let image = NSWorkspace.shared.icon(forFile: path)
        iconCache[path] = image
        return image
    }

    func folder(_ id: UUID) -> Folder? {
        for case .folder(let f) in layout where f.id == id { return f }
        return nil
    }

    var folders: [Folder] {
        layout.compactMap { item -> Folder? in
            if case .folder(let f) = item { return f }
            return nil
        }
    }

    func displayName(_ item: LaunchItem) -> String {
        switch item {
        case .app(let path): return apps[path]?.name ?? ""
        case .folder(let folder): return folder.name
        }
    }

    func position(for entry: GridEntry) -> CGPoint {
        if entry.item.id == draggingID { return dragLocation }
        return metrics.center(index: entry.index, currentPage: currentPage, offset: scrollOffset)
    }

    /// 현재 페이지와 양옆 페이지만 그립니다
    func visibleGridEntries() -> [GridEntry] {
        let per = metrics.perPage
        let lo = max(0, (currentPage - 1) * per)
        let hi = min(layout.count, (currentPage + 2) * per)
        var result: [GridEntry] = []
        if lo < hi {
            for i in lo..<hi { result.append(GridEntry(index: i, item: layout[i])) }
        }
        if let d = draggingID, let di = layout.firstIndex(where: { $0.id == d }), di < lo || di >= hi {
            result.append(GridEntry(index: di, item: layout[di]))
        }
        return result
    }

    func visibleSearchEntries() -> [SearchEntry] {
        let per = metrics.perPage
        let lo = max(0, (currentPage - 1) * per)
        let hi = min(searchResults.count, (currentPage + 2) * per)
        guard lo < hi else { return [] }
        return (lo..<hi).map { SearchEntry(index: $0, app: searchResults[$0]) }
    }

    private func updateSearchResults() {
        let q = query.trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty else { searchResults = []; return }
        let lowered = q.lowercased()
        let matches = apps.values.filter { app in
            app.name.localizedCaseInsensitiveContains(q) || choseongString(app.name).contains(q)
        }
        searchResults = matches.sorted { a, b in
            let ap = a.name.lowercased().hasPrefix(lowered) || choseongString(a.name).hasPrefix(q)
            let bp = b.name.lowercased().hasPrefix(lowered) || choseongString(b.name).hasPrefix(q)
            if ap != bp { return ap }
            return a.name.localizedStandardCompare(b.name) == .orderedAscending
        }
    }

    // MARK: 실행 / 열기

    func launch(_ path: String) {
        // Launchboard closes without restoring focus to the previous app.
        // Otherwise its delayed fade-out can push Siri behind another window.
        onLaunch?()

        // A click queued before reload may still carry the legacy Siri path.
        let targetPath = path == "/System/Applications/Siri.app"
            ? Self.modernSiriPath(in: apps) ?? path
            : path
        let url = URL(fileURLWithPath: targetPath)
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true
        configuration.hides = false
        // Respect the selected bundle's actual path even when two Siri apps
        // share a bundle identifier or one is already running.
        configuration.allowsRunningApplicationSubstitution = false
        NSWorkspace.shared.openApplication(at: url, configuration: configuration) { app, _ in
            guard let app else { return }
            DispatchQueue.main.async {
                if app.isHidden { _ = app.unhide() }
                _ = app.activate(options: [.activateAllWindows])
            }
        }
    }

    func activate(_ item: LaunchItem) {
        switch item {
        case .app(let path):
            // Launchpad처럼 흔들림 모드에서는 앱을 클릭해도 실행하지 않음
            if !editing { launch(path) }
        case .folder(let folder):
            openFolder(folder.id)
        }
    }

    /// 폴더 안 앱 클릭
    func activateInFolder(_ path: String) {
        if !editing { launch(path) }
    }

    /// 아이콘을 길게 눌러 흔들림 모드 시작
    func enterEditing() {
        guard !editing else { return }
        NSHapticFeedbackManager.defaultPerformer.perform(.levelChange, performanceTime: .now)
        editingFromDrag = false
        withAnimation(.easeOut(duration: 0.15)) { editing = true }
    }

    private func beginDragEditing() {
        if !editing { editingFromDrag = true }
        editing = true
    }

    private func endDragEditing() {
        if editingFromDrag && !Config.dragKeepsEditing {
            editingFromDrag = false
            withAnimation(.easeOut(duration: 0.2)) { editing = false }
        }
    }

    func launchSelection() {
        guard searchSelection < searchResults.count else { return }
        launch(searchResults[searchSelection].path)
    }

    func openFolder(_ id: UUID) {
        withAnimation(.spring(response: 0.32, dampingFraction: 0.86)) { openFolderID = id }
    }

    func closeFolder() {
        withAnimation(.spring(response: 0.3, dampingFraction: 0.9)) { openFolderID = nil }
        focusToken += 1
    }

    func backgroundClicked() {
        if editing {
            withAnimation { editing = false }
        } else {
            onDismiss?()
        }
    }

    func prepareForShow() {
        query = ""
        openFolderID = nil
        editing = false
        draggingID = nil
        folderDragPath = nil
        scrollOffset = 0
        reload()
        focusToken += 1
    }

    /// Esc. 처리했으면 true, 창을 닫아야 하면 false
    func handleEscape() -> Bool {
        if draggingID != nil || folderDragPath != nil { return true }
        if openFolderID != nil { closeFolder(); return true }
        if editing { withAnimation { editing = false }; return true }
        if !query.isEmpty { query = ""; return true }
        return false
    }

    /// 방향키. 처리했으면 true
    func arrow(dx: Int, dy: Int) -> Bool {
        if openFolderID != nil { return false }
        if isSearching {
            guard !searchResults.isEmpty else { return true }
            let next = searchSelection + dx + dy * metrics.cols
            searchSelection = min(max(0, next), searchResults.count - 1)
            let page = searchSelection / metrics.perPage
            if page != currentPage { goToPage(page) }
            return true
        }
        if dx != 0 { goToPage(currentPage + dx); return true }
        return false
    }

    // MARK: 페이지

    func goToPage(_ page: Int) {
        let maxPage = draggingID != nil ? pageCount : pageCount - 1
        let target = min(max(0, page), maxPage)
        withAnimation(.spring(response: 0.38, dampingFraction: 0.86)) {
            currentPage = target
            scrollOffset = 0
        }
    }

    // MARK: 마우스로 빈 곳을 끌어서 페이지 넘기기

    func mouseSwipeChanged(_ translation: CGFloat) {
        guard openFolderID == nil, draggingID == nil else { return }
        let atStart = currentPage == 0 && translation > 0
        let atEnd = currentPage >= pageCount - 1 && translation < 0
        scrollOffset = (atStart || atEnd) ? translation * 0.3 : translation
    }

    func mouseSwipeEnded(_ translation: CGFloat, predicted: CGFloat) {
        guard openFolderID == nil, draggingID == nil else { return }
        let threshold = metrics.size.width * 0.12
        // 짧게 휙 넘긴 경우도 인정 (관성 예측값 사용)
        let decisive = abs(predicted) > abs(translation) * 1.5 ? predicted : translation
        if decisive < -threshold {
            goToPage(currentPage + 1)
        } else if decisive > threshold {
            goToPage(currentPage - 1)
        } else {
            goToPage(currentPage)
        }
    }

    // MARK: 목록에서 숨기기 (파일은 그대로 둠)

    private let hiddenKey = "hiddenApps"

    var hiddenAppPaths: Set<String> {
        Set((UserDefaults.standard.stringArray(forKey: hiddenKey) ?? []).map {
            URL(fileURLWithPath: $0).resolvingSymlinksInPath().standardizedFileURL.path
        })
    }

    func hideFromList(_ path: String) {
        let resolved = URL(fileURLWithPath: path).resolvingSymlinksInPath().standardizedFileURL.path
        var set = hiddenAppPaths
        set.insert(resolved)
        UserDefaults.standard.set(Array(set), forKey: hiddenKey)
        removeFromLayout(resolved)
    }

    func showAllHiddenApps() {
        UserDefaults.standard.removeObject(forKey: hiddenKey)
        reload()
    }

    // MARK: 앱 삭제 (휴지통으로 이동)

    func isDeletable(_ path: String) -> Bool { apps[path]?.deletable ?? false }

    func requestDelete(_ path: String) {
        guard let app = apps[path], app.deletable else { return }
        let url = URL(fileURLWithPath: path)

        let confirm = NSAlert()
        confirm.messageText = "‘\(app.name)’을(를) 삭제하겠습니까?"
        confirm.informativeText = "앱이 휴지통으로 이동됩니다."
        confirm.icon = icon(for: path)
        confirm.addButton(withTitle: "삭제")
        confirm.addButton(withTitle: "취소")
        confirm.buttons[0].hasDestructiveAction = true
        guard confirm.runModal() == .alertFirstButtonReturn else { return }

        let running = NSWorkspace.shared.runningApplications.filter {
            $0.bundleURL?.resolvingSymlinksInPath().path == path
        }
        Task { [weak self] in
            guard let self else { return }
            if !running.isEmpty {
                let ask = NSAlert()
                ask.messageText = "‘\(app.name)’이(가) 실행 중입니다."
                ask.informativeText = "앱을 종료한 뒤 삭제할까요?"
                ask.addButton(withTitle: "종료 후 삭제")
                ask.addButton(withTitle: "취소")
                guard ask.runModal() == .alertFirstButtonReturn else { return }
                running.forEach { $0.terminate() }
                for _ in 0..<50 where running.contains(where: { !$0.isTerminated }) {
                    try? await Task.sleep(nanoseconds: 100_000_000)
                }
                if running.contains(where: { !$0.isTerminated }) {
                    self.showDeleteError(app.name, reason: "앱이 종료되지 않았어요. 직접 종료한 뒤 다시 시도해 주세요.")
                    return
                }
            }
            if self.moveToTrash(url) {
                self.removeFromLayout(path)
            } else {
                self.showDeleteError(app.name, reason: "권한이 없거나 시스템이 보호하는 앱일 수 있어요.")
            }
        }
    }

    private func moveToTrash(_ url: URL) -> Bool {
        // 1) 일반 권한으로 시도
        if (try? FileManager.default.trashItem(at: url, resultingItemURL: nil)) != nil { return true }
        // 2) 관리자 권한이 필요한 앱(App Store 앱 등)은 Finder에게 맡깁니다 — Finder가 암호를 물어봐요
        let escaped = url.path
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
        let source = "tell application \"Finder\" to delete (POSIX file \"\(escaped)\" as alias)"
        var error: NSDictionary?
        NSAppleScript(source: source)?.executeAndReturnError(&error)
        return !FileManager.default.fileExists(atPath: url.path)
    }

    private func removeFromLayout(_ path: String) {
        withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
            var newLayout: [LaunchItem] = []
            for item in layout {
                switch item {
                case .app(let p):
                    if p != path { newLayout.append(item) }
                case .folder(var f):
                    f.apps.removeAll { $0 == path }
                    if f.apps.count >= 2 {
                        newLayout.append(.folder(f))
                    } else if let only = f.apps.first {
                        newLayout.append(.app(only))
                        if openFolderID == f.id { openFolderID = nil }
                    }
                }
            }
            layout = newLayout
        }
        iconCache[path] = nil
        saveLayout()
        reload()
    }

    private func showDeleteError(_ name: String, reason: String) {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "‘\(name)’을(를) 삭제할 수 없습니다."
        alert.informativeText = reason
        alert.runModal()
    }

    func handleScroll(_ event: NSEvent) {
        guard openFolderID == nil, shown else { return }
        if event.momentumPhase != [] { return }
        let dx = event.scrollingDeltaX
        let dy = event.scrollingDeltaY
        let delta = abs(dx) >= abs(dy) ? dx : dy

        if event.hasPreciseScrollingDeltas && event.phase != [] {
            // 트랙패드: 손가락을 따라 움직이다가 놓으면 페이지에 맞춤
            if event.phase.contains(.began) || event.phase.contains(.changed) {
                let atStart = currentPage == 0 && scrollOffset + delta > 0
                let atEnd = currentPage >= pageCount - 1 && scrollOffset + delta < 0
                scrollOffset += (atStart || atEnd) ? delta * 0.3 : delta
            }
            if event.phase.contains(.ended) || event.phase.contains(.cancelled) {
                let threshold = metrics.size.width * 0.1
                if scrollOffset < -threshold {
                    goToPage(currentPage + 1)
                } else if scrollOffset > threshold {
                    goToPage(currentPage - 1)
                } else {
                    goToPage(currentPage)
                }
            }
        } else {
            // 마우스 휠: 한 번에 한 페이지
            guard abs(delta) > 0.5, Date().timeIntervalSince(lastWheelFlip) > 0.35 else { return }
            lastWheelFlip = Date()
            goToPage(currentPage + (delta < 0 ? 1 : -1))
        }
    }

    // MARK: 메인 격자 드래그

    func dragChanged(id: String, location: CGPoint, start: CGPoint) {
        if draggingID == nil {
            guard let idx = layout.firstIndex(where: { $0.id == id }) else { return }
            let c = metrics.center(index: idx, currentPage: currentPage, offset: scrollOffset)
            grabOffset = CGSize(width: start.x - c.x, height: start.y - c.y)
            dragLocation = c
            withAnimation(.easeOut(duration: 0.15)) {
                draggingID = id
                beginDragEditing()
            }
        }
        lastCursor = location
        dragLocation = CGPoint(x: location.x - grabOffset.width, y: location.y - grabOffset.height)
        updateDragTarget()
    }

    private func updateDragTarget() {
        guard let id = draggingID, let from = layout.firstIndex(where: { $0.id == id }) else { return }
        let m = metrics

        // 화면 가장자리에 머물면 페이지 넘김
        let edge: CGFloat = 40
        let dir: Int
        if lastCursor.x < edge { dir = -1 } else if lastCursor.x > m.size.width - edge { dir = 1 } else { dir = 0 }
        if dir != edgeDirection {
            edgeDirection = dir
            edgeTask?.cancel()
            edgeTask = nil
            if dir != 0 {
                edgeTask = Task { [weak self] in
                    while !Task.isCancelled {
                        try? await Task.sleep(nanoseconds: 650_000_000)
                        guard !Task.isCancelled, let self else { return }
                        self.goToPage(self.currentPage + dir)
                        self.updateDragTarget()
                    }
                }
            }
        }
        if dir != 0 { clearMerge(); return }

        let probe = CGPoint(x: dragLocation.x, y: dragLocation.y - labelOffset)
        guard let slot = m.slot(at: probe), !layout.isEmpty else { clearMerge(); return }
        let target = min(currentPage * m.perPage + slot, layout.count - 1)
        guard target != from else { clearMerge(); return }

        // 아이콘 한가운데 위 → 폴더 만들기 후보
        let tc = m.center(index: target, currentPage: currentPage, offset: 0)
        let dist = hypot(probe.x - tc.x, probe.y - (tc.y - labelOffset))
        var draggingApp = false
        if case .app = layout[from] { draggingApp = true }
        if draggingApp && dist < m.iconSize * 0.42 && target / m.perPage == currentPage {
            let tid = layout[target].id
            if mergeCandidateID != tid {
                clearMerge()
                mergeCandidateID = tid
                mergeTask = Task { [weak self] in
                    try? await Task.sleep(nanoseconds: 350_000_000)
                    guard !Task.isCancelled, let self, self.mergeCandidateID == tid else { return }
                    withAnimation(.easeOut(duration: 0.15)) { self.mergeTargetID = tid }
                }
            }
            return
        }

        // 아이콘 사이 → 자리 바꾸기
        clearMerge()
        withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) {
            layout.move(fromOffsets: IndexSet(integer: from), toOffset: target > from ? target + 1 : target)
        }
    }

    private func clearMerge() {
        mergeTask?.cancel()
        mergeTask = nil
        mergeCandidateID = nil
        if mergeTargetID != nil {
            withAnimation(.easeOut(duration: 0.15)) { mergeTargetID = nil }
        }
    }

    func dragEnded() {
        edgeTask?.cancel()
        edgeTask = nil
        edgeDirection = 0
        mergeTask?.cancel()
        mergeTask = nil
        if let id = draggingID, let target = mergeTargetID {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) { merge(id, into: target) }
        }
        mergeTargetID = nil
        mergeCandidateID = nil
        withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) { draggingID = nil }
        endDragEditing()
        if currentPage > pageCount - 1 { goToPage(pageCount - 1) }
        saveLayout()
    }

    private func merge(_ dragID: String, into targetID: String) {
        guard let from = layout.firstIndex(where: { $0.id == dragID }),
              case .app(let path) = layout[from],
              let ti = layout.firstIndex(where: { $0.id == targetID }), ti != from else { return }
        switch layout[ti] {
        case .folder(var folder):
            folder.apps.append(path)
            layout[ti] = .folder(folder)
        case .app(let other):
            let name = categoryName(forAppAt: other) ?? categoryName(forAppAt: path) ?? "폴더"
            layout[ti] = .folder(Folder(name: name, apps: [other, path]))
        }
        layout.remove(at: from)
    }

    // MARK: 폴더 안 드래그

    func folderDragChanged(folderID: UUID, path: String, location: CGPoint, start: CGPoint) {
        guard var f = folder(folderID) else { return }
        let g = FolderGeometry(count: f.apps.count, metrics: metrics)
        if folderDragPath == nil {
            guard let idx = f.apps.firstIndex(of: path) else { return }
            let c = g.center(idx)
            grabOffset = CGSize(width: start.x - c.x, height: start.y - c.y)
            dragLocation = c
            withAnimation(.easeOut(duration: 0.15)) {
                folderDragPath = path
                beginDragEditing()
            }
        }
        dragLocation = CGPoint(x: location.x - grabOffset.width, y: location.y - grabOffset.height)

        let outside = !g.rect.insetBy(dx: -8, dy: -8).contains(location)
        if outside != folderDragOutside {
            withAnimation(.easeOut(duration: 0.15)) { folderDragOutside = outside }
        }
        let probe = CGPoint(x: dragLocation.x, y: dragLocation.y - labelOffset)
        guard !outside, let slot = g.slot(at: probe), let from = f.apps.firstIndex(of: path) else { return }
        let target = min(slot, f.apps.count - 1)
        guard target != from else { return }
        f.apps.move(fromOffsets: IndexSet(integer: from), toOffset: target > from ? target + 1 : target)
        withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) { replaceFolder(f) }
    }

    func folderDragEnded(folderID: UUID) {
        guard let path = folderDragPath else { return }
        let takeOut = folderDragOutside
        withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) {
            folderDragPath = nil
            folderDragOutside = false
        }
        endDragEditing()
        if takeOut {
            removeFromFolder(path, folderID: folderID)
            closeFolder()
        }
        saveLayout()
    }

    // MARK: 폴더 편집

    private func replaceFolder(_ folder: Folder) {
        let key = "folder:" + folder.id.uuidString
        guard let i = layout.firstIndex(where: { $0.id == key }) else { return }
        layout[i] = .folder(folder)
    }

    func createFolder(with path: String) {
        guard let i = layout.firstIndex(of: .app(path)) else { return }
        let name = categoryName(forAppAt: path) ?? "새 폴더"
        let folder = Folder(name: name, apps: [path])
        layout[i] = .folder(folder)
        saveLayout()
        openFolder(folder.id)
    }

    func addToFolder(_ path: String, folderID: UUID) {
        guard var f = folder(folderID) else { return }
        layout.removeAll { $0 == .app(path) }
        f.apps.append(path)
        replaceFolder(f)
        saveLayout()
    }

    func removeFromFolder(_ path: String, folderID: UUID) {
        let key = "folder:" + folderID.uuidString
        guard let i = layout.firstIndex(where: { $0.id == key }),
              case .folder(var folder) = layout[i] else { return }
        folder.apps.removeAll { $0 == path }
        var replacement: [LaunchItem] = []
        if folder.apps.count >= 2 {
            replacement.append(.folder(folder))
        } else {
            // Launchpad처럼 앱이 하나만 남으면 폴더를 없앱니다
            replacement.append(contentsOf: folder.apps.map { LaunchItem.app($0) })
            if openFolderID == folderID { openFolderID = nil }
        }
        replacement.append(.app(path))
        withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) {
            layout.replaceSubrange(i...i, with: replacement)
        }
        saveLayout()
    }

    func ungroup(_ id: UUID) {
        let key = "folder:" + id.uuidString
        guard let i = layout.firstIndex(where: { $0.id == key }),
              case .folder(let folder) = layout[i] else { return }
        withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) {
            layout.replaceSubrange(i...i, with: folder.apps.map { LaunchItem.app($0) })
        }
        if openFolderID == id { openFolderID = nil }
        saveLayout()
    }

    func renameFolder(_ id: UUID, to name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, var f = folder(id), f.name != trimmed else { return }
        f.name = trimmed
        replaceFolder(f)
        saveLayout()
    }

    func sortByName() {
        withAnimation(.spring(response: 0.4, dampingFraction: 0.85)) {
            layout.sort { displayName($0).localizedStandardCompare(displayName($1)) == .orderedAscending }
        }
        saveLayout()
    }

    func resetLayout() {
        withAnimation(.spring(response: 0.4, dampingFraction: 0.85)) {
            layout = defaultLayout()
            currentPage = 0
        }
        openFolderID = nil
        saveLayout()
    }
}
