import AppKit
import SwiftUI

/// 一覧の1行の中身
struct Row: Identifiable, Equatable, Sendable {
    let project: Project
    let visitors: Int
    let previous: Int

    var id: String { project.id }
    var delta: Int { visitors - previous }

    /// 訪問者の多い順。同じ数なら名前の順
    static func sorted(_ rows: [Row]) -> [Row] {
        rows.sorted {
            $0.visitors != $1.visitors
                ? $0.visitors > $1.visitors
                : $0.project.name.localizedStandardCompare($1.project.name) == .orderedAscending
        }
    }
}

/// 窓に出すものを集める。取り直すのは、窓を開いたときと ⌘R と期間を変えたときだけ
@MainActor
final class Model: ObservableObject {
    enum State: Equatable {
        /// トークンが無い。rejected は入れたものが断られたとき
        case needsToken(rejected: Bool)
        case loading
        case loaded
        case failed
    }

    @Published private(set) var rows: [Row] = []
    @Published private(set) var state: State = .needsToken(rejected: false)
    @Published var period = Period.chosen {
        didSet {
            guard period != oldValue else { return }
            Period.chosen = period
            reload()
        }
    }
    private var task: Task<Void, Never>?

    var total: Int { rows.reduce(0) { $0 + $1.visitors } }

    func save(token: String) {
        let token = token.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !token.isEmpty, Keychain.save(token) else { return }
        rows = []
        reload()
    }

    func tokenRemoved() {
        task?.cancel()
        rows = []
        state = .needsToken(rejected: false)
    }

    func reload() {
        guard let token = Keychain.effectiveToken else {
            state = .needsToken(rejected: false)
            return
        }
        task?.cancel()
        // 取り直すあいだも前の数字は出したままにする
        state = .loading
        let period = period
        task = Task {
            do {
                let client = VercelClient(token: token)
                let projects = try await client.projects()
                let now = Date()
                let rows = try await concurrentMap(projects, limit: 8) { project in
                    async let visitors = client.visitors(project, in: period.current(now: now))
                    async let previous = client.visitors(project, in: period.previous(now: now))
                    return Row(project: project, visitors: try await visitors, previous: try await previous)
                }
                try Task.checkCancellation()
                self.rows = Row.sorted(rows)
                self.state = .loaded
            } catch VercelError.invalidToken {
                self.rows = []
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
                        HStack(spacing: 10) {
                            if model.state == .loading { ProgressView().controlSize(.small) }
                            Picker("", selection: $model.period) {
                                ForEach(Period.allCases) { Text($0.label).tag($0) }
                            }
                            .labelsHidden()
                            .fixedSize()
                        }
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
        guard !model.rows.isEmpty else { return nil }
        return Strings.summary(projects: model.rows.count, visitors: Format.number(model.total))
    }

    @ViewBuilder private var list: some View {
        if !model.rows.isEmpty {
            Card {
                VStack(spacing: 0) {
                    ForEach(Array(model.rows.enumerated()), id: \.element.id) { index, row in
                        if index > 0 { Divider() }
                        ProjectRow(row: row)
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
            model.reload()
        }
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate()
    }
}
