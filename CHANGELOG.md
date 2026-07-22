# Changelog

All notable changes to Calenfi are documented here.
The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

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

[Unreleased]: https://github.com/karpovilia/calenfi/compare/v0.1.0...HEAD
[0.1.0]: https://github.com/karpovilia/calenfi/releases/tag/v0.1.0
