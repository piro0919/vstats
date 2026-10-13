import Foundation

/// 画面の言語。既定はシステムに従い、日本語の環境なら日本語、それ以外は英語にする
enum Language: String, CaseIterable {
    case system, ja, en

    private static let key = "language"

    static var chosen: Language {
        get { UserDefaults.standard.string(forKey: key).flatMap(Language.init(rawValue:)) ?? .system }
        set {
            UserDefaults.standard.set(newValue.rawValue, forKey: key)
            NotificationCenter.default.post(name: .languageChanged, object: nil)
        }
    }

    static var resolved: Language {
        switch chosen {
        case .ja: return .ja
        case .en: return .en
        case .system: return (Locale.preferredLanguages.first ?? "en").hasPrefix("ja") ? .ja : .en
        }
    }

    var label: String {
        switch self {
        case .system: return Strings.t("システムに従う", "Follow system")
        case .ja: return "日本語"
        case .en: return "English"
        }
    }
}

extension Notification.Name {
    static let languageChanged = Notification.Name("vstats.languageChanged")
    static let tokenChanged = Notification.Name("vstats.tokenChanged")
}

/// 画面に出す文言。言語は設定で切り替えられるので、読むたびに選び直す
enum Strings {
    static var isJapanese: Bool { Language.resolved == .ja }

    static func t(_ ja: String, _ en: String) -> String { isJapanese ? ja : en }

    /// 数字の書式に使う地域。言語がシステムに従うなら OS の設定そのもの
    static var locale: Locale {
        let current = Locale.current
        let code = current.language.languageCode?.identifier
        switch Language.chosen {
        case .system: return current
        case .ja: return code == "ja" ? current : Locale(identifier: "ja_JP")
        case .en: return code == "en" ? current : Locale(identifier: "en_US")
        }
    }

    static var projects: String { t("プロジェクト", "Projects") }
    /// 見出しの下の灰色の1行。取り直すのは1時間ごとなので、いつの数字かを添える
    static func summary(projects: Int, fetchedAt: String) -> String {
        t("\(projects) 件 · \(fetchedAt) 時点", "\(projects) projects · as of \(fetchedAt)")
    }
    static var noProjects: String {
        t("Web Analytics が有効なプロジェクトはありません", "No projects with Web Analytics enabled")
    }
    static var loadFailed: String { t("読み込めませんでした", "Couldn't load") }
    static var retry: String { t("もう一度", "Try Again") }
    static var reload: String { t("再読み込み", "Reload") }

    static var tokenTitle: String { t("Vercel のトークン", "Vercel Token") }
    static var tokenPlaceholder: String { t("トークンを貼り付け", "Paste a token") }
    static var save: String { t("保存", "Save") }
    static var createToken: String { t("トークンを作成", "Create Token") }
    static var tokenRejected: String { t("このトークンは使えません", "This token was rejected") }
    static var token: String { t("トークン", "Token") }
    static var removeToken: String { t("削除", "Remove") }
    static var noToken: String { t("未設定", "Not set") }
    static var tokenSaved: String { t("設定済み", "Saved") }

    static var settings: String { t("設定…", "Settings…") }
    static var settingsTitle: String { t("設定", "Settings") }
    static var quit: String { t("VStats を終了", "Quit VStats") }
    static var language: String { t("言語", "Language") }
    static var checkForUpdates: String { t("アップデートを確認", "Check for Updates") }
}
