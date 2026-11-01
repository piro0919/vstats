import Foundation

/// 一覧の並べ方。名前の順か、ある期間の数の多い順。列の見出しを押して変える
enum Sort: Equatable, Sendable {
    case name
    case period(Period)

    private static let key = "sort"

    /// UserDefaults の `sort`。期間は Period の rawValue、名前は "name" で置く。既定は 7日
    static var saved: Sort {
        get {
            switch UserDefaults.standard.string(forKey: key) {
            case "name": .name
            case let raw?: Period(rawValue: raw).map(Sort.period) ?? .period(.week)
            case nil: .period(.week)
            }
        }
        set {
            switch newValue {
            case .name: UserDefaults.standard.set("name", forKey: key)
            case .period(let period): UserDefaults.standard.set(period.rawValue, forKey: key)
            }
        }
    }
}
