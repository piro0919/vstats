# Changelog

Notable changes to VStats. `release.sh` publishes the section for the version being released as
its release notes, and stops if that section is missing or empty — so before releasing, rename
`Unreleased` to `[x.y.z] - YYYY-MM-DD` and commit.

## [0.1.0] - 2026-10-13

### Added

- The first version. Lists every Vercel project with Web Analytics enabled, across all the teams
  your token can see, with visitors and page views over the last 24 hours, 7 days, 30 days and
  3 months, and the change from the previous period.
- Periods are counted the way the Vercel dashboard counts them. The 3-month column can come out
  slightly lower, because the API only reaches back 92 days.
- Click a name to open the site, and a number to open the dashboard for that project and period.
- The numbers are fetched again when they are an hour old, or with ⌘R.
