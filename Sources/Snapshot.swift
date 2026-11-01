import Foundation

/// 前回取った一覧。開くたびに取り直さず、前回から時間がたったときだけ取り直す。
/// 訪問者数とプロジェクトの名前だけで、トークンは入れない
struct Snapshot: Codable, Equatable {
    let fetchedAt: Date
    let rows: [Row]
    /// 取り方の版。取り方を変えたら上げ、更新した直後に前の版の取り方で取った数字を出し続けないようにする。
    /// 0.1.0 のものには無い。2 はドメインを付けたドメインの一覧から選び直すようにした版
    var format: Int? = Self.currentFormat

    static let currentFormat = 2

    /// これより前に取ったものは古いとみなし、開いたときに取り直す。
    /// 24時間の列が1時間単位で区切られるので、それより短く取り直しても数はほとんど変わらない
    static let lifetime: TimeInterval = 3600

    func isStale(now: Date = Date()) -> Bool {
        format != Self.currentFormat || now.timeIntervalSince(fetchedAt) >= Self.lifetime
    }

    private static var url: URL {
        URL.applicationSupportDirectory.appending(path: "VStats/snapshot.json")
    }

    static func load() -> Snapshot? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try? decoder.decode(Snapshot.self, from: data)
    }

    func save() {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        guard let data = try? encoder.encode(self) else { return }
        try? FileManager.default.createDirectory(
            at: Self.url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? data.write(to: Self.url, options: .atomic)
    }

    /// トークンを消したら、そのトークンで取った数字も消す
    static func remove() {
        try? FileManager.default.removeItem(at: url)
    }
}
