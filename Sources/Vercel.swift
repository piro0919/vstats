import Foundation

/// 一覧の1行に出すプロジェクト
struct Project: Identifiable, Equatable, Sendable {
    let id: String
    let name: String
    let teamID: String
    let teamSlug: String
    /// 本番の独自ドメイン。無ければ vercel.app のもの
    let domain: String?

    /// 行を押したときに開く、Vercel の Analytics の画面
    var analyticsURL: URL {
        URL(string: "https://vercel.com/\(teamSlug)/\(name)/analytics")!
    }
}

enum VercelError: Error, Equatable {
    /// トークンが無効か、期限切れ
    case invalidToken
    case http(Int)
}

/// Vercel の REST API。トークンは利用者が入れた個人用のもの。
/// MCP のコネクタからは Web Analytics が 404 になるので、ここでは使わない
struct VercelClient: Sendable {
    let token: String
    var base = URL(string: "https://api.vercel.com")!

    // MARK: - チームとプロジェクト

    /// 見えるすべてのチームの、Web Analytics が有効なプロジェクト
    func projects() async throws -> [Project] {
        let teams = try await teams()
        return try await withThrowingTaskGroup(of: [Project].self) { group in
            for team in teams {
                group.addTask { try await projects(team: team) }
            }
            var all: [Project] = []
            var seen = Set<String>()
            for try await list in group {
                for project in list where seen.insert(project.id).inserted { all.append(project) }
            }
            return all
        }
    }

    func teams() async throws -> [Team] {
        var teams: [Team] = []
        var until: Int64?
        repeat {
            var query = [URLQueryItem(name: "limit", value: "100")]
            if let until { query.append(URLQueryItem(name: "until", value: String(until))) }
            let data: Data
            do {
                data = try await get("/v2/teams", query)
            } catch VercelError.http(let code) where code == 401 || code == 403 {
                throw VercelError.invalidToken
            }
            let page = try JSONDecoder().decode(TeamsPage.self, from: data)
            teams += page.teams.map { Team(id: $0.id, slug: $0.slug) }
            until = page.pagination?.next
        } while until != nil
        return teams
    }

    /// トークンがチームを絞って作られていると、ほかのチームは 403 になる。そのチームは飛ばす
    private func projects(team: Team) async throws -> [Project] {
        var projects: [Project] = []
        var until: Int64?
        repeat {
            var query = [
                URLQueryItem(name: "teamId", value: team.id),
                URLQueryItem(name: "limit", value: "100"),
            ]
            // 続きは until で取る。from は境目の1件が前のページと重なる
            if let until { query.append(URLQueryItem(name: "until", value: String(until))) }
            let data: Data
            do {
                data = try await get("/v10/projects", query)
            } catch VercelError.http(403) {
                return projects
            }
            let page = try Self.parseProjects(data, team: team)
            projects += page.projects
            until = page.next
        } while until != nil
        return projects
    }

    // MARK: - 訪問者

    /// 一覧の行。チームごとに今の期間と前の期間を1回ずつ聞く
    func rows(period: Period, now: Date = Date()) async throws -> [Row] {
        let projects = try await projects()
        let teams = Dictionary(grouping: projects, by: \.teamID).values.compactMap(\.first)
            .map { Team(id: $0.teamID, slug: $0.teamSlug) }
        var current: [String: Int] = [:]
        var previous: [String: Int] = [:]
        for team in teams {
            async let latest = visitors(team: team, in: period.current(now: now))
            async let before = visitors(team: team, in: period.previous(now: now))
            current.merge(try await latest) { $1 }
            previous.merge(try await before) { $1 }
        }
        return Row.sorted(
            projects.map { Row(project: $0, visitors: current[$0.id] ?? 0, previous: previous[$0.id] ?? 0) })
    }

    /// チームの全プロジェクトの、期間の訪問者数（プロジェクトの id ごと）。本番の環境だけを数える。
    /// Web Analytics の API（/v1/query/web-analytics）はプロジェクトごとにしか聞けず、1時間に 400 回までしか
    /// 聞けない。50 件で今と前の期間を聞くと1回の表示で 100 回になり、4回開くと止まった。
    /// `vercel metrics --all --group-by projectId` が使う観測の API なら、チーム全体を1回で数えられる
    func visitors(team: Team, in interval: DateInterval) async throws -> [String: Int] {
        let body = try JSONEncoder().encode(Self.metricsQuery(owner: team.id, interval: interval))
        let data = try await send("/metrics/v1", [URLQueryItem(name: "teamId", value: team.id)], body: body)
        return try Self.parseVisitors(data)
    }

    /// 窓の両端は1時間に揃える。Web Analytics の API が丸めていたのと同じ揃え方
    static func metricsQuery(owner: String, interval: DateInterval) -> MetricsQuery {
        let hour: TimeInterval = 3600
        let start = (interval.start.timeIntervalSince1970 / hour).rounded(.down) * hour
        let end = (interval.end.timeIntervalSince1970 / hour).rounded(.up) * hour
        let format = Date.ISO8601FormatStyle(includingFractionalSeconds: true)
        return MetricsQuery(
            scope: .init(ownerId: owner),
            timeRange: .init(
                start: Date(timeIntervalSince1970: start).formatted(format),
                end: Date(timeIntervalSince1970: end).formatted(format)),
            // 区切りは最大で1日。期間全体の数は区切りごとの数とは別に summary に入る
            bucketSeconds: 86_400,
            groupBy: ["projectId"],
            filter: "environment:production",
            metrics: [
                "value": .init(
                    metric: "vercel.analytics.page_view.count", aggregation: "unique", dimensions: ["visitorId"])
            ],
            outputs: ["value"],
            // 系列（プロジェクト）の数の上限。API が受け付けるのは 500 まで
            seriesSelection: .init(limit: 500, mode: "exact", rankBy: [.init(metric: "value", direction: "desc")]))
    }

    // MARK: - 通信

    private func get(_ path: String, _ query: [URLQueryItem]) async throws -> Data {
        try await send(path, query, body: nil)
    }

    private func send(_ path: String, _ query: [URLQueryItem], body: Data?) async throws -> Data {
        var components = URLComponents(url: base.appendingPathComponent(path), resolvingAgainstBaseURL: false)!
        components.queryItems = query
        var request = URLRequest(url: components.url!)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        if let body {
            request.httpMethod = "POST"
            request.httpBody = body
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }
        // 混んでいると 429 が返る。少し待って聞き直す
        for attempt in 0..<4 {
            let (data, response) = try await URLSession.shared.data(for: request)
            let http = response as? HTTPURLResponse
            let status = http?.statusCode ?? 0
            if ProcessInfo.processInfo.environment["VSTATS_DIAG"] != nil, let http {
                let limits = http.allHeaderFields.filter { "\($0.key)".lowercased().hasPrefix("x-ratelimit") }
                FileHandle.standardError.write(Data("\(status) \(path) \(limits)\n".utf8))
                if status >= 400 { FileHandle.standardError.write(data + Data("\n".utf8)) }
            }
            if status == 429, attempt < 3 {
                let wait = http?.value(forHTTPHeaderField: "Retry-After").flatMap(Double.init)
                try await Task.sleep(for: .seconds(min(wait ?? Double(attempt + 1), 10)))
                continue
            }
            guard (200..<300).contains(status) else { throw VercelError.http(status) }
            return data
        }
        throw VercelError.http(429)
    }

    // MARK: - 読み取り（自己テストからも呼ぶ）

    static func parseProjects(_ data: Data, team: Team) throws -> (projects: [Project], next: Int64?) {
        let page = try JSONDecoder().decode(ProjectsPage.self, from: data)
        let projects = page.projects.filter { isEnabled($0.webAnalytics) }.map {
            Project(
                id: $0.id, name: $0.name, teamID: team.id, teamSlug: team.slug,
                domain: domain($0.targets?.production?.alias ?? []))
        }
        return (projects, page.pagination?.next)
    }

    /// 一度切って入れ直すと enabledAt と disabledAt の両方が残る。後に起きたほうが今の状態
    static func isEnabled(_ analytics: ProjectsPage.Analytics?) -> Bool {
        guard let enabled = analytics?.enabledAt else { return false }
        guard let disabled = analytics?.disabledAt else { return true }
        return enabled > disabled
    }

    /// 本番の別名のうち、独自ドメインを先に選ぶ
    static func domain(_ aliases: [String]) -> String? {
        aliases.first { !$0.hasSuffix(".vercel.app") } ?? aliases.first
    }

    /// 期間全体の数は summary にある。訪問の無いプロジェクトは載らない
    static func parseVisitors(_ data: Data) throws -> [String: Int] {
        let page = try JSONDecoder().decode(MetricsPage.self, from: data)
        var visitors: [String: Int] = [:]
        for row in page.summary {
            visitors[row.dimensions.projectId, default: 0] += row.values.value ?? 0
        }
        return visitors
    }
}

struct Team: Equatable, Sendable {
    let id: String
    let slug: String
}

struct Pagination: Decodable {
    let next: Int64?
}

struct TeamsPage: Decodable {
    struct Item: Decodable {
        let id: String
        let slug: String
    }
    let teams: [Item]
    let pagination: Pagination?
}

struct ProjectsPage: Decodable {
    struct Analytics: Decodable {
        let enabledAt: Int64?
        let disabledAt: Int64?
    }
    struct Targets: Decodable {
        struct Target: Decodable { let alias: [String]? }
        let production: Target?
    }
    struct Item: Decodable {
        let id: String
        let name: String
        let webAnalytics: Analytics?
        let targets: Targets?
    }
    let projects: [Item]
    let pagination: Pagination?
}

/// 観測の API（/metrics/v1）に送る問い合わせ。形は Vercel CLI の `vercel metrics` が送るものを写した
struct MetricsQuery: Encodable, Equatable {
    struct Scope: Encodable, Equatable { let ownerId: String }
    struct TimeRange: Encodable, Equatable {
        let start: String
        let end: String
    }
    struct Metric: Encodable, Equatable {
        let metric: String
        let aggregation: String
        let dimensions: [String]
    }
    struct Rank: Encodable, Equatable {
        let metric: String
        let direction: String
    }
    struct Selection: Encodable, Equatable {
        let limit: Int
        let mode: String
        let rankBy: [Rank]
    }
    let scope: Scope
    let timeRange: TimeRange
    let bucketSeconds: Int
    let groupBy: [String]
    let filter: String
    let metrics: [String: Metric]
    let outputs: [String]
    let seriesSelection: Selection
}

struct MetricsPage: Decodable {
    struct Row: Decodable {
        struct Dimensions: Decodable { let projectId: String }
        struct Values: Decodable { let value: Int? }
        let dimensions: Dimensions
        let values: Values
    }
    let summary: [Row]
}
