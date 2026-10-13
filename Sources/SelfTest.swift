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
                page?.projects.first?.siteURL?.absoluteString == "https://owler.kkweb.io", "名前を押すとサイトを開く")
            check(
                page?.projects.first?.analyticsURL.absoluteString == "https://vercel.com/kkweb/owler/analytics",
                "Vercel の Analytics の画面を開く")
            check(
                page?.projects.first?.analyticsURL(.day).absoluteString
                    == "https://vercel.com/kkweb/owler/analytics?period=24h",
                "数字を押すとその期間を選んだ画面を開く")
            check(
                Period.allCases.map(\.dashboardParameter) == ["24h", "7d", "30d", "90d"], "Vercel の画面の期間の値")
            let last = try? VercelClient.parseProjects(
                Data(#"{"projects":[],"pagination":{"next":null}}"#.utf8), team: team)
            check(last != nil && last?.next == nil, "最後のページでは続きが無い")
        }

        // 訪問者数とページビュー。形は 2026-10-13 に観測の API が返したもの
        do {
            let json = """
                {"series":[{"timestamp":"2026-10-06T00:00:00.000Z","dimensions":{"projectId":"p1"},
                            "values":{"visitors":15,"pageViews":30}}],
                 "summary":[{"dimensions":{"projectId":"p1"},"values":{"visitors":357,"pageViews":629}},
                            {"dimensions":{"projectId":"p2"},"values":{"visitors":null,"pageViews":null}}]}
                """
            let counts = try? VercelClient.parseCounts(Data(json.utf8))
            check(counts?["p1"]?[.visitors] == 357, "期間全体の訪問者数は summary から読む")
            check(counts?["p1"]?[.pageViews] == 629, "ページビューも同じ行から読む")
            check(counts?["p2"]?[.visitors] == 0, "値が無ければ 0")
            check(counts?["p3"] == nil, "訪問の無いプロジェクトは載らない")
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
            check(query?.metrics["visitors"]?.dimensions == ["visitorId"], "訪問者は visitorId の数で数える")
            check(query?.metrics["pageViews"]?.aggregation == "count", "ページビューは回数を数える")
            check(query?.outputs == ["visitors", "pageViews"], "2つの値を1回で聞く")
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
            func check(_ period: Period, _ start: String, _ end: String) {
                Self.check(
                    period.current(now: now, calendar: tokyo) == DateInterval(start: iso(start), end: iso(end)),
                    "\(period.rawValue) の窓")
            }
            check(.day, "2026-10-12T03:00:00Z", "2026-10-13T03:00:00Z")
            check(.week, "2026-10-05T15:00:00Z", "2026-10-13T15:00:00Z")
            check(.month, "2026-09-12T15:00:00Z", "2026-10-13T15:00:00Z")
            func previous(_ period: Period, _ start: String, _ end: String) {
                Self.check(
                    period.previous(now: now, calendar: tokyo) == DateInterval(start: iso(start), end: iso(end)),
                    "\(period.rawValue) の前の窓")
            }
            previous(.day, "2026-10-11T03:00:00Z", "2026-10-12T03:00:00Z")
            previous(.week, "2026-09-28T15:00:00Z", "2026-10-06T15:00:00Z")
            previous(.month, "2026-08-13T15:00:00Z", "2026-09-13T15:00:00Z")
            Self.check(Period.allCases.filter { !$0.comparable } == [.quarter], "比べられないのは3か月だけ")
            Self.check(
                Period.allCases.filter(\.comparable).allSatisfy {
                    $0.previous(now: now, calendar: tokyo).start >= now.addingTimeInterval(-92 * 86_400)
                },
                "前の窓も観測の API が聞ける 92 日に収まる")
            let quarter = Period.quarter.current(now: now, calendar: tokyo)
            Self.check(quarter.end == iso("2026-10-13T15:00:00Z"), "3か月も今日の終わりまで")
            Self.check(quarter.duration <= 92 * 86_400, "3か月は観測の API が聞ける 92 日に収める")
            Self.check(
                quarter.start >= now.addingTimeInterval(-92 * 86_400), "3か月の始まりは 92 日より前にしない")
            Self.check(Period.day.bucketSeconds(calendar: tokyo, at: now) == 3600, "24時間は1時間で区切る")
            Self.check(Period.week.bucketSeconds(calendar: tokyo, at: now) == 10_800, "日本では日本の0時にそろう3時間")
            var utc = Calendar(identifier: .gregorian)
            utc.timeZone = TimeZone(identifier: "UTC")!
            Self.check(Period.week.bucketSeconds(calendar: utc, at: now) == 86_400, "UTC なら1日")
        }

        // 並び順と増減の率
        do {
            func row(_ name: String, week: Int, day: Int = 0, views: Int = 0) -> Row {
                Row(
                    project: Project(id: name, name: name, teamID: "t", teamSlug: "s", domain: nil),
                    counts: [.visitors: [.day: day, .week: week], .pageViews: [.week: views]], previous: [:])
            }
            let rows = [
                row("b", week: 3, day: 9), row("c", week: 10), row("a", week: 3, views: 50), row("d", week: 0, day: 1),
            ]
            check(
                Row.sorted(rows, by: .week, .visitors).map(\.project.name) == ["c", "a", "b", "d"],
                "選んだ期間の多い順、同じなら名前の順")
            check(
                Row.sorted(rows, by: .day, .visitors).map(\.project.name) == ["b", "d", "a", "c"], "期間を変えると並びも変わる")
            check(Row.sorted(rows, by: .week, .pageViews).first?.project.name == "a", "ページビューでも並べられる")

            // koidamashii の7日は、画面で 357 人・+136%（前の期間は 151 人）だった
            let koi = Row(
                project: Project(id: "k", name: "koidamashii", teamID: "t", teamSlug: "s", domain: nil),
                counts: [.visitors: [.week: 357, .quarter: 526]], previous: [.visitors: [.week: 151, .day: 0]])
            check(koi.change(.visitors, .week) == 136, "前の期間からの増減の率")
            check(koi.change(.visitors, .quarter) == nil, "前の期間が無ければ率は出さない")
            check(koi.change(.visitors, .day) == nil, "前の期間が 0 なら率は出さない")
            check(Format.change(136) == "+136%" && Format.change(-98) == "-98%", "率には符号を付ける")
        }

        // 前回の数字
        do {
            let fetched = iso("2026-10-13T02:00:00Z")
            let snapshot = Snapshot(fetchedAt: fetched, rows: [])
            check(!snapshot.isStale(now: fetched.addingTimeInterval(59 * 60)), "1時間たつまでは取り直さない")
            check(snapshot.isStale(now: fetched.addingTimeInterval(60 * 60)), "1時間たったら取り直す")

            let row = Row(
                project: Project(id: "p", name: "kk-web", teamID: "t", teamSlug: "kkweb", domain: "kkweb.io"),
                counts: [.visitors: [.day: 27, .week: 131], .pageViews: [.week: 476]],
                previous: [.visitors: [.week: 117]])
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            let original = Snapshot(fetchedAt: fetched, rows: [row])
            let restored = (try? encoder.encode(original)).flatMap { try? decoder.decode(Snapshot.self, from: $0) }
            check(restored == original, "書いて読み戻すと同じ")

            var tokyo = Calendar(identifier: .gregorian)
            tokyo.timeZone = TimeZone(identifier: "Asia/Tokyo")!
            let ja = Locale(identifier: "ja_JP")
            check(
                Format.fetchedAt(fetched, now: fetched.addingTimeInterval(600), calendar: tokyo, locale: ja) == "11:00",
                "今日なら時刻だけ")
            check(
                Format.fetchedAt(fetched, now: fetched.addingTimeInterval(86_400), calendar: tokyo, locale: ja)
                    .hasPrefix("10月13日"),
                "前の日なら日付も付ける")
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
