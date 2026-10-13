import Foundation

/// 数字の書き方。桁区切りは地域に合わせて OS の書式に任せる
enum Format {
    static func number(_ value: Int, locale: Locale = Strings.locale) -> String {
        value.formatted(.number.locale(locale))
    }

    /// 前の期間との差。人数で、符号を付ける。差が無ければ何も出さない
    static func delta(_ value: Int, locale: Locale = Strings.locale) -> String? {
        guard value != 0 else { return nil }
        let digits = number(abs(value), locale: locale)
        // マイナスは数学の記号にする。ハイフンだと細くて符号に見えない
        return value > 0 ? "+\(digits)" : "\u{2212}\(digits)"
    }
}
