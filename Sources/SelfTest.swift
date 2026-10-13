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
            let one = #"{"data":[{"environment":"production","visitors":120,"pageviews":459}]}"#
            check(VercelClient.parseVisitors(Data(one.utf8)) == 120, "本番の訪問者数を読む")
            check(VercelClient.parseVisitors(Data(#"{"data":[]}"#.utf8)) == 0, "訪問が無ければ 0")
        }

        // 期間
        do {
            let now = Date(timeIntervalSince1970: 1_000_000)
            let current = Period.week.current(now: now)
            let previous = Period.week.previous(now: now)
            check(current.end == now && current.duration == 7 * 86_400, "今に向かう7日間")
            check(previous.end == current.start && previous.duration == current.duration, "すぐ前の同じ長さ")
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
}
