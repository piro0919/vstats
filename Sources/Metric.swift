import Foundation

/// 数える値。Vercel の Analytics 画面の Visitors と Page Views。
/// Bounce Rate は観測の API に項目が無いので置いていない（画面は内部用の API から取っている）
enum Metric: String, CaseIterable, Identifiable, Codable, Sendable {
    case visitors, pageViews

    var id: String { rawValue }

    private static let key = "metric"

    /// 右上の切り替えで選んでいる値
    static var chosen: Metric {
        get { UserDefaults.standard.string(forKey: key).flatMap(Metric.init(rawValue:)) ?? .visitors }
        set { UserDefaults.standard.set(newValue.rawValue, forKey: key) }
    }

    /// Vercel の画面と同じ英語の名前。日本語の Vercel の画面は無いので訳さない
    var label: String {
        switch self {
        case .visitors: "Visitors"
        case .pageViews: "Page Views"
        }
    }

    /// 観測の API に渡す集計。どちらもページビューを数える指標で、訪問者は visitorId の重なりを除いて数える
    var query: MetricsQuery.Metric {
        switch self {
        case .visitors:
            .init(metric: "vercel.analytics.page_view.count", aggregation: "unique", dimensions: ["visitorId"])
        case .pageViews:
            .init(metric: "vercel.analytics.page_view.count", aggregation: "count", dimensions: nil)
        }
    }
}
