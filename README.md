# VStats

A macOS app that shows Vercel Web Analytics for all your projects in one window.

Vercel's dashboard shows Web Analytics one project at a time. With a few dozen
sites, you end up opening Analytics over and over and still never see the whole
picture. VStats lists every project that has Web Analytics enabled, across all the
teams your token can see, with its visitors over the last 24 hours, 7 days, 30 days
and 3 months side by side.

Switch between **Visitors** and **Page Views** at the top right. Each number shows
the change from the previous period, the way the dashboard does. Click a column
header to sort by that period, a project's name to open the site, and a number to
open the Vercel dashboard for that project and period.

There is a page for it at [vstats.kkweb.io](https://vstats.kkweb.io).

macOS 14+. No Xcode needed: `./build.sh` compiles with the Swift that ships with
the Command Line Tools.

## Installing

With Homebrew:

```bash
brew install --cask piro0919/tap/vstats
```

Or download the DMG from [Releases](https://github.com/piro0919/vstats/releases/latest)
and drag VStats into Applications.

The first launch will be blocked: VStats is signed with a self-signed certificate,
not an Apple Developer ID, so macOS cannot verify who made it. To let it through,
open **System Settings → Privacy & Security**, scroll to the bottom, and click
**Open Anyway** next to the message about VStats. You only do this once.

Updates arrive through Sparkle. VStats looks once at launch and only says
something when there is one.

## Your token

VStats reads your analytics with a Vercel access token. Create one under
[Account Settings → Tokens](https://vercel.com/account/settings/tokens) and paste
it into the window. A token scoped to a single team works too; VStats then shows
that team's projects.

The token is kept in the macOS Keychain and sent only to `api.vercel.com`. Remove
it from **Settings…**.

## How the numbers are counted

VStats counts each period the way the Vercel dashboard does, so the numbers match
what you see there:

- **24 hours** ends at the top of the next hour.
- **7 days** and **30 days** are stretched to whole days in your time zone, up to
  the end of today.
- **3 months** starts three calendar months back. The API it uses only reaches 92
  days into the past, so this column can come out slightly lower than the
  dashboard, and it has no previous period to compare with.

Each team is counted with a handful of requests to Vercel's metrics API — the one
behind `vercel metrics` — rather than one request per project. The numbers are
kept on your Mac and fetched again only when they are an hour old, or when you
press ⌘R. The window says when they were fetched.

Bounce rate is not shown: the public API doesn't provide it.

## Building

```bash
./build.sh
./VStats.app/Contents/MacOS/VStats --selftest
./Tools/design-rules.sh
open ./VStats.app
```

`VStats --dump` prints the same table as text. Set `VSTATS_TOKEN` to try a token
without saving it to the Keychain.

## License

MIT
