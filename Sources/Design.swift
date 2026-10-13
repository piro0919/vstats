import SwiftUI

// 見た目の決まり。手本は Vercel のプロジェクト一覧と Analytics の画面。
// 寸法・字の大きさ・角はここにだけ書き、ほかのファイルでは Design の値と部品を使う。
// 外れた書き方は Tools/design-rules.sh が落とす（CI でも回る）。
//
// - 字: 見出しは 24pt の太字。数字は等幅の数字（monospacedDigit）
// - 角: 枠は 10pt の角丸に、区切りの色の細い線
// - 余白: 窓の縁から 28pt、見出しと枠の間は 20pt、行の左右は 16pt
// - 行: 高さ 56pt。押せる行は、乗ったときだけ薄く塗る
// - 差: 増えたら緑、減ったら赤。差が無ければ何も出さない
enum Design {
    static let pagePadding: CGFloat = 28
    static let sectionSpacing: CGFloat = 20
    static let cornerRadius: CGFloat = 10
    static let rowHeight: CGFloat = 56
    static let rowPadding: CGFloat = 16
    static let messagePadding: CGFloat = 36
    static let deltaWidth: CGFloat = 64
    static let formWidth: CGFloat = 480
    static let windowMinWidth: CGFloat = 560
    static let windowMinHeight: CGFloat = 420

    static let titleFont = Font.system(size: 24, weight: .bold)
    static let numberFont = Font.system(size: 17, weight: .semibold).monospacedDigit()
    static let deltaFont = Font.callout.monospacedDigit()
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

/// プロジェクトの1行。名前とドメイン、訪問者数と前の期間との差。押すと Vercel の画面を開く
struct ProjectRow: View {
    let row: Row
    @State private var hovering = false

    var body: some View {
        Button {
            NSWorkspace.shared.open(row.project.analyticsURL)
        } label: {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(row.project.name).fontWeight(.medium).lineLimit(1)
                    if let domain = row.project.domain {
                        Text(domain).font(.callout).foregroundStyle(.secondary).lineLimit(1)
                    }
                }
                Spacer(minLength: 12)
                Text(Format.number(row.visitors)).font(Design.numberFont)
                Text(row.delta.flatMap { Format.delta($0) } ?? "")
                    .font(Design.deltaFont)
                    .foregroundStyle((row.delta ?? 0) > 0 ? Color.green : Color.red)
                    .frame(width: Design.deltaWidth, alignment: .leading)
            }
            .padding(.horizontal, Design.rowPadding)
            .frame(height: Design.rowHeight)
            .contentShape(Rectangle())
            .background(hovering ? Color.primary.opacity(0.04) : .clear)
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .accessibilityLabel(
            [row.project.name, Format.number(row.visitors), row.delta.flatMap { Format.delta($0) }].compactMap { $0 }
                .joined(separator: " "))
    }
}
