import Foundation
import Security

/// Vercel のトークンの置き場。プロジェクトの削除までできる強さを持つので、ファイルや UserDefaults には置かない
enum Keychain {
    private static let service = "io.kkweb.vstats"
    private static let account = "vercel-token"

    private static var query: [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
    }

    static var token: String? {
        var item: CFTypeRef?
        var search = query
        search[kSecReturnData as String] = true
        search[kSecMatchLimit as String] = kSecMatchLimitOne
        guard SecItemCopyMatching(search as CFDictionary, &item) == errSecSuccess,
            let data = item as? Data
        else { return nil }
        return String(data: data, encoding: .utf8)
    }

    @discardableResult
    static func save(_ token: String) -> Bool {
        let data = Data(token.utf8)
        let status = SecItemUpdate(query as CFDictionary, [kSecValueData as String: data] as CFDictionary)
        if status == errSecSuccess { return true }
        guard status == errSecItemNotFound else { return false }
        var item = query
        item[kSecValueData as String] = data
        item[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        return SecItemAdd(item as CFDictionary, nil) == errSecSuccess
    }

    /// 窓とコマンドが使うトークン。環境変数 VSTATS_TOKEN があればそちらを先に使う。
    /// 手元で確かめるとき、キーチェーンに書かずに済ませるため
    static var effectiveToken: String? {
        ProcessInfo.processInfo.environment["VSTATS_TOKEN"] ?? token
    }

    static func remove() {
        SecItemDelete(query as CFDictionary)
    }
}
