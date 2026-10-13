import Foundation

/// 数字を数える期間。今に向かって動く窓で、Vercel の Analytics 画面の期間の選び方に合わせる。
/// API は時刻を1時間単位に丸めるので、画面の数字とは数件ずれることがある
enum Period: String, CaseIterable, Identifiable {
    case day, week, month, quarter

    var id: String { rawValue }

    private static let key = "period"

    static var chosen: Period {
        get { UserDefaults.standard.string(forKey: key).flatMap(Period.init(rawValue:)) ?? .week }
        set { UserDefaults.standard.set(newValue.rawValue, forKey: key) }
    }

    var seconds: TimeInterval {
        switch self {
        case .day: 86_400
        case .week: 7 * 86_400
        case .month: 30 * 86_400
        case .quarter: 90 * 86_400
        }
    }

    var label: String {
        switch self {
        case .day: Strings.t("過去24時間", "Last 24 Hours")
        case .week: Strings.t("過去7日間", "Last 7 Days")
        case .month: Strings.t("過去30日間", "Last 30 Days")
        case .quarter: Strings.t("過去90日間", "Last 90 Days")
        }
    }

    /// 今の窓
    func current(now: Date) -> DateInterval {
        DateInterval(start: now.addingTimeInterval(-seconds), end: now)
    }

    /// 差を取る相手。今の窓のすぐ前の、同じ長さの窓
    func previous(now: Date) -> DateInterval {
        DateInterval(start: now.addingTimeInterval(-2 * seconds), end: now.addingTimeInterval(-seconds))
    }
}
