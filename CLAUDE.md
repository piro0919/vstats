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
- 期間は既定が直近7日。切り替えの選択肢は Vercel の Analytics 画面に合わせる（**実物での確認がまだ。** `Period`）
- 取り直すのは、窓を開いたとき・⌘R・期間を変えたときだけ。自動では取り直さない
- 窓の手本は Vercel。一覧はプロジェクト一覧、数字の見せ方は Analytics の画面。Owler と同じ系統の見た目

## Vercel の API

- トークンは利用者が作った個人用のもの。キーチェーン（サービス `io.kkweb.vstats`、アカウント `vercel-token`）に置く。
  プロジェクトの削除までできる強さがあるので、ファイルや UserDefaults には置かない
- **Vercel の MCP コネクタでは Web Analytics が 404 になる**（2026-10-13 に `count_pageviews` と `aggregate_pageviews` で確認。
  同じ条件の `vercel api` は 200）。なのでアプリは REST API を直接叩く
- 訪問者数は `/v1/query/web-analytics/visits/aggregate` に `by=environment` を付けて取る。`visits/count` は
  since と until を**日単位（UTC）に丸める**ので、24時間の窓が切れない。aggregate は1時間単位に丸めるので、
  Vercel の画面と同じ「今に向かう窓」になる。既定で本番の環境だけに絞られ、行は多くても1つ。訪問が無ければ空の配列
- Web Analytics が有効かは、プロジェクトの `webAnalytics` の `enabledAt` と `disabledAt` の**後に起きたほう**で決める。
  切って入れ直すと両方が残り、`disabledAt` があるだけで無効と読むと間違える（kk-web がそう）
- プロジェクト一覧の続きは `until=<pagination.next>` で取る。`from` は境目の1件が前のページと重なる
- トークンをチームを絞って作ると、ほかのチームの一覧は 403 になる。そのチームは黙って飛ばす。
  トークンそのものが断られたかは `/v2/teams` の 401/403 で見る
- 50 件で問い合わせは 100 回。同時に 8 本まで流し、429 は待って聞き直す（`concurrentMap`、`VercelClient.get`）。手元で約7秒

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

- 期間の選択肢を Vercel の実物と照らすこと
- アイコン
- GitHub のリポジトリ、README、LP
