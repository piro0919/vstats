import Foundation

/// 数字を数える期間。区切り方は Vercel の Analytics 画面が裏で投げている問い合わせ
/// （/api/web-analytics/v2/overview）を写した。2026-10-13 に kk-web で、画面と同じ数になるのを確かめた
enum Period: String, CaseIterable, Identifiable, Codable, Sendable {
    case day, week, month, quarter

    var id: String { rawValue }

    private static let sortKey = "sort"

    /// 一覧をどの期間の数で並べるか。列の見出しを押して変える
    static var sorted: Period {
        get { UserDefaults.standard.string(forKey: sortKey).flatMap(Period.init(rawValue:)) ?? .week }
        set { UserDefaults.standard.set(newValue.rawValue, forKey: sortKey) }
    }

    var days: Int {
        switch self {
        case .day: 1
        case .week: 7
        case .month: 30
        case .quarter: 90
        }
    }

    /// Vercel の Analytics 画面の URL で期間を選ぶ値（`?period=7d`）。2026-10-13 に実物で確認
    var dashboardParameter: String {
        switch self {
        case .day: "24h"
        case .week: "7d"
        case .month: "30d"
        case .quarter: "90d"
        }
    }

    /// 列の見出し。Vercel の画面の「Last 24 Hours」などを短くしたもの。
    /// Vercel の画面にある 12 か月と 24 か月は、観測の API が 92 日前より古い時刻を聞けないので置いていない
    var label: String {
        switch self {
        case .day: Strings.t("24時間", "24 Hours")
        case .week: Strings.t("7日", "7 Days")
        case .month: Strings.t("30日", "30 Days")
        case .quarter: Strings.t("3か月", "3 Months")
        }
    }

    /// 今の窓。
    /// - 24時間: 今の時刻を1時間に切り上げ、そこから24時間
    /// - それ以外: 今の1時間の頭から N 日前までを、利用者の暦の日に広げる。今日の終わりまで入るので N+1 日になる
    func current(now: Date, calendar: Calendar = .current) -> DateInterval {
        let (from, to) = raw(now: now, calendar: calendar)
        let window = widen(from, to, calendar: calendar)
        guard self == .quarter else { return window }
        // 暦の3か月は 92 日を超えることがある。観測の API が聞ける一番古い区切りまでで切る。
        // 始まりは今から 92 日以内、長さも 92 日以内（終わりは今日の終わりなので、こちらのほうが効く）。
        // そのぶん Vercel の画面より少なく出る（2026-10-13 の kk-web で 1,326 に対して 1,292 だった）
        let bucket = TimeInterval(bucketSeconds(calendar: calendar, at: now))
        let oldest = max(now, window.end.addingTimeInterval(-3600)).addingTimeInterval(-92 * 86_400 + 3600)
        let start = max(
            window.start, Date(timeIntervalSince1970: (oldest.timeIntervalSince1970 / bucket).rounded(.up) * bucket))
        return DateInterval(start: start, end: window.end)
    }

    /// 前の期間と比べられるか。観測の API は 92 日前より古い時刻を聞けないので、3か月の前の期間は取れない
    var comparable: Bool { self != .quarter }

    /// 比べる相手の窓。広げる前の窓のすぐ前の同じ長さを、同じように広げる。
    /// 日単位の期間では今の窓と1日重なる（Vercel の画面がそう数えている）
    func previous(now: Date, calendar: Calendar = .current) -> DateInterval {
        let (from, to) = raw(now: now, calendar: calendar)
        return widen(from.addingTimeInterval(-to.timeIntervalSince(from)), from, calendar: calendar)
    }

    /// 問い合わせの区切りの長さ。日単位の期間は、利用者の暦の0時にそろう、なるべく長い区切りにする。
    /// 区切りが UTC の0時から数えられるので、日単位（86400）のままだと日本では9時間ずれて数が増える
    func bucketSeconds(calendar: Calendar = .current, at date: Date) -> Int {
        guard self != .day else { return 3600 }
        let offset = abs(calendar.timeZone.secondsFromGMT(for: date)) % 86_400
        return gcd(86_400, offset)
    }

    /// 3か月だけは日数ではなく暦の月で戻る。URL は `?period=90d` だが、画面の始まりは3か月前の同じ日（2026-10-13 に実物で確認）
    private func raw(now: Date, calendar: Calendar) -> (Date, Date) {
        let hour: TimeInterval = 3600
        let floor = Date(timeIntervalSince1970: (now.timeIntervalSince1970 / hour).rounded(.down) * hour)
        let to = floor.addingTimeInterval(hour)
        let from: Date
        switch self {
        case .day: from = to.addingTimeInterval(-86_400)
        case .quarter: from = calendar.date(byAdding: .month, value: -3, to: floor)!
        default: from = floor.addingTimeInterval(-Double(days) * 86_400)
        }
        return (from, to)
    }

    private func widen(_ from: Date, _ to: Date, calendar: Calendar) -> DateInterval {
        guard self != .day else { return DateInterval(start: from, end: to) }
        let start = calendar.startOfDay(for: from)
        let end = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: to.addingTimeInterval(-1)))!
        return DateInterval(start: start, end: end)
    }

    private func gcd(_ a: Int, _ b: Int) -> Int { b == 0 ? a : gcd(b, a % b) }
}
