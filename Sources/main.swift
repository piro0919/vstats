import AppKit

/// 窓を1枚出す。閉じたらアプリも終わる
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let main = MainWindowController()
    private var settingsWindow = SettingsWindowController()

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.mainMenu = makeMenu()
        // 言語を変えたら、文字を焼き込んでいる窓とメニューを作り直す
        NotificationCenter.default.addObserver(forName: .languageChanged, object: nil, queue: .main) {
            [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                NSApp.mainMenu = self.makeMenu()
                self.main.reloadLanguage()
                let wasVisible = self.settingsWindow.window?.isVisible ?? false
                self.settingsWindow.close()
                self.settingsWindow = SettingsWindowController()
                if wasVisible { self.settingsWindow.show() }
            }
        }
        NotificationCenter.default.addObserver(forName: .tokenChanged, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.main.model.tokenRemoved() }
        }
        main.show()
        Updater.shared.checkQuietly()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }

    @objc func openSettings() { settingsWindow.show() }

    @objc func reload() { main.model.reload() }

    private func makeMenu() -> NSMenu {
        let menu = NSMenu()
        let appItem = NSMenuItem()
        let app = NSMenu()
        app.addItem(withTitle: Strings.settings, action: #selector(openSettings), keyEquivalent: ",")
        app.addItem(.separator())
        app.addItem(withTitle: Strings.quit, action: #selector(NSApp.terminate), keyEquivalent: "q")
        appItem.submenu = app
        menu.addItem(appItem)

        let fileItem = NSMenuItem()
        let file = NSMenu(title: Strings.t("ファイル", "File"))
        file.addItem(withTitle: Strings.t("閉じる", "Close"), action: #selector(NSWindow.performClose), keyEquivalent: "w")
        fileItem.submenu = file
        menu.addItem(fileItem)

        // トークンを貼り付けられるように
        let editItem = NSMenuItem()
        let edit = NSMenu(title: Strings.t("編集", "Edit"))
        edit.addItem(withTitle: Strings.t("カット", "Cut"), action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        edit.addItem(withTitle: Strings.t("コピー", "Copy"), action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        edit.addItem(withTitle: Strings.t("ペースト", "Paste"), action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        edit.addItem(
            withTitle: Strings.t("すべてを選択", "Select All"), action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        editItem.submenu = edit
        menu.addItem(editItem)

        let viewItem = NSMenuItem()
        let view = NSMenu(title: Strings.t("表示", "View"))
        view.addItem(withTitle: Strings.reload, action: #selector(reload), keyEquivalent: "r")
        viewItem.submenu = view
        menu.addItem(viewItem)
        return menu
    }
}

if CommandLine.arguments.dropFirst().first == "--selftest" {
    exit(MainActor.assumeIsolated { SelfTest.run() })
}

/// 窓に出すのと同じ一覧を文字で書き出す。トークンは環境変数 VSTATS_TOKEN か、キーチェーンのもの
if CommandLine.arguments.dropFirst().first == "--dump" {
    guard let token = Keychain.effectiveToken else {
        FileHandle.standardError.write(Data("no token\n".utf8))
        exit(1)
    }
    let period = Period.chosen
    let done = DispatchSemaphore(value: 0)
    Task.detached {
        do {
            let client = VercelClient(token: token)
            let now = Date()
            let rows = try await concurrentMap(try await client.projects(), limit: 8) { project in
                Row(
                    project: project,
                    visitors: try await client.visitors(project, in: period.current(now: now)),
                    previous: try await client.visitors(project, in: period.previous(now: now)))
            }
            for row in Row.sorted(rows) {
                print("\(row.project.teamSlug)/\(row.project.name)\t\(row.visitors)\t\(row.delta)")
            }
        } catch {
            print("error: \(error)")
        }
        done.signal()
    }
    done.wait()
    exit(0)
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.regular)
app.run()
