import Foundation

/// 画面もネットワークもキーチェーンも触らずに、規則だけを確かめる。`./VStats --selftest` で走る
@MainActor
enum SelfTest {
    private static var failures = 0

    static func run() -> Int32 {
        failures = 0
        let team = Team(id: "team_a", slug: "kkweb")

        // Web Analytics が有効か
        do {
            typealias A = ProjectsPage.Analytics
            check(!VercelClient.isEnabled(nil), "項目が無ければ無効")
            check(!VercelClient.isEnabled(A(enabledAt: nil, disabledAt: nil)), "id だけなら無効")
            check(VercelClient.isEnabled(A(enabledAt: 10, disabledAt: nil)), "有効にした日だけなら有効")
            check(VercelClient.isEnabled(A(enabledAt: 10, disabledAt: 5)), "切ってから入れ直したなら有効")
            check(!VercelClient.isEnabled(A(enabledAt: 5, disabledAt: 10)), "入れてから切ったなら無効")
        }

        // 本番のドメイン
        do {
            check(
                VercelClient.domain(["owler-kkweb.vercel.app", "owler.kkweb.io"]) == "owler.kkweb.io",
                "独自ドメインを先に選ぶ")
            check(VercelClient.domain(["a-kkweb.vercel.app"]) == "a-kkweb.vercel.app", "無ければ vercel.app")
            check(VercelClient.domain([]) == nil, "別名が無ければ出さない")
        }

        // プロジェクトの一覧
        do {
            let json = """
                {"projects":[
                  {"id":"p1","name":"owler","webAnalytics":{"id":"x","enabledAt":1,"hasData":true},
                   "targets":{"production":{"alias":["owler.kkweb.io"]}}},
                  {"id":"p2","name":"off","webAnalytics":{"id":"y"}},
                  {"id":"p3","name":"bare"}
                ],"pagination":{"count":3,"next":42,"prev":1}}
                """
            let page = try? VercelClient.parseProjects(Data(json.utf8), team: team)
            check(page?.projects.map(\.name) == ["owler"], "有効なプロジェクトだけを拾う")
            check(page?.next == 42, "続きの目印を読む")
            check(page?.projects.first?.domain == "owler.kkweb.io", "本番のドメインを持つ")
            check(
                page?.projects.first?.analyticsURL.absoluteString == "https://vercel.com/kkweb/owler/analytics",
                "Vercel の Analytics の画面を開く")
            let last = try? VercelClient.parseProjects(
                Data(#"{"projects":[],"pagination":{"next":null}}"#.utf8), team: team)
            check(last != nil && last?.next == nil, "最後のページでは続きが無い")
        }

        // 訪問者数
        do {
            let json = """
                {"series":[{"timestamp":"2026-10-06T00:00:00.000Z","dimensions":{"projectId":"p1"},"values":{"value":15}}],
                 "summary":[{"dimensions":{"projectId":"p1"},"values":{"value":353}},
                            {"dimensions":{"projectId":"p2"},"values":{"value":null}}]}
                """
            let visitors = try? VercelClient.parseVisitors(Data(json.utf8))
            check(visitors?["p1"] == 353, "期間全体の数は summary から読む")
            check(visitors?["p2"] == 0, "値が無ければ 0")
            check(visitors?["p3"] == nil, "訪問の無いプロジェクトは載らない")
        }

        // 観測の API に送る問い合わせ
        do {
            let interval = DateInterval(start: iso("2026-10-05T15:00:00Z"), end: iso("2026-10-13T15:00:00Z"))
            let ids = (1...50).map { "p\($0)" }
            let queries = VercelClient.metricsQueries(
                owner: "team_a", projects: ids, interval: interval, bucket: 10_800)
            let query = queries.first
            check(queries.count == 1, "7日なら1回で聞く")
            check(query?.timeRange.start == "2026-10-05T15:00:00.000Z", "窓の両端をそのまま渡す")
            check(query?.bucketSeconds == 10_800, "区切りを渡す")
            check(query?.seriesSelection.limit == 50, "系列はプロジェクトの数だけ")
            check(query?.metrics["value"]?.dimensions == ["visitorId"], "訪問者は visitorId の数で数える")
            check(query?.filter == "environment:production", "本番だけを数える")
            let quarter = DateInterval(start: iso("2026-07-14T15:00:00Z"), end: iso("2026-10-13T15:00:00Z"))
            let split = VercelClient.metricsQueries(owner: "team_a", projects: ids, interval: quarter, bucket: 10_800)
            check(split.count == 3, "3か月はプロジェクトを分けて聞く")
            check(split.map(\.seriesSelection.limit) == [20, 20, 10], "分けた数だけ系列を取る")
            check(
                split.first?.filter.hasPrefix("environment:production AND projectId:(p1 OR p2 OR") == true,
                "分けたプロジェクトで絞る")
        }

        // 期間。値は Vercel の画面が 2026-10-13 11:46（日本時間）に投げていた問い合わせのもの
        do {
            var tokyo = Calendar(identifier: .gregorian)
            tokyo.timeZone = TimeZone(identifier: "Asia/Tokyo")!
            let now = iso("2026-10-13T02:46:00Z")
            func check(_ period: Period, _ current: (String, String), _ previous: (String, String)) {
                let a = period.current(now: now, calendar: tokyo)
                let b = period.previous(now: now, calendar: tokyo)
                Self.check(
                    a == DateInterval(start: iso(current.0), end: iso(current.1)), "\(period.rawValue) の今の窓")
                Self.check(
                    b == DateInterval(start: iso(previous.0), end: iso(previous.1)), "\(period.rawValue) の前の窓")
            }
            check(
                .day, ("2026-10-12T03:00:00Z", "2026-10-13T03:00:00Z"), ("2026-10-11T03:00:00Z", "2026-10-12T03:00:00Z")
            )
            check(
                .week, ("2026-10-05T15:00:00Z", "2026-10-13T15:00:00Z"),
                ("2026-09-28T15:00:00Z", "2026-10-06T15:00:00Z"))
            check(
                .month, ("2026-09-12T15:00:00Z", "2026-10-13T15:00:00Z"),
                ("2026-08-13T15:00:00Z", "2026-09-13T15:00:00Z"))
            Self.check(Period.day.bucketSeconds(calendar: tokyo, at: now) == 3600, "24時間は1時間で区切る")
            Self.check(Period.week.bucketSeconds(calendar: tokyo, at: now) == 10_800, "日本では日本の0時にそろう3時間")
            var utc = Calendar(identifier: .gregorian)
            utc.timeZone = TimeZone(identifier: "UTC")!
            Self.check(Period.week.bucketSeconds(calendar: utc, at: now) == 86_400, "UTC なら1日")
        }

        // 並び順と差
        do {
            func row(_ name: String, _ visitors: Int, _ previous: Int = 0) -> Row {
                Row(
                    project: Project(id: name, name: name, teamID: "t", teamSlug: "s", domain: nil),
                    visitors: visitors, previous: previous)
            }
            let sorted = Row.sorted([row("b", 3), row("c", 10), row("a", 3), row("d", 0)])
            check(sorted.map(\.project.name) == ["c", "a", "b", "d"], "多い順、同じなら名前の順")
            check(row("x", 5, 8).delta == -3, "差は今から前を引く")
            let incomparable = Row(
                project: Project(id: "y", name: "y", teamID: "t", teamSlug: "s", domain: nil), visitors: 5,
                previous: nil)
            check(incomparable.delta == nil, "前の期間が無ければ差も無い")
            check(Period.allCases.filter { !$0.comparable } == [.quarter], "比べられないのは3か月だけ")
            let now = Date()
            let oldest = now.addingTimeInterval(-92 * 86_400)
            check(
                Period.allCases.allSatisfy {
                    ($0.comparable ? $0.previous(now: now) : $0.current(now: now)).start >= oldest
                },
                "どの期間も、聞く範囲は観測の API がさかのぼれる 92 日に収まる")

            let ja = Locale(identifier: "ja_JP")
            check(Format.delta(12, locale: ja) == "+12", "増えたら +")
            check(Format.delta(-1234, locale: ja) == "\u{2212}1,234", "減ったらマイナス記号と桁区切り")
            check(Format.delta(0, locale: ja) == nil, "差が無ければ出さない")
        }

        print(failures == 0 ? "selftest: ok" : "selftest: \(failures) failed")
        return failures == 0 ? 0 : 1
    }

    private static func check(_ condition: Bool, _ name: String) {
        if !condition {
            failures += 1
            print("NG: \(name)")
        }
    }

    private static func iso(_ text: String) -> Date {
        try! Date(text, strategy: .iso8601)
    }
}
