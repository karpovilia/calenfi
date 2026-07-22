# Changelog

All notable changes to Calenfi are documented here.
The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

## [0.1.1] — 2026-07-23

### Added
- **Recurring events**: Outlook-style recurrence editor (daily/weekly/monthly/
  yearly, every-N interval, weekday picks, Nth-weekday-of-month, end:
  never / after N occurrences / by date). Providers now send recurrence on
  create/update — Google and CalDAV as RRULE, Microsoft Graph via a
  patternedRecurrence converter.
- CLI: `--rrule` on `create`, new `secret-set` command for storing provider
  credentials (e.g. Zoom Server-to-Server OAuth keys) in the OS keyring.

### Fixed
- CalDAV: event ids are now calendar-scoped. Servers like Yandex place one
  invitation (one UID) into several collections; the copies used to collide on
  one row and an event could vanish from the grid when a hidden calendar's
  copy overwrote the visible one.
- Desktop gestures: trackpad two-finger scroll no longer accidentally moves,
  resizes or draws events (trackpad uses long-press-to-drag); mouse click-drag
  works as before.
- The sync button now flushes **all** pending edits to the outbox before a
  single sync pass — previously only the first moved event was pushed.
- Cross-account create guard hardened (engine and CLI): an event queued for
  one account can neither be created in another account's calendar nor be
  silently dropped from the outbox by another account's sync pass.

### Tests
- Regression suite covering each of the above (77 tests), including widget
  tests pinning the trackpad-vs-mouse gesture contract; grid tests made
  independent of timezone and time of day.

## [0.1.0] — 2026-07-22

First public release.

### Added
- Local-first calendar aggregator for **macOS, Linux, Windows and Android**.
- Providers: **Google Calendar**, **Microsoft 365 (Graph)**, **Yandex (CalDAV)**
  and self-hosted **Exchange (EWS)** — merged into one reactive grid.
- Day / week / month views with drag-to-move and edge-resize (desktop),
  long-press-to-move (touch and trackpad).
- Deduplication of identical events across calendars, with a toggle to keep
  each copy separate.
- Conference provisioning (Teams / Meet / Zoom / Telemost) decoupled from the
  host calendar.
- Per-calendar visibility, colour and default reminder overrides.
- Local reminders and a home-screen agenda widget (Android).
- Agent-facing JSON CLI (`tools/calenfi`) for reading/creating/updating events.
- Secrets (app passwords, OAuth tokens) stored in the **OS keyring**
  (libsecret / Keychain / DPAPI), with an encrypted-at-rest file fallback and
  `flutter_secure_storage` on mobile.

[Unreleased]: https://github.com/karpovilia/calenfi/compare/v0.1.1...HEAD
[0.1.1]: https://github.com/karpovilia/calenfi/compare/v0.1.0...v0.1.1
[0.1.0]: https://github.com/karpovilia/calenfi/releases/tag/v0.1.0
