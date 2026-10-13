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

    /// 期間の訪問者数。本番の環境だけを数える（Vercel の画面の既定と同じ）。
    /// visits/count は日単位に丸めるので、時間単位で窓を切れる aggregate を環境で分けて使う
    func visitors(_ project: Project, in interval: DateInterval) async throws -> Int {
        let query = [
            URLQueryItem(name: "teamId", value: project.teamID),
            URLQueryItem(name: "projectId", value: project.id),
            URLQueryItem(name: "since", value: String(Int64(interval.start.timeIntervalSince1970 * 1000))),
            URLQueryItem(name: "until", value: String(Int64(interval.end.timeIntervalSince1970 * 1000))),
            URLQueryItem(name: "by", value: "environment"),
        ]
        return Self.parseVisitors(try await get("/v1/query/web-analytics/visits/aggregate", query))
    }

    // MARK: - 通信

    private func get(_ path: String, _ query: [URLQueryItem]) async throws -> Data {
        var components = URLComponents(url: base.appendingPathComponent(path), resolvingAgainstBaseURL: false)!
        components.queryItems = query
        var request = URLRequest(url: components.url!)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        // 一度に何十件も聞くので、混んでいると 429 が返る。少し待って聞き直す
        for attempt in 0..<4 {
            let (data, response) = try await URLSession.shared.data(for: request)
            let status = (response as? HTTPURLResponse)?.statusCode ?? 0
            if status == 429, attempt < 3 {
                let wait = (response as? HTTPURLResponse)?.value(forHTTPHeaderField: "Retry-After").flatMap(Double.init)
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

    /// 本番だけに絞った集計なので、行は多くても1つ。訪問が無い期間は空の配列が返る
    static func parseVisitors(_ data: Data) -> Int {
        guard let page = try? JSONDecoder().decode(AggregatePage.self, from: data) else { return 0 }
        return page.data.reduce(0) { $0 + $1.visitors }
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

struct AggregatePage: Decodable {
    struct Row: Decodable { let visitors: Int }
    let data: [Row]
}

/// 何十件もの問い合わせを、同時に投げすぎないように流す
func concurrentMap<T: Sendable, R: Sendable>(
    _ items: [T], limit: Int, _ transform: @escaping @Sendable (T) async throws -> R
) async throws -> [R] {
    try await withThrowingTaskGroup(of: (Int, R).self) { group in
        var results = [R?](repeating: nil, count: items.count)
        var next = 0
        for _ in 0..<min(limit, items.count) {
            let index = next
            group.addTask { (index, try await transform(items[index])) }
            next += 1
        }
        while let (index, result) = try await group.next() {
            results[index] = result
            if next < items.count {
                let index = next
                group.addTask { (index, try await transform(items[index])) }
                next += 1
            }
        }
        return results.map { $0! }
    }
}
