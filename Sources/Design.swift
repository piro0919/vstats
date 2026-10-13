import SwiftUI

// 見た目の決まり。手本は Vercel のプロジェクト一覧と Analytics の画面。
// 寸法・字の大きさ・角はここにだけ書き、ほかのファイルでは Design の値と部品を使う。
// 外れた書き方は Tools/design-rules.sh が落とす（CI でも回る）。
//
// - 字: 見出しは 24pt の太字。数字は等幅の数字（monospacedDigit）
// - 角: 枠は 10pt の角丸に、区切りの色の細い線
// - 余白: 窓の縁から 28pt、見出しと枠の間は 20pt、行の左右は 16pt
// - 行: 高さ 56pt。押せる行は、乗ったときだけ薄く塗る
// - 列: 4つの期間の数を右寄せで並べる。並べ替えに使っている列だけ濃く、ほかは灰色
// - 率: 数の下に小さく前の期間からの増減（Vercel の画面と同じ %）。増えたら緑、減ったら赤、出せなければ空ける
// - 推移: 名前と数の間に、並べている期間の小さな折れ線。緑の線だけで、目盛りも軸も無い
enum Design {
    static let pagePadding: CGFloat = 28
    static let sectionSpacing: CGFloat = 20
    static let cornerRadius: CGFloat = 10
    static let rowHeight: CGFloat = 56
    static let rowPadding: CGFloat = 16
    static let messagePadding: CGFloat = 36
    static let columnWidth: CGFloat = 72
    static let columnSpacing: CGFloat = 12
    static let headerHeight: CGFloat = 36
    static let sparklineWidth: CGFloat = 96
    static let sparklineHeight: CGFloat = 24
    static let sparklineLine: CGFloat = 1.5
    static let formWidth: CGFloat = 480
    static let windowMinWidth: CGFloat = 560
    static let windowMinHeight: CGFloat = 420

    static let titleFont = Font.system(size: 24, weight: .bold)
    static let numberFont = Font.system(size: 17, weight: .semibold).monospacedDigit()
    static let changeFont = Font.caption.monospacedDigit()
    /// アイコンの棒と同じ緑
    static let accent = Color(red: 0x3d / 255, green: 0xdc / 255, blue: 0x84 / 255)

    /// 増減の率の色。増えたら緑、減ったら赤、変わらなければ灰色
    static func changeColor(_ change: Int?) -> Color {
        switch change {
        case let change? where change > 0: .green
        case let change? where change < 0: .red
        default: .secondary
        }
    }
}

/// 大きな見出しと、灰色の1行。右に操作を置く
struct Header<Trailing: View>: View {
    let title: String
    var subtitle: String? = nil
    @ViewBuilder let trailing: Trailing

    var body: some View {
        HStack(alignment: .top, spacing: Design.rowPadding) {
            VStack(alignment: .leading, spacing: 6) {
                Text(title).font(Design.titleFont)
                if let subtitle {
                    Text(subtitle).foregroundStyle(.secondary).monospacedDigit()
                }
            }
            Spacer(minLength: 0)
            trailing
        }
    }
}

/// 細い線で縁取った角丸の枠
struct Card<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        content
            .background(Color(nsColor: .controlBackgroundColor))
            .clipShape(RoundedRectangle(cornerRadius: Design.cornerRadius))
            .overlay(
                RoundedRectangle(cornerRadius: Design.cornerRadius).strokeBorder(Color(nsColor: .separatorColor)))
    }
}

/// 枠の中に1行だけ出す知らせ。押せるボタンを添えられる
struct Message: View {
    let text: String
    var action: (title: String, run: () -> Void)? = nil

    var body: some View {
        VStack(spacing: 10) {
            Text(text).foregroundStyle(.secondary)
            if let action { Button(action.title, action: action.run) }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, Design.messagePadding)
    }
}

/// 列の見出し。期間の名前を並べ、押すとその期間の数で並べ替える。並べている列だけ濃く、下向きの印を付ける
struct ColumnHeader: View {
    @Binding var sort: Period

    var body: some View {
        HStack(spacing: Design.columnSpacing) {
            Spacer(minLength: 0)
            ForEach(Period.allCases) { period in
                Button {
                    sort = period
                } label: {
                    HStack(spacing: 2) {
                        Text(period.label)
                        if period == sort { Image(systemName: "chevron.down").font(.caption2) }
                    }
                    .frame(width: Design.columnWidth, alignment: .trailing)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .font(.callout)
                .foregroundStyle(period == sort ? .primary : .secondary)
            }
        }
        .padding(.horizontal, Design.rowPadding)
        .frame(height: Design.headerHeight)
    }
}

/// プロジェクトの1行。名前とドメイン、4つの期間の訪問者数。
/// 名前を押すとそのサイトを、数字を押すとその期間を選んだ Vercel の Analytics の画面を開く。名前に乗ると下線を引く
struct ProjectRow: View {
    let row: Row
    let sort: Period
    let metric: Metric
    @State private var hovering = false
    @State private var hoveringName = false

    var body: some View {
        HStack(spacing: Design.columnSpacing) {
            Button {
                NSWorkspace.shared.open(row.project.siteURL ?? row.project.analyticsURL)
            } label: {
                VStack(alignment: .leading, spacing: 2) {
                    Text(row.project.name).fontWeight(.medium).lineLimit(1).underline(hoveringName)
                    if let domain = row.project.domain {
                        Text(domain).font(.callout).foregroundStyle(.secondary).lineLimit(1)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .onHover { hoveringName = $0 }
            .help(row.project.siteURL?.absoluteString ?? "")
            .accessibilityLabel(row.project.name)

            // 並べている期間の推移。数字の「+136%」だけでは、急に伸びたのか、じわじわ伸びたのかが分からない
            Sparkline(values: row.trend[metric]?[sort] ?? [])
                .frame(width: Design.sparklineWidth, height: Design.sparklineHeight)
                .accessibilityHidden(true)

            ForEach(Period.allCases) { period in
                Button {
                    NSWorkspace.shared.open(row.project.analyticsURL(period))
                } label: {
                    VStack(alignment: .trailing, spacing: 2) {
                        Text(Format.number(row.count(metric, period)))
                            .font(Design.numberFont)
                            .foregroundStyle(period == sort ? .primary : .secondary)
                        // 前の期間が取れない3か月や、前が 0 のときも行の高さをそろえるため、空でも置く
                        Text(row.change(metric, period).map(Format.change) ?? " ")
                            .font(Design.changeFont)
                            .foregroundStyle(Design.changeColor(row.change(metric, period)))
                    }
                    .frame(width: Design.columnWidth, alignment: .trailing)
                    .frame(maxHeight: .infinity)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(
                    [
                        period.label, Format.number(row.count(metric, period)),
                        row.change(metric, period).map(Format.change),
                    ]
                    .compactMap { $0 }.joined(separator: " "))
            }
        }
        .padding(.horizontal, Design.rowPadding)
        .frame(height: Design.rowHeight)
        .background(hovering ? Color.primary.opacity(0.04) : .clear)
        .onHover { hovering = $0 }
    }
}

/// 推移の小さな折れ線。目盛りも軸も無く、形だけを見せる。いちばん大きい点を上端、0 を下端にそろえる。
/// 色はアイコンの棒と同じ緑。点が1つも無いか、すべて 0 なら下端に灰色の線だけを引く
struct Sparkline: View {
    let values: [Int]

    var body: some View {
        GeometryReader { geometry in
            let peak = values.max() ?? 0
            let inset = Design.sparklineLine / 2
            let height = geometry.size.height - Design.sparklineLine
            Path { path in
                guard values.count > 1, peak > 0 else {
                    path.move(to: CGPoint(x: 0, y: geometry.size.height - inset))
                    path.addLine(to: CGPoint(x: geometry.size.width, y: geometry.size.height - inset))
                    return
                }
                let step = geometry.size.width / CGFloat(values.count - 1)
                for (index, value) in values.enumerated() {
                    let point = CGPoint(
                        x: CGFloat(index) * step, y: inset + height * (1 - CGFloat(value) / CGFloat(peak)))
                    if index == 0 { path.move(to: point) } else { path.addLine(to: point) }
                }
            }
            .stroke(
                (values.max() ?? 0) > 0 ? Design.accent : Color.secondary.opacity(0.4),
                style: StrokeStyle(lineWidth: Design.sparklineLine, lineCap: .round, lineJoin: .round))
        }
    }
}
