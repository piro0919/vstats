import AppKit
import SwiftUI

/// 一覧の1行の中身。4つの期間の訪問者数を持つ
struct Row: Identifiable, Equatable, Codable, Sendable {
    let project: Project
    let visitors: [Period: Int]

    var id: String { project.id }

    /// 選んだ期間の訪問者の多い順。同じ数なら名前の順
    static func sorted(_ rows: [Row], by period: Period) -> [Row] {
        rows.sorted {
            let a = $0.visitors[period] ?? 0
            let b = $1.visitors[period] ?? 0
            return a != b ? a > b : $0.project.name.localizedStandardCompare($1.project.name) == .orderedAscending
        }
    }
}

/// 窓に出すものを集める。取り直すのは、開いたときに前回から1時間たっていたときと、⌘R のときだけ
@MainActor
final class Model: ObservableObject {
    enum State: Equatable {
        /// トークンが無い。rejected は入れたものが断られたとき
        case needsToken(rejected: Bool)
        case loading
        case loaded
        case failed
    }

    @Published private(set) var snapshot = Snapshot.load()
    @Published private(set) var state: State = .needsToken(rejected: false)
    @Published var sort = Period.sorted {
        didSet { Period.sorted = sort }
    }
    private var task: Task<Void, Never>?

    var rows: [Row] { Row.sorted(snapshot?.rows ?? [], by: sort) }

    func save(token: String) {
        let token = token.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !token.isEmpty, Keychain.save(token) else { return }
        reload()
    }

    func tokenRemoved() {
        task?.cancel()
        Snapshot.remove()
        snapshot = nil
        state = .needsToken(rejected: false)
    }

    /// 窓を開いたとき。前回の数字があれば出し、古ければ取り直す
    func open() {
        guard Keychain.effectiveToken != nil else {
            state = .needsToken(rejected: false)
            return
        }
        if let snapshot, !snapshot.isStale() {
            state = .loaded
        } else {
            reload()
        }
    }

    func reload() {
        guard let token = Keychain.effectiveToken else {
            state = .needsToken(rejected: false)
            return
        }
        task?.cancel()
        // 取り直すあいだも前の数字は出したままにする
        state = .loading
        task = Task {
            do {
                let rows = try await VercelClient(token: token).rows()
                try Task.checkCancellation()
                let snapshot = Snapshot(fetchedAt: Date(), rows: rows)
                snapshot.save()
                self.snapshot = snapshot
                self.state = .loaded
            } catch VercelError.invalidToken {
                Snapshot.remove()
                self.snapshot = nil
                self.state = .needsToken(rejected: true)
            } catch is CancellationError {
            } catch {
                if !Task.isCancelled { self.state = .failed }
            }
        }
    }
}

struct MainView: View {
    @ObservedObject var model: Model

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Design.sectionSpacing) {
                if case .needsToken(let rejected) = model.state {
                    Header(title: Strings.tokenTitle) { EmptyView() }
                    TokenForm(rejected: rejected, save: model.save(token:))
                } else {
                    Header(title: Strings.projects, subtitle: subtitle) {
                        if model.state == .loading { ProgressView().controlSize(.small) }
                    }
                    list
                }
            }
            .padding(Design.pagePadding)
        }
        .frame(minWidth: Design.windowMinWidth, minHeight: Design.windowMinHeight)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private var subtitle: String? {
        guard let snapshot = model.snapshot, !snapshot.rows.isEmpty else { return nil }
        return Strings.summary(projects: snapshot.rows.count, fetchedAt: Format.fetchedAt(snapshot.fetchedAt))
    }

    @ViewBuilder private var list: some View {
        if !model.rows.isEmpty {
            Card {
                VStack(spacing: 0) {
                    ColumnHeader(sort: $model.sort)
                    ForEach(model.rows) { row in
                        Divider()
                        ProjectRow(row: row, sort: model.sort)
                    }
                }
            }
        } else if model.state == .failed {
            Card { Message(text: Strings.loadFailed, action: (Strings.retry, model.reload)) }
        } else if model.state == .loaded {
            Card { Message(text: Strings.noProjects) }
        }
    }
}

/// トークンを入れる枠。入れるまでは一覧の代わりにこれだけを出す
struct TokenForm: View {
    let rejected: Bool
    let save: (String) -> Void
    @State private var token = ""

    var body: some View {
        Card {
            VStack(alignment: .leading, spacing: 12) {
                SecureField(Strings.tokenPlaceholder, text: $token)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit(submit)
                if rejected {
                    Text(Strings.tokenRejected).font(.callout).foregroundStyle(.red)
                }
                HStack {
                    Link(Strings.createToken, destination: URL(string: "https://vercel.com/account/settings/tokens")!)
                    Spacer()
                    Button(Strings.save, action: submit)
                        .buttonStyle(.borderedProminent)
                        .disabled(token.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
            .padding(Design.rowPadding)
        }
        .frame(maxWidth: Design.formWidth)
    }

    private func submit() {
        save(token)
        token = ""
    }
}

/// 窓を1枚だけ持つ
@MainActor
final class MainWindowController {
    private var window: NSWindow?
    let model = Model()

    /// 文字は描くときに読むので、言語を変えたら中身を作り直す
    func reloadLanguage() {
        window?.contentView = NSHostingView(rootView: MainView(model: model))
    }

    func show() {
        if window == nil {
            let window = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 720, height: 640),
                styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
                backing: .buffered, defer: false)
            window.title = "VStats"
            window.titleVisibility = .hidden
            window.titlebarAppearsTransparent = true
            window.contentView = NSHostingView(rootView: MainView(model: model))
            window.isReleasedWhenClosed = false
            window.setFrameAutosaveName("Main")
            if !window.setFrameUsingName("Main") { window.center() }
            self.window = window
            model.open()
        }
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate()
    }
}
