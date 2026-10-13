# VStats

開発者向けの設計メモ。

Vercel の Web Analytics の訪問者数を、複数のサイトにまたがって1枚の窓で見る Mac アプリ。
Vercel の画面では Analytics をプロジェクトごとに開き直す必要があり、サイトが何十本もあると全体が見えない。
2026-10-13 に壁打ちで決めた範囲だけを作っている。足すときは慎重に。

## 決めたこと

- 窓は1枚。プロジェクトを訪問者数の多い順に並べ、各行に前の期間との差を人数で添える。
  訪問者の少ないサイトが多いので、率（%）にすると 2人→4人 が +100% になって荒れる。だから人数
- 行を押すと、ブラウザでそのプロジェクトの Vercel の Analytics の画面を開く。詳細は Vercel の画面に任せる
- 一覧に載るのは、トークンで見えるすべてのチームの、Web Analytics が有効なプロジェクト全部。選ぶ設定は無い
- 期間は既定が直近7日。選択肢は過去24時間・7日間・30日間・3か月（`Period`）。Vercel の画面（2026-10-13 に実物で確認）は
  ほかに 12 か月と 24 か月（Web Analytics Plus 専用）を持つが、観測の API は 92 日前より古い時刻を聞けない
  （`timeRange cannot begin more than 92 days ago`）ので置かない。3か月は前の期間が取れないので差を出さない。
  数え方は「期間の数え方」の節
- 取り直すのは、窓を開いたとき・⌘R・期間を変えたときだけ。自動では取り直さない
- 窓の手本は Vercel。一覧はプロジェクト一覧、数字の見せ方は Analytics の画面。Owler と同じ系統の見た目

## Vercel の API

- トークンは利用者が作った個人用のもの。キーチェーン（サービス `io.kkweb.vstats`、アカウント `vercel-token`）に置く。
  プロジェクトの削除までできる強さがあるので、ファイルや UserDefaults には置かない
- **Vercel の MCP コネクタでは Web Analytics が 404 になる**（2026-10-13 に `count_pageviews` と `aggregate_pageviews` で確認。
  同じ条件の `vercel api` は 200）。なのでアプリは REST API を直接叩く
- 訪問者数は観測の API `POST /metrics/v1?teamId=…` で、**チームごとに1回**で取る（`VercelClient.metricsQuery`）。
  形は `vercel metrics vercel.analytics.page_view.count --all --group-by projectId --aggregation unique/visitorId`
  が送るものを写した（CLI の `createCanonicalMetricsRequest`）。期間全体の数は応答の `summary` にあり、
  訪問の無いプロジェクトは載らない。`bucketSeconds` は 86400 まで、`seriesSelection.limit` は 500 まで。
  集計は `aggregation: "unique"` に `dimensions: ["visitorId"]`。`"unique/visitorId"` と書くと 400
- **Web Analytics の API（`/v1/query/web-analytics/*`）は使わない。** プロジェクトごとにしか聞けず、
  **1時間に 400 回まで**（`x-ratelimit-limit`）。枠はトークンではなくアカウントかチームで数えるらしく、
  新しいトークンでも残りが 14 だった。50 件 × 今と前の2回で1回の表示が 100 回になり、初版は4回開くと止まった（2026-10-13）。
  なお `visits/count` は since と until を日単位（UTC）に丸める
- 1回の応答の行（プロジェクトの数 × 区切りの数）が多すぎると 413（`Query result is too large`）。3か月を3時間で
  区切って 50 件まとめると落ち、25 件は通った。行が 15,000 を超えるときはプロジェクトを分け、
  `projectId:(a OR b …)` で絞って聞く（`VercelClient.metricsQueries`）。訪問者数は足し合わせられないので、期間ではなくプロジェクトを分ける
- Web Analytics が有効かは、プロジェクトの `webAnalytics` の `enabledAt` と `disabledAt` の**後に起きたほう**で決める。
  切って入れ直すと両方が残り、`disabledAt` があるだけで無効と読むと間違える（kk-web がそう）
- プロジェクト一覧の続きは `until=<pagination.next>` で取る。`from` は境目の1件が前のページと重なる
- トークンをチームを絞って作ると、ほかのチームの一覧は 403 になる。そのチームは黙って飛ばす。
  トークンそのものが断られたかは `/v2/teams` の 401/403 で見る
- 1回の表示の問い合わせは、チーム一覧1回・プロジェクト一覧がチームごと・訪問者がチームごとに2回（3か月は分けた数だけ）。kk-web だけなら5回、約2秒。3か月は約5秒。
  429 は待って聞き直す（`VercelClient.send`）。環境変数 `VSTATS_DIAG` で、応答の状態と回数の上限、失敗の中身を標準エラーに出す
- 自己署名のアプリは、作り直すたびにキーチェーンの許可を求められる（2026-10-13、本人の画面で出た）

## 期間の数え方

Vercel の Analytics 画面が裏で投げる問い合わせ（`vercel.com/api/web-analytics/v2/overview`、応答の `queryResults.query`）を
playwright で読んで写した（2026-10-13）。kk-web で 24時間 27/21、7日 131/117、30日 424/400（今/前）と画面に一致した。

- 24時間: 今の時刻を1時間に切り上げ、そこから24時間。前の期間はその直前の24時間
- 7日・30日: 今の1時間の頭から N 日前を、**利用者の暦の日**（画面は `bucketTimezone: Asia/Tokyo`）に広げる。
  終わりは今日の終わりなので、実際は N+1 日。前の期間は広げる前の窓を同じ長さだけ戻して広げるので、今の窓と1日重なる
- 3か月: URL は `?period=90d` だが、始まりは暦で3か月前の同じ日。観測の API は始まりが 92 日以内・長さも 92 日以内しか
  聞けないので、そこで切る。そのぶん画面より少ない（kk-web で 1,326 に対して 1,313）
- 観測の API の区切り（`bucketSeconds`）は UTC の0時から数えられ、端の区切りがはみ出すと数が増える。
  日単位の期間は、利用者の暦の0時にそろうなるべく長い区切りにする（日本なら3時間、UTC なら1日。`Period.bucketSeconds`）。
  1日のままだと 7日の kk-web が 139 になった。タイムゾーンを渡す鍵（`bucketTimezone` など）は受け付けない
- 画面は本番に加えて環境が空の訪問も数える（`environment eq 'production' or environment eq ''`）。アプリは本番だけだが、
  上の照合では差が出なかった
- 画面の左上に出る期間（`Oct 6, 11:00 - Oct 13, 11:59`）と、実際に数えている範囲は違う

## Design rules

見た目の決まりは `Sources/Design.swift` の先頭にある。寸法・字の大きさ・角の数字はそこにだけ書き、ほかでは
`Design` の値と部品（`Header`・`Card`・`Message`・`ProjectRow`）を使う。外れた書き方は `Tools/design-rules.sh` が落とす。
AppKit で組んだ設定の窓は macOS の見た目に従うので対象外。

## 手元で動かす

```sh
./build.sh
./VStats.app/Contents/MacOS/VStats --selftest
./Tools/design-rules.sh
open ./VStats.app
```

- `--dump` で、窓に出すのと同じ一覧を文字で書き出す
- 環境変数 `VSTATS_TOKEN` があれば、キーチェーンより先にそれを使う。キーチェーンに書かずに確かめるため。
  `open -g --env VSTATS_TOKEN=… ./VStats.app` で窓にも効く。Vercel CLI のトークンは
  `~/Library/Application Support/com.vercel.cli/auth.json` にある（期限切れなら先に `vercel whoami`）

## リリース

Owler と同じ。`./release.sh <版>` でビルド・`--selftest`・DMG・更新用の zip・署名した `appcast.xml` を作り、
GitHub Releases に上げる。リリースノートは CHANGELOG.md のその版の節から取る。Sparkle の鍵は兄弟分と共有で、
秘密鍵はログインキーチェーンにある。署名は自己署名の「Okigae Dev」。

## まだやっていないこと

- 3か月の数を画面とそろえること（API の 92 日の制約で、今は無理）
- アイコン
- GitHub のリポジトリ、README、LP
