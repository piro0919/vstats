import Foundation

/// 数字と時刻の書き方。桁区切りや時刻の形は地域に合わせて OS の書式に任せる
enum Format {
    static func number(_ value: Int, locale: Locale = Strings.locale) -> String {
        value.formatted(.number.locale(locale))
    }

    /// 数字を取った時刻。今日なら時刻だけ、それより前なら日付も付ける
    static func fetchedAt(
        _ date: Date, now: Date = Date(), calendar: Calendar = .current, locale: Locale = Strings.locale
    ) -> String {
        let style = Date.FormatStyle(locale: locale, calendar: calendar, timeZone: calendar.timeZone)
        if calendar.isDate(date, inSameDayAs: now) {
            return date.formatted(style.hour().minute())
        }
        return date.formatted(style.month().day().hour().minute())
    }
}
